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

    @AppStorage("aiConversationID") private var conversationID = ""
    @AppStorage("aiFirstLaunchDone") private var firstLaunchDone = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("userGender") private var userGender = ""
    @AppStorage("onboardingGoalsRaw") private var onboardingGoalsRaw = ""
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @AppStorage("aiKnownModulesRaw") private var aiKnownModulesRaw = ""
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("appTheme") private var appThemeRaw = "classic"

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
            DisplayMessage(id: UUID(), role: "assistant", text: "…", date: .now, actions: [])
        }

        private init(id: UUID, role: String, text: String, date: Date, actions: [AIAction]) {
            self.id = id
            self.role = role
            self.text = text
            self.date = date
            self.actions = actions
        }
    }

    func loadHistory() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<AIMessage>(sortBy: [SortDescriptor(\.date)])
        let stored = (try? ctx.fetch(descriptor)) ?? []
        messages = stored.map { DisplayMessage(from: $0) }

        if !firstLaunchDone {
            triggerWelcome()
        } else {
            checkForNewModules()
            checkAbandonedChallenges()
        }
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
        // Basé sur un backend distant non déployé → désactivé (coach 100% on-device).
    }

    private func triggerProactive(prompt: String) {
        guard !isLoading, prompt.contains("[NOUVEAU_MODULE]") else { return }
        // Message proactif local quand l'utilisateur vient d'ajouter un module.
        appendThinking()
        isLoading = true
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            removeThinking()
            appendAssistantMessage(
                "Nouveau module activé 💪 Je l'ai pris en compte. Dis-moi ce que tu veux mettre en place dedans (une habitude, un objectif, un rappel) et je m'en occupe.",
                actions: [])
            isLoading = false
        }
    }

    func send(text: String? = nil, module: String? = nil) {
        let content = (text ?? inputText).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty, !isLoading else { return }
        inputText = ""
        Haptics.tap()

        appendUserMessage(content)
        appendThinking()
        isLoading = true

        // Coach 100% ON-DEVICE (aucun serveur) — lit les vraies données + agit.
        Task {
            // Petit délai pour l'effet « réflexion » naturel.
            try? await Task.sleep(nanoseconds: 350_000_000)
            let reply: String
            if let ctx = modelContext {
                reply = LocalCoach.respond(to: content, ctx: ctx)
            } else {
                reply = "Je suis prêt, mais je n'ai pas encore accès à tes données. Réessaie dans un instant."
            }
            removeThinking()
            appendAssistantMessage(reply, actions: [])
            isLoading = false
        }
    }

    /// Analyse une image on-device (Vision) et route vers la bonne catégorie — sans backend.
    func analyzeImage(_ image: UIImage) {
        guard !isLoading else { return }
        Haptics.tap()
        appendUserMessage("📷 Photo envoyée")
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

        let wake = String(format: "%02d:%02d", wakeupHour, wakeupMinute)

        let prompt = """
        [PREMIER_LANCEMENT]
        Prénom: \(userName.isEmpty ? "non renseigné" : userName)
        Genre: \(userGender.isEmpty ? "non renseigné" : userGender)
        Objectifs déclarés: \(goals.isEmpty ? "non renseignés" : goals)
        Modules activés: \(modules.isEmpty ? "aucun" : modules)
        Heure de réveil: \(wake)
        """

        _ = prompt   // le contexte reste dispo si un LLM est branché plus tard
        appendThinking()
        isLoading = true
        firstLaunchDone = true
        aiKnownModulesRaw = recommendedModulesRaw

        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            removeThinking()
            appendAssistantMessage(LocalCoach.welcome(name: userName), actions: [])
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
                try? ctx.save()
            }
        case .scheduleReminder:
            if let body = action.reminderBody {
                let delay = TimeInterval(action.delaySeconds ?? 3600)
                scheduleLocalNotification(title: "LifeOS", body: body, delay: delay)
            }
        case .createChallenge:
            if let title = action.title, let days = action.durationDays {
                scheduleLocalNotification(
                    title: "Défi démarré",
                    body: "\(title) — \(days) jours. Tu peux le faire !",
                    delay: 2
                )
            }
        case .addModule:
            if let module = action.module {
                addModuleToProfile(module)
            }
        case .removeModule:
            if let module = action.module {
                removeModuleFromProfile(module)
            }
        case .openModule, .updateConfig:
            break
        }
    }

    private func addModuleToProfile(_ module: String) {
        var current = Set(recommendedModulesRaw.split(separator: ",").map(String.init))
        guard !current.contains(module) else { return }
        current.insert(module)
        recommendedModulesRaw = current.joined(separator: ",")
        aiKnownModulesRaw = recommendedModulesRaw
    }

    private func removeModuleFromProfile(_ module: String) {
        var current = Set(recommendedModulesRaw.split(separator: ",").map(String.init))
        guard current.contains(module) else { return }
        current.remove(module)
        recommendedModulesRaw = current.joined(separator: ",")
        aiKnownModulesRaw = recommendedModulesRaw
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
        try? modelContext?.save()
        messages.append(DisplayMessage(from: msg))
    }

    private func appendAssistantMessage(_ text: String, actions: [AIAction]) {
        let actionsData = try? JSONEncoder().encode(actions)
        let msg = AIMessage(role: "assistant", text: text, actions: actionsData)
        modelContext?.insert(msg)
        try? modelContext?.save()
        messages.append(DisplayMessage(from: msg))
    }

    private func appendThinking() {
        messages.append(.thinking())
    }

    private func removeThinking() {
        messages.removeAll { $0.isThinking }
    }
}

