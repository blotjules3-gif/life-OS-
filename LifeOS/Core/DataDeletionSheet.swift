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
    @State private var syncOn = LocalStore.cloudKitEnabled
    @State private var exporting = false
    /// Pourquoi la sauvegarde a echoue. Sans ca, le bouton ne faisait
    /// visiblement rien et l'utilisateur pouvait effacer quand meme.
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // onChange et pas didSet: un didSet sur @State ne se
                    // declenche pas quand le Toggle ecrit par son binding.
                    Toggle(isOn: $syncOn) {
                        Label("Synchro iCloud", systemImage: "icloud")
                    }
                    .onChange(of: syncOn) { _, on in LocalStore.cloudKitEnabled = on }
                } footer: {
                    // Ce texte disait "uniquement sur cet appareil". Avec la
                    // synchro, c'est faux, et c'est exactement le genre de
                    // phrase qu'on lit avant d'effacer.
                    Text(syncOn
                         ? "Tes données sont sur cet appareil et dans ton iCloud, pour les retrouver sur ton iPad, ton Mac et ta montre. Aucun autre serveur ne les conserve. Le changement s'applique au prochain lancement."
                         : "Tes données restent uniquement sur cet appareil. Aucun serveur ne les conserve. Le changement s'applique au prochain lancement.")
                }

                Section {
                    Text(syncOn
                         ? "Effacer ici efface aussi dans iCloud, donc sur tous tes appareils. Cette action est **irréversible**."
                         : "Cette action est **irréversible**.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section("Sauvegarde") {
                    Button {
                        Task { await prepareExport() }
                    } label: {
                        HStack {
                            Label("Exporter mes données (aperçu JSON)", systemImage: "square.and.arrow.up")
                            if exporting { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(exporting)
                    .accessibilityLabel("Exporter un aperçu de mes données au format JSON")

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Partager le fichier", systemImage: "paperplane.fill")
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
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

    /// Prepare le fichier de sauvegarde.
    ///
    /// Cet ecran est le seul filet avant un effacement irreversible. Une
    /// panne silencieuse ici est donc la pire de l'app: le bouton ne faisait
    /// rien de visible, aucun lien de partage n'apparaissait, et on pouvait
    /// enchainer sur "Tout effacer" en croyant avoir sa copie. Chaque sortie
    /// dit maintenant ce qui s'est passe.
    private func prepareExport() async {
        await MainActor.run { exporting = true; exportError = nil; exportURL = nil }

        // Le message d'echec est volontairement le meme dans les deux cas et
        // dit quoi faire: l'utilisateur n'a pas a distinguer "encodage rate"
        // de "ecriture ratee", il a besoin de savoir qu'il ne doit pas
        // effacer maintenant.
        var failure: String?
        var ready: URL?

        if let data = DataEraser.exportBackup(container: ctx.container) {
            let filename = "lifeos-backup-\(Int(Date().timeIntervalSince1970)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url, options: .atomic)
                ready = url
            } catch {
                AppLog.data.error("prepareExport write failed: \(error.localizedDescription, privacy: .public)")
                failure = "Écriture impossible : \(error.localizedDescription). N'efface rien et réessaie."
            }
        } else {
            AppLog.data.error("prepareExport: exportBackup a rendu nil")
            failure = "La sauvegarde n'a pas pu être préparée. N'efface rien et réessaie."
        }

        await MainActor.run {
            exportURL = ready
            exportError = failure
            exporting = false
        }
    }
}
