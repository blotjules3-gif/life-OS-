import SwiftUI
import SwiftData

// MARK: - Recherche globale
//
// Un seul champ : les outils de tous les espaces ET les contenus (taches, notes,
// habitudes, contacts, documents, reves, repas, depenses, voyages). Ouverte depuis
// Mes espaces, l'accueil ou le lien `lifeos://search?q=`.

struct GlobalSearchView: View {
    var initialQuery: String = ""

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ToolNames.storageKey) private var toolNamesRaw = ""

    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var pushedTool: CategoryTool?
    @State private var coverTool: CategoryTool?
    @State private var openRecord: SearchRecordRef?
    @State private var seeded = false

    init(initialQuery: String = "") {
        self.initialQuery = initialQuery
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if trimmed.isEmpty {
                    ContentUnavailableView {
                        Label("Rechercher dans LifeOS", systemImage: "magnifyingglass")
                    } description: {
                        Text("Un outil, une tâche, une note, un contact, un document, un repas, une dépense ou un voyage.")
                    }
                } else if results.isEmpty && !searching {
                    ContentUnavailableView.search(text: trimmed)
                } else {
                    resultList
                }
            }
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Outil, tâche, note, contact…")
            .autocorrectionDisabled()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .navigationDestination(item: $pushedTool) { $0.dest() }
            .fullScreenCover(item: $coverTool) { $0.dest() }
            .sheet(item: $openRecord) { SearchRecordDestination(ref: $0) }
            // Attente de 250 ms apres la derniere frappe : pas de recherche par lettre.
            .task(id: query) {
                let q = trimmed
                guard !q.isEmpty else { results = []; searching = false; return }
                searching = true
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                results = SearchIndex.search(q, in: ctx)
                searching = false
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                if !initialQuery.isEmpty { query = initialQuery }
            }
        }
    }

    private var resultList: some View {
        List {
            ForEach(SearchIndex.grouped(results), id: \.kind) { group in
                Section {
                    ForEach(group.hits) { hit in
                        Button { open(hit) } label: { SearchHitRow(hit: hit) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Label(group.kind.groupTitle, systemImage: group.kind.icon)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: results.map(\.id))
    }

    private func open(_ hit: SearchHit) {
        Haptics.tap()
        if let record = hit.record, SearchRecordDestination.hasEditor(record.kind) {
            openRecord = record
            return
        }
        guard let cat = hit.toolCategory, let name = hit.toolName,
              let tool = DeepLink.resolveTool(cat, name) else { return }
        if tool.fullScreen { coverTool = tool } else { pushedTool = tool }
    }
}

extension SearchRecordRef: Identifiable {}

/// Ligne de resultat : icone teintee de l'espace, titre, detail. Le type est dit
/// en toutes lettres pour la lecture sans couleur et VoiceOver.
struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: hit.icon, tint: hit.category.tint, size: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !hit.subtitle.isEmpty {
                    Text(hit.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.title), \(hit.kind.groupTitle)")
        .accessibilityHint(hit.subtitle)
    }
}

/// Ouvre l'element lui-meme quand il a un editeur, sinon l'outil qui le contient.
struct SearchRecordDestination: View {
    let ref: SearchRecordRef
    @Environment(\.modelContext) private var ctx

    static func hasEditor(_ kind: SearchKind) -> Bool {
        switch kind {
        case .task, .note, .dream, .trip: return true
        default: return false
        }
    }

    var body: some View {
        switch ref.kind {
        case .task:
            if let t = ctx.model(for: ref.id) as? TodoItem, !t.isDeleted { TodoEditor(task: t) } else { missing }
        case .note:
            if let n = ctx.model(for: ref.id) as? Note, !n.isDeleted { NavigationStack { NoteEditor(note: n) } } else { missing }
        case .dream:
            if let d = ctx.model(for: ref.id) as? DreamEntry, !d.isDeleted { DreamEditor(dream: d) } else { missing }
        case .trip:
            if let v = ctx.model(for: ref.id) as? Trip, !v.isDeleted { NavigationStack { TripDetailView(trip: v) } } else { missing }
        default:
            if let home = ref.kind.home, let tool = DeepLink.resolveTool(home.0, home.1) {
                NavigationStack { tool.dest() }
            } else { missing }
        }
    }

    private var missing: some View {
        ContentUnavailableView("Élément introuvable", systemImage: "questionmark.folder",
                               description: Text("Il a peut-être été supprimé."))
    }
}
