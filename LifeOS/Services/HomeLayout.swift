import Foundation

/// Les blocs de l'accueil, que l'utilisateur deplace et masque comme les
/// widgets d'un ecran d'accueil iOS.
///
/// Lot 8 : quatre blocs organisent l'accueil (Maintenant, Aujourd'hui, A surveiller,
/// Capture rapide). Les anciens restent disponibles dans la galerie.
enum HomeWidget: String, CaseIterable, Identifiable {
    case now, capture, today, watch
    case score, shortcuts, coach, agenda, habits, tasks, weekRecap, goals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .now:       return "Maintenant"
        case .capture:   return "Capture rapide"
        case .today:     return "Aujourd'hui"
        case .watch:     return "À surveiller"
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
        case .now:       return "arrow.right.circle.fill"
        case .capture:   return "square.and.pencil"
        case .today:     return "sun.max.fill"
        case .watch:     return "gauge.with.dots.needle.50percent"
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

    /// Une ligne d'explication dans la galerie.
    var blurb: String {
        switch self {
        case .now:       return "La prochaine chose à faire."
        case .capture:   return "Note une tâche, une dépense ou une idée."
        case .today:     return "Agenda, 3 priorités et habitudes du jour."
        case .watch:     return "Les chiffres que tu choisis de suivre."
        case .score:     return "Ton score et ta série."
        case .shortcuts: return "Tes outils favoris."
        case .coach:     return "Les conseils de ton coach."
        case .agenda:    return "Ce qui est prévu dans tes modules."
        case .habits:    return "Toutes tes habitudes du jour."
        case .tasks:     return "Tes tâches ouvertes."
        case .weekRecap: return "Le bilan des 7 derniers jours."
        case .goals:     return "Pas, eau, calories."
        }
    }

    /// Blocs du lot 8, ajoutes aux accueils deja ranges.
    static let lot8Kinds: [HomeWidget] = [.now, .capture, .today, .watch]
}

/// Ordre et blocs masques de l'accueil, stockes en texte: "a,b,c|d,e".
/// Avant la barre, les blocs affiches dans l'ordre. Apres, les masques.
///
/// La lecture ne fait jamais disparaitre un bloc par accident: un bloc ajoute
/// dans une mise a jour, donc absent du texte enregistre, arrive a la FIN des
/// blocs affiches. Sans ca, une nouveaute resterait invisible chez tous ceux
/// qui ont deja range leur accueil.
struct HomeLayout: Equatable {
    /// Lot 8 : nouvelle cle. L'ancienne est lue une fois pour la reprise.
    static let storageKey = "homeLayout.v2"
    static let legacyKey = "homeLayout.v1"

    /// L'ordre d'avant le lot 8, celui que l'accueil avait en dur.
    static let legacyOrder: [HomeWidget] =
        [.score, .shortcuts, .coach, .agenda, .habits, .tasks, .weekRecap, .goals]

    /// Ordre complet de reference : un bloc inconnu du texte stocke est ajoute dans
    /// cet ordre.
    static let defaultOrder: [HomeWidget] = HomeWidget.lot8Kinds + legacyOrder

    private(set) var visible: [HomeWidget]
    private(set) var hidden: [HomeWidget]

    init(visible: [HomeWidget], hidden: [HomeWidget]) {
        self.visible = visible
        self.hidden = hidden
    }

    /// `raw` vide = accueil par defaut (voir `defaultLayout(for:)`).
    static func parse(_ raw: String, domains: [AppCategory] = []) -> HomeLayout {
        guard !raw.isEmpty else { return defaultLayout(for: domains) }
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

    /// Reprise de l'accueil range avant le lot 8 : l'ordre et les blocs masques de
    /// l'utilisateur restent tels quels, les 4 nouveaux blocs s'ajoutent a la fin
    /// (meme regle que tout bloc ajoute par une mise a jour).
    static func migrate(legacyRaw: String) -> HomeLayout {
        let old = parse(legacyRaw.isEmpty ? legacyOrder.map(\.rawValue).joined(separator: ",") + "|" : legacyRaw)
        return old
    }

    /// Accueil d'un nouvel utilisateur : les 4 blocs du lot 8, le coach et les
    /// raccourcis. Les anciens blocs sont dans la galerie, pas sur l'ecran : on ne
    /// surcharge pas l'accueil avec tout.
    static func defaultLayout(for domains: [AppCategory]) -> HomeLayout {
        var visible: [HomeWidget] = [.now, .capture, .today, .watch, .shortcuts, .coach]
        // Un domaine Productivite garde la liste des taches visible.
        if domains.contains(.productivity) { visible.insert(.tasks, at: 4) }
        let hidden = legacyOrder.filter { !visible.contains($0) }
        return HomeLayout(visible: visible, hidden: hidden)
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

// MARK: - Chargement et reprise (UserDefaults)

enum HomeLayoutStore {
    /// Texte de l'accueil a utiliser. Fait la reprise v1 -> v2 une seule fois et
    /// fige l'accueil par defaut d'un nouvel utilisateur (un changement de domaines
    /// plus tard ne reorganise jamais l'ecran tout seul).
    @discardableResult
    static func ensure(_ defaults: UserDefaults = .standard) -> String {
        if let v2 = defaults.string(forKey: HomeLayout.storageKey), !v2.isEmpty { return v2 }
        let layout: HomeLayout
        if let v1 = defaults.string(forKey: HomeLayout.legacyKey), !v1.isEmpty {
            layout = HomeLayout.migrate(legacyRaw: v1)
        } else {
            layout = HomeLayout.defaultLayout(for: PriorityDomains.current(defaults))
        }
        // Le bloc « A surveiller » arrive avec des indicateurs tires des domaines,
        // pour un nouvel utilisateur comme pour une reprise.
        seedIndicatorsIfNeeded(defaults)
        defaults.set(layout.raw, forKey: HomeLayout.storageKey)
        return layout.raw
    }

    /// « Revenir a l'ordre d'origine » : l'accueil par defaut des domaines actuels.
    static func resetRaw(_ defaults: UserDefaults = .standard) -> String {
        HomeLayout.defaultLayout(for: PriorityDomains.current(defaults)).raw
    }

    static func seedIndicatorsIfNeeded(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: HomeIndicator.storageKey) == nil else { return }
        let list = HomeIndicator.defaults(for: PriorityDomains.current(defaults))
        defaults.set(list.map(\.rawValue).joined(separator: ","), forKey: HomeIndicator.storageKey)
    }
}

// MARK: - Indicateurs « A surveiller »

/// Ce que l'utilisateur peut suivre dans le bloc « A surveiller ».
enum HomeIndicator: String, CaseIterable, Identifiable {
    case water, macros, steps, sleep, budget, weight, fasting, focus, habits

    static let storageKey = "homeIndicators"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .water:   return "Eau"
        case .macros:  return "Calories et macros"
        case .steps:   return "Pas"
        case .sleep:   return "Sommeil de la nuit"
        case .budget:  return "Budget du mois"
        case .weight:  return "Poids"
        case .fasting: return "Jeûne"
        case .focus:   return "Concentration"
        case .habits:  return "Habitudes"
        }
    }

