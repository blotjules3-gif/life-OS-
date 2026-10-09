import Foundation

// MARK: - Reprise d'une activite apres fermeture de l'app
//
// Une lecon, une seance ou un minuteur doit reprendre la ou il en etait quand
// l'app a ete tuee. Chaque genre d'activite garde UN instantane Codable dans
// UserDefaults, avec son heure d'ecriture. Un instantane trop vieux est oublie
// au lieu d'etre propose: reprendre une lecon d'il y a trois jours au milieu
// d'une question n'aide personne.
//
// Tabata garde son propre format (`TabataSessionStore`), plus ancien et plus
// riche (file Sante). Ce helper sert aux autres: Trilingo d'abord.

/// Genres d'activite qui savent reprendre. La valeur brute fait partie de la
/// cle de stockage: ne jamais la renommer.
/// Un nouveau genre ajoute un cas ici et son age maximal.
enum SessionRestoreKind: String, CaseIterable {
    case trilingoLesson

    /// Age maximal d'un instantane avant d'etre oublie.
    var maxAge: TimeInterval {
        switch self {
        case .trilingoLesson: return 24 * 3600
        }
    }
}

/// Enveloppe ecrite sur le disque: version, heure d'ecriture, contenu.
struct SessionRestoreEnvelope<Payload: Codable>: Codable {
    static var currentVersion: Int { 1 }
    var version: Int
    var savedAt: Date
    var payload: Payload
}

/// Lecture et ecriture des instantanes. `UserDefaults` et l'horloge sont
/// injectables pour les tests.
struct SessionRestore {
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    static func key(_ kind: SessionRestoreKind) -> String { "sessionRestore.\(kind.rawValue)" }

    func save<T: Codable>(_ payload: T, kind: SessionRestoreKind) {
        let envelope = SessionRestoreEnvelope(version: SessionRestoreEnvelope<T>.currentVersion,
                                              savedAt: now(), payload: payload)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else { return }
        defaults.set(data, forKey: Self.key(kind))
    }

    /// L'instantane s'il existe, se lit, n'est pas d'une version future et n'a
    /// pas depasse `maxAge` (par defaut celui du genre). Sinon nil, et un
    /// instantane illisible ou perime est efface pour ne plus etre propose.
    func load<T: Codable>(_ type: T.Type, kind: SessionRestoreKind,
                          maxAge: TimeInterval? = nil) -> (payload: T, savedAt: Date)? {
        guard let data = defaults.data(forKey: Self.key(kind)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(SessionRestoreEnvelope<T>.self, from: data),
              envelope.version <= SessionRestoreEnvelope<T>.currentVersion else {
            clear(kind)
            return nil
        }
        let age = now().timeIntervalSince(envelope.savedAt)
        // Une heure d'ecriture dans le futur (horloge changee) n'est pas fiable.
        guard age >= -60, age <= (maxAge ?? kind.maxAge) else {
            clear(kind)
            return nil
        }
        return (envelope.payload, envelope.savedAt)
    }

    func has(_ kind: SessionRestoreKind) -> Bool { defaults.data(forKey: Self.key(kind)) != nil }

    func clear(_ kind: SessionRestoreKind) {
        defaults.removeObject(forKey: Self.key(kind))
    }
}

// MARK: - Lecon Trilingo en cours

/// Tout ce qu'il faut pour rouvrir une lecon Trilingo a la meme etape: la
/// langue, la liste d'exercices tiree au depart, l'etape, le score et la
/// reponse en cours. Les reponses DEJA validees sont dans la progression
/// (`TrilingoStore`), pas ici: reprendre ne les compte jamais deux fois.
struct TrilingoLessonSnapshot: Codable, Equatable {
    struct Exercise: Codable, Equatable {
        var kind: String
        var item: TrilingoItem
        var skill: TrilingoSkill
        var options: [String]
        var tiles: [String]
        var isReview: Bool
    }

    /// Identifiant de la lecon, pose a son depart.
    var lessonID: UUID
    /// Langue cible du cours (code du cours, ex. "spa").
    var language: String
    /// Vrai pour la seance du jour, faux pour "Revoir mes erreurs".
    var countsAsDay: Bool
    var exercises: [Exercise]
    var index: Int
    var correctCount: Int
    /// Reponse en cours sur l'etape `index`.
    var built: [String] = []
    var typed: String = ""
    var chosen: String? = nil
    var verdict: Bool? = nil

    var total: Int { exercises.count }

    /// Instantane valide pour la langue choisie: meme langue, etape dans la
    /// liste. Une lecon d'une autre langue ne se reprend jamais.
    func isResumable(forLanguage target: String?) -> Bool {
        guard let target, target == language else { return false }
        return !exercises.isEmpty && exercises.indices.contains(index)
    }
}

extension TrilingoLessonSnapshot.Exercise {
    init(_ e: TrilingoExercise) {
        self.init(kind: e.kind.rawValue, item: e.item, skill: e.skill,
                  options: e.options, tiles: e.tiles, isReview: e.isReview)
    }

    /// nil si le genre d'exercice n'existe plus dans cette version.
    var exercise: TrilingoExercise? {
        guard let k = TrilingoExercise.Kind(rawValue: kind) else { return nil }
        return TrilingoExercise(kind: k, item: item, skill: skill, options: options, tiles: tiles, isReview: isReview)
    }
}

extension TrilingoLessonSnapshot {
    /// Exercices reconstruits. Si un seul genre est inconnu, la lecon entiere
    /// est refusee (nil): reprendre avec une etape manquante decalerait tout.
    var restoredExercises: [TrilingoExercise]? {
        let list = exercises.compactMap(\.exercise)
        return list.count == exercises.count ? list : nil
    }
}

/// Acces de Trilingo a son instantane.
enum TrilingoLessonRestore {
    static func load(_ restore: SessionRestore = SessionRestore()) -> TrilingoLessonSnapshot? {
        restore.load(TrilingoLessonSnapshot.self, kind: .trilingoLesson)?.payload
    }
    static func save(_ snapshot: TrilingoLessonSnapshot, _ restore: SessionRestore = SessionRestore()) {
        restore.save(snapshot, kind: .trilingoLesson)
    }
    static func clear(_ restore: SessionRestore = SessionRestore()) {
        restore.clear(.trilingoLesson)
    }
}
