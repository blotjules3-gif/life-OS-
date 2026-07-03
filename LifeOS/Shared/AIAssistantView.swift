import SwiftUI
import SwiftData
import PhotosUI
import Vision
import UIKit

// MARK: - Persistent message model

@Model
final class AIMessage {
    var id: UUID
    var role: String  // "user" | "assistant"
    var text: String
    var date: Date
    var actions: Data?  // JSON-encoded [AIAction]

    init(role: String, text: String, date: Date = .now, actions: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.date = date
        self.actions = actions
    }
}

// MARK: - Action model (backend → iOS)

struct AIAction: Codable, Identifiable {
    enum ActionType: String, Codable {
        case createTodo = "create_todo"
        case openModule = "open_module"
        case scheduleReminder = "schedule_reminder"
        case updateConfig = "update_config"
        case createChallenge = "create_challenge"
        case createHabit = "create_habit"
        case addModule = "add_module"
        case removeModule = "remove_module"
    }

    var id: UUID = UUID()
    let type: ActionType
    let title: String?
    let module: String?
    let priority: Int?
    let reminderBody: String?
    let delaySeconds: Int?
    let challengeId: String?
    let dailyTarget: Double?
    let unit: String?
    let durationDays: Int?

    enum CodingKeys: String, CodingKey {
        case type, title, module, priority, unit
        case reminderBody = "reminder_body"
        case delaySeconds = "delay_seconds"
        case challengeId = "challenge_id"
        case dailyTarget = "daily_target"
        case durationDays = "duration_days"
    }

    init(type: ActionType, title: String? = nil, module: String? = nil, priority: Int? = nil, reminderBody: String? = nil, delaySeconds: Int? = nil, challengeId: String? = nil, dailyTarget: Double? = nil, unit: String? = nil, durationDays: Int? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.module = module
        self.priority = priority
        self.reminderBody = reminderBody
        self.delaySeconds = delaySeconds
        self.challengeId = challengeId
        self.dailyTarget = dailyTarget
        self.unit = unit
        self.durationDays = durationDays
    }
}

// MARK: - ViewModel

@MainActor
final class AIAssistantViewModel: ObservableObject {

