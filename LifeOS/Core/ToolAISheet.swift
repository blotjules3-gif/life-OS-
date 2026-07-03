import SwiftUI

// MARK: - Feuille d'édition « en langage naturel » d'un outil
// L'utilisateur écrit ce qu'il veut changer ; un handler local applique la modif
// et renvoie un message de résultat. Réutilisable dans tous les outils.

struct ToolAISheet: View {
    let title: String
    var placeholder: String = "Décris ce que tu veux changer…"
    /// Reçoit la demande, applique la modif, renvoie un message de retour.
    let onApply: (String) -> String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(Color.accentColor)
                        Text("Dis ce que tu veux, je m'en occupe").font(.headline)
                    }
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder).foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        TextEditor(text: $text)
                            .focused($focused)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(minHeight: 110)
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

                    if let result {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Color.accentColor)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        let r = onApply(text)
                        withAnimation { result = r }
                        text = ""
                    } label: {
                        Text("Appliquer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                    Text("Fonctionne sur l'appareil (sans connexion).")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}
