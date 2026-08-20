import SwiftUI

/// Vue de debug interne — inspection des sessions IA récentes.
///
/// Accessible depuis le menu du chat (uniquement en DEBUG ou si toggle activé).
/// Aucun contenu textuel affiché (respect confidentialité) — que des métadonnées :
/// - Latence
/// - Provider utilisé
/// - Tokens (contexte, output)
/// - Sections tronquées
/// - Tools appelés
/// - Classification (intent, sentiment)
/// - Post-processing issues
///
/// Utilité : voir en live ce qui se passe pour améliorer prompts/routing/pipeline.
struct AIDebugView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = AIActivityLogger.shared

    var body: some View {
        NavigationStack {
            Group {
                if logger.sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Debug coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Vider") { logger.clear() }
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Aucune session")
                .font(.headline).foregroundStyle(.secondary)
            Text("Envoie un message au coach pour voir apparaître les métadonnées de la session.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                providersRow
            } header: {
                Text("Providers enregistrés")
            }
            Section {
                ForEach(logger.sessions.reversed()) { session in
                    sessionRow(session)
                }
            } header: {
                Text("Sessions (\(logger.sessions.count))")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Providers snapshot

    private var providersRow: some View {
        let snapshot = AIModelRouter.shared.snapshot()
        return ForEach(snapshot.providers, id: \.id) { p in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(p.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    availabilityBadge(p.availability)
                }
                Text(p.id).font(.caption2).foregroundStyle(.tertiary)
                Text("Capacités : \(capabilitiesString(p.capabilities))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Session

    @ViewBuilder
    private func sessionRow(_ session: AISession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if session.hasError {
                    Text("erreur").font(.caption2).foregroundStyle(.red)
                } else if session.isCompleted {
                    Text("\(session.durationMs ?? 0) ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                } else {
                    Text("en cours").font(.caption2).foregroundStyle(.orange)
                }
            }

            if let c = session.classification {
                HStack(spacing: 6) {
                    chip(c.intentType, tint: .blue)
                    chip(c.sentiment, tint: sentimentColor(c.sentiment))
                    chip(c.complexity, tint: .gray)
                    if c.topicsCount > 0 {
                        chip("\(c.topicsCount) cat.", tint: .purple)
                    }
                }
            }

            if let providerID = session.providerID {
                HStack(spacing: 6) {
                    Image(systemName: session.wasFallback ? "arrow.uturn.backward.circle" : "sparkles")
                        .font(.caption2).foregroundStyle(session.wasFallback ? .orange : .accentColor)
                    Text(providerID).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            if let ctx = session.contextTokens, let budget = session.contextBudget {
                HStack(spacing: 6) {
                    Text("Ctx: \(ctx)/\(budget) tokens")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ctx > budget * 90 / 100 ? .orange : .secondary)
                    if !session.truncations.isEmpty {
                        Text("tronq: \(session.truncations.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !session.toolCallsRequested.isEmpty {
                Text("Tools requested : \(session.toolCallsRequested.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !session.toolsExecuted.isEmpty {
                Text("Tools executed : \(session.toolsExecuted.map { "\($0.toolName)(\($0.durationMs)ms)" }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !session.postProcessingIssues.isEmpty {
                Text("PostProc : \(session.postProcessingIssues.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let err = session.error {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Helpers UI

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private func availabilityBadge(_ avail: AIAvailability) -> some View {
        let (label, color): (String, Color) = {
            switch avail {
            case .available: return ("actif", .green)
            case .unavailable(let reason): return (reason.rawValue, .red)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private func capabilitiesString(_ caps: AICapabilities) -> String {
        var list: [String] = []
        if caps.contains(.textGeneration) { list.append("text") }
        if caps.contains(.structuredOutput) { list.append("json") }
        if caps.contains(.toolCalling) { list.append("tools") }
        if caps.contains(.streaming) { list.append("stream") }
        if caps.contains(.vision) { list.append("vision") }
        if caps.contains(.offline) { list.append("offline") }
        if caps.contains(.onDevice) { list.append("on-device") }
        if caps.contains(.longContext) { list.append("long-ctx") }
        return list.joined(separator: " · ")
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment {
        case "positive": return .green
        case "frustrated": return .red
        case "discouraged": return .orange
        case "anxious": return .yellow
        default: return .gray
        }
    }
}
