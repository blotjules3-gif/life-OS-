import SwiftUI

/// Rangée de message dans le chat coach — bulle user (droite, accent) ou
/// coach (gauche, secondary). Gère :
///   • État "thinking" (indicateur 3 points)
///   • Reveal typewriter pour réponses fraîches
///   • Rendu markdown pour les réponses coach (bold, italic, listes, liens)
///   • Badge sécurité inline si dosage / med / conseil financier détecté
///   • Bouton speaker (TTS) si prefs activent la lecture vocale
///   • Menu contextuel "Signaler / Aimé / Pas aimé"
///
/// Extrait de `AIAssistantView.swift` pour réduire le God file.
struct AIAssistantMessageRow: View {
    let message: AIAssistantViewModel.DisplayMessage
    let accent: Color
    var reveal: Bool = false
    var onReport: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onDislike: (() -> Void)? = nil

    @AppStorage(AppStorageKeys.coachTTSEnabled) private var ttsEnabled = false
    @ObservedObject private var speech = CoachSpeech.shared

    var isUser: Bool { message.role == "user" }

    private var cleanedText: String {
        CoachTextCleaner.clean(message.text)
    }

    private var safetyBadge: CoachSafetyScanner.RiskBadge? {
        guard !isUser, !message.isThinking else { return nil }
        return CoachSafetyScanner.scan(cleanedText)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 56) }

                Group {
                    if message.isThinking {
                        ThinkingIndicator()
                    } else if reveal, !isUser {
                        TypewriterText(text: cleanedText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } else if !isUser {
                        // Rendu markdown pour les messages coach : bold, italic, listes, liens.
                        // Fallback silencieux vers plain text si parse échoue.
                        markdownText(cleanedText)
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
                    if !isUser, !message.isThinking {
                        Button {
                            UIPasteboard.general.string = cleanedText
                            Haptics.tap()
                        } label: {
                            Label("Copier", systemImage: "doc.on.doc")
                        }
                        if let onLike {
                            Button(action: onLike) {
                                Label("J'aime cette réponse", systemImage: "hand.thumbsup")
                            }
                        }
                        if let onDislike {
                            Button(action: onDislike) {
                                Label("Pas satisfait", systemImage: "hand.thumbsdown")
                            }
                        }
                        if let onReport {
                            Button(role: .destructive, action: onReport) {
                                Label("Signaler cette réponse", systemImage: "flag")
                            }
                        }
                    }
                }

                if !isUser { Spacer(minLength: 56) }
            }

            // Bouton speaker (TTS) sous la bulle coach si prefs activent la voix
            if !isUser, !message.isThinking, ttsEnabled {
                speakerButton
            }

            // Badge sécurité inline (dosage, médicament, finance, restriction)
            if let badge = safetyBadge {
                safetyBadgeView(badge)
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

    // MARK: - Speaker

    private var isPlayingThisMessage: Bool {
        speech.speakingID == message.id
    }

    private var speakerButton: some View {
        Button {
            speech.toggle(text: cleanedText, id: message.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPlayingThisMessage ? "stop.circle.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(isPlayingThisMessage ? "Arrêter" : "Écouter")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isPlayingThisMessage ? accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color(uiColor: .tertiarySystemBackground))
            )
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlayingThisMessage ? "Arrêter la lecture" : "Écouter la réponse")
    }

    // MARK: - Safety badge

    private func safetyBadgeView(_ badge: CoachSafetyScanner.RiskBadge) -> some View {
        HStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(badge.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
        }
        .foregroundStyle(Color(hex: 0xE0A23C))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(hex: 0xE0A23C).opacity(0.12))
        )
        .accessibilityLabel(badge.label)
    }

    // MARK: - Action chips

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
