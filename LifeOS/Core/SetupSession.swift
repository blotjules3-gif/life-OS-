import Foundation

// MARK: - Etat d'un questionnaire

/// Ou en est l'utilisateur avec le questionnaire d'une categorie.
///
/// Avant, seul "fait / pas fait" existait (`setup.done.*`), plus un drapeau "deja
/// propose". Un questionnaire abandonne a l'etape 5 repartait de l'etape 1, et rien
/// ne distinguait "jamais commence" de "ignore volontairement".
enum SetupStatus: Equatable {
    case notStarted
    case skipped
    case partial(page: Int, of: Int)
    case completed
}

extension CategorySetup {
    private static func key(_ what: String, _ c: AppCategory) -> String { "setup.\(what).\(c.rawValue)" }

    static func status(_ c: AppCategory, defaults d: UserDefaults = .standard) -> SetupStatus {
        if d.bool(forKey: key("done", c)) { return .completed }
        switch d.string(forKey: key("state", c)) {
        case "skipped": return .skipped
        case "partial":
            let total = max(1, d.integer(forKey: key("pageCount", c)))
            return .partial(page: min(d.integer(forKey: key("draftPage", c)), total - 1), of: total)
        default: return .notStarted
        }
    }

    /// "Plus tard": garde la page atteinte pour reprendre au meme endroit.
    static func saveDraft(_ c: AppCategory, page: Int, pageCount: Int, answered: Bool,
                          defaults d: UserDefaults = .standard) {
        guard !d.bool(forKey: key("done", c)) else { return }
        d.set(answered || page > 0 ? "partial" : "skipped", forKey: key("state", c))
        d.set(page, forKey: key("draftPage", c))
        d.set(pageCount, forKey: key("pageCount", c))
    }

    static func markCompleted(_ c: AppCategory, defaults d: UserDefaults = .standard) {
        d.set(true, forKey: key("done", c))
        d.set("completed", forKey: key("state", c))
        d.removeObject(forKey: key("draftPage", c))
    }

    /// Page d'ouverture: la page du brouillon, bornee a la longueur actuelle du
    /// questionnaire. Un questionnaire deja termine s'ouvre au debut, pre-rempli.
    static func resumePage(_ c: AppCategory, pageCount: Int, defaults d: UserDefaults = .standard) -> Int {
        guard case .partial = status(c, defaults: d), pageCount > 0 else { return 0 }
        return min(max(0, d.integer(forKey: key("draftPage", c))), pageCount - 1)
    }
}

// MARK: - Session: appliquer, montrer, garder ou annuler

/// Une ouverture de questionnaire.
///
/// Regle: RIEN n'est ecrit en base avant "Appliquer". Les commits des modules
/// (programme de sport regenere, articles de courses, comptes) ne tournent qu'a
/// l'acceptation. L'apercu est calcule a partir des reponses elles-memes.
///
/// Pourquoi pas "appliquer puis defaire": mesure le 28 septembre, le gestionnaire
/// d'annulation de SwiftData retire bien une insertion enregistree mais ne REND
/// PAS un objet supprime et enregistre. Un "Annuler" aurait laisse l'ancien
/// programme de sport efface. Test `testCancelRevertsSavedInsertsDeletesAndEdits`
/// supprime avec cette decision.
///
/// Reste a proteger: certains questionnaires ecrivent des REGLAGES a chaque choix.
/// La session les photographie a l'ouverture et les remet si on annule.
@MainActor
final class SetupSession {
    let category: AppCategory
    private let defaults: UserDefaults
    private var snapshot: [String: Any] = [:]
    private var doneAtBegin = false

    /// Cles de tenue interne: ecrites par l'app pendant la session pour d'autres
    /// raisons. Ni montrees comme un changement, ni remises a l'annulation, sinon
    /// annuler un questionnaire effacerait une ecriture sans rapport.
    static let bookkeepingPrefixes = ["setup.", "analytics.", "engagement.", "demoSeed.",
                                      "NS", "Apple", "com.apple.", "WebKit", "last", "tabata_last"]

    init(category: AppCategory, defaults: UserDefaults = .standard) {
        self.category = category
        self.defaults = defaults
    }

    /// Seuls les reglages que les questionnaires ecrivent au fil des choix sont
    /// suivis. Mesure au simulateur: pendant un questionnaire, l'app ecrit aussi
    /// des caches (noms d'outils, suggestion de la semaine). Les suivre les
    /// affichait dans l'apercu comme des "reponses", et "Annuler" les aurait
    /// remis en arriere sans raison.
    static var watchedKeys: Set<String> { Set(SetupLabels.names.keys) }

