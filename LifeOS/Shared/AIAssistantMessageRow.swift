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
    /// Loop 15 — action "reformule" : relance le message précédent avec un
    /// system prompt correctif. Réponse alternative sans que l'user retape.
    var onRephrase: (() -> Void)? = nil

    @AppStorage(AppStorageKeys.coachTTSEnabled) private var ttsEnabled = false
    @ObservedObject private var speech = CoachSpeech.shared

    // Dynamic Type — badges et bouton speaker grossissent avec la taille système.
    @ScaledMetric(relativeTo: .footnote) private var badgeIconSize: CGFloat = 11
    @ScaledMetric(relativeTo: .footnote) private var badgeTextSize: CGFloat = 11

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
                        if let onRephrase {
                            Button(action: onRephrase) {
                                Label("Reformule ta réponse", systemImage: "arrow.triangle.2.circlepath")
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

            // Label discret "via [Provider]" sous la bulle coach — transparence
            // user sur quelle IA vient de répondre. Silencieux pour user/thinking
            // ou si providerID inconnu.
            if !isUser, !message.isThinking,
               let providerName = AIProviderResolver.displayName(for: message.providerID) {
                HStack(spacing: 4) {
                    Image(systemName: AIProviderResolver.iconName(for: message.providerID))
                        .font(.system(size: 9))
                    Text("via \(providerName)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
                .accessibilityLabel("Réponse générée via \(providerName)")
            }

            // Boutons inline sous la bulle coach (feedback + TTS + safety)
            if !isUser, !message.isThinking {
                inlineActionRow
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

    // MARK: - Inline actions (feedback + speaker)

    @State private var feedbackGiven: FeedbackKind?
    /// Vrai après tap sur 👎 → affiche les chips de raison (trop long, hors sujet…).
    @State private var showingDislikeReasons = false

    private enum FeedbackKind {
        case liked, disliked
    }

    /// Ligne d'actions sous chaque bulle coach : like, dislike, écouter.
    /// Fait sortir le feedback du contextMenu (découvrabilité 0) vers un tap direct.
    private var inlineActionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let onLike {
                    inlineActionButton(
                        icon: feedbackGiven == .liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                        label: "J'aime",
                        active: feedbackGiven == .liked
                    ) {
                        guard feedbackGiven == nil else { return }
                        feedbackGiven = .liked
                        onLike()
                    }
                }
                if let onDislike {
                    inlineActionButton(
                        icon: feedbackGiven == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                        label: "Pas top",
                        active: feedbackGiven == .disliked
                    ) {
                        guard feedbackGiven == nil else { return }
                        feedbackGiven = .disliked
                        onDislike()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showingDislikeReasons = true
                        }
                    }
                }
                if ttsEnabled {
                    speakerButton
                }
                Spacer()
            }
            if showingDislikeReasons {
                dislikeReasonsRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Chips à taper après un dislike pour préciser la raison.
    /// Aide le coach à comprendre CE QUI ne va pas (pas juste "mauvais").
    private var dislikeReasonsRow: some View {
        HStack(spacing: 6) {
            ForEach(CoachFeedbackStore.DislikeReason.allCases, id: \.rawValue) { reason in
                Button {
                    CoachFeedbackStore.record(.dislike, response: cleanedText, reason: reason)
                    AnalyticsEvents.chatFeedbackReason(reason: reason.rawValue)
                    withAnimation { showingDislikeReasons = false }
                } label: {
                    Text(reason.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inlineActionButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: badgeIconSize, weight: .semibold))
                Text(label)
                    .font(.system(size: badgeTextSize, weight: .medium))
            }
            .foregroundStyle(active ? accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(active ? accent.opacity(0.12) : Color(uiColor: .tertiarySystemBackground))
            )
            .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(feedbackGiven != nil && !active)
        .accessibilityLabel(active ? "\(label), déjà noté" : label)
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
                    .font(.system(size: badgeIconSize, weight: .semibold))
                Text(isPlayingThisMessage ? "Arrêter" : "Écouter")
                    .font(.system(size: badgeTextSize, weight: .medium))
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
                .font(.system(size: badgeIconSize, weight: .semibold))
            Text(badge.label)
                .font(.system(size: badgeTextSize, weight: .medium))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
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
