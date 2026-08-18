import SwiftUI

/// Rangée de message dans le chat coach — bulle user (droite, accent) ou
/// coach (gauche, secondary). Gère :
///   • État "thinking" (indicateur 3 points)
///   • Reveal typewriter pour réponses fraîches
///   • Rendu markdown pour les réponses coach (bold, italic, listes, liens)
///   • Action chips sous les messages coach avec `actions` non vide
///   • Menu contextuel "Signaler cette réponse"
///
/// Extrait de `AIAssistantView.swift` pour réduire le God file (1665 → ~1550 lignes).
struct AIAssistantMessageRow: View {
    let message: AIAssistantViewModel.DisplayMessage
    let accent: Color
    var reveal: Bool = false
    var onReport: (() -> Void)? = nil

    var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 56) }

                Group {
                    if message.isThinking {
                        ThinkingIndicator()
                    } else if reveal, !isUser {
                        TypewriterText(text: CoachTextCleaner.clean(message.text))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } else if !isUser {
                        // Rendu markdown pour les messages coach : bold, italic, listes, liens.
                        // Fallback silencieux vers plain text si parse échoue.
                        markdownText(CoachTextCleaner.clean(message.text))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else {
                        Text(message.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.onAccent)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? accent : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .shadow(
                    color: isUser ? accent.opacity(0.18) : Color.black.opacity(0.06),
                    radius: isUser ? 8 : 4,
                    x: 0,
                    y: isUser ? 3 : 2
                )
                .contextMenu {
                    if !isUser, !message.isThinking, let onReport {
                        Button(role: .destructive, action: onReport) {
                            Label("Signaler cette réponse", systemImage: "flag")
                        }
                    }
                }

                if !isUser { Spacer(minLength: 56) }
            }

            // Action chips (after assistant message)
            if !isUser && !message.actions.isEmpty {
                actionChips
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: isUser ? .trailing : .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94, anchor: isUser ? .bottomTrailing : .bottomLeading)),
            removal: .opacity.combined(with: .scale(scale: 0.97))
        ))
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(message.actions.filter { $0.title != nil }) { action in
                    Label(action.title!, systemImage: iconFor(action.type))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    /// Rend un texte comme markdown (bold `**x**`, italic `*x*`, listes `- x`, liens).
    /// Fallback silencieux sur plain text si le parse échoue.
    @ViewBuilder
    private func markdownText(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
        } else {
            Text(raw)
        }
    }

    private func iconFor(_ type: AIAction.ActionType) -> String {
        switch type {
        case .createTodo: return "checkmark.circle"
        case .openModule: return "arrow.right.circle"
        case .scheduleReminder: return "bell"
        case .updateConfig: return "slider.horizontal.3"
        case .createChallenge: return "flame"
        case .createHabit: return "repeat.circle.fill"
        case .addModule: return "plus.circle"
        case .removeModule: return "minus.circle"
        }
    }
}
