import SwiftUI

/// Écran Réglages "Moteur du coach" — choix + configuration du provider.
///
/// L'utilisateur peut :
///   1. Sélectionner son provider préféré
///   2. Ajouter/modifier la clé API (Keychain, jamais UserDefaults)
///   3. Tester la connectivité avant enregistrement
///   4. Voir le statut de chaque provider
struct CoachAIProviderView: View {
    @StateObject private var vm = ViewModel()
    /// Observation live du tracker → la section "Usage" se met à jour
    /// dès qu'une requête cloud est enregistrée pendant que le sheet est ouvert.
    @ObservedObject private var usageTracker = AIProviderUsageTracker.shared
    @State private var showResetConfirm = false

    var body: some View {
        List {
            Section {
                appleIntelligenceRow
            } footer: {
                Text("Apple Intelligence tourne 100 % sur ton iPhone. Gratuit, privé, latence <1s. Requiert un iPhone 15 Pro ou plus récent.")
            }

            Section {
                ForEach(SlotDisplay.allCases, id: \.self) { slot in
                    providerRow(slot)
                }
            } header: {
                Text("Providers cloud (payants)")
            } footer: {
                Text("Ces providers nécessitent une clé API. Tu payes directement le provider — LifeOS ne voit rien. La clé est stockée dans le Trousseau iOS, jamais envoyée ailleurs qu'au provider choisi.")
            }

            // Section usage — visible uniquement si au moins un provider cloud
            // a été utilisé aujourd'hui ou dans le mois. Aide à surveiller la facture.
            if vm.hasUsageToday {
                Section {
                    ForEach(SlotDisplay.allCases, id: \.self) { slot in
                        usageRow(for: slot)
                    }
                } header: {
                    Text("Usage cloud")
                } footer: {
                    Text("Coût estimé approximatif (barème \(vm.pricingCatalogVersion), conversion 1 USD ≈ 0,92 €). Vérifie ta facture réelle chez le provider. Compteur du jour remis à zéro à minuit.")
                }
            }

            // Section cost guard — plafond quotidien user-configurable pour
            // éviter les factures surprise (Loop 6).
            Section {
                Toggle("Limiter le coût cloud", isOn: $vm.costGuardEnabled)
                if vm.costGuardEnabled {
                    Stepper(
                        value: $vm.costGuardCapEUR,
                        in: 0.5...50,
                        step: 0.5
                    ) {
                        HStack {
                            Text("Plafond quotidien")
                            Spacer()
                            Text(String(format: "%.1f €/jour", vm.costGuardCapEUR))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if vm.hasUsageToday {
                        HStack {
                            Text("Consommé aujourd'hui")
                                .font(.caption)
                            Spacer()
                            Text(UsageFormatter.costEUR(usd: vm.todayCumulativeCostUSD))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(
                                    vm.isCapReached ? .red : .secondary
                                )
                        }
                    }
                }
            } header: {
                Text("Plafond de sécurité")
            } footer: {
                Text(vm.costGuardEnabled
                     ? "Quand le plafond est atteint, ton coach continue via Apple Intelligence ou en local — les providers cloud sont mis en pause jusqu'au lendemain."
                     : "Aucune limite — les providers cloud consomment tant qu'ils ont une clé valide. Active pour te protéger d'une facture surprise.")
            }

            // Section bilans quotidiens — Loop 14 (config UI pour l'API Loop 12).
            Section {
                Toggle("Bilans matin & soir", isOn: $vm.bilansEnabled)
                if vm.bilansEnabled {
                    Stepper(value: $vm.bilanMorningHour, in: 5...12) {
                        HStack {
                            Text("Notif du matin")
                            Spacer()
                            Text("\(vm.bilanMorningHour)h00")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $vm.bilanEveningHour, in: 18...23) {
                        HStack {
                            Text("Notif du soir")
                            Spacer()
                            Text("\(vm.bilanEveningHour)h00")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Rythme quotidien")
            } footer: {
                Text(vm.bilansEnabled
                     ? "Ton coach t'envoie 2 notifications par jour pour ouvrir le chat au bon moment."
                     : "Les bilans automatiques sont désactivés — le coach reste dispo à la demande.")
            }

            // Section bilan mensuel — Loop 23 fix A1 (bouton "Générer maintenant")
            Section {
                Toggle("Bilan mensuel automatique", isOn: $vm.monthlyReviewEnabled)
                Button {
                    vm.showMonthlyReview = true
                } label: {
                    Label("Générer mon bilan maintenant", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Bilan mensuel")
            } footer: {
                Text("Notification le 1er de chaque mois à 10h avec un résumé auto de tes 30 derniers jours (habitudes, sommeil, poids, nutrition).")
            }

            if vm.currentPreference != nil {
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("Retour à la sélection automatique")
                    }
                }
            }
        }
        .navigationTitle("Moteur du coach")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $vm.editingSlot) { slot in
            ProviderKeyEditor(
                slot: slot,
                existingKeyMasked: vm.maskedKey(for: slot)
            ) { key in
                _ = vm.saveKey(key, for: slot)
                vm.reload()
            } onDelete: {
                vm.deleteKey(for: slot)
                vm.reload()
            }
        }
        .confirmationDialog(
            "Retour au choix automatique du coach ?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirmer", role: .destructive) { vm.clearPreference() }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $vm.showMonthlyReview) {
            MonthlyReviewSheet()
        }
        .onAppear { vm.reload() }
    }

    // MARK: - Rows

    @ViewBuilder
    private var appleIntelligenceRow: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(vm.appleAvailable ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Apple Intelligence")
                    if vm.appleAvailable {
                        Text("Recommandé")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                Text(vm.appleAvailable ? "Disponible sur cet iPhone" : "Non disponible sur cet iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.currentPreference == "apple.intelligence.on-device" {
                Text("Actif").font(.caption.weight(.semibold)).foregroundStyle(.green)
            } else if vm.appleAvailable {
                Button("Choisir") { vm.setPreferred(providerID: "apple.intelligence.on-device") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// Rangée d'usage par provider — affichée uniquement si l'user a des
    /// requêtes cloud aujourd'hui. Affiche compteur + coût EUR + moyenne
    /// tokens/req + total 30j. Accessible VoiceOver.
    @ViewBuilder
    private func usageRow(for slot: SlotDisplay) -> some View {
        let today = vm.usageSnapshot(for: slot)
        let month = vm.monthlySnapshot(for: slot)
        if today.requestCount > 0 || month.requestCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(slot.displayName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(UsageFormatter.costEUR(usd: today.estimatedCostUSD))
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                HStack(spacing: 10) {
                    Label(UsageFormatter.requestCount(today.requestCount), systemImage: "arrow.up.arrow.down")
                    if today.averageTokensPerRequest > 0 {
                        Text("• \(UsageFormatter.averageTokens(today.averageTokensPerRequest))")
                    }
                    Spacer()
                    if month.estimatedCostUSD > 0 {
                        Text("30j : \(UsageFormatter.costEUR(usd: month.estimatedCostUSD))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(today: today, month: month, name: slot.displayName))
        }
    }

    /// Label VoiceOver descriptif pour la ligne d'usage — évite le lecteur
    /// de mixer chiffres et abréviations.
    private func accessibilityLabel(
        today: AIProviderUsageTracker.Snapshot,
        month: AIProviderUsageTracker.Snapshot,
        name: String
    ) -> String {
        var parts = ["\(name), \(UsageFormatter.requestCount(today.requestCount)) aujourd'hui"]
        parts.append("coût estimé \(UsageFormatter.costEUR(usd: today.estimatedCostUSD))")
        if month.estimatedCostUSD > 0 {
            parts.append("30 derniers jours : \(UsageFormatter.costEUR(usd: month.estimatedCostUSD))")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func providerRow(_ slot: SlotDisplay) -> some View {
        let hasKey = vm.slotHasKey[slot] ?? false
        let isPreferred = vm.currentPreference == slot.providerID
        HStack {
            Image(systemName: hasKey ? "checkmark.seal.fill" : "key")
                .foregroundStyle(hasKey ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayName)
                Text(hasKey ? "Clé configurée" : "Aucune clé — tape pour ajouter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPreferred {
                Text("Actif").font(.caption.weight(.semibold)).foregroundStyle(.green)
            } else if hasKey {
                Button("Choisir") { vm.setPreferred(providerID: slot.providerID) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.editingSlot = slot }
    }
}

// MARK: - View helpers

/// Miroir de `AIProviderCredentials.Slot` avec métadonnées d'affichage.
private enum SlotDisplay: String, CaseIterable, Identifiable {
    case openai, anthropic, mistral, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai:    return "OpenAI (GPT-4o mini)"
        case .anthropic: return "Anthropic (Claude Haiku)"
        case .mistral:   return "Mistral (Small)"
        case .gemini:    return "Google Gemini (Flash)"
        }
    }

    var credentialSlot: AIProviderCredentials.Slot {
        switch self {
        case .openai:    return .openai
        case .anthropic: return .anthropic
        case .mistral:   return .mistral
        case .gemini:    return .gemini
        }
    }

    var providerID: String { credentialSlot.providerID }
}

// MARK: - Key editor sheet

private struct ProviderKeyEditor: View {
    let slot: SlotDisplay
    let existingKeyMasked: String?
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: String = ""
    @State private var showDelete = false
    @State private var validationError: String?
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle
        case testing
        case ok(String)     // e.g. "Provider a répondu en 1.4s"
        case failed(String) // message d'erreur
    }

    var body: some View {
        NavigationStack {
            Form {
                if let masked = existingKeyMasked {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            Text("Clé enregistrée : \(masked)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Colle une nouvelle clé pour la remplacer, ou utilise « Supprimer » plus bas.")
                    }
                }

                Section {
                    SecureField(existingKeyMasked == nil ? "sk-... ta clé" : "Nouvelle clé (laisser vide pour garder)",
                                text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let err = validationError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                } footer: {
                    if let url = slot.credentialSlot.docsURL {
                        Link("Où récupérer une clé \(slot.displayName)", destination: url)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await testKey() }
                    } label: {
                        HStack {
                            if testStatus == .testing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Tester la clé")
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || testStatus == .testing)

                    switch testStatus {
                    case .ok(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let msg):
                        Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.footnote)
                    default:
                        EmptyView()
                    }
                }

                Section {
                    Button {
                        saveIfValid()
                    } label: {
                        Text("Enregistrer la clé")
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if existingKeyMasked != nil {
                    Section {
                        Button(role: .destructive) {
                            showDelete = true
                        } label: {
                            Text("Supprimer la clé enregistrée")
                        }
                    } footer: {
                        Text("La clé est stockée dans le Trousseau iOS. Elle sera supprimée aussi si tu désinstalles LifeOS.")
                    }
                }
            }
            .navigationTitle(slot.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .confirmationDialog("Supprimer la clé ?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private func saveIfValid() {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if let err = AIProviderCredentials.shared.validate(trimmed, for: slot.credentialSlot) {
            validationError = err.localizedDescription
            return
        }
        validationError = nil
        onSave(trimmed)
        dismiss()
    }

    /// Envoie un vrai POST minimal au provider pour valider la clé — pas de
    /// coût perceptible (max_tokens=1). Sauve temporairement la clé, teste,
    /// puis restaure l'état si l'user ne save pas.
    private func testKey() async {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if let err = AIProviderCredentials.shared.validate(trimmed, for: slot.credentialSlot) {
            testStatus = .failed(err.localizedDescription)
            return
        }
        testStatus = .testing

        // On sauvegarde temporairement pour que le provider puisse lire la clé
        // via son Keychain lookup. Backup de la clé précédente pour restore.
        let previous = AIProviderCredentials.shared.key(for: slot.credentialSlot)
        _ = AIProviderCredentials.shared.setKey(trimmed, for: slot.credentialSlot)

        let start = Date()
        let request = AIRequest(
            messages: [
                .system("Réponds uniquement 'ok'."),
                .user("ping"),
            ],
            maxOutputTokens: 5,
            timeout: 12
        )
        let response = await providerFor(slot).complete(request)

        // Restore l'ancienne clé si l'user ne save pas ensuite.
        if let previous {
            _ = AIProviderCredentials.shared.setKey(previous, for: slot.credentialSlot)
        } else {
            _ = AIProviderCredentials.shared.deleteKey(for: slot.credentialSlot)
        }

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        if response.isSuccess {
            testStatus = .ok("Réponse reçue en \(ms) ms")
        } else if case .unavailable(.invalidCredentials) = response.error {
            testStatus = .failed("Clé refusée par le provider (401/403).")
        } else if case .rateLimited = response.error {
            testStatus = .failed("Rate limit — la clé marche mais tu as trop de requêtes.")
        } else if case .timeout = response.error {
            testStatus = .failed("Timeout — provider trop lent ou réseau instable.")
        } else if case .networkError = response.error {
            testStatus = .failed("Réseau injoignable.")
        } else {
            testStatus = .failed("Erreur : \(response.error.map(String.init(describing:)) ?? "inconnue")")
        }
    }

    private func providerFor(_ slot: SlotDisplay) -> any AIProvider {
        switch slot {
        case .openai:    return OpenAIProvider()
        case .anthropic: return AnthropicProvider()
        case .mistral:   return MistralProvider()
        case .gemini:    return GeminiProvider()
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class ViewModel: ObservableObject {
    @Published var slotHasKey: [SlotDisplay: Bool] = [:]
    @Published var currentPreference: String?
    @Published var appleAvailable: Bool = false
    @Published var editingSlot: SlotDisplay?

    func reload() {
        var map: [SlotDisplay: Bool] = [:]
        for s in SlotDisplay.allCases {
            map[s] = AIProviderCredentials.shared.hasKey(for: s.credentialSlot)
        }
        slotHasKey = map
        currentPreference = AIProviderPreference.shared.preferred
        appleAvailable = AppleIntelligenceProvider().availability.isAvailable
    }

    /// Retourne les 4 derniers chars d'une clé enregistrée, ou `nil` si aucune.
    /// Ex: "sk-...aB3f" — assez pour reconnaître, pas assez pour compromettre.
    func maskedKey(for slot: SlotDisplay) -> String? {
        guard let full = AIProviderCredentials.shared.key(for: slot.credentialSlot),
              full.count >= 4 else { return nil }
        let last4 = String(full.suffix(4))
        return "••••\(last4)"
    }

    func saveKey(_ key: String, for slot: SlotDisplay) -> Bool {
        AIProviderCredentials.shared.setKey(key, for: slot.credentialSlot)
    }

    func deleteKey(for slot: SlotDisplay) {
        AIProviderCredentials.shared.deleteKey(for: slot.credentialSlot)
        if currentPreference == slot.providerID {
            AIProviderPreference.shared.clearPreference()
        }
    }

    func setPreferred(providerID: String) {
        AIProviderPreference.shared.setPreferredProviderID(providerID)
        currentPreference = providerID
    }

    func clearPreference() {
        AIProviderPreference.shared.clearPreference()
        currentPreference = nil
    }

    // MARK: - Usage tracking

    /// Snapshot d'usage du jour pour un provider donné.
    func usageSnapshot(for slot: SlotDisplay) -> AIProviderUsageTracker.Snapshot {
        AIProviderUsageTracker.shared.todaySnapshot(providerID: slot.providerID)
    }

    /// Snapshot cumulé des 30 derniers jours (proxy facture mensuelle).
    func monthlySnapshot(for slot: SlotDisplay) -> AIProviderUsageTracker.Snapshot {
        AIProviderUsageTracker.shared.monthlySnapshot(providerID: slot.providerID)
    }

    /// Vrai si au moins un provider a été utilisé aujourd'hui OU dans le mois.
    var hasUsageToday: Bool {
        SlotDisplay.allCases.contains { slot in
            let today = AIProviderUsageTracker.shared.todaySnapshot(providerID: slot.providerID)
            let month = AIProviderUsageTracker.shared.monthlySnapshot(providerID: slot.providerID)
            return today.requestCount > 0 || month.requestCount > 0
        }
    }

    /// Version du barème de tarifs (affiché en footer pour transparence).
    var pricingCatalogVersion: String { AIProviderUsageTracker.pricingCatalogVersion }

    // MARK: - Cost guard (Loop 6)

    /// Toggle activation du plafond quotidien. Setter écrit dans la préférence
    /// via un cap par défaut de 5 € si activation, 0 si désactivation.
    var costGuardEnabled: Bool {
        get { AICostGuardPreference.shared.isEnabled }
        set {
            AICostGuardPreference.shared.dailyCapEUR = newValue ? max(0.5, AICostGuardPreference.shared.dailyCapEUR) : 0
            if newValue && AICostGuardPreference.shared.dailyCapEUR == 0 {
                AICostGuardPreference.shared.dailyCapEUR = 5
            }
            objectWillChange.send()
        }
    }

    /// Seuil courant EUR/jour. Setter propage à la préférence.
    var costGuardCapEUR: Double {
        get { AICostGuardPreference.shared.dailyCapEUR }
        set {
            AICostGuardPreference.shared.dailyCapEUR = newValue
            objectWillChange.send()
        }
    }

    /// Cumul USD du jour tous providers cloud confondus (pour affichage).
    var todayCumulativeCostUSD: Double {
        SlotDisplay.allCases.reduce(0.0) { total, slot in
            total + AIProviderUsageTracker.shared.todaySnapshot(providerID: slot.providerID).estimatedCostUSD
        }
    }

    /// Vrai si le cumul du jour a atteint le cap (affichage rouge).
    var isCapReached: Bool {
        guard costGuardEnabled else { return false }
        return AICostGuard.todayCumulativeCostEUR() >= costGuardCapEUR
    }

    // MARK: - Bilans quotidiens (Loop 14 — expose l'API Loop 12)

    var bilansEnabled: Bool {
        get { CoachDailyBilan.isEnabled }
        set {
            CoachDailyBilan.isEnabled = newValue
            CoachDailyBilan.rescheduleNow()
            objectWillChange.send()
        }
    }

    var bilanMorningHour: Int {
        get { CoachDailyBilan.morningHour }
        set {
            CoachDailyBilan.morningHour = newValue
            CoachDailyBilan.rescheduleNow()
            objectWillChange.send()
        }
    }

    var bilanEveningHour: Int {
        get { CoachDailyBilan.eveningHour }
        set {
            CoachDailyBilan.eveningHour = newValue
            CoachDailyBilan.rescheduleNow()
            objectWillChange.send()
        }
    }

    // MARK: - Bilan mensuel (Loop 23 fix A1)

    var monthlyReviewEnabled: Bool {
        get { MonthlyReviewScheduler.isEnabled }
        set {
            MonthlyReviewScheduler.isEnabled = newValue
            MonthlyReviewScheduler.scheduleIfNeeded()
            objectWillChange.send()
        }
    }

    @Published var showMonthlyReview: Bool = false
}
