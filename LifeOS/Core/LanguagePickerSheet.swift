import SwiftUI

/// Sheet de sélection de la langue de l'app.
///
/// **UX** :
/// - Choix Automatique par défaut → l'app suit la langue de l'iPhone
/// - Français / English si l'user veut forcer
/// - Applique via `LanguageForcer.set(_:)` (persiste + override AppleLanguages)
/// - Alerte "Redémarre l'app pour appliquer" à la validation
///
/// **Honnêteté** : la traduction EN n'est pas complète (≈5% du texte user-facing
/// est traduit). Le sheet le signale explicitement pour éviter la frustration.
struct LanguagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: LanguageForcer.Option = LanguageForcer.current
    @State private var showRestartAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LanguageForcer.Option.allCases) { option in
                        Button {
                            selection = option
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: iconFor(option))
                                    .frame(width: 22)
                                    .foregroundStyle(tintFor(option))
                                Text(option.label)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Langue de l'app")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatique : LifeOS suit la langue de ton iPhone.")
                        Text("Force le français ou l'anglais si tu préfères ne pas dépendre du système.")
                    }
                    .font(.caption)
                }

                if selection == .en {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Theme.warning)
                            Text("La traduction anglaise n'est pas encore complète. Certaines parties de l'app resteront en français en attendant.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Langue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if selection != LanguageForcer.current {
                            LanguageForcer.set(selection)
                            showRestartAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(selection == LanguageForcer.current)
                }
            }
            .alert("Redémarre l'app", isPresented: $showRestartAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Ferme complètement LifeOS puis rouvre-le pour appliquer la nouvelle langue.")
            }
        }
    }

    private func iconFor(_ option: LanguageForcer.Option) -> String {
        switch option {
        case .auto: return "globe"
        case .fr:   return "flag.fill"
        case .en:   return "flag.fill"
        }
    }

    private func tintFor(_ option: LanguageForcer.Option) -> Color {
        switch option {
        case .auto: return Theme.accent
        case .fr:   return Color(hex: 0x0055A4)   // bleu drapeau français
        case .en:   return Color(hex: 0xC8102E)   // rouge drapeau UK
        }
    }
}