    private func domain() -> [String: Any] {
        defaults.dictionaryRepresentation().filter {
            Self.watchedKeys.contains($0.key) && !Self.isBookkeeping($0.key)
        }
    }

    private static func isBookkeeping(_ k: String) -> Bool {
        bookkeepingPrefixes.contains { k.hasPrefix($0) }
    }

    func begin() {
        snapshot = domain()
        doneAtBegin = defaults.bool(forKey: "setup.done.\(category.rawValue)")
    }

    /// Le questionnaire etait-il deja termine quand on l'a ouvert (mode "modifier").
    var wasCompleted: Bool { doneAtBegin }

    struct Change: Identifiable, Equatable {
        let key: String
        let label: String
        let before: String
        let after: String
        var id: String { key }

        /// Pour les apercus fournis par les modules, a partir de leurs reponses.
        static func make(_ label: String, _ before: String, _ after: String) -> Change? {
            before == after ? nil : Change(key: label, label: label, before: before, after: after)
        }
    }

    /// Reglages deja modifies pendant le questionnaire (modules qui ecrivent au fil
    /// des choix).
    func pendingChanges() -> [Change] {
        let now = domain()
        let keys = Set(snapshot.keys).union(now.keys)
        return keys.compactMap { k -> Change? in
            let a = snapshot[k], b = now[k]
            guard !Self.same(a, b) else { return nil }
            return Change(key: k, label: SetupLabels.label(for: k),
                          before: SetupLabels.format(a, key: k), after: SetupLabels.format(b, key: k))
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Remet les reglages comme a l'ouverture. La base n'a pas besoin d'etre
    /// touchee: elle n'a rien recu.
    func cancel() {
        let now = domain()
        for (k, _) in now where snapshot[k] == nil { defaults.removeObject(forKey: k) }
        for (k, v) in snapshot where !Self.same(v, now[k]) { defaults.set(v, forKey: k) }
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x as NSObject, y as NSObject): return x.isEqual(y)
        default: return false
        }
    }
}

// MARK: - Libelles lisibles pour l'apercu

/// Noms en clair des reglages que les questionnaires touchent. Une cle inconnue
/// s'affiche quand meme, avec son nom technique, plutot que d'etre cachee.
enum SetupLabels {
    static let names: [String: (String, String)] = [
        "kcalGoal": ("Objectif calories", "kcal"),
        "userGoalFit": ("Objectif sport", ""),
        "waterGoal": ("Objectif eau", "ml"),
        "proteinGoal": ("Objectif protéines", "g"),
        "userGender": ("Sexe", ""),
        "userAge": ("Âge", "ans"),
        "userWeight": ("Poids", "kg"),
        "userHeight": ("Taille", "cm"),
        "userActivity": ("Niveau d'activité", ""),
        "budgetGoal": ("Budget mensuel", "€"),
        "stepGoal": ("Objectif de pas", "pas"),
        "focusMinGoal": ("Minutes de focus par jour", "min"),
        "focusLen": ("Durée d'un Pomodoro", "min"),
        "socialMaxMin": ("Réseaux sociaux max", "min"),
        "meditGoal": ("Méditation par jour", "min"),
        "wakeupHour": ("Heure de réveil", "h"),
        "wakeupEnabled": ("Réveil activé", ""),
        "sleepTargetHours": ("Durée de sommeil visée", "h"),
        "skinType": ("Type de peau", ""),
        "cycleLength": ("Durée du cycle", "jours"),
    ]

    static func label(for key: String) -> String { names[key]?.0 ?? key }

    static func format(_ v: Any?, key: String) -> String {
        guard let v else { return "—" }
        let unit = names[key]?.1 ?? ""
        let text: String
        switch v {
        case let b as Bool: text = b ? "Oui" : "Non"
        case let n as NSNumber:
            let d = n.doubleValue
            text = d.rounded() == d ? "\(Int(d))" : String(format: "%.1f", d)
        case let s as String: text = s.isEmpty ? "—" : s
        case let date as Date:
            text = date.formatted(date: .abbreviated, time: .omitted)
        default: text = String(describing: v)
        }
        return unit.isEmpty || text == "—" ? text : "\(text) \(unit)"
    }
}
