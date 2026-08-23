import SwiftData
import SwiftUI

/// Écran "Ce que je sais de toi" — preview complète et interactive de tout
/// ce qui va dans le prompt système du coach à chaque message.
///
/// Loop 12 fixes :
///   - B4 : Bouton "Corriger" par ProfileField (ouvre `ProfileFieldsView`)
///   - M7 : Sections ajoutées : historique messages + awareness + sleep breakdown
///   - M8 : Refresh live via `.onReceive` NotificationCenter
struct CoachKnowledgePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = ViewModel()
    @State private var showingProfileEditor = false

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if !vm.profileFields.isEmpty {
                    Section {
                        ForEach(vm.profileFields, id: \.fieldID) { field in
                            profileRow(field)
                        }
                    } header: {
                        HStack {
                            Text("Profil confirmé")
                            Spacer()
                            Button("Corriger") { showingProfileEditor = true }
                                .font(.caption.weight(.medium))
                                .textCase(nil)
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

                if !vm.sleepBreakdownLine.isEmpty {
                    Section("Sommeil nuit dernière") {
                        Text(vm.sleepBreakdownLine).font(.subheadline)
                    }
                }

                if !vm.insightsBlock.isEmpty {
                    Section("Tendances cette semaine") {
                        Text(vm.insightsBlock)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }

                if !vm.recentMessages.isEmpty {
                    Section("Historique conversationnel (3 derniers)") {
                        ForEach(vm.recentMessages.indices, id: \.self) { i in
                            messageRow(vm.recentMessages[i])
                        }
                    }
                }

                if !vm.awarenessLine.isEmpty {
                    Section("Contexte du moment") {
                        Text(vm.awarenessLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showingProfileEditor) {
                ProfileFieldsView()
                    .onDisappear { vm.reload(context: modelContext) }
            }
            .onAppear { vm.reload(context: modelContext) }
            // Loop 12 fix M8 — refresh live si le user modifie un ProfileField
            // ou une mémoire depuis un autre écran ouvert en parallèle.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                vm.reload(context: modelContext)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            Text("Voici exactement ce que ton coach connaît sur toi. Ces infos sont envoyées à chaque message pour personnaliser sa réponse. Tape « Corriger » pour éditer ton profil.")
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
    private func messageRow(_ msg: AIMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(msg.role == "user" ? "Toi" : "Coach")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(msg.role == "user" ? .blue : .green)
            Text(msg.text.prefix(180) + (msg.text.count > 180 ? "…" : ""))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
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
        // Loop 12 fix m2 — remplace "70 %" par label lisible
        let (label, color): (String, Color) = {
            if confidence >= 0.85 { return ("fiable", .green) }
            if confidence >= 0.6  { return ("modéré", .orange) }
            return ("faible", .secondary)
        }()
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }
}

// MARK: - ViewModel

@MainActor
private final class ViewModel: ObservableObject {
    @Published var profileFields: [ProfileField] = []
    @Published var memories: [MemoryEntry] = []
    @Published var recentMessages: [AIMessage] = []
    @Published var cycleLine: String = ""
    @Published var goalsBlock: String = ""
    @Published var insightsBlock: String = ""
    @Published var sleepBreakdownLine: String = ""
    @Published var awarenessLine: String = ""

    func reload(context: ModelContext?) {
        profileFields = ProfileStore.shared.allFields()
        cycleLine = CycleAwareness.promptLine()
        goalsBlock = GoalsProgress.promptBlock()
        insightsBlock = CoachInsights.promptBlock()
        memories = fetchTopMemories()
        recentMessages = fetchRecentMessages(context: context)
        sleepBreakdownLine = fetchSleepBreakdownLine()
        awarenessLine = fetchAwarenessLine()
    }

    private func fetchTopMemories() -> [MemoryEntry] {
        guard let ctx = SharedModelContextProvider.shared.context else { return [] }
        var descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\.created, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        let all = (try? ctx.fetch(descriptor)) ?? []
        return Array((all.filter(\.isPinned) + all.filter { !$0.isPinned }).prefix(10))
    }

    private func fetchRecentMessages(context: ModelContext?) -> [AIMessage] {
        guard let ctx = context ?? SharedModelContextProvider.shared.context else { return [] }
        var descriptor = FetchDescriptor<AIMessage>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 8
        let all = (try? ctx.fetch(descriptor)) ?? []
        return Array(all.reversed().suffix(6))
    }

    /// Lit le blob `sleep_breakdown_last_night` publié par HealthAutoSync.
    private func fetchSleepBreakdownLine() -> String {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app"),
              let data = grp.data(forKey: "sleep_breakdown_last_night"),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        let deep = (d["deep"] as? Double) ?? 0
        let rem = (d["rem"] as? Double) ?? 0
        let awakenings = (d["awakenings"] as? Int) ?? 0
        let bedtime = d["bedtime"] as? String
        if deep == 0 && rem == 0 { return "" }
        var parts = [String(format: "%.1fh deep, %.1fh REM", deep, rem)]
        if awakenings > 0 { parts.append("\(awakenings) réveils") }
        if let b = bedtime { parts.append("coucher \(b)") }
        return parts.joined(separator: " · ")
    }

    /// Ligne compacte du contexte temporel/environnemental — proxy simple de
    /// ce que `AwarenessContext` injecte au prompt (heure + moment du jour).
    private func fetchAwarenessLine() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM, HH:mm"
        return f.string(from: .now)
    }
}
