import SwiftUI

// MARK: - Chat Message Model

struct ModuleChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()
    var isThinking = false
}

// MARK: - ModuleChatView

struct ModuleChatView: View {
    let module: String
    let moduleTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @AppStorage("appTheme") private var appThemeRaw = "classic"
    @AppStorage("coachDisclaimerAccepted") private var disclaimerAccepted = false
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }

    @State private var messages: [ModuleChatMessage] = []
    @State private var inputText = ""
    @State private var conversationID: String? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var isServerOffline = false
    @State private var goalsBadge = false
    @State private var configBadge = false
    @State private var messageToReport: ModuleChatMessage? = nil
    @State private var reportConfirmed = false
    @FocusState private var inputFocused: Bool

    private let suggestedMessages: [String]

    init(module: String, moduleTitle: String) {
        self.module = module
        self.moduleTitle = moduleTitle
        self.suggestedMessages = Self.suggestions(for: module)
    }

    var body: some View {
        Group {
            if !disclaimerAccepted {
                CoachDisclaimerSheet(
                    onAccept: { disclaimerAccepted = true },
                    onDismiss: { dismiss() }
                )
            } else {
                chatContent
            }
        }
    }

    private var chatContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesScrollView
                if isServerOffline {
                    moduleChatOfflineBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                inputBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Personnaliser \(moduleTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .alert("Erreur", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Signaler cette réponse ?",
                isPresented: Binding(
                    get: { messageToReport != nil },
                    set: { if !$0 { messageToReport = nil } }
                ),
                presenting: messageToReport
            ) { msg in
                Button("Signaler", role: .destructive) { submitReport(msg) }
                Button("Annuler", role: .cancel) { messageToReport = nil }
            } message: { _ in
                Text("Nous relisons chaque signalement pour bloquer les réponses inappropriées.")
            }
            .alert("Signalement envoyé", isPresented: $reportConfirmed) {
                Button("OK") { reportConfirmed = false }
            } message: {
                Text("Merci, nous allons relire cette réponse.")
            }
        }
        .onAppear {
            sendWelcomeMessage()
            Task { await RemoteConfig.shared.refreshIfNeeded() }
        }
    }

    // MARK: - Messages Scroll

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        suggestionsView
                    }
                    ForEach(messages) { msg in
                        MessageBubble(
                            message: msg,
                            accentColor: appTheme.accent,
                            onReport: msg.role == .assistant && !msg.isThinking
                                ? { messageToReport = msg }
                                : nil
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Suggested messages

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commence par …")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            ForEach(suggestedMessages, id: \.self) { suggestion in
                Button {
                    inputText = suggestion
                    sendMessage()
                } label: {
                    Text(suggestion)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.cardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(appTheme.accent.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Dis-moi ce que tu veux…", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($inputFocused)
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: isLoading ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? appTheme.accent : Color.secondary.opacity(0.3))
                    .symbolEffect(.bounce, value: isLoading)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Theme.card
                .shadow(color: .black.opacity(0.05), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool { !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading }

    private var moduleChatOfflineBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text("Serveur inaccessible")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                isServerOffline = false
                sendMessage()
            } label: {
                Text("Reessayer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Send Logic

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        inputFocused = false
        Haptics.tap()

        messages.append(ModuleChatMessage(role: .user, text: text))

        // Add typing indicator
        let thinking = ModuleChatMessage(role: .assistant, text: "…", isThinking: true)
        messages.append(thinking)
        isLoading = true

        Task {
            do {
                let response = try await AgentAPI.shared.chat(
                    message: text,
                    module: module,
                    conversationID: conversationID
                )
                conversationID = response.conversation_id

                // Replace thinking bubble
                await MainActor.run {
                    messages.removeAll { $0.isThinking }
                    messages.append(ModuleChatMessage(role: .assistant, text: response.reply))
                    isServerOffline = false

                    if response.module_config_updated {
                        configBadge = true
                        Haptics.success()
                    }
                    if response.goals_updated {
                        goalsBadge = true
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.removeAll { $0.isThinking }
                    if let apiErr = error as? AgentAPIError, case .networkError = apiErr {
                        isServerOffline = true
                    } else {
                        errorMessage = (error as? AgentAPIError)?.errorDescription ?? error.localizedDescription
                    }
                    isLoading = false
                }
            }
        }
    }

    private func submitReport(_ msg: ModuleChatMessage) {
        let content = msg.text
        let convID = conversationID
        messageToReport = nil
        Haptics.tap()
        Task {
            try? await AgentAPI.shared.reportMessage(
                conversationID: convID,
                messageContent: content,
                reason: "user_flagged"
            )
            await MainActor.run { reportConfirmed = true }
        }
    }

    private func sendWelcomeMessage() {
        let welcome = ModuleChatMessage(
            role: .assistant,
            text: "Bonjour ! Je suis là pour t'aider à personnaliser ton module \(moduleTitle). Dis-moi tes objectifs, ta fréquence, ou ce que tu veux améliorer."
        )
        messages.append(welcome)
    }

    // MARK: - Suggestions per module

    private static func suggestions(for module: String) -> [String] {
        switch module {
        case "sport":
            return [
                "Je veux m'entraîner 4x par semaine",
                "Mon objectif : perdre 5 kg en 3 mois",
                "Ajoute un objectif de course à pied 10 km",
            ]
        case "nutrition":
            return [
                "Mon objectif calorique est 1800 kcal par jour",
                "Je suis un régime végétarien",
                "Je veux boire 2,5 L d'eau par jour",
            ]
        case "finance":
            return [
                "Mon salaire mensuel est 2500 €",
                "Je veux épargner 20% de mes revenus",
                "Montre-moi une simulation de placement modéré",
            ]
        case "mobility":
            return [
                "Mon réservoir fait 50 L, conso 7L/100km",
                "J'ai fait 120 km cette semaine",
                "Quel est mon carburant restant estimé ?",
            ]
        case "productivity":
            return [
                "Je veux valider 5 habitudes par jour",
                "Objectif : 2h de focus par matin",
                "Rappelle-moi mes habitudes à 19h",
            ]
        default:
            return [
                "Comment personnaliser ce module ?",
                "Ajoute un objectif pour ce module",
            ]
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ModuleChatMessage
    let accentColor: Color
    var onReport: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 48) }

            if message.isThinking {
                ThinkingDots()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? accentColor
                            : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                    .contextMenu {
                        if let onReport {
                            Button(role: .destructive, action: onReport) {
                                Label("Signaler cette réponse", systemImage: "flag")
                            }
                        }
                    }
            }

            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .transition(.asymmetric(
            insertion: .move(edge: message.role == .user ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - Thinking dots animation

private struct ThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.4 : 1.0)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .onAppear { phase = 1 }
    }
}
