import SwiftUI

/// Écran d'accueil au tout premier lancement du chat coach.
///
/// L'utilisateur choisit comment son coach va fonctionner :
///   1. Ma propre clé — l'user colle une clé d'un provider (OpenRouter, OpenAI…)
///   2. Apple Intelligence — 100% local, gratuit, sur iPhone compatible
///   3. LifeOS Premium — bouton grisé, "bientôt dispo"
///   4. Continuer sans coach — bascule sur le coach local règles (offline)
///
/// L'onboarding est "soft" : rien n'oblige à choisir un provider payant. L'user
/// peut vivre l'app avec le coach local ou Apple Intelligence.
///
/// Une fois un choix fait (ou "continuer sans"), le flag
/// `coachOnboardingCompleted` empêche l'écran de réapparaître.
struct CoachFirstLaunchSheet: View {

    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showProviderPicker = false
    @State private var showKeyEditor = false
    @State private var selectedSlot: AIProviderCredentials.Slot?
    @AppStorage(AppStorageKeys.coachOnboardingCompleted) private var completed = false
    @State private var appleAvailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    choices
                    footerNote
                }
                .padding(20)
                .padding(.top, 8)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") {
                        completed = true
                        onDone()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                appleAvailable = AppleIntelligenceProvider().availability.isAvailable
            }
            .sheet(isPresented: $showProviderPicker) {
                ProviderQuickPicker { slot in
                    selectedSlot = slot
                    showProviderPicker = false
                    // Petit délai pour éviter double-sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showKeyEditor = true
                    }
                }
            }
            .sheet(isPresented: $showKeyEditor) {
                if let slot = selectedSlot {
                    QuickKeyEntry(slot: slot) {
                        completed = true
                        AIProviderPreference.shared.setPreferredProviderID(slot.providerID)
                        showKeyEditor = false
                        onDone()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("Choisis ton coach")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
            Text("Ton coach écoute tes données de vie et t'aide au quotidien. Tu choisis quel moteur il utilise.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Choix

    private var choices: some View {
        VStack(spacing: 12) {
            // Option 1 — Ma propre clé (mise en avant)
            choiceCard(
                icon: "key.fill",
                iconColor: Color.accentColor,
                title: "J'ai déjà une clé",
                subtitle: "Colle une clé OpenRouter, OpenAI, Claude, Mistral… Ton compte, tes tokens, ta facture.",
                badge: "Recommandé",
                action: { showProviderPicker = true }
            )

            // Option 2 — Apple Intelligence (si dispo)
            if appleAvailable {
                choiceCard(
                    icon: "iphone",
                    iconColor: .green,
                    title: "Apple Intelligence",
                    subtitle: "100% sur ton iPhone, gratuit, aucune donnée ne sort. Latence quasi instantanée.",
                    badge: "Gratuit",
                    action: {
                        AIProviderPreference.shared.setPreferredProviderID("apple.intelligence.on-device")
                        completed = true
                        onDone()
                    }
                )
            }

            // Option 3 — LifeOS Premium (bientôt)
            choiceCard(
                icon: "star.fill",
                iconColor: .yellow,
                title: "LifeOS Premium",
                subtitle: "Bientôt : coach illimité inclus dans l'abonnement, aucune clé à gérer.",
                badge: "Bientôt",
                disabled: true,
                action: { }
            )

            // Option 4 — Continuer sans clé
            Button {
                completed = true
                onDone()
            } label: {
                HStack {
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                    Text("Continuer sans coach cloud")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Card générique

    private func choiceCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        badge: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(disabled ? Color.secondary : iconColor)
                    .frame(width: 36, height: 36)
                    .background(
                        (disabled ? Color.secondary : iconColor).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(disabled ? .secondary : .primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    (disabled ? Color.secondary : iconColor).opacity(0.16),
                                    in: Capsule()
                                )
                                .foregroundStyle(disabled ? Color.secondary : iconColor)
                        }
                        Spacer()
                        if !disabled {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1.0)
    }

    // MARK: - Footer

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sécurité et confidentialité")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Ta clé est stockée dans le Trousseau iOS. Elle n'est envoyée qu'au provider que tu choisis. LifeOS ne voit rien.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

// MARK: - Provider quick picker (grille de tuiles)

/// Grille compacte des providers cloud pour choisir vite le sien.
private struct ProviderQuickPicker: View {

    let onPick: (AIProviderCredentials.Slot) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Ordre affichage : OpenRouter en tête (recommandé grand public),
    /// puis les gros, puis les niches.
    private let ordered: [AIProviderCredentials.Slot] = [
        .openrouter, .openai, .anthropic, .mistral, .gemini, .deepseek, .groq, .xai,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ordered, id: \.self) { slot in
                        tile(for: slot)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Choisis un provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func tile(for slot: AIProviderCredentials.Slot) -> some View {
        Button {
            onPick(slot)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(slot.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    if slot == .openrouter {
                        Text("Reco")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(shortDescription(for: slot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 100, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Baseline courte affichée sur la tuile — ce que l'user gagne à le choisir.
    private func shortDescription(for slot: AIProviderCredentials.Slot) -> String {
        switch slot {
        case .openrouter: return "1 clé, 200+ modèles au choix. Idéal pour tester."
        case .openai:     return "GPT-4o mini. Standard fiable et populaire."
        case .anthropic:  return "Claude Haiku. Réponses nuancées, longues."
        case .mistral:    return "Français, RGPD ok. Rapide et pas cher."
        case .gemini:     return "Google. Flash rapide, quota gratuit."
        case .deepseek:   return "Ultra pas cher. Fort en raisonnement."
        case .groq:       return "Vitesse extrême sur Llama. Free tier."
        case .xai:        return "Grok. Intégration X, humour."
        }
    }
}

// MARK: - Quick key entry (colle + teste + save)

/// Écran compact pour coller sa clé et la valider en 1 étape.
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
        NavigationStack {
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
            .navigationTitle("Ajouter ta clé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    detectClipboardKey()
                }
            }
            .onAppear { detectClipboardKey() }
        }
    }

    // MARK: - Clipboard banner (détection auto au retour d'app)

    /// Bannière affichée en tête de Form si le presse-papier contient une clé
    /// avec le préfixe attendu par le provider ET que le champ est vide.
    /// Sur "Oui" → remplit + déclenche le test. Sur "Non" → cache la bannière.
    @ViewBuilder
    private var clipboardBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Clé \(slot.displayName) détectée")
                    .font(.subheadline.weight(.semibold))
                Text("Une clé est dans ton presse-papier. Utiliser cette clé ?")
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

    /// Vérifie le presse-papier et affiche la bannière si une clé plausible
    /// pour ce provider y est présente. Aucun log du contenu presse-papier.
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
        withAnimation(.easeOut(duration: 0.25)) {
            pastebardBannerVisible = true
        }
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
        // Save d'abord (le provider lit dans le Keychain)
        _ = AIProviderCredentials.shared.setKey(trimmed, for: slot)

        // Ping léger
        let response = await pingProvider(slot: slot)
        testing = false

        if response.isSuccess {
            success = true
            // Petit délai visuel pour que l'user voie le "validé", puis on ferme.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onSaved()
            }
        } else if case .unavailable(.invalidCredentials) = response.error {
            errorMsg = "Clé refusée par \(slot.displayName). Vérifie qu'elle est bien copiée."
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
            errorMsg = "Erreur de connexion à \(slot.displayName). Retente ou choisis un autre provider."
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
