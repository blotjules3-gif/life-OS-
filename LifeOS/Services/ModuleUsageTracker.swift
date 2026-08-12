import Foundation

/// Suit l'usage réel des modules LifeOS.
///
/// **Pourquoi** : la centralisation n'a de valeur que si l'utilisateur ouvre
/// effectivement plusieurs modules. Sans données factuelles, impossible de savoir
/// si un module mérite du temps de dev, ou s'il faut le simplifier voire l'archiver.
///
/// **Utilisation** :
///   ```swift
///   NavigationLink { CategoryHubView(category: cat) }
///       .simultaneousGesture(TapGesture().onEnded { ModuleUsageTracker.shared.track(cat) })
///   ```
/// Ou plus simple, appeler `track()` dès qu'un hub s'ouvre :
///   ```swift
///   .onAppear { ModuleUsageTracker.shared.track(.fitness) }
///   ```
///
/// **Lecture des données** : `ModuleUsageTracker.shared.report()` retourne les
/// modules triés par nombre d'ouvertures. À afficher dans un écran debug
/// (`#if DEBUG`) pour prendre la décision produit à ~J14.
///
/// Ne collecte AUCUNE donnée personnelle — juste compteurs locaux dans
/// UserDefaults standard. Aucun envoi réseau.
@MainActor
final class ModuleUsageTracker {
    static let shared = ModuleUsageTracker()
    private init() {}

    private let defaults = UserDefaults.standard
    private let prefix = "module_usage_"
    private let lastSuffix = "_last"
    private let firstSuffix = "_first"

    /// Enregistre une ouverture du module.
    /// Idempotent par jour : n'incrémente pas 2 fois dans la même minute
    /// (évite les doubles-comptages sur re-render SwiftUI).
    func track(_ module: AppCategory) {
        let now = Date()
        let key = prefix + module.rawValue
        let lastKey = key + lastSuffix
        let firstKey = key + firstSuffix

        // Anti-doublon : ne compte pas si dernière ouverture < 60s
        if let last = defaults.object(forKey: lastKey) as? Date,
           now.timeIntervalSince(last) < 60 {
            return
        }

        let count = defaults.integer(forKey: key) + 1
        defaults.set(count, forKey: key)
        defaults.set(now, forKey: lastKey)
        if defaults.object(forKey: firstKey) == nil {
            defaults.set(now, forKey: firstKey)
        }
    }

    /// Rapport trié par nombre d'ouvertures décroissant.
    /// Utile pour un écran debug ou une décision produit ("quel module tue-t-on").
    struct Report {
        let module: AppCategory
        let count: Int
        let firstSeen: Date?
        let lastSeen: Date?

        /// Ouvertures par jour depuis le premier usage.
        var perDay: Double {
            guard let first = firstSeen else { return 0 }
            let days = max(1.0, Date().timeIntervalSince(first) / 86_400)
            return Double(count) / days
        }
    }

    func report() -> [Report] {
        AppCategory.allCases.map { c in
            let key = prefix + c.rawValue
            return Report(
                module: c,
                count: defaults.integer(forKey: key),
                firstSeen: defaults.object(forKey: key + firstSuffix) as? Date,
                lastSeen: defaults.object(forKey: key + lastSuffix) as? Date
            )
        }
        .sorted { $0.count > $1.count }
    }

    /// Modules avec 0 ouverture — candidats à archiver.
    func unusedModules() -> [AppCategory] {
        report().filter { $0.count == 0 }.map(\.module)
    }

    /// Modules ouverts au moins 3 fois par semaine — cœur d'usage réel.
    func coreModules() -> [AppCategory] {
        report().filter { $0.perDay >= 3.0 / 7.0 }.map(\.module)
    }

    /// Reset complet — pour debug ou nouveau cycle de mesure.
    func reset() {
        for c in AppCategory.allCases {
            let key = prefix + c.rawValue
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: key + lastSuffix)
            defaults.removeObject(forKey: key + firstSuffix)
        }
    }

    /// Résumé texte prêt pour la console ou un rapport.
    func textReport() -> String {
        let rows = report()
        var out = "═══ Module Usage LifeOS ═══\n"
        for r in rows {
            let count = String(r.count).padding(toLength: 5, withPad: " ", startingAt: 0)
            let perDay = String(format: "%.2f", r.perDay).padding(toLength: 6, withPad: " ", startingAt: 0)
            out += "\(count) \(perDay)/j  \(r.module.rawValue)\n"
        }
        out += "═══════════════════════════"
        return out
    }
}
