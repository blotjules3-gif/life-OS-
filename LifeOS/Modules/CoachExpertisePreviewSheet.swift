import SwiftUI

/// Sheet de debug — inspecte ce que le coach reçoit dans son contexte à un instant T.
/// Utilise en local pour tuner l'injection d'expertise sans envoyer un vrai message.
/// - Champ texte pour simuler un message utilisateur
/// - Chips des topics détectés
/// - Bytes total du contexte injecté (proxy tokens : ~1 token ≈ 4 chars)
/// - Rendu monospace du contexte complet, scrollable
///
/// Volontairement placée dans Modules/ (pas de gate #if DEBUG côté fichier — le point
/// d'entrée dans ProfileView est lui gated en DEBUG).
struct CoachExpertisePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var simulatedMessage: String = ""
    @State private var expandedContext: Bool = true
    @FocusState private var messageFocused: Bool

    private var detectedTopics: [String] {
        guard !simulatedMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let raw = CoachExpertise.detectTopics(in: simulatedMessage)
        return topicOrder.filter { raw.contains($0) }
    }

    private var contextText: String {
        UserContextBuilder.shared.build(
            message: simulatedMessage.isEmpty ? nil : simulatedMessage
        )
    }

    private var charCount: Int { contextText.count }
    private var estimatedTokens: Int { max(1, charCount / 4) }

    private let topicOrder = [
        "fitness", "nutrition", "sleep", "mind", "productivity", "cycle", "medical", "looks"
    ]

    private func label(for topic: String) -> String {
        switch topic {
        case "fitness":      return "Sport"
        case "nutrition":    return "Nutrition"
        case "sleep":        return "Sommeil"
        case "mind":         return "Mental"
        case "productivity": return "Productivité"
        case "cycle":        return "Cycle"
        case "medical":      return "Longévité"
        case "looks":        return "Peau"
        default:             return topic
        }
    }

    private func color(for topic: String) -> Color {
        switch topic {
        case "fitness":      return Color(hex: 0x618EF1)
        case "nutrition":    return Color(hex: 0xF1746C)
        case "sleep":        return Color(hex: 0x6C7BF1)
        case "mind":         return Color(hex: 0x9B6CF1)
        case "productivity": return Color(hex: 0x4CC38A)
        case "cycle":        return Color(hex: 0xE05A7A)
        case "medical":      return Color(hex: 0x3CD0C8)
        case "looks":        return Color(hex: 0xE0A23C)
        default:             return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inputCard
                    topicsCard
                    metricsCard
                    contextCard
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Coach expertise — debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message utilisateur simulé")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField("Ex. je dors mal après le sport", text: $simulatedMessage, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 15))
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($messageFocused)
            HStack(spacing: 6) {
                sampleChip("je dors mal après le sport")
                sampleChip("prise de masse ?")
                sampleChip("procrastination")
            }
        }
    }

    private func sampleChip(_ text: String) -> some View {
        Button { simulatedMessage = text } label: {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var topicsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Topics détectés")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if detectedTopics.isEmpty {
                Text(simulatedMessage.isEmpty
                     ? "Vide → fallback module-based (activeModules)"
                     : "Aucun topic détecté → fallback module-based")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                FlexibleChips(items: detectedTopics) { topic in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(color(for: topic))
                            .frame(width: 6, height: 6)
                        Text(label(for: topic))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(color(for: topic))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color(for: topic).opacity(0.12), in: Capsule())
                }
                Text("Max 3 blocs (+ méta) — les 3 premiers dans l'ordre canonique sont injectés.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var metricsCard: some View {
        HStack(spacing: 10) {
            metric("Chars", "\(charCount)")
            metric("~Tokens", "\(estimatedTokens)")
            metric("Lignes", "\(contextText.split(separator: "\n").count)")
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Contexte injecté au coach")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    UIPasteboard.general.string = contextText
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            Text(contextText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Layout helper (chips wrap)

private struct FlexibleChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

/// Simple flow layout (chips qui passent à la ligne).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW {
                x = 0
                y += lineH + spacing
                lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += lineH + spacing
                lineH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
