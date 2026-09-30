import Foundation

/// Reponses d'un questionnaire pas encore applique, gardees entre deux lancements.
///
/// Avant (brief du 28 septembre): seule la PAGE atteinte etait retenue. Dix
/// questionnaires gardaient leurs reponses en memoire: l'app fermee, on
/// reprenait "a l'etape 3" avec les reponses remises aux valeurs par defaut.
///
/// Stockage en texte, par cle: simple, lisible, et un questionnaire qui change
/// de forme ignore les cles qu'il ne connait plus au lieu de planter.
struct SetupDraft: Equatable {
    private(set) var values: [String: String] = [:]

    init(values: [String: String] = [:]) { self.values = values }

    var isEmpty: Bool { values.isEmpty }

    private static let setSeparator = "\u{1F}"

    mutating func put(_ key: String, _ v: Int) { values[key] = String(v) }
    mutating func put(_ key: String, _ v: String) { values[key] = v }
    mutating func put(_ key: String, _ v: Bool) { values[key] = v ? "1" : "0" }
    mutating func put(_ key: String, _ v: Date) { values[key] = String(v.timeIntervalSince1970) }
    mutating func put(_ key: String, _ v: Set<String>) {
        values[key] = v.sorted().joined(separator: Self.setSeparator)
    }

    func int(_ key: String) -> Int? { values[key].flatMap(Int.init) }
    func string(_ key: String) -> String? { values[key] }
    func bool(_ key: String) -> Bool? { values[key].map { $0 == "1" } }
    func date(_ key: String) -> Date? { values[key].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
    func set(_ key: String) -> Set<String>? {
        guard let raw = values[key] else { return nil }
        return raw.isEmpty ? [] : Set(raw.components(separatedBy: Self.setSeparator))
    }
}

/// Ce qu'un questionnaire donne a `SetupFlow` pour garder ses reponses.
struct SetupDraftIO {
    let save: () -> SetupDraft
    let restore: (SetupDraft) -> Void
}

extension CategorySetup {
    private static func answersKey(_ c: AppCategory) -> String { "setup.draftAnswers.\(c.rawValue)" }

    static func saveAnswers(_ c: AppCategory, _ draft: SetupDraft, defaults d: UserDefaults = .standard) {
        guard !d.bool(forKey: "setup.done.\(c.rawValue)") else { return }
        d.set(draft.values, forKey: answersKey(c))
    }

    /// Les reponses d'un brouillon EN COURS seulement: un questionnaire termine
    /// se rouvre depuis les reglages appliques, pas depuis un vieux brouillon.
    static func loadAnswers(_ c: AppCategory, defaults d: UserDefaults = .standard) -> SetupDraft? {
        guard case .partial = status(c, defaults: d),
              let dict = d.dictionary(forKey: answersKey(c)) as? [String: String], !dict.isEmpty
        else { return nil }
        return SetupDraft(values: dict)
    }

    static func clearAnswers(_ c: AppCategory, defaults d: UserDefaults = .standard) {
        d.removeObject(forKey: answersKey(c))
    }
}
