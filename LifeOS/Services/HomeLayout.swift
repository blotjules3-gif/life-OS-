import Foundation

/// Les blocs de l'accueil, que l'utilisateur deplace et masque comme les
/// widgets d'un ecran d'accueil iOS.
enum HomeWidget: String, CaseIterable, Identifiable {
    case score, shortcuts, coach, agenda, habits, tasks, weekRecap, goals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .score:     return "Score du jour"
        case .shortcuts: return "Raccourcis"
        case .coach:     return "Ton coach"
        case .agenda:    return "Agenda du jour"
        case .habits:    return "Habitudes"
        case .tasks:     return "Tâches"
        case .weekRecap: return "Ta semaine"
        case .goals:     return "Objectifs du jour"
        }
    }

    var icon: String {
        switch self {
        case .score:     return "flame.fill"
        case .shortcuts: return "square.grid.2x2.fill"
        case .coach:     return "infinity"
        case .agenda:    return "calendar"
        case .habits:    return "checkmark.seal.fill"
        case .tasks:     return "checklist"
        case .weekRecap: return "chart.bar.fill"
        case .goals:     return "target"
        }
    }
}

/// Ordre et blocs masques de l'accueil, stockes en texte: "a,b,c|d,e".
/// Avant la barre, les blocs affiches dans l'ordre. Apres, les masques.
///
/// La lecture ne fait jamais disparaitre un bloc par accident: un bloc ajoute
/// dans une mise a jour, donc absent du texte enregistre, arrive a la FIN des
/// blocs affiches. Sans ca, une nouveaute resterait invisible chez tous ceux
/// qui ont deja range leur accueil.
struct HomeLayout: Equatable {
    static let storageKey = "homeLayout.v1"

    /// L'ordre d'avant la personnalisation, celui que l'accueil avait en dur.
    static let defaultOrder: [HomeWidget] =
        [.score, .shortcuts, .coach, .agenda, .habits, .tasks, .weekRecap, .goals]

    private(set) var visible: [HomeWidget]
    private(set) var hidden: [HomeWidget]

    static func parse(_ raw: String) -> HomeLayout {
        guard !raw.isEmpty else { return HomeLayout(visible: defaultOrder, hidden: []) }
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        func read(_ part: Substring?) -> [HomeWidget] {
            guard let part else { return [] }
            return part.split(separator: ",").compactMap { HomeWidget(rawValue: String($0)) }
        }
        var seen = Set<HomeWidget>()
        let vis = read(parts.first).filter { seen.insert($0).inserted }
        let hid = read(parts.count > 1 ? parts[1] : nil).filter { seen.insert($0).inserted }
        let newcomers = defaultOrder.filter { !seen.contains($0) }
        return HomeLayout(visible: vis + newcomers, hidden: hid)
    }

    var raw: String {
        visible.map(\.rawValue).joined(separator: ",") + "|" + hidden.map(\.rawValue).joined(separator: ",")
    }

    /// Deplace `widget` a la place de `target`, comme quand on survole un
    /// autre widget pendant un glisser: en descendant il passe apres, en
    /// montant il passe avant.
    mutating func move(_ widget: HomeWidget, to target: HomeWidget) {
        guard widget != target,
              let from = visible.firstIndex(of: widget),
              let to = visible.firstIndex(of: target) else { return }
        visible.remove(at: from)
        visible.insert(widget, at: to)
    }

    /// Un cran vers le haut ou le bas, pour VoiceOver: le glisser n'est pas
    /// faisable sans voir l'ecran.
    mutating func shift(_ widget: HomeWidget, by delta: Int) {
        guard let i = visible.firstIndex(of: widget) else { return }
        let j = min(max(0, i + delta), visible.count - 1)
        guard i != j else { return }
        visible.remove(at: i)
        visible.insert(widget, at: j)
    }

    mutating func hide(_ widget: HomeWidget) {
        guard let i = visible.firstIndex(of: widget) else { return }
        visible.remove(at: i)
        hidden.append(widget)
    }

    /// Un bloc remis s'ajoute en bas, comme un widget ajoute sur iOS.
    mutating func show(_ widget: HomeWidget) {
        guard let i = hidden.firstIndex(of: widget) else { return }
        hidden.remove(at: i)
        visible.append(widget)
    }
}
