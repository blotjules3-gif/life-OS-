import SwiftUI

/// Écran "Ce que je sais de toi" — preview transparente de tout ce qui va
/// dans le prompt système du coach à chaque message.
///
/// Trust building : l'user voit exactement quelles données personnelles sont
/// envoyées à l'IA (Apple Intelligence local ou provider cloud). Peut corriger
/// ou supprimer par item.
///
/// Structuré en sections cohérentes avec ce que `UserContextBuilder` injecte :
///   - Profil confirmé (ProfileField)
///   - Cycle menstruel (si applicable)
///   - Objectifs actifs
///   - Sommeil dernière nuit
///   - Mémoire long terme
///   - Insights hebdo
struct CoachKnowledgePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ViewModel()

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if !vm.profileFields.isEmpty {
                    Section("Profil confirmé") {
                        ForEach(vm.profileFields, id: \.fieldID) { field in
                            profileRow(field)
                        }
                    }
                }

                if !vm.cycleLine.isEmpty {
                    Section("Cycle") {
                        Text(vm.cycleLine).font(.subheadline)
                    }
                }

                if !vm.goalsBlock.isEmpty {
                    Section("Objectifs actifs") {
                        Text(vm.goalsBlock)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }

                if !vm.insightsBlock.isEmpty {
                    Section("Tendances cette semaine") {
                        Text(vm.insightsBlock)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }

                if !vm.memories.isEmpty {
                    Section("Mémoire long terme (top 10)") {
                        ForEach(vm.memories, id: \.id) { mem in
                            memoryRow(mem)
                        }
                    }
                }
            }
            .navigationTitle("Ce que je sais")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear { vm.reload() }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            Text("Voici exactement ce que ton coach connaît sur toi. Ces infos sont envoyées à chaque message pour personnaliser sa réponse. Tu peux les corriger ou les effacer via les autres écrans dédiés.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func profileRow(_ field: ProfileField) -> some View {
        let spec = ProfileFieldCatalog.all[field.fieldID]
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec?.displayName ?? field.fieldID)
                    .font(.subheadline)
                Text(field.valueString + (spec?.unit.map { " \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            confidenceBadge(field.confidence)
        }
    }

    @ViewBuilder
    private func memoryRow(_ mem: MemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(mem.category)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if mem.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Text(mem.created, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(mem.content)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color = confidence >= 0.8 ? .green : (confidence >= 0.6 ? .orange : .secondary)
        Text(String(format: "%.0f %%", confidence * 100))
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(color)
    }
}

// MARK: - ViewModel

@MainActor
private final class ViewModel: ObservableObject {
    @Published var profileFields: [ProfileField] = []
    @Published var memories: [MemoryEntry] = []
    @Published var cycleLine: String = ""
    @Published var goalsBlock: String = ""
    @Published var insightsBlock: String = ""

    func reload() {
        profileFields = ProfileStore.shared.allFields()
        cycleLine = CycleAwareness.promptLine()
        goalsBlock = GoalsProgress.promptBlock()
        insightsBlock = CoachInsights.promptBlock()
        memories = fetchTopMemories()
    }

    private func fetchTopMemories() -> [MemoryEntry] {
        guard let ctx = SharedModelContextProvider.shared.context else { return [] }
        var descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\.isPinned, order: .reverse), SortDescriptor(\.created, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        return (try? ctx.fetch(descriptor)) ?? []
    }
}