// MARK: - Import for notifications

import UserNotifications

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
            let reply = "🍽️ On dirait : \(g.name) (~\(g.kcal) kcal). Je l'ai ajouté à ton journal du jour — tu peux l'ajuster dans Nutrition."
            return (.food(g), reply, [AIAction(type: .openModule, title: "Nutrition", module: "nutrition")])
        }

        // 2) Beaucoup de texte → document / justificatif (pôle Admin)
        let text = await recognizeText(image)
        if text.count >= 20 {
            let snippet = String(text.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let reply = "📄 J'ai lu du texte sur cette image :\n« \(snippet)… »\nÇa ressemble à un document — tu peux le classer dans Documents / Admin."
            return (.document(text), reply, [AIAction(type: .openModule, title: "Documents", module: "admin")])
        }

        // 3) Sinon : description brute + suggestion
        let top = labels.first?.label.split(separator: ",").first.map(String.init)?.capitalized ?? "quelque chose"
        let reply = "🔍 J'ai analysé ta photo : \(top). Dis-moi ce que tu veux en faire (l'ajouter quelque part, créer un rappel…)."
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
            ZStack {
                Theme.screenBG

                VStack(spacing: 0) {
                    messagesArea
                    inputArea
                }
            }
            .navigationTitle("Assistant IA")
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
                        MessageRow(message: msg, accent: accent)
                            .id(msg.id)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Quick suggestions — toujours visibles sauf pendant le chargement
                    if !vm.isLoading {
                        quickSuggestionsRow
                            .padding(.top, 8)
                    }

                    Color.clear.frame(height: 16).id("bottom")
                }
                .padding(.top, 16)
            }
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
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
                            .padding(.vertical, 15)
                            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 0.5))
                            .softElevation()
                    }
                    .buttonStyle(PressableButtonStyle())
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
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(vm.isLoading ? Color.secondary : accent)
                        .frame(width: 34, height: 34)
                }
                .disabled(vm.isLoading)
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

                TextField("Dis-moi quelque chose…", text: $vm.inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                    .focused($inputFocused)
                    .onSubmit { vm.send() }

                Button { vm.send() } label: {
                    ZStack {
                        Circle()
                            .fill(canSend ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                            .frame(width: 38, height: 38)
                            .shadow(color: canSend ? accent.opacity(0.35) : .clear, radius: 6, y: 2)
                        Image(systemName: vm.isLoading ? "ellipsis" : "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canSend ? .white : .secondary)
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSend)
                .animation(.spring(duration: 0.2), value: canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.isGlassActive ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.bg))
        }
    }

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isLoading
    }

    // MARK: - Clear

    private func clearHistory() {
        let descriptor = FetchDescriptor<AIMessage>()
        let all = (try? ctx.fetch(descriptor)) ?? []
        all.forEach { ctx.delete($0) }
        try? ctx.save()
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

    var isUser: Bool { message.role == "user" }

    /// Rend le markdown inline (**gras**, sauts de ligne) d'une String dynamique.
    static func markdown(_ s: String) -> AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 56) }

                Group {
                    if message.isThinking {
                        ThinkingIndicator()
                    } else {
                        Text(Self.markdown(message.text))
                            .font(.system(size: 15))
                            .foregroundStyle(isUser ? .white : .primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(accent.gradient) : Theme.cardFill,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    if !isUser {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 0.5)
                    }
                }
                .softElevation()

                if !isUser { Spacer(minLength: 56) }
            }

            // Action chips (after assistant message)
            if !isUser && !message.actions.isEmpty {
                actionChips
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: isUser ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
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
        case .addModule: return "plus.circle"
        case .removeModule: return "minus.circle"
        }
    }
}

// MARK: - Thinking indicator

private struct ThinkingIndicator: View {
    @State private var active = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(active ? 1.35 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}
