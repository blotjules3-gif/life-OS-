import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
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
    @Published var errorBanner: String?
    @Published var isServerOffline = false
    @Published var pendingModuleSetup: AppCategory?
    @Published var actionToast: ActionToast?
    @Published var revealID: UUID?
    @Published var streamingText: String?
    @Published var showAddFlow = false
    @Published var addFlowKind: AddAnythingSheet.Kind = .task
    @Published var addFlowPrefill = ""

    struct ActionToast: Identifiable {
        let id = UUID()
        let message: String
        let module: String?
    }

    @AppStorage(AppStorageKeys.aiConversationID) private var conversationID = ""
    @AppStorage(AppStorageKeys.aiConversationDay) private var conversationDay = ""
    @AppStorage(AppStorageKeys.aiFirstLaunchDone) private var firstLaunchDone = false
    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.userGender) private var userGender = ""
    @AppStorage(AppStorageKeys.onboardingGoalsRaw) private var onboardingGoalsRaw = ""
    @AppStorage(AppStorageKeys.recommendedModules) private var recommendedModulesRaw = ""
    @AppStorage(AppStorageKeys.aiKnownModulesRaw) private var aiKnownModulesRaw = ""
    @AppStorage(AppStorageKeys.wakeupHour) private var wakeupHour = 7
    @AppStorage(AppStorageKeys.wakeupMinute) private var wakeupMinute = 0
    @AppStorage(AppStorageKeys.appTheme) private var appThemeRaw = "classic"
    @AppStorage(AppStorageKeys.habitModulesRaw) private var habitModulesRaw = ""

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
        // Les challenges vivaient côté Railway ; feature retirée depuis Option C.
        // Un tracker local pourra revenir en Phase 2B.5 quand on aura un modèle
        // SwiftData `LifeChallenge` local.
    }

    private func triggerProactive(prompt: String) {
        guard !isLoading else { return }
        appendThinking()
        isLoading = true

        Task {
            let reply = await OnDeviceLLM.respond(to: prompt, ctx: modelContext)
            isServerOffline = false
            removeThinking()
            appendAssistantMessage(reply.text, actions: [])
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
            let reply = await OnDeviceLLM.respond(
                to: content,
                ctx: modelContext,
                moduleContext: module
            )
            isServerOffline = false
            removeThinking()
            streamingText = nil
            appendAssistantMessage(reply.text, actions: [], animateReveal: true)
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

    // MARK: - Feedback loop

    /// L'utilisateur a aimé cette réponse — on le loggue pour la boucle
    /// d'apprentissage (CoachFeedbackStore) qui l'injecte dans les prompts
    /// suivants. Bruit d'entrée limité aux 30 derniers votes.
    func recordLike(for message: DisplayMessage) {
        CoachFeedbackStore.record(.like, response: message.text)
        showToast("Merci — je vais reproduire ce style", module: nil)
    }

    /// L'utilisateur n'a pas aimé — le prochain prompt inclura ce snippet
    /// dans la section "à éviter".
    func recordDislike(for message: DisplayMessage) {
        CoachFeedbackStore.record(.dislike, response: message.text)
        showToast("Compris — j'ajuste au prochain message", module: nil)
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

        // Contexte cross-modules (sommeil, muscu 7j, kcal, humeur, insights).
        // Tronqué à 3000 chars pour le welcome — pas besoin des blocs d'expertise
        // complets, juste les données de vie récentes.
        let fullContext = UserContextBuilder.shared.build()
        let liveContext = fullContext.count > 3000
            ? String(fullContext.prefix(3000)) + "\n[…]"
            : fullContext

        let prompt = """
        [PREMIER_LANCEMENT]
        Prénom: \(userName.isEmpty ? "non renseigné" : userName)
        Genre: \(userGender.isEmpty ? "non renseigné" : userGender)
        Objectifs: \(goals.isEmpty ? "non renseignés" : goals)
        Modules activés: \(modules.isEmpty ? "aucun" : modules)
        Heure de réveil: \(wake)
        Modules pour habitudes: \(habitModules.isEmpty ? "aucun" : habitModules)
        Config modules: \(moduleConfigs.isEmpty ? "aucune" : moduleConfigs)

        Contexte de vie actuel :
        \(liveContext)

        Instruction: Salue \(userName.isEmpty ? "l'utilisateur" : userName) en 2-3 phrases MAX, chaleureuses. Si le contexte de vie contient des données récentes (sommeil, séance, kcal, humeur, insights cross-modules), MENTIONNE-LES concrètement pour prouver que tu connais son quotidien. Ensuite propose UNE action précise adaptée. Puis pose UNE question ouverte. Pour chaque module avec habitudes, prépare-toi à poser des questions précises (durée séance, nombre d'exercices) pour créer des habitudes personnalisées via l'action create_habit — mais pas dans ce premier message.
        """

        appendThinking()
        isLoading = true
        // NE PAS mettre firstLaunchDone = true ici — seulement après succès réseau.
        // Si le serveur est offline on réessaie au prochain lancement.
        aiKnownModulesRaw = recommendedModulesRaw

        Task {
            let reply = await OnDeviceLLM.respond(to: prompt, ctx: modelContext)
            firstLaunchDone = true
            isServerOffline = false
            removeThinking()
            appendAssistantMessage(reply.text, actions: [])
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
                do { try ctx.save() } catch { AppLog.data.error("createTodo failed: \(error.localizedDescription, privacy: .public)") }
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
                    title: "Nouvelle habitude",
                    body: "\(title) — \(days) jours. Tu peux le faire !",
                    delay: 2
                )
                showToast("Habitude créée : \(title)", module: nil)
            }
        case .createHabit:
            if let title = action.title {
                let d = HabitDefaults.iconAndColor(for: action.module ?? "")
                let habit = Habit(name: title, icon: d.icon, colorHex: d.colorHex, isPending: true, moduleTag: action.module ?? "")
                ctx.insert(habit)
                do { try ctx.save() } catch { AppLog.data.error("createHabit failed: \(error.localizedDescription, privacy: .public)") }
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
                    AppLog.coach.warning("updateConfig: clé refusée (hors allowlist) — \(key, privacy: .public)")
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
        do { try modelContext?.save() } catch { AppLog.data.error("appendUserMessage failed: \(error.localizedDescription, privacy: .public)") }
        // Extraction mémoire long terme — analyse le message pour capturer
        // objectifs, préférences, habitudes, faits. Alimente le contexte coach.
        if let ctx = modelContext {
            let n = MemoryExtractor.extract(from: text, context: ctx)
            if n > 0 { AppLog.coach.debug("MemoryExtractor: \(n) new memories") }
        }
        AnalyticsEvents.chatMessageSent()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
            messages.append(DisplayMessage(from: msg))
        }
    }

    private func appendAssistantMessage(_ text: String, actions: [AIAction], animateReveal: Bool = true) {
        let actionsData = try? JSONEncoder().encode(actions)
        let msg = AIMessage(role: "assistant", text: text, actions: actionsData)
        modelContext?.insert(msg)
        do { try modelContext?.save() } catch { AppLog.data.error("appendAssistantMessage failed: \(error.localizedDescription, privacy: .public)") }
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
                do { try ctx.save() } catch { AppLog.data.error("food entry save failed: \(error.localizedDescription, privacy: .public)") }
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
                let obs = (req.results ?? []).filter { $0.confidence > 0.05 }
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
                let strings = (req.results ?? [])
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
    @AppStorage(AppStorageKeys.appTheme) private var appThemeRaw = "classic"
    @AppStorage(AppStorageKeys.coachDisclaimerAccepted) private var disclaimerAccepted = false
    private var accent: Color { (AppTheme(rawValue: appThemeRaw) ?? .classic).accent }
    @FocusState private var inputFocused: Bool
    @State private var showClearConfirm = false
    @State private var showServerConfig = false
    @State private var showCoachPrefs = false
    @State private var showHistory = false
    @State private var photoItem: PhotosPickerItem?
    @State private var speech = SpeechRecognizer()
    @State private var textBeforeVoice: String = ""
    @State private var micPulse = false
    @State private var voiceDragOffset: CGFloat = 0
    @State private var messageToReport: AIAssistantViewModel.DisplayMessage?
    private let cancelThreshold: CGFloat = 90

    // Quick suggestions change per time of day + selon le contexte réel
    // (données récentes : sommeil, streak habitudes, séance manquée). Les 1-2
    // suggestions "réactives" sont insérées en tête pour maximiser la
    // pertinence perçue au moment où l'user ouvre le chat.
    private var quickSuggestions: [(label: String, message: String, module: String?)] {
        let hour = Calendar.current.component(.hour, from: .now)
        var base: [(label: String, message: String, module: String?)]
        switch hour {
        case 5..<10:
            base = [
                ("Plan du matin", "C'est quoi ma priorité ce matin ?", nil),
                ("Calories", "Mon objectif calories pour aujourd'hui", "nutrition"),
                ("Sport", "Créer une séance pour aujourd'hui", "fitness"),
                ("Humeur", "Je ne suis pas en forme ce matin", "mind"),
            ]
        case 10..<14:
            base = [
                ("Check objectifs", "Où j'en suis sur mes objectifs ?", nil),
                ("Budget", "Analyser mes dépenses ce mois", "finance"),
                ("Focus", "J'arrive pas à me concentrer", "productivity"),
                ("Repas", "Que manger ce midi ?", "nutrition"),
            ]
        case 14..<19:
            base = [
                ("Bilan du jour", "Comment je m'en sors aujourd'hui ?", nil),
                ("Séance", "Logger ma séance de sport", "fitness"),
                ("Rappel soir", "Mets-moi un rappel ce soir", nil),
                ("Stress", "Je suis stressé cet après-midi", "mind"),
            ]
        default:
            base = [
                ("Bilan semaine", "Bilan rapide de ma semaine", nil),
                ("Sommeil", "Conseils pour mieux dormir ce soir", "sleep"),
                ("Demain", "Ma priorité pour demain", nil),
                ("Habitude", "Créer une nouvelle habitude", "productivity"),
            ]
        }
        // Insertions réactives en tête, basées sur les données réelles.
        let reactive = reactiveSuggestions()
        return reactive + base
    }

    /// Génère 0 à 2 suggestions basées sur l'état actuel (sommeil, streak, séance,
    /// score énergie). Limité pour ne pas noyer la liste.
    private func reactiveSuggestions() -> [(label: String, message: String, module: String?)] {
        var out: [(label: String, message: String, module: String?)] = []
        let ud = UserDefaults.standard
        let grp = UserDefaults(suiteName: "group.lifeos.app")

        let sleepH = ud.integer(forKey: "lastSleepHours")
        let energyScore = ud.integer(forKey: "todayEnergyScore")
        let avgStreak = grp?.integer(forKey: "habits_avg_streak") ?? 0
        let fitSummary = grp?.string(forKey: "fitness_summary_7d") ?? ""

        // Nuit courte → propose bilan récup
        if sleepH > 0, sleepH < 6 {
            out.append(("Récup", "J'ai mal dormi, comment optimiser ma journée ?", "sleep"))
        }
        // Streak fort à préserver
        if avgStreak >= 7 {
            out.append(("Streak \(avgStreak)j", "Comment garder mon streak ?", "productivity"))
        }
        // Semaine sans séance
        if !fitSummary.contains("séries") || fitSummary.contains("0 jour") {
            out.append(("Reprise sport", "Je n'ai pas fait de sport cette semaine, aide-moi", "fitness"))
        }
        // Énergie basse
        if energyScore > 0, energyScore < 50 {
            out.append(("Énergie basse", "Mon énergie est faible aujourd'hui, pourquoi ?", "mind"))
        }
        return Array(out.prefix(2))
    }

    var body: some View {
        if !disclaimerAccepted {
            CoachDisclaimerSheet(
                onAccept: { disclaimerAccepted = true },
                onDismiss: { dismiss() }
            )
        } else {
            chatContent
        }
    }

    private var chatContent: some View {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCoachPrefs = true
                        } label: {
                            Label("Personnaliser le coach", systemImage: "slider.horizontal.3")
                        }
                        Button {
                            showHistory = true
                        } label: {
                            Label("Historique", systemImage: "clock.arrow.circlepath")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Effacer la conversation", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Menu")
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
            .coachReportAlerts(
                for: $messageToReport,
                messageText: { $0.text },
                conversationID: {
                    let raw = UserDefaults.standard.string(forKey: "aiConversationID") ?? ""
                    return raw.isEmpty ? nil : raw
                }
            )
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
            .sheet(isPresented: $showCoachPrefs) {
                CoachPreferencesView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showHistory) {
                CoachHistoryView()
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
            await RemoteConfig.shared.refreshIfNeeded()
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Input section (offline banner + input bar)

    private var inputSection: some View {
        VStack(spacing: 0) {
            coachDownBanner
            if vm.isServerOffline {
                offlineBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputArea
        }
        .background(Theme.bg)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: vm.isServerOffline)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: serverStatus.coach)
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
                        AIAssistantMessageRow(
                            message: msg,
                            accent: accent,
                            reveal: msg.id == vm.revealID,
                            onReport: msg.role == "assistant" && !msg.isThinking
                                ? { messageToReport = msg }
                                : nil,
                            onLike: msg.role == "assistant" && !msg.isThinking
                                ? { vm.recordLike(for: msg) }
                                : nil,
                            onDislike: msg.role == "assistant" && !msg.isThinking
                                ? { vm.recordDislike(for: msg) }
                                : nil
                        )
                        .id(msg.id)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Réponse en cours de streaming (mise à jour token par token)
                    if let streamed = vm.streamingText, !streamed.isEmpty {
                        AIAssistantMessageRow(message: .streaming(CoachTextCleaner.clean(streamed)), accent: accent)
                            .id("streaming")
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Chips de réponse rapide sous le dernier message assistant
                    // (uniquement si pas en train de charger ni de streamer, et si
                    // le dernier message est bien du coach + génère des suggestions).
                    if !vm.isLoading, vm.streamingText == nil,
                       let last = vm.messages.last, last.role == "assistant", !last.isThinking,
                       let chips = ChatSuggestionBuilder.suggestions(for: last.text) {
                        ChatQuickReplies(suggestions: chips, accent: accent) { text in
                            vm.send(text: text)
                        }
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }

                    // Quick suggestions — cachées après l'envoi d'un message,
                    // réapparaissent après 1 h sans nouveau message. TimelineView
                    // force une réévaluation toutes les 60 s.
                    if !vm.isLoading {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            if shouldShowSuggestions(at: context.date) {
                                quickSuggestionsRow
                                    .padding(.top, 8)
                                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                            }
                        }
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
                    .font(.caption)
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

            // Bouton « Ajouter » — flux guidé (tâche, complément, course, aliment, habitude, note + rappel)
            Button {
                Haptics.tap()
                vm.addFlowKind = .task; vm.addFlowPrefill = ""; vm.showAddFlow = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 17, weight: .bold))
                    Text("Ajouter quelque chose").font(.system(size: 15, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).opacity(0.6)
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
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
                if speech.isRecording {
                    WaveformView(level: speech.audioLevel, accent: Color(hex: 0xF1746C))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                } else {
                    let loading = vm.isLoading
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(loading ? Color.secondary : accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(loading)
                    .accessibilityLabel("Ajouter une photo")
                    .onChange(of: photoItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let ui = UIImage(data: data) {
                                vm.analyzeImage(ui)
                            }
                            photoItem = nil
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                TextField(recordingPlaceholder, text: $vm.inputText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { vm.send() }
                    .disabled(speech.isRecording)
                    .opacity(speech.isRecording ? max(0.3, 1 - abs(voiceDragOffset) / cancelThreshold) : 1)
                    .onChange(of: speech.transcript) { _, new in
                        guard speech.isRecording else { return }
                        if textBeforeVoice.isEmpty {
                            vm.inputText = new
                        } else if new.isEmpty {
                            vm.inputText = textBeforeVoice
                        } else {
                            vm.inputText = textBeforeVoice + " " + new
                        }
                    }

                sendOrMicButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.bg)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: speech.isRecording)
            .overlay(alignment: .top) {
                if let msg = speech.errorMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: 0xF1746C), in: Capsule())
                        .offset(y: -18)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if speech.isRecording {
                    cancelHint
                        .offset(y: -22)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var recordingPlaceholder: String {
        guard speech.isRecording else { return "Dis-moi quelque chose…" }
        return speech.locale.identifier.hasPrefix("en") ? "Listening…" : "J'écoute…"
    }

    private var cancelHint: some View {
        let progress = min(1, abs(voiceDragOffset) / cancelThreshold)
        return HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
            Text(progress >= 1 ? "Relâche pour annuler" : "Glisse pour annuler")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(progress >= 1 ? Color(hex: 0xF1746C) : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .opacity(1 - progress * 0.3)
    }

    @ViewBuilder private var sendOrMicButton: some View {
        if speech.isRecording {
            recordingStopButton
        } else if canSend {
            Button { vm.send() } label: {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 36, height: 36)
                    Image(systemName: vm.isLoading ? "ellipsis" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(vm.isLoading)
            .accessibilityLabel("Envoyer")
        } else {
            Button { startVoice() } label: {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(vm.isLoading)
            .accessibilityLabel("Message vocal")
        }
    }

    private var recordingStopButton: some View {
        let progress = min(1, abs(voiceDragOffset) / cancelThreshold)
        return ZStack {
            Circle()
                .fill(Color(hex: 0xF1746C).opacity(micPulse ? 0.35 : 0.15))
                .frame(width: 52, height: 52)
                .scaleEffect(micPulse ? 1.15 : 1.0)
            Circle()
                .fill(Color(hex: 0xF1746C))
                .frame(width: 36, height: 36)
            Image(systemName: progress >= 1 ? "xmark" : "stop.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: micPulse)
        .offset(x: max(-cancelThreshold, voiceDragOffset))
        .scaleEffect(1 - progress * 0.15)
        .contentShape(Circle().size(width: 60, height: 60))
        .onTapGesture { stopVoiceAndSend() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let dx = min(0, value.translation.width)
                    voiceDragOffset = dx
                    if abs(dx) >= cancelThreshold, micPulse {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        micPulse = false
                    } else if abs(dx) < cancelThreshold, !micPulse {
                        micPulse = true
                    }
                }
                .onEnded { value in
                    let dx = min(0, value.translation.width)
                    if abs(dx) >= cancelThreshold {
                        cancelVoice()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            voiceDragOffset = 0
                        }
                        stopVoiceAndSend()
                    }
                }
        )
        .onAppear { micPulse = true }
        .onDisappear { micPulse = false }
        .accessibilityLabel("Terminer et envoyer, glisser pour annuler")
    }

    private func startVoice() {
        Task {
            let ok = await speech.requestAuthorization()
            guard ok else { return }
            speech.setLanguage(preferredSpeechLocale())
            textBeforeVoice = vm.inputText.trimmingCharacters(in: .whitespaces)
            voiceDragOffset = 0
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            speech.start()
            inputFocused = false
        }
    }

    private func stopVoiceAndSend() {
        speech.stop()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let trimmed = vm.inputText.trimmingCharacters(in: .whitespaces)
        textBeforeVoice = ""
        voiceDragOffset = 0
        guard !trimmed.isEmpty, !vm.isLoading else { return }
        vm.send()
    }

    private func cancelVoice() {
        speech.cancel()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // restaure le texte pré-enregistrement
        vm.inputText = textBeforeVoice
        textBeforeVoice = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            voiceDragOffset = 0
        }
    }

    private func preferredSpeechLocale() -> String {
        let raw = Locale.preferredLanguages.first ?? "fr-FR"
        let code = String(raw.prefix(2)).lowercased()
        switch code {
        case "en": return "en-US"
        case "es": return "es-ES"
        case "de": return "de-DE"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        default:   return "fr-FR"
        }
    }

    @ObservedObject private var serverStatus = ServerStatusMonitor.shared

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty
            && !vm.isLoading
            && serverStatus.canSendChatMessages
    }

    /// Bannière affichée en haut du chat quand le coach est indisponible.
    /// Se met à jour automatiquement via l'ObservedObject serverStatus.
    @ViewBuilder private var coachDownBanner: some View {
        switch serverStatus.coach {
        case .online, .unknown:
            EmptyView()
        case .backendDown:
            coachBannerContent(
                icon: "moon.zzz.fill",
                title: "Le coach dort",
                subtitle: "Serveur en veille — réessaie dans 30 s"
            )
        case .llmDown:
            coachBannerContent(
                icon: "exclamationmark.triangle.fill",
                title: "Coach indisponible",
                subtitle: "Service momentanément en panne — réessaie plus tard"
            )
        }
    }

    private func coachBannerContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(hex: 0xE0A23C), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                serverStatus.pingNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xE0A23C))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xE0A23C).opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vérifier à nouveau")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0xE0A23C).opacity(0.08))
        .overlay(
            Rectangle().fill(Color(hex: 0xE0A23C).opacity(0.4)).frame(height: 0.5),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Affiche les suggestions rapides tant que l'utilisateur n'a pas encore parlé,
    /// ou après 1 h de silence depuis son dernier message.
    private func shouldShowSuggestions(at now: Date) -> Bool {
        guard let lastUserMsg = vm.messages.last(where: { $0.role == "user" }) else {
            return true // aucun message envoyé → visible
        }
        return now.timeIntervalSince(lastUserMsg.date) >= 3600
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
        do { try ctx.save() } catch { AppLog.data.error("clearHistory failed: \(error.localizedDescription, privacy: .public)") }
        vm.messages = []
        UserDefaults.standard.removeObject(forKey: "aiConversationID")
        UserDefaults.standard.removeObject(forKey: "aiKnownModulesRaw")
        vm.loadHistory()
    }

}

// MARK: - MessageRow → extrait dans LifeOS/Shared/AIAssistantMessageRow.swift
// Utiliser `AIAssistantMessageRow(message:accent:reveal:onReport:)` à la place.

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
                        .font(.caption)
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

// MARK: - Composants extraits
// ThinkingIndicator, TypewriterText, CoachTextCleaner, PressScaleButtonStyle,
// WaveformView → LifeOS/Shared/AIAssistantComponents.swift