    @Published var messages: [DisplayMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var errorBanner: String? = nil
    @Published var isServerOffline = false
    @Published var pendingModuleSetup: AppCategory? = nil
    @Published var actionToast: ActionToast? = nil
    @Published var revealID: UUID? = nil
    @Published var streamingText: String? = nil
    @Published var showAddFlow = false
    @Published var addFlowKind: AddAnythingSheet.Kind = .task
    @Published var addFlowPrefill = ""

    struct ActionToast: Identifiable {
        let id = UUID()
        let message: String
        let module: String?
    }

    @AppStorage("aiConversationID") private var conversationID = ""
    @AppStorage("aiConversationDay") private var conversationDay = ""
    @AppStorage("aiFirstLaunchDone") private var firstLaunchDone = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("userGender") private var userGender = ""
    @AppStorage("onboardingGoalsRaw") private var onboardingGoalsRaw = ""
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @AppStorage("aiKnownModulesRaw") private var aiKnownModulesRaw = ""
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("appTheme") private var appThemeRaw = "classic"
    @AppStorage("habitModulesRaw") private var habitModulesRaw = ""

    var modelContext: ModelContext?

    struct DisplayMessage: Identifiable {
        let id: UUID
        let role: String
        let text: String
        let date: Date
        var isThinking: Bool = false
        let actions: [AIAction]

        init(from model: AIMessage) {
            self.id = model.id
            self.role = model.role
            self.text = model.text
            self.date = model.date
            self.actions = (try? JSONDecoder().decode([AIAction].self, from: model.actions ?? Data())) ?? []
            self.isThinking = false
        }

        static func thinking() -> DisplayMessage {
            var msg = DisplayMessage(id: UUID(), role: "assistant", text: "…", date: .now, actions: [])
            msg.isThinking = true
            return msg
        }

        // ID stable : SwiftUI met à jour la même bulle à chaque token au lieu
        // d'en recréer une (ce qui rejouerait la transition d'insertion).
        static let streamingID = UUID()

        static func streaming(_ text: String) -> DisplayMessage {
            DisplayMessage(id: streamingID, role: "assistant", text: text, date: .now, actions: [])
        }

        private init(id: UUID, role: String, text: String, date: Date, actions: [AIAction]) {
            self.id = id
            self.role = role
            self.text = text
            self.date = date
            self.actions = actions
        }
    }

    // Nouvelle conversation serveur chaque jour : le backend ne relit que 20 messages,
    // sans rotation une vieille conversation finit par masquer les échanges récents.
    // La mémoire long terme (user_notes) est liée au user, pas à la conversation : elle survit.
    private func rotateConversationIfNeeded() {
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard conversationDay != today else { return }
        conversationDay = today
        conversationID = ""
    }

    func loadHistory() {
        rotateConversationIfNeeded()
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<AIMessage>(sortBy: [SortDescriptor(\.date)])
        let stored = (try? ctx.fetch(descriptor)) ?? []
        messages = stored.map { DisplayMessage(from: $0) }

        if !firstLaunchDone {
            prefillPendingHabits()
            triggerWelcome()
        } else {
            checkForNewModules()
            checkAbandonedChallenges()
        }
    }

    private func prefillPendingHabits() {
        guard let ctx = modelContext else { return }
        let modules = habitModulesRaw.split(separator: ",").map(String.init)
        HabitDefaults.insertPendingHabits(for: modules, into: ctx)
    }

    private func checkForNewModules() {
        guard !recommendedModulesRaw.isEmpty else { return }
        let current = Set(recommendedModulesRaw.split(separator: ",").map(String.init))
        let known = Set(aiKnownModulesRaw.split(separator: ",").map(String.init))
        let newModules = current.subtracting(known)
        guard !newModules.isEmpty else { return }

        aiKnownModulesRaw = current.joined(separator: ",")

        let moduleLabels: [String: String] = [
            "fitness": "Sport", "nutrition": "Nutrition", "sleep": "Sommeil",
            "looks": "Corps", "mind": "Bien-être mental", "productivity": "Productivité",
            "finance": "Finance", "invest": "Investissement", "career": "Carrière",
            "learning": "Apprentissage", "social": "Social", "home": "Maison",
            "mobility": "Mobilité", "admin": "Admin", "travel": "Voyage", "cycle": "Cycle",
        ]
        let labels = newModules.compactMap { moduleLabels[$0] }.sorted().joined(separator: ", ")
        let moduleKey = newModules.first ?? ""

        let prompt = "[NOUVEAU_MODULE] Module(s) ajouté(s) par l'utilisateur : \(labels) (\(moduleKey))"
        triggerProactive(prompt: prompt)
    }

    private func checkAbandonedChallenges() {
        Task {
            guard let challenges = try? await AgentAPI.shared.fetchChallenges() else { return }
            guard let abandoned = challenges.first(where: { $0.isAbandoned }) else { return }
            let prompt = "[DÉFI_ABANDONNÉ] Défi : \"\(abandoned.title)\" — streak actuel : \(abandoned.streak_days) jour(s), dernier check-in : \(abandoned.days_since_checkin.map { "\($0) jour(s) ago" } ?? "jamais")"
            await MainActor.run { triggerProactive(prompt: prompt) }
        }
    }

    private func triggerProactive(prompt: String) {
        guard !isLoading else { return }
        appendThinking()
        isLoading = true

        Task {
            do {
                let response = try await AgentAPI.shared.chat(
                    message: prompt,
                    module: nil,
                    conversationID: conversationID.isEmpty ? nil : conversationID
                )
                conversationID = response.conversation_id
                isServerOffline = false
                removeThinking()
                appendAssistantMessage(response.reply, actions: response.actions ?? [])
                for action in (response.actions ?? []) {
                    await execute(action: action)
                }
            } catch {
                removeThinking()
                if let apiErr = error as? AgentAPIError {
                    switch apiErr {
                    case .networkError(let underlying):
                        let urlErr = underlying as? URLError
                        if urlErr?.code == .notConnectedToInternet || urlErr?.code == .networkConnectionLost {
                            isServerOffline = true
                        }
                    case .invalidResponse(404):
                        conversationID = ""
                    default:
                        break
                    }
                }
            }
            isLoading = false
        }
    }

    func send(text: String? = nil, module: String? = nil) {
        rotateConversationIfNeeded()
        let content = (text ?? inputText).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty, !isLoading else { return }
        inputText = ""
        Haptics.tap()

        appendUserMessage(content)

        // Intention « ajouter » → ouvre le flux guidé (choisir quoi ajouter + rappel).
        if let (kind, prefill) = Self.detectAddIntent(content) {
            addFlowKind = kind
            addFlowPrefill = prefill
            appendAssistantMessage("Ok, je t'ai ouvert le formulaire. Tu pourras aussi y mettre un rappel.", actions: [])
            showAddFlow = true
            return
        }

        appendThinking()
        isLoading = true

        Task {
            do {
                let response = try await AgentAPI.shared.chatStream(
                    message: content,
                    module: module,
                    conversationID: conversationID.isEmpty ? nil : conversationID
                ) { [weak self] token in
                    self?.handleStreamToken(token)
                }
                conversationID = response.conversation_id
                isServerOffline = false
                removeThinking()
                let wasStreamed = streamingText != nil
                streamingText = nil
                // Pas de machine à écrire après un stream : le texte est déjà apparu token par token.
                appendAssistantMessage(response.reply, actions: response.actions ?? [], animateReveal: !wasStreamed)

                // Execute local iOS actions
                for action in (response.actions ?? []) {
                    await execute(action: action)
                }
            } catch {
                // Serveur pas encore à jour (404 sur /chat/stream) ou flux interrompu :
                // on retombe sur l'endpoint classique.
                streamingText = nil
                await fallbackSend(content: content, module: module)
            }
            isLoading = false
        }
    }

    private func handleStreamToken(_ token: String) {
        if streamingText == nil {
            removeThinking()
            streamingText = token
        } else {
            streamingText? += token
        }
    }

    private func fallbackSend(content: String, module: String?) async {
        if !messages.contains(where: { $0.isThinking }) { appendThinking() }
        do {
            let response = try await AgentAPI.shared.chat(
                message: content,
                module: module,
                conversationID: conversationID.isEmpty ? nil : conversationID
            )
            conversationID = response.conversation_id
            isServerOffline = false
            removeThinking()
            appendAssistantMessage(response.reply, actions: response.actions ?? [])
            for action in (response.actions ?? []) {
                await execute(action: action)
            }
        } catch {
            removeThinking()
            if let apiErr = error as? AgentAPIError {
                switch apiErr {
                case .networkError(let underlying):
                    let urlErr = underlying as? URLError
                    let offlineCodes: [URLError.Code] = [
                        .notConnectedToInternet, .networkConnectionLost,
                        .cannotConnectToHost, .cannotFindHost
                    ]
                    if urlErr?.code == .timedOut {
                        errorBanner = "Ton coach met trop de temps à répondre. Réessaie."
                    } else if let code = urlErr?.code, offlineCodes.contains(code) {
                        isServerOffline = true
                        // Le chat ne reste pas muet : réponse composée depuis les données locales.
                        appendAssistantMessage(OfflineCoach.reply(to: content, ctx: modelContext), actions: [])
                    } else {
                        errorBanner = "Erreur réseau. Réessaie dans un instant."
                    }
                case .invalidResponse(404): conversationID = ""
                default: errorBanner = apiErr.errorDescription
                }
            } else {
                errorBanner = error.localizedDescription
            }
        }
    }

    private func triggerWelcome() {
        let goalLabels: [String: String] = [
            "health": "Santé & forme",
            "performance": "Performance",
            "money": "Argent & carrière",
            "mind": "Focus & bien-être",
            "habits": "Meilleures habitudes",
        ]
        let moduleLabels: [String: String] = [
            "fitness": "Sport", "nutrition": "Nutrition", "sleep": "Sommeil",
            "looks": "Corps", "mind": "Bien-être mental", "productivity": "Productivité",
            "finance": "Finance", "invest": "Investissement", "career": "Carrière",
            "learning": "Apprentissage", "social": "Social", "home": "Maison",
            "mobility": "Mobilité", "admin": "Admin", "travel": "Voyage", "cycle": "Cycle",
        ]

        let goals = onboardingGoalsRaw.split(separator: ",")
            .compactMap { goalLabels[String($0)] }
            .joined(separator: ", ")

        let modules = recommendedModulesRaw.split(separator: ",")
            .compactMap { moduleLabels[String($0)] }
            .joined(separator: ", ")

        let habitModules = habitModulesRaw.split(separator: ",")
            .compactMap { moduleLabels[String($0)] }
            .joined(separator: ", ")

        let wake = String(format: "%02d:%02d", wakeupHour, wakeupMinute)

        // Collect per-module config answers saved during onboarding
        let moduleConfigs = recommendedModulesRaw.split(separator: ",").compactMap { key -> String? in
            let k = String(key)
            guard let raw = UserDefaults.standard.string(forKey: "moduleConfig_\(k)"),
                  let data = raw.data(using: .utf8),
                  let config = try? JSONDecoder().decode([String: String].self, from: data),
                  !config.isEmpty else { return nil }
            let label = moduleLabels[k] ?? k
            let detail = config.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            return "\(label):\(detail)"
        }.joined(separator: " | ")

        let prompt = """
        [PREMIER_LANCEMENT]
        Prénom: \(userName.isEmpty ? "non renseigné" : userName)
        Genre: \(userGender.isEmpty ? "non renseigné" : userGender)
        Objectifs: \(goals.isEmpty ? "non renseignés" : goals)
        Modules activés: \(modules.isEmpty ? "aucun" : modules)
        Heure de réveil: \(wake)
        Modules pour habitudes: \(habitModules.isEmpty ? "aucun" : habitModules)
        Config modules: \(moduleConfigs.isEmpty ? "aucune" : moduleConfigs)
        Instruction: Pour chaque module avec habitudes, pose des questions précises (durée séance, nombre d'exercices, etc.) pour créer des habitudes personnalisées. Demande l'accord avant de créer chaque habitude (action create_habit).
        """

        appendThinking()
        isLoading = true
        // NE PAS mettre firstLaunchDone = true ici — seulement après succès réseau.
        // Si le serveur est offline on réessaie au prochain lancement.
        aiKnownModulesRaw = recommendedModulesRaw

        Task {
            do {
                let response = try await AgentAPI.shared.chat(
                    message: prompt,
                    module: nil,
                    conversationID: nil
                )
                // Succès — on marque le welcome comme vu seulement maintenant
                firstLaunchDone = true
                conversationID = response.conversation_id
                isServerOffline = false
                removeThinking()
                appendAssistantMessage(response.reply, actions: response.actions ?? [])
                for action in (response.actions ?? []) {
                    await execute(action: action)
                }
            } catch {
                removeThinking()
                if let apiErr = error as? AgentAPIError, case .networkError = apiErr {
                    isServerOffline = true
                }
                // firstLaunchDone reste false → réessai au prochain lancement
                let name = userName.isEmpty ? "" : " \(userName)"
                appendAssistantMessage(
                    "Connexion impossible. Je te retrouve dès que le réseau est disponible. En attendant, dis-moi par où tu veux commencer.",
                    actions: []
                )
            }
            isLoading = false
        }
    }

    // MARK: - iOS local action execution

    private func execute(action: AIAction) async {
        guard let ctx = modelContext else { return }
        switch action.type {
        case .createTodo:
            if let title = action.title {
                let todo = TodoItem(title: title, priority: action.priority ?? 1)
                ctx.insert(todo)
                do { try ctx.save() } catch { print("[SwiftData] createTodo failed: \(error)") }
                showToast("Tâche ajoutée : \(title)", module: "productivity")
            }
        case .scheduleReminder:
            if let body = action.reminderBody {
                let delay = TimeInterval(action.delaySeconds ?? 3600)
                scheduleLocalNotification(title: "LifeOS", body: body, delay: delay)
                showToast("Rappel programmé", module: nil)
            }
        case .createChallenge:
            if let title = action.title, let days = action.durationDays {
                scheduleLocalNotification(
                    title: "Défi démarré",
                    body: "\(title) — \(days) jours. Tu peux le faire !",
                    delay: 2
                )
                showToast("Défi créé : \(title)", module: nil)
            }
        case .createHabit:
            if let title = action.title {
                let d = HabitDefaults.iconAndColor(for: action.module ?? "")
                let habit = Habit(name: title, icon: d.icon, colorHex: d.colorHex, isPending: true, moduleTag: action.module ?? "")
                ctx.insert(habit)
                do { try ctx.save() } catch { print("[SwiftData] createHabit failed: \(error)") }
                showToast("Habitude ajoutée : \(title)", module: action.module)
            }
        case .addModule:
            if let module = action.module {
                addModuleToProfile(module)
            }
        case .removeModule:
            if let module = action.module {
                removeModuleFromProfile(module)
            }
        case .openModule:
            if let module = action.module {
                NotificationCenter.default.post(
                    name: .lifeOSOpenModule,
                    object: nil,
                    userInfo: ["module": module]
                )
            }
        case .updateConfig:
            // title = clé AppStorage (ex: "kcalGoal"), reminderBody = valeur en string.
            // Allowlist stricte : la réponse serveur ne doit jamais pouvoir écrire
            // des clés sensibles (dev.apiBaseURL, dev.apiKey, état interne…).
            if let key = action.title, let rawValue = action.reminderBody {
                let allowedConfigKeys: Set<String> = [
                    "kcalGoal", "proteinGoal", "carbGoal", "fatGoal",
                    "waterGoal", "glassesGoal", "fastTarget",
                    "stepGoal", "focusMinGoal", "screenGoal", "socialMaxMin",
                    "bedHour", "bedMinute", "wakeupHour", "wakeupMinute",
                    "gymReminderHour", "gymReminderMinute",
                    "budgetGoal"
                ]
                guard allowedConfigKeys.contains(key) else {
                    print("[updateConfig] clé refusée : \(key)")
                    return
                }
                if let intVal = Int(rawValue) {
                    UserDefaults.standard.set(intVal, forKey: key)
                } else if let doubleVal = Double(rawValue) {
                    UserDefaults.standard.set(doubleVal, forKey: key)
                } else {
                    UserDefaults.standard.set(rawValue, forKey: key)
                }
            }
        }
    }

    private func addModuleToProfile(_ module: String) {
        var current = Set(recommendedModulesRaw.split(separator: ",").map(String.init))
        guard !current.contains(module) else { return }
        current.insert(module)
        recommendedModulesRaw = current.joined(separator: ",")
        aiKnownModulesRaw = recommendedModulesRaw
        // Ouvre le questionnaire de configuration des notifications
        if let category = AppCategory(rawValue: module) {
            pendingModuleSetup = category
        }
    }

    private func removeModuleFromProfile(_ module: String) {
        var current = Set(recommendedModulesRaw.split(separator: ",").map(String.init))
        guard current.contains(module) else { return }
        current.remove(module)
        recommendedModulesRaw = current.joined(separator: ",")
        aiKnownModulesRaw = recommendedModulesRaw
    }

    private func showToast(_ message: String, module: String?) {
        actionToast = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                self.actionToast = ActionToast(message: message, module: module)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeOut(duration: 0.25)) { self.actionToast = nil }
            }
        }
    }

    private func scheduleLocalNotification(title: String, body: String, delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Message helpers

    private func appendUserMessage(_ text: String) {
        let msg = AIMessage(role: "user", text: text)
        modelContext?.insert(msg)
        do { try modelContext?.save() } catch { print("[SwiftData] appendUserMessage failed: \(error)") }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
            messages.append(DisplayMessage(from: msg))
        }
    }

    private func appendAssistantMessage(_ text: String, actions: [AIAction], animateReveal: Bool = true) {
        let actionsData = try? JSONEncoder().encode(actions)
        let msg = AIMessage(role: "assistant", text: text, actions: actionsData)
        modelContext?.insert(msg)
        do { try modelContext?.save() } catch { print("[SwiftData] appendAssistantMessage failed: \(error)") }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
            messages.append(DisplayMessage(from: msg))
        }
        Haptics.soft()
        guard animateReveal else { return }
        revealID = msg.id
        Task { [id = msg.id] in
            try? await Task.sleep(for: .seconds(3))
            if revealID == id { revealID = nil }
        }
    }

    private func appendThinking() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            messages.append(.thinking())
        }
    }

    private func removeThinking() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            messages.removeAll { $0.isThinking }
        }
    }

    /// Détecte une intention « ajouter » et devine le type + le nom de l'objet.
    static func detectAddIntent(_ raw: String) -> (AddAnythingSheet.Kind, String)? {
        let t = raw.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        // Uniquement la famille « ajouter » — ne PAS intercepter « créer une séance/habitude »
        // (gérées par le coach) ni les questions contenant « ajoute ».
        let addWords = ["ajoute ", "ajouter", "ajoute-", "rajoute", "rajouter"]
        guard addWords.contains(where: { t.contains($0) }) || t.hasPrefix("add ") || t == "add" || t == "ajouter" else { return nil }

        let kind: AddAnythingSheet.Kind
        if t.contains("complement") || t.contains("vitamine") || t.contains("creatine") || t.contains("magnesium") || t.contains("omega") || t.contains("zinc") { kind = .supplement }
        else if t.contains("course") || t.contains("liste") || t.contains("acheter") || t.contains("panier") { kind = .shopping }
        else if t.contains(" eau") || t.contains("hydrat") || t.contains("boire") { kind = .water }
        else if t.contains("humeur") || t.contains("mood") || t.contains("moral") { kind = .mood }
        else if t.contains("depense") || t.contains("achat") || t.contains("paye") || t.contains("depenser") { kind = .expense }
        else if t.contains("abonnement") || t.contains("subscription") { kind = .subscription }
        else if t.contains("seance") || t.contains("entrainement") || t.contains("exercice") || t.contains("muscu") || t.contains("workout") { kind = .workout }
        else if t.contains("evenement") || t.contains("rendez") || t.contains(" rdv") || t.contains("anniversaire") { kind = .event }
        else if t.contains("echeance") || t.contains("deadline") || t.contains("facture") { kind = .deadline }
        else if t.contains("menage") || t.contains("nettoyer") || t.contains("ranger") || t.contains("corvee") { kind = .chore }
        else if t.contains("plein") || t.contains("essence") || t.contains("carburant") || t.contains("gasoil") { kind = .fuel }
        else if t.contains("habitude") || t.contains("chaque jour") || t.contains("quotidien") || t.contains("tous les jours") { kind = .habit }
        else if t.contains("aliment") || t.contains("repas") || t.contains("manger") || t.contains("bouffe") || t.contains("nourriture") || t.contains("calorie") { kind = .food }
        else if t.contains("note") || t.contains("idee") { kind = .note }
        else { kind = .task }

        // Extraire un nom lisible en retirant les mots de commande.
        var name = raw.trimmingCharacters(in: .whitespaces)
        let leading = ["ajouter", "ajoute", "rajouter", "rajoute", "add", "je veux", "peux-tu", "peux tu", "stp"]
        var changed = true
        while changed {
            changed = false
            let low = name.lowercased()
            for w in leading where low.hasPrefix(w) {
                name = String(name.dropFirst(w.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :,-'"))
                changed = true; break
            }
        }
        let nouns = ["une tache", "un complement", "un complément", "une habitude", "un aliment", "une note",
                     "un article", "a ma liste de course", "à ma liste de course", "a ma liste", "à ma liste",
                     "de course", "quotidienne", "sur ma liste"]
        for w in nouns {
            let low = name.lowercased()
            if low.hasPrefix(w) { name = String(name.dropFirst(w.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :,-'")) }
            name = name.replacingOccurrences(of: w, with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
        }
        for art in ["un ", "une ", "des ", "le ", "la ", "les ", "mon ", "ma ", "mes "] {
            if name.lowercased().hasPrefix(art) { name = String(name.dropFirst(art.count)) }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " :,-'"))
        if name.count < 2 { name = "" }
        return (kind, name)
    }

    /// Analyse une image on-device (Vision) et route vers la bonne catégorie — sans backend.
    func analyzeImage(_ image: UIImage) {
        guard !isLoading else { return }
        Haptics.tap()
        appendUserMessage("Photo envoyée")
        appendThinking()
        isLoading = true

        Task {
            let result = await ImageIntel.analyze(image)
            // Effet concret : si c'est un aliment, on le journalise directement.
            if case let .food(guess) = result.route, let ctx = modelContext {
                ctx.insert(FoodEntry(name: guess.name, calories: guess.kcal,
                                     protein: guess.protein, carbs: guess.carbs, fat: guess.fat,
                                     meal: currentMeal()))
                try? ctx.save()
            }
            removeThinking()
            appendAssistantMessage(result.reply, actions: result.actions)
            isLoading = false
        }
    }

    private func currentMeal() -> String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11:  return "Petit-déj"
        case 11..<15: return "Déjeuner"
        case 15..<18: return "Collation"
        default:      return "Dîner"
        }
    }
}

// MARK: - On-device image understanding + routing

enum ImageRoute { case food(FoodGuess), document(String), general(String) }

enum ImageIntel {
    /// Classe l'image, lit le texte éventuel, et décide vers quel pôle router — 100% on-device.
    static func analyze(_ image: UIImage) async -> (route: ImageRoute, reply: String, actions: [AIAction]) {
        let labels = await classify(image)

        // 1) Aliment reconnu → journalisation calories (pôle Nutrition)
        if let hit = labels.first(where: { FoodCalorieDB.match($0.label) != nil }),
           let m = FoodCalorieDB.match(hit.label) {
            let g = FoodGuess(name: m.0, kcal: m.1, protein: m.2, carbs: m.3, fat: m.4, confidence: Double(hit.confidence))
            let reply = "On dirait : \(g.name) (~\(g.kcal) kcal). Je l'ai ajouté à ton journal du jour — tu peux l'ajuster dans Nutrition."
            return (.food(g), reply, [AIAction(type: .openModule, title: "Nutrition", module: "nutrition")])
        }

        // 2) Beaucoup de texte → document / justificatif (pôle Admin)
        let text = await recognizeText(image)
        if text.count >= 20 {
            let snippet = String(text.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let reply = "J'ai lu du texte sur cette image :\n« \(snippet)… »\nÇa ressemble à un document — tu peux le classer dans Documents / Admin."
            return (.document(text), reply, [AIAction(type: .openModule, title: "Documents", module: "admin")])
        }

        // 3) Sinon : description brute + suggestion
        let top = labels.first?.label.split(separator: ",").first.map(String.init)?.capitalized ?? "quelque chose"
        let reply = "J'ai analysé ta photo : \(top). Dis-moi ce que tu veux en faire (l'ajouter quelque part, créer un rappel…)."
        return (.general(top), reply, [])
    }

    private static func classify(_ image: UIImage) async -> [(label: String, confidence: Float)] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                let obs = (req.results as? [VNClassificationObservation] ?? []).filter { $0.confidence > 0.05 }
                cont.resume(returning: obs.prefix(15).map { ($0.identifier, $0.confidence) })
            }
        }
    }

    private static func recognizeText(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .fast
            req.recognitionLanguages = ["fr-FR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                let strings = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: strings.joined(separator: "\n"))
            }
        }
    }
}

