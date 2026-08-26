import SwiftUI
import UIKit

/// Affiche le résumé mensuel généré à la demande (bouton "Générer maintenant"
/// dans Réglages Coach IA — Loop 23 fix A1).
///
/// Deux actions à partir de la sheet :
///   - Copier : place le texte dans le presse-papier
///   - Ouvrir dans le chat : post `.lifeOSOpenAIChat` avec prefill
struct MonthlyReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summary: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(summary.isEmpty ? "Chargement…" : summary)
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Bilan mensuel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = summary
                        } label: {
                            Label("Copier", systemImage: "doc.on.doc")
                        }
                        Button {
                            openInChat()
                        } label: {
                            Label("Ouvrir dans le chat", systemImage: "bubble.left.and.text.bubble.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                summary = MonthlyReviewGenerator.generateSummary()
            }
        }
    }

    private func openInChat() {
        NotificationCenter.default.post(
            name: .lifeOSOpenAIChat,
            object: nil,
            userInfo: ["prefill": summary]
        )
        dismiss()
    }
}
