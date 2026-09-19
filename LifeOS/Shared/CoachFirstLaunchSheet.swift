import SwiftUI

/// Écran d'accueil au premier lancement du chat coach.
///
/// Design volontairement épuré : titre court + grille de tuiles marques,
/// navigation en push (pas de sheets en cascade) pour éviter les bugs de
/// présentation.
///
/// Flow :
///   1. L'user voit la grille des marques (Claude, ChatGPT, Gemini, Mistral,
///      Grok, DeepSeek, Llama, OpenRouter) + Apple Intelligence si dispo
///   2. Tap sur une tuile → push vers l'écran de clé (QuickKeyEntry)
///   3. Clé validée → dismiss + onDone
///
/// Aucun texte technique, aucun choix de modèle. L'user pense en marque.
struct CoachFirstLaunchSheet: View {

    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.coachOnboardingCompleted) private var completed = false
    @State private var appleAvailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    grid
                    if appleAvailable {
                        appleOption
                    }
                    laterButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        completed = true
                        onDone()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                appleAvailable = AppleIntelligenceProvider().availability.isAvailable
            }
        }
    }

    // MARK: - Header (épuré)

    private var header: some View {
        VStack(spacing: 10) {
            Text("Choisis ton coach")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Une seule question : à quelle IA veux-tu le brancher ?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
    }

    // MARK: - Grille (2 colonnes, cards épurées)

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(orderedSlots, id: \.self) { slot in
                NavigationLink {
                    QuickKeyEntry(slot: slot) {
                        completed = true
                        AIProviderPreference.shared.setPreferredProviderID(slot.providerID)
                        onDone()
                    }
                } label: {
                    tile(for: slot)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96))
            }
        }
    }

    /// Ordre affichage : OpenRouter en premier (recommandé, 1 clé = 200 modèles),
    /// puis les 3 stars du grand public, puis les autres.
    private let orderedSlots: [AIProviderCredentials.Slot] = [
        .openrouter, .openai, .anthropic, .gemini, .mistral, .groq, .deepseek, .xai,
    ]

    private func tile(for slot: AIProviderCredentials.Slot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: slot.publicIconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Color(hex: slot.publicAccentHex),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                Spacer()
                if slot == .openrouter {
                    Text("Reco")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.publicBrandName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text(slot.publicTagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 140, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Apple Intelligence (option gratuite en dessous de la grille)

    private var appleOption: some View {
        Button {
            AIProviderPreference.shared.setPreferredProviderID("apple.intelligence.on-device")
            completed = true
            onDone()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "iphone")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Apple Intelligence")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Gratuit")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Text("100% sur ton iPhone, aucune clé à gérer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
    }

    // MARK: - Bouton "Plus tard" discret

    private var laterButton: some View {
        Button {
            completed = true
            onDone()
        } label: {
            Text("Je choisirai plus tard")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick key entry (colle + teste + save)

/// Écran compact pour coller sa clé et la valider en 1 étape.
/// Poussé dans la NavigationStack au tap d'une tuile (pas en sheet =
/// évite le bug de double-présentation).
private struct QuickKeyEntry: View {

    let slot: AIProviderCredentials.Slot
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var key: String = ""
    @State private var testing = false
    @State private var errorMsg: String?
    @State private var success = false
    @State private var pastebardBannerVisible = false

    var body: some View {
        Form {
            Section {
                ProviderKeyHelpView(slot: slot) { pastedKey in
                    key = pastedKey
                    Task { await saveAndTest() }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .listRowBackground(Color.clear)
            }

            if pastebardBannerVisible {
                Section {
                    clipboardBanner
                }
            }

            Section {
                SecureField("Ou colle ta clé ici", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let errorMsg {
                    Label(errorMsg, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                if success {
                    Label("Clé validée. Ton coach est prêt.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    HStack {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(testing ? "Test en cours…" : "Enregistrer et tester")
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || testing)
            }
        }
        .navigationTitle(slot.publicBrandName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { detectClipboardKey() }
        }
        .onAppear { detectClipboardKey() }
    }

    // MARK: - Clipboard banner

    @ViewBuilder
    private var clipboardBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Clé \(slot.publicBrandName) détectée")
                    .font(.subheadline.weight(.semibold))
                Text("Une clé est dans ton presse-papier. L'utiliser ?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        useClipboardKey()
                    } label: {
                        Text("Oui, l'utiliser")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button("Ignorer") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            pastebardBannerVisible = false
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detectClipboardKey() {
        guard key.isEmpty else { return }
        let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, raw.count >= slot.minLength else {
            pastebardBannerVisible = false
            return
        }
        if let prefix = slot.expectedPrefix, !raw.hasPrefix(prefix) {
            pastebardBannerVisible = false
            return
        }
        withAnimation(.easeOut(duration: 0.25)) { pastebardBannerVisible = true }
    }

    private func useClipboardKey() {
        let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return }
        key = raw
        pastebardBannerVisible = false
        Task { await saveAndTest() }
    }

    private func saveAndTest() async {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        errorMsg = nil
        success = false

        if let err = AIProviderCredentials.shared.validate(trimmed, for: slot) {
            errorMsg = err.localizedDescription
            return
        }

        testing = true
        _ = AIProviderCredentials.shared.setKey(trimmed, for: slot)

        let response = await pingProvider(slot: slot)
        testing = false

        if response.isSuccess {
            success = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onSaved()
            }
        } else if case .unavailable(.invalidCredentials) = response.error {
            errorMsg = "Clé refusée par \(slot.publicBrandName). Vérifie qu'elle est bien copiée."
            AIProviderCredentials.shared.deleteKey(for: slot)
        } else if case .rateLimited = response.error {
            errorMsg = "Rate limit — mais ta clé marche. Tu peux enregistrer."
            success = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onSaved()
            }
        } else if case .networkError = response.error {
            errorMsg = "Pas de réseau. Vérifie ta connexion et retente."
            AIProviderCredentials.shared.deleteKey(for: slot)
        } else {
            errorMsg = "Erreur de connexion à \(slot.publicBrandName). Retente ou choisis autre chose."
            AIProviderCredentials.shared.deleteKey(for: slot)
        }
    }

    private func pingProvider(slot: AIProviderCredentials.Slot) async -> AIResponse {
        let request = AIRequest(
            messages: [.system("Réponds uniquement 'ok'."), .user("ping")],
            maxOutputTokens: 5,
            timeout: 12
        )
        switch slot {
        case .openai:     return await OpenAIProvider().complete(request)
        case .anthropic:  return await AnthropicProvider().complete(request)
        case .mistral:    return await MistralProvider().complete(request)
        case .gemini:     return await GeminiProvider().complete(request)
        case .openrouter: return await OpenRouterProvider().complete(request)
        case .deepseek:   return await DeepSeekProvider().complete(request)
        case .groq:       return await GroqProvider().complete(request)
        case .xai:        return await XAIProvider().complete(request)
        }
    }
}
