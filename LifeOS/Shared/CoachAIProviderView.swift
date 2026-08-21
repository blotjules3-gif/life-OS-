import SwiftUI

/// Écran Réglages "Coach IA" — choix + configuration du provider LLM.
///
/// L'utilisateur peut :
///   1. Sélectionner son provider préféré (Apple Intelligence si dispo, ou un
///      provider cloud dont il a la clé API)
///   2. Ajouter/modifier la clé API de chaque provider cloud (stockée dans
///      le Keychain, jamais dans UserDefaults)
///   3. Tester la connectivité (envoie un ping minimal via `AIModelRouter`)
///   4. Voir le statut de chaque provider (configuré, en erreur, actif)
struct CoachAIProviderView: View {
    @StateObject private var vm = ViewModel()

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
                Text("Providers cloud")
            } footer: {
                Text("Ces providers nécessitent une clé API. Tu payes directement le provider — LifeOS ne voit rien. La clé est stockée dans le Trousseau iOS, jamais envoyée ailleurs qu'au provider choisi.")
            }

            if vm.currentPreference != nil {
                Section {
                    Button(role: .destructive) {
                        vm.clearPreference()
                    } label: {
                        Text("Retour à la sélection automatique")
                    }
                }
            }
        }
        .navigationTitle("Coach IA")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $vm.editingSlot) { slot in
            ProviderKeyEditor(slot: slot) { key in
                _ = vm.saveKey(key, for: slot)
                vm.reload()
            } onDelete: {
                vm.deleteKey(for: slot)
                vm.reload()
            }
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
                Text("Apple Intelligence")
                Text(vm.appleAvailable ? "Disponible sur cet iPhone" : "Non disponible sur cet iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.currentPreference == "apple.intelligence.on-device" {
                Text("Actif").font(.caption).foregroundStyle(.green)
            } else if vm.appleAvailable {
                Button("Choisir") { vm.setPreferred(providerID: "apple.intelligence.on-device") }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ slot: SlotDisplay) -> some View {
        let hasKey = vm.slotHasKey[slot] ?? false
        let isPreferred = vm.currentPreference == slot.preferenceValue
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
                Text("Actif").font(.caption).foregroundStyle(.green)
            } else if hasKey {
                Button("Choisir") { vm.setPreferred(providerID: slot.preferenceValue) }
                    .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.editingSlot = slot }
    }
}

// MARK: - View helpers

/// Miroir de `AIProviderCredentials.Slot` avec métadonnées d'affichage —
/// évite d'importer le type interne dans la View SwiftUI.
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

    /// Le token utilisé côté `AIProviderPreference` pour matcher un provider.
    var preferenceValue: String {
        switch self {
        case .openai:    return "openai"
        case .anthropic: return "anthropic"
        case .mistral:   return "mistral"
        case .gemini:    return "gemini"
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
}

// MARK: - Key editor sheet

private struct ProviderKeyEditor: View {
    let slot: SlotDisplay
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: String = ""
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-... / clé API", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let url = slot.credentialSlot.docsURL {
                        Link("Où récupérer une clé \(slot.displayName)", destination: url)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        onSave(key)
                        dismiss()
                    } label: {
                        Text("Enregistrer la clé")
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).count < 8)
                }

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
            .navigationTitle(slot.displayName)
            .navigationBarTitleDisplayMode(.inline)
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

    func saveKey(_ key: String, for slot: SlotDisplay) -> Bool {
        AIProviderCredentials.shared.setKey(key, for: slot.credentialSlot)
    }

    func deleteKey(for slot: SlotDisplay) {
        AIProviderCredentials.shared.deleteKey(for: slot.credentialSlot)
        // Si c'était le préféré, on retire la préférence.
        if currentPreference == slot.preferenceValue {
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
}
