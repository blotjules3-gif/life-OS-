import SwiftUI

#if DEBUG
/// Ouvre chaque outil de chaque categorie, l'un apres l'autre, dans un vrai
/// `NavigationStack`, et note lesquels sont reellement apparus.
///
/// Pourquoi: sur bureau, cinq outils ne s'ouvraient pas parce que le panneau de
/// categorie n'avait pas de conteneur de navigation. Taper les 87 tuiles a la
/// main a chaque passe ne tient pas; ce passage automatique le fait en deux
/// minutes et laisse une preuve ecrite.
///
/// Sortie: `Documents/routesmoke.txt`, reecrit apres CHAQUE outil. Si l'app
/// plante, la derniere ligne "OUVERTURE" sans "OK" designe le coupable.
/// Lancement: `-routeSmoke` (et `-desktop` pour la mise en page bureau).
struct RouteSmokeView: View {
    private struct Item: Hashable {
        let category: AppCategory
        let index: Int
        let title: String
        let fullScreen: Bool
    }

    private let items: [Item] = AppCategory.allCases.flatMap { c in
        c.tools.enumerated().map { Item(category: c, index: $0.offset, title: $0.element.title,
                                        fullScreen: $0.element.fullScreen) }
    }

    @State private var path: [Item] = []
    @State private var cover: Item?
    @State private var cursor = 0
    @State private var lines: [String] = []
    @State private var appeared: Set<Int> = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                Text("Passage des routes").font(.headline)
                Text("\(min(cursor, items.count)) / \(items.count)").monospacedDigit()
            }
            .navigationDestination(for: Item.self) { item in
                tool(item)
            }
        }
        .fullScreenCover(item: Binding(get: { cover.map(Wrapped.init) }, set: { cover = $0?.item })) { w in
            tool(w.item)
        }
        .task { await run() }
    }

    private struct Wrapped: Identifiable { let item: Item; var id: Item { item } }

    private func tool(_ item: Item) -> some View {
        item.category.tools[item.index].dest()
            .onAppear { appeared.insert(key(item)) }
    }

    private func key(_ i: Item) -> Int { i.category.hashValue &* 31 &+ i.index }

    @MainActor
    private func run() async {
        write("# \(items.count) outils, \(Date().formatted(date: .numeric, time: .standard))")
        for (n, item) in items.enumerated() {
            cursor = n
            write("OUVERTURE \(item.category.rawValue) / \(item.title)")
            if item.fullScreen { cover = item } else { path = [item] }
            // Laisser le temps a la vue de s'installer et a son onAppear de tourner.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let ok = appeared.contains(key(item))
            lines[lines.count - 1] += ok ? "  OK" : "  ABSENTE"
            flush()
            cover = nil; path = []
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        cursor = items.count
        let missing = lines.filter { $0.hasSuffix("ABSENTE") }.count
        write("# FIN: \(items.count - missing) apparus, \(missing) absents")
    }

    private func write(_ line: String) {
        lines.append(line)
        flush()
    }

    private func flush() {
        let dir = AppPaths.documents
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("routesmoke.txt"),
                                                  atomically: true, encoding: .utf8)
    }
}
#endif