    var icon: String {
        switch self {
        case .water:   return "drop.fill"
        case .macros:  return "fork.knife"
        case .steps:   return "figure.walk"
        case .sleep:   return "moon.zzz.fill"
        case .budget:  return "eurosign.circle.fill"
        case .weight:  return "scalemass.fill"
        case .fasting: return "hourglass"
        case .focus:   return "brain.head.profile"
        case .habits:  return "checkmark.seal.fill"
        }
    }

    /// Domaine qui rend cet indicateur pertinent (pour la couleur et la raison).
    var domain: AppCategory {
        switch self {
        case .water, .macros, .fasting: return .nutrition
        case .steps, .weight:           return .fitness
        case .sleep:                    return .sleep
        case .budget:                   return .finance
        case .focus:                    return .mind
        case .habits:                   return .productivity
        }
    }

    /// Indicateurs proposes pour un domaine.
    static func forDomain(_ d: AppCategory) -> [HomeIndicator] {
        switch d {
        case .nutrition:    return [.water, .macros]
        case .fitness:      return [.steps, .weight]
        case .sleep:        return [.sleep]
        case .finance, .invest: return [.budget]
        case .mind:         return [.focus]
        case .productivity: return [.habits, .focus]
        case .looks:        return [.weight]
        case .medical, .cycle: return [.sleep, .water]
        default:            return []
        }
    }

    /// Choix par defaut d'apres les domaines, 4 au plus, eau + pas + habitudes si rien.
    static func defaults(for domains: [AppCategory]) -> [HomeIndicator] {
        var out: [HomeIndicator] = []
        for d in domains { for i in forDomain(d) where !out.contains(i) { out.append(i) } }
        if out.isEmpty { out = [.water, .steps, .habits] }
        return Array(out.prefix(4))
    }

    static func parse(_ raw: String) -> [HomeIndicator] {
        var seen = Set<HomeIndicator>()
        return raw.split(separator: ",").compactMap { HomeIndicator(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
    }
}

// MARK: - Recommandations expliquees

/// Une suggestion de l'accueil, toujours avec sa raison, et que l'on peut ignorer.
struct HomeRecommendation: Identifiable, Equatable {
    enum Kind: Equatable { case indicator(HomeIndicator), shortcut(String) }
    let kind: Kind
    let domain: AppCategory
    var id: String {
        switch kind {
        case .indicator(let i): return "ind.\(i.rawValue)"
        case .shortcut(let s):  return "sc.\(s)"
        }
    }
    var reason: String { PriorityDomains.reason(domain) }
}

enum HomeRecommendationEngine {
    static let dismissedKey = "homeRecoDismissed"

    /// Raccourcis proposes pour un domaine (valeurs brutes de `ShortcutTool`).
    static func shortcuts(for d: AppCategory) -> [String] {
        switch d {
        case .nutrition:    return ["calories", "water"]
        case .fitness:      return ["tabata"]
        case .sleep:        return ["bedtime"]
        case .mind:         return ["focus", "mood"]
        case .productivity: return ["todo"]
        case .finance:      return ["budget"]
        case .invest:       return ["portfolio"]
        case .learning:     return ["flashcards"]
        case .looks:        return ["progressPhotos"]
        default:            return []
        }
    }

    /// Au plus `limit` suggestions, dans l'ordre des domaines : ce qui n'est pas deja
    /// suivi et que l'utilisateur n'a pas ignore.
    static func recommendations(domains: [AppCategory], indicators: [HomeIndicator],
                                shortcuts: [String], dismissed: Set<String>, limit: Int = 2) -> [HomeRecommendation] {
        var out: [HomeRecommendation] = []
        for d in domains {
            for i in HomeIndicator.forDomain(d) where !indicators.contains(i) {
                let r = HomeRecommendation(kind: .indicator(i), domain: d)
                if !dismissed.contains(r.id) && !out.contains(r) { out.append(r) }
            }
            for s in Self.shortcuts(for: d) where !shortcuts.contains(s) {
                let r = HomeRecommendation(kind: .shortcut(s), domain: d)
                if !dismissed.contains(r.id) && !out.contains(r) { out.append(r) }
            }
        }
        return Array(out.prefix(limit))
    }
}