// MARK: - Import for notifications

import UserNotifications

// MARK: - Main View

struct AIAssistantView: View {
    var prefill: String? = nil
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AIAssistantViewModel()
    @AppStorage("appTheme") private var appThemeRaw = "classic"
    private var accent: Color { (AppTheme(rawValue: appThemeRaw) ?? .classic).accent }
    @FocusState private var inputFocused: Bool
    @State private var showClearConfirm = false
    @State private var showServerConfig = false
    @State private var photoItem: PhotosPickerItem?

    // Quick suggestions change per time of day
    private var quickSuggestions: [(label: String, message: String, module: String?)] {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<10:
            return [
                ("Plan du matin", "C'est quoi ma priorité ce matin ?", nil),
                ("Calories", "Mon objectif calories pour aujourd'hui", "nutrition"),
                ("Sport", "Créer une séance pour aujourd'hui", "fitness"),
                ("Humeur", "Je ne suis pas en forme ce matin", "mind"),
            ]
        case 10..<14:
            return [
                ("Check objectifs", "Où j'en suis sur mes objectifs ?", nil),
                ("Budget", "Analyser mes dépenses ce mois", "finance"),
                ("Focus", "J'arrive pas à me concentrer", "productivity"),
                ("Repas", "Que manger ce midi ?", "nutrition"),
            ]
        case 14..<19:
            return [
                ("Bilan du jour", "Comment je m'en sors aujourd'hui ?", nil),
                ("Séance", "Logger ma séance de sport", "fitness"),
                ("Rappel soir", "Mets-moi un rappel ce soir", nil),
                ("Stress", "Je suis stressé cet après-midi", "mind"),
            ]
        default:
            return [
                ("Bilan semaine", "Bilan rapide de ma semaine", nil),
                ("Sommeil", "Conseils pour mieux dormir ce soir", "sleep"),
                ("Demain", "Ma priorité pour demain", nil),
                ("Habitude", "Créer une nouvelle habitude", "productivity"),
            ]
        }
    }

    var body: some View {
        NavigationStack {
            messagesArea
                .background(Theme.bg.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    inputSection
                }
            .navigationTitle("Ton coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog("Effacer la conversation ?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { clearHistory() }
                Button("Annuler", role: .cancel) { }
            }
            .alert("Erreur", isPresented: .constant(vm.errorBanner != nil)) {
                Button("OK") { vm.errorBanner = nil }
            } message: {
                Text(vm.errorBanner ?? "")
            }
            #if DEBUG
            .sheet(isPresented: $showServerConfig) {
                ServerConfigView {
                    showServerConfig = false
                    vm.isServerOffline = false
                    vm.loadHistory()
                }
            }
            #endif
            .sheet(item: $vm.pendingModuleSetup) { category in
                ModuleSetupView(module: category)
            }
            .sheet(isPresented: $vm.showAddFlow) {
                AddAnythingSheet(initialKind: vm.addFlowKind, prefillName: vm.addFlowPrefill)
                    .presentationDetents([.large])
            }
            .overlay(alignment: .top) {
                if let toast = vm.actionToast {
                    actionToastView(toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: vm.actionToast?.id)
        }
        .task {
            vm.modelContext = ctx
            vm.loadHistory()
            if let prefill, vm.inputText.isEmpty {
                vm.inputText = prefill
                inputFocused = true
            }
        }
    }

    private func actionToastView(_ toast: AIAssistantViewModel.ActionToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x4CC38A))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if toast.module != nil {
                Button {
                    vm.actionToast = nil
                    NotificationCenter.default.post(
                        name: .lifeOSOpenModule,
                        object: nil,
                        userInfo: ["module": toast.module!]
                    )
                } label: {
                    Text("Voir →")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Input section (offline banner + input bar)

    private var inputSection: some View {
        VStack(spacing: 0) {
            if vm.isServerOffline {
                offlineBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputArea
        }
        .background(Theme.bg)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: vm.isServerOffline)
    }

    // MARK: - Messages area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Avatar header
                    aiHeader
                        .padding(.bottom, 20)

                    // Messages
                    ForEach(vm.messages) { msg in
                        MessageRow(message: msg, accent: accent, reveal: msg.id == vm.revealID)
                            .id(msg.id)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Réponse en cours de streaming (mise à jour token par token)
                    if let streamed = vm.streamingText, !streamed.isEmpty {
                        MessageRow(message: .streaming(streamed), accent: accent)
                            .id("streaming")
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Quick suggestions — toujours visibles sauf pendant le chargement
                    if !vm.isLoading {
                        quickSuggestionsRow
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                    }

                    Color.clear.frame(height: 24).id("bottom")
                }
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // Pas d'animation ici : un spring rejoué à chaque token rend le scroll saccadé
            .onChange(of: vm.streamingText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.28
                withAnimation(.easeOut(duration: duration)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - AI Header

    private var aiHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 3) {
                Text("Assistant LifeOS")
                    .font(.system(size: 16, weight: .semibold))
                Text("Personnalise tes modules, crée des objectifs, suis tes habitudes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Quick suggestions

    private var quickSuggestionsRow: some View {
        VStack(spacing: 10) {
            // Header avec bouton effacer
            HStack {
                Text("SUGGESTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                if !vm.messages.isEmpty {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Text("Effacer")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            // Grille 2×2
            let cols = Array(quickSuggestions.prefix(4))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(cols, id: \.label) { s in
                    Button {
                        vm.send(text: s.message, module: s.module)
                    } label: {
                        Text(s.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(uiColor: .secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 10) {
                TextField("Dis-moi quelque chose…", text: $vm.inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { vm.send() }

                Button { vm.send() } label: {
                    ZStack {
                        Circle()
                            .fill(canSend ? accent : Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSend)
                        Image(systemName: vm.isLoading ? "ellipsis" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSend ? .white : .secondary)
                            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    }
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.bg)
        }
    }

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isLoading
    }

    private var offlineBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("Serveur inaccessible")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                #if DEBUG
                Button {
                    showServerConfig = true
                } label: {
                    Text("Configurer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #endif

                Button {
                    vm.isServerOffline = false
                    vm.send(text: vm.inputText.isEmpty ? nil : vm.inputText)
                } label: {
                    Text("Réessayer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            Text("URL actuelle : \(Configuration.apiBaseURL)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 7)
        }
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Clear

    private func clearHistory() {
        let descriptor = FetchDescriptor<AIMessage>()
        let all = (try? ctx.fetch(descriptor)) ?? []
        all.forEach { ctx.delete($0) }
        do { try ctx.save() } catch { print("[SwiftData] clearHistory failed: \(error)") }
        vm.messages = []
        UserDefaults.standard.removeObject(forKey: "aiConversationID")
        UserDefaults.standard.removeObject(forKey: "aiKnownModulesRaw")
        vm.loadHistory()
    }
}

// MARK: - MessageRow

private struct MessageRow: View {
    let message: AIAssistantViewModel.DisplayMessage
    let accent: Color
    var reveal: Bool = false

    var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 56) }

                Group {
                    if message.isThinking {
                        ThinkingIndicator()
                    } else if reveal, !isUser {
                        TypewriterText(text: message.text)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    } else {
                        Text(message.text)
                            .font(.system(size: 15))
                            .foregroundStyle(isUser ? .white : .primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? accent : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .shadow(
                    color: isUser ? accent.opacity(0.18) : Color.black.opacity(0.06),
                    radius: isUser ? 8 : 4,
                    x: 0,
                    y: isUser ? 3 : 2
                )

                if !isUser { Spacer(minLength: 56) }
            }

            // Action chips (after assistant message)
            if !isUser && !message.actions.isEmpty {
                actionChips
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: isUser ? .trailing : .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94, anchor: isUser ? .bottomTrailing : .bottomLeading)),
            removal: .opacity.combined(with: .scale(scale: 0.97))
        ))
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(message.actions.filter { $0.title != nil }) { action in
                    Label(action.title!, systemImage: iconFor(action.type))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func iconFor(_ type: AIAction.ActionType) -> String {
        switch type {
        case .createTodo: return "checkmark.circle"
        case .openModule: return "arrow.right.circle"
        case .scheduleReminder: return "bell"
        case .updateConfig: return "slider.horizontal.3"
        case .createChallenge: return "flame"
        case .createHabit: return "repeat.circle.fill"
        case .addModule: return "plus.circle"
        case .removeModule: return "minus.circle"
        }
    }
}

// MARK: - Thinking indicator

// MARK: - Server Config Sheet

// Outil de dev uniquement : en prod, l'URL et la clé API viennent de
// Config.xcconfig et ne doivent pas être modifiables depuis l'UI.
#if DEBUG
struct ServerConfigView: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = Configuration.apiBaseURL
    @State private var keyText = Configuration.apiKey
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL du serveur")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("http://192.168.1.x:8000", text: $urlText)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($urlFocused)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clé API")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SecureField("api-key", text: $keyText)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Connexion backend LifeOS")
                } footer: {
                    Text("Lance le serveur sur ton Mac puis entre son adresse IP locale (même réseau Wi-Fi). Exemple : http://192.168.1.7:8000")
                        .font(.system(size: 12))
                }

                Section {
                    Button("Utiliser l'adresse par défaut") {
                        urlText = "http://192.168.1.7:8000"
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Configurer le serveur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: "dev.apiBaseURL")
                        let trimmedKey = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(trimmedKey.isEmpty ? nil : trimmedKey, forKey: "dev.apiKey")
                        onSave()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { urlFocused = true }
        }
    }
}
#endif

// MARK: - Thinking indicator

private struct ThinkingIndicator: View {
    @State private var active = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(active ? 1.0 : 0.65)
                    .opacity(active ? 0.85 : 0.3)
                    .offset(y: active ? -3 : 0)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: active
                    )
            }
        }
        .padding(.vertical, 2)
        .onAppear { active = true }
    }
}

// MARK: - Typewriter reveal (réponses fraîches uniquement)

private struct TypewriterText: View {
    let text: String
    @State private var displayed = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayed)
            .animation(.easeOut(duration: 0.12), value: displayed)
            .task {
                guard !reduceMotion else { displayed = text; return }
                let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                // Durée totale plafonnée à ~1,2 s quelle que soit la longueur.
                let delay = min(0.05, 1.2 / Double(max(1, words.count)))
                for word in words {
                    displayed = displayed.isEmpty ? word : displayed + " " + word
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                displayed = text
            }
    }
}

// MARK: - PressScaleButtonStyle

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
