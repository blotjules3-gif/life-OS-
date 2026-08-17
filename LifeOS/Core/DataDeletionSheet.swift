import SwiftUI
import SwiftData

/// Écran de suppression des données — conforme guideline App Store 5.1.1(v).
///
/// Deux options :
///   • Recommencer à zéro : garde thème + prénom, reset les données de vie
///   • Tout effacer : reset TOTAL, retour à l'état "premier lancement"
///
/// Double confirmation obligatoire pour éviter les erreurs. Un export JSON
/// est proposé avant chaque suppression via ShareLink.
struct DataDeletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var confirmingFull = false
    @State private var confirmingReset = false
    @State private var didErase = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Toutes tes données LifeOS sont stockées **uniquement sur cet appareil**. Aucun serveur ne les conserve. Cette action est **irréversible**.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section("Sauvegarde") {
                    Button {
                        Task { await prepareExport() }
                    } label: {
                        Label("Exporter mes données (aperçu JSON)", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Exporter un aperçu de mes données au format JSON")

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Partager le fichier", systemImage: "paperplane.fill")
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }

                Section("Effacer") {
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("Recommencer à zéro", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityHint("Efface tes données mais garde ton prénom et ton thème")

                    Button(role: .destructive) {
                        confirmingFull = true
                    } label: {
                        Label("Tout effacer", systemImage: "trash.fill")
                    }
                    .accessibilityHint("Efface toutes les données et repart de l'onboarding")
                }
                .listRowSeparator(.hidden)

                if didErase {
                    Section {
                        Text("Effacé. Ferme puis rouvre l'app pour finaliser.")
                            .font(.footnote)
                            .foregroundStyle(Theme.success)
                    }
                }
            }
            .navigationTitle("Mes données")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Recommencer à zéro ?", isPresented: $confirmingReset) {
                Button("Annuler", role: .cancel) { }
                Button("Effacer", role: .destructive) { doErase(keepOnboarding: true) }
            } message: {
                Text("Toutes les données (habitudes, sommeil, humeur, finances, chat coach…) seront effacées. Ton prénom et ton thème sont conservés.")
            }
            .alert("Tout effacer ?", isPresented: $confirmingFull) {
                Button("Annuler", role: .cancel) { }
                Button("Tout effacer", role: .destructive) { doErase(keepOnboarding: false) }
            } message: {
                Text("Suppression totale. L'app retournera à l'écran d'onboarding au prochain lancement. Aucune récupération possible.")
            }
        }
    }

    private func doErase(keepOnboarding: Bool) {
        let container = ctx.container
        if keepOnboarding {
            DataEraser.eraseAndKeepOnboarding(container: container)
        } else {
            DataEraser.eraseAllData(container: container)
        }
        didErase = true
        Haptics.success()
    }

    private func prepareExport() async {
        let container = ctx.container
        guard let data = DataEraser.exportBackup(container: container) else { return }
        let filename = "lifeos-backup-\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            await MainActor.run { exportURL = url }
        } catch {
            AppLog.data.error("prepareExport write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
