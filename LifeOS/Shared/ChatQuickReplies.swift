import SwiftUI

/// Chips de réponse rapide sous le dernier message coach.
///
/// **Pourquoi** : ~60 % des messages coach appellent une réponse binaire ("tu veux
/// qu'on ajuste ta journée ?"). Sans chips, l'user doit taper. Avec, un tap.
///
/// **Détection** : heuristique locale sur le texte du dernier message assistant.
/// Pas de dépendance backend — marche même hors ligne.
///
/// **Rendu** : ligne horizontale scrollable de chips arrondis, animation d'entrée
/// séquentielle (stagger 60 ms).
struct ChatQuickReplies: View {
    let suggestions: [String]
    let accent: Color
    let onTap: (String) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, text in
                    Button {
                        onTap(text)
                    } label: {
                        Text(text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accent.opacity(0.10), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(0.20), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Répondre : \(text)")
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 6)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.2)
                            : .spring(response: 0.35, dampingFraction: 0.85).delay(Double(index) * 0.06),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Génération heuristique de suggestions

enum ChatSuggestionBuilder {

    /// Retourne 2-3 chips adaptés au dernier message coach (nil si non pertinent).
    static func suggestions(for coachText: String) -> [String]? {
        let t = coachText.lowercased()
        // Pas de suggestions si le message est très court ou n'invite pas à répondre.
        guard coachText.count > 20 else { return nil }

        // Question directe qui appelle un choix
        if t.contains("tu veux") || t.contains("on regarde") || t.contains("on ajuste") ||
           t.contains("tu préfères") || t.contains("je te propose") {
            return ["Oui, vas-y", "Pas maintenant", "Explique"]
        }
        // Demande d'info / clarification
        if t.contains("dis-moi") || t.contains("raconte-moi") || t.contains("comment tu te sens") {
            return ["Ça va", "Bof", "Fatigué"]
        }
        // Question ouverte (finit par ?)
        if t.hasSuffix("?") || t.contains(" ?\n") || t.contains(" ? ") {
            return ["OK je note", "Non merci", "Reformule"]
        }
        // Résumé / bilan → propositions de suite
        if t.contains("bilan") || t.contains("résumé") || t.contains("récap") {
            return ["Plan demain", "Détaille", "OK merci"]
        }
        return nil
    }
}
