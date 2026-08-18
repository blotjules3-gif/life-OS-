import SwiftUI

/// Composants réutilisables du chat coach — extraits de `AIAssistantView.swift`
/// pour réduire le God file (1708 → 1573 lignes après extraction).
///
/// Contient :
///   • `ThinkingIndicator` — 3 points qui pulsent pendant "coach réfléchit"
///   • `TypewriterText` — texte révélé mot par mot pour les réponses fraîches
///   • `CoachTextCleaner` — enum static de nettoyage du markdown parasite
///   • `PressScaleButtonStyle` — style bouton avec léger scale au press
///   • `WaveformView` — barres verticales animées pour feedback vocal live
///
/// Tous étaient privés dans le fichier source. Passés à internal (default) ici,
/// accessibles depuis n'importe quel fichier du module LifeOS.

// MARK: - ThinkingIndicator

struct ThinkingIndicator: View {
    @State private var active = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(active ? 1.0 : 0.65)
                    .opacity(active ? 0.85 : 0.3)
                    .offset(y: active ? -3 : 0)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: active
                    )
            }
        }
        .padding(.vertical, 2)
        .onAppear { active = true }
    }
}

// MARK: - TypewriterText (réponses fraîches uniquement)

struct TypewriterText: View {
    let text: String
    @State private var displayed = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayed)
            .animation(.easeOut(duration: 0.12), value: displayed)
            .task {
                guard !reduceMotion else { displayed = text; return }
                let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                // Durée totale plafonnée à ~1,2 s quelle que soit la longueur.
                let delay = min(0.05, 1.2 / Double(max(1, words.count)))
                for word in words {
                    displayed = displayed.isEmpty ? word : displayed + " " + word
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                displayed = text
            }
    }
}

// MARK: - Coach text sanitizer

/// Nettoie les réponses du coach : retire les caractères markdown parasites
/// (astérisques de gras/italique, dièses de titres, chevrons de citation,
/// séparateurs ===/---, puces "- " ou "* " en début de ligne).
/// Reste tolérant si le coach envoie du texte propre.
enum CoachTextCleaner {
    static func clean(_ raw: String) -> String {
        var s = raw

        // 1) Emphases markdown : **gras**, *italique*, __gras__, _italique_
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        // Astérisques et underscores isolés (autour d'un mot) → retirer
        s = s.replacingOccurrences(of: #"(?<!\w)\*(?=\S)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<=\S)\*(?!\w)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<!\w)_(?=\S)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<=\S)_(?!\w)"#, with: "", options: .regularExpression)

        // 2) Backticks code inline
        s = s.replacingOccurrences(of: "`", with: "")

        // 3) Titres markdown en début de ligne (### Titre → Titre)
        s = s.replacingOccurrences(of: #"(?m)^\s*#{1,6}\s+"#, with: "", options: .regularExpression)

        // 4) Puces "- " / "* " / "• " en début de ligne
        s = s.replacingOccurrences(of: #"(?m)^\s*[-*•]\s+"#, with: "", options: .regularExpression)

        // 5) Chevrons de citation "> " en début de ligne
        s = s.replacingOccurrences(of: #"(?m)^\s*>\s+"#, with: "", options: .regularExpression)

        // 6) Séparateurs horizontaux (---, ***, ===) sur ligne entière
        s = s.replacingOccurrences(of: #"(?m)^\s*(?:-{3,}|\*{3,}|={3,})\s*$"#, with: "", options: .regularExpression)

        // 7) Boîtes ASCII (═══, ──, ▬▬) sur ligne entière
        s = s.replacingOccurrences(of: #"(?m)^\s*[═─▬━┈┄]{3,}\s*$"#, with: "", options: .regularExpression)

        // 8) Puces numérotées "1. " → conserver le chiffre naturellement (on ne touche pas)

        // 9) Écraser 3+ lignes vides consécutives à 2 max
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        // 10) Trim final
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - PressScaleButtonStyle

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - WaveformView (feedback vocal live)

struct WaveformView: View {
    let level: Float
    let accent: Color
    /// Historique lissé des 5 dernières mesures pour rendre le mouvement continu.
    @State private var levels: [Float] = Array(repeating: 0, count: 5)

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: barHeight(for: levels[i]))
            }
        }
        .frame(width: 34, height: 34)
        .onChange(of: level) { _, new in
            withAnimation(.easeOut(duration: 0.09)) {
                levels.removeFirst()
                levels.append(new)
            }
        }
        .accessibilityHidden(true)
    }

    private func barHeight(for value: Float) -> CGFloat {
        let clamped = CGFloat(max(0.05, min(1, value)))
        return 6 + clamped * 22
    }
}
