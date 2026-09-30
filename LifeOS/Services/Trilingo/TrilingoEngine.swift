import Foundation

// MARK: - Profil, progression, seance

struct TrilingoProfile: Codable, Equatable {
    var source = "fra"
    var target: String
    /// voyage, travail, etudes, culture, famille, autre
    var goal: String
    /// jamais, bases, intermediaire
    var experience: String
    var dailyMinutes: Int
    var reminderOn: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var createdAt = Date()
}

enum TrilingoSkill: String, Codable, CaseIterable {
    case reading = "lecture", listening = "écoute", writing = "écriture", speaking = "oral"
}

struct TrilingoSRS: Codable, Equatable {
    var box = 0
    /// Jour metier "yyyy-MM-dd" de la prochaine revision.
    var due: String
    var errors = 0
    var seen = 0
}

struct TrilingoProgress: Codable, Equatable {
    var target: String
    var placementDone = false
    /// Jour de depart choisi par le test de placement (1 = debutant complet).
    var placementDay = 1
    /// Prochaine phrase nouvelle, index dans toutes les phrases du cours.
    var nextItem = 0
    var completedDates: [String] = []
    /// Cle "tid|competence".
    var srs: [String: TrilingoSRS] = [:]
    /// Carnet d'erreurs: phrases ratees, a revoir (tid).
    var mistakes: [Int] = []

    var streak: Int {
        let cal = Calendar(identifier: .gregorian)
        var day = Date()
        var n = 0
        let set = Set(completedDates)
        // Aujourd'hui pas encore fait ne casse pas la serie.
        if !set.contains(TrilingoEngine.dayKey(day)) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while set.contains(TrilingoEngine.dayKey(day)) {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }
}

struct TrilingoExercise: Identifiable, Equatable {
    enum Kind: String, Equatable {
        /// Decouverte: la phrase, son audio, sa traduction.
        case intro
        /// Phrase cible -> choisir le sens parmi 4.
        case chooseMeaning
        /// Ecouter -> choisir le sens (sans voir la phrase).
        case listenChoose
        /// Sens -> reconstruire la phrase cible avec des etiquettes.
        case build
        /// Ecouter -> ecrire la phrase cible.
        case dictation
        /// Dire la phrase cible au micro.
        case speak
        /// Sens -> ecrire la phrase cible sans aide.
        case translate
    }
    let id = UUID()
    let kind: Kind
    let item: TrilingoItem
    let skill: TrilingoSkill
    var options: [String] = []
    var tiles: [String] = []
    let isReview: Bool

    static func == (a: TrilingoExercise, b: TrilingoExercise) -> Bool { a.id == b.id }
}

struct TrilingoCapabilities: Equatable {
    /// Une voix de l'appareil (ou un enregistrement) pour la langue cible.
    var audio: Bool
    /// Reconnaissance vocale disponible pour la langue cible.
    var speech: Bool
}

// MARK: - Moteur (pur, teste)

enum TrilingoEngine {
    /// Intervalles de revision par boite, en jours (repetition espacee).
    static let intervals = [1, 2, 4, 7, 15, 30, 60, 120]

    static func dayKey(_ d: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func addDays(_ key: String, _ n: Int) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        return f.string(from: d.addingTimeInterval(Double(n) * 86_400))
    }

    /// Phrases nouvelles par seance selon le temps choisi. Un jour de cours = 12
    /// phrases: 10 min ou plus avancent d'un jour de cours par seance.
    static func newPerSession(_ minutes: Int) -> Int {
        switch minutes { case ..<8: 6; case ..<13: 12; case ..<18: 12; default: 18 }
    }

    static func reviewLimit(_ minutes: Int) -> Int { max(10, minutes * 3) }

    static func tokens(_ text: String, noSpaces: Bool) -> [String] {
        if noSpaces { return text.filter { $0.isLetter || $0.isNumber }.map(String.init) }
        return text.split(whereSeparator: { $0 == " " }).map(String.init)
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }

    /// Correspondance tolerante (accents, casse, ponctuation): pour l'ecrit et l'oral.
    static func similarity(_ expected: String, _ given: String, noSpaces: Bool = false) -> Double {
        let a = noSpaces ? normalize(expected).filter { $0 != " " }.map(String.init) : normalize(expected).split(separator: " ").map(String.init)
        let b = noSpaces ? normalize(given).filter { $0 != " " }.map(String.init) : normalize(given).split(separator: " ").map(String.init)
        guard !a.isEmpty else { return 0 }
        var pool = b
        var hit = 0
        for w in a { if let i = pool.firstIndex(of: w) { hit += 1; pool.remove(at: i) } }
        let extra = Double(pool.count) * 0.5
        return max(0, (Double(hit) - extra) / Double(a.count))
    }

    /// Revisions dues aujourd'hui, les plus en retard d'abord.
    static func dueReviews(_ p: TrilingoProgress, today: String) -> [(tid: Int, skill: TrilingoSkill)] {
        p.srs.filter { $0.value.due <= today }
            .sorted { $0.value.due != $1.value.due ? $0.value.due < $1.value.due : $0.key < $1.key }
            .compactMap { key, _ in
                let parts = key.split(separator: "|")
                guard parts.count == 2, let tid = Int(parts[0]), let sk = TrilingoSkill(rawValue: String(parts[1])) else { return nil }
                return (tid, sk)
            }
    }

    /// Compose la seance du jour: revisions dues puis phrases nouvelles, chacune vue
    /// sous plusieurs competences. Deterministe pour une graine donnee (tests).
    static func session(course: TrilingoCourse, progress: TrilingoProgress, today: String, minutes: Int,
                        caps: TrilingoCapabilities, seed: UInt64 = 1) -> [TrilingoExercise] {
        // hashValue change a chaque lancement en Swift: graine stable a partir du texte.
        let dayHash = today.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        var rng = SeededRNG(seed: seed ^ dayHash)
        let all = course.allItems
        let byID = Dictionary(all.map { ($0.tid, $0) }, uniquingKeysWith: { a, _ in a })
        let noSpaces = course.noSpaces ?? false
        var out: [TrilingoExercise] = []

        for r in dueReviews(progress, today: today).prefix(reviewLimit(minutes)) {
            guard let item = byID[r.tid] else { continue }
            out.append(exercise(for: r.skill, item: item, pool: all, review: true, noSpaces: noSpaces, caps: caps, rng: &rng))
        }
        let start = max(progress.nextItem, (progress.placementDay - 1) * (course.days.first?.items.count ?? 12))
        let fresh = all.dropFirst(start).prefix(newPerSession(minutes))
        for item in fresh {
            out.append(TrilingoExercise(kind: .intro, item: item, skill: .reading, isReview: false))
            out.append(exercise(for: .reading, item: item, pool: all, review: false, noSpaces: noSpaces, caps: caps, rng: &rng))
            out.append(exercise(for: .writing, item: item, pool: all, review: false, noSpaces: noSpaces, caps: caps, rng: &rng))
            if caps.audio { out.append(exercise(for: .listening, item: item, pool: all, review: false, noSpaces: noSpaces, caps: caps, rng: &rng)) }
        }
        // Un peu d'oral a chaque seance, sur les phrases du jour.
        if caps.audio && caps.speech {
            for item in fresh.prefix(3) {
                out.append(TrilingoExercise(kind: .speak, item: item, skill: .speaking, isReview: false))
            }
        }
        return out
    }

    static func exercise(for skill: TrilingoSkill, item: TrilingoItem, pool: [TrilingoItem], review: Bool,
                         noSpaces: Bool, caps: TrilingoCapabilities, rng: inout SeededRNG) -> TrilingoExercise {
        // Distracteurs pris AUTOUR de la phrase dans le cours (meme niveau): une phrase
        // du jour 200 a cote d'une phrase du jour 1 se reconnait trop facilement.
        let at = pool.firstIndex { $0.tid == item.tid } ?? 0
        let window = pool[max(0, at - 60)..<min(pool.count, at + 61)]
        let distractors = window.filter { $0.tid != item.tid && $0.s != item.s }
        func meanings() -> [String] {
            var o = [item.s]
            // Distracteurs proches dans le cours (meme niveau), pas au hasard total.
            let near = distractors.shuffled(using: &rng).prefix(3).map(\.s)
            o += near
            return o.shuffled(using: &rng)
        }
        switch skill {
        case .reading:
            return TrilingoExercise(kind: .chooseMeaning, item: item, skill: .reading, options: meanings(), isReview: review)
        case .listening:
            if caps.audio {
                return review || rng.next() % 2 == 0
                    ? TrilingoExercise(kind: .dictation, item: item, skill: .listening, isReview: review)
                    : TrilingoExercise(kind: .listenChoose, item: item, skill: .listening, options: meanings(), isReview: review)
            }
            return TrilingoExercise(kind: .chooseMeaning, item: item, skill: .reading, options: meanings(), isReview: review)
        case .writing:
            if review && !noSpaces {
                return TrilingoExercise(kind: .translate, item: item, skill: .writing, isReview: review)
            }
            let words = tokens(item.t, noSpaces: noSpaces)
            let extra = distractors.shuffled(using: &rng).prefix(2).flatMap { tokens($0.t, noSpaces: noSpaces).prefix(1) }
            return TrilingoExercise(kind: .build, item: item, skill: .writing, tiles: (words + extra).shuffled(using: &rng), isReview: review)
        case .speaking:
            return caps.speech
                ? TrilingoExercise(kind: .speak, item: item, skill: .speaking, isReview: review)
                : TrilingoExercise(kind: .chooseMeaning, item: item, skill: .reading, options: meanings(), isReview: review)
        }
    }

    /// Enregistre une reponse: bonne = boite suivante, fausse = boite 0 et carnet d'erreurs.
    static func record(_ p: inout TrilingoProgress, exercise: TrilingoExercise, correct: Bool, today: String) {
        guard exercise.kind != .intro else { return }
        let key = "\(exercise.item.tid)|\(exercise.skill.rawValue)"
        var s = p.srs[key] ?? TrilingoSRS(due: today)
        s.seen += 1
        if correct {
            s.box = min(s.box + 1, intervals.count - 1)
            if exercise.isReview { p.mistakes.removeAll { $0 == exercise.item.tid } }
        } else {
            s.box = 0; s.errors += 1
            if !p.mistakes.contains(exercise.item.tid) { p.mistakes.append(exercise.item.tid) }
        }
        s.due = addDays(today, correct ? intervals[s.box] : 1)
        p.srs[key] = s
    }

    /// Fin de seance: les phrases nouvelles sont acquises, la journee compte.
    static func finish(_ p: inout TrilingoProgress, session: [TrilingoExercise], today: String, perDay: Int = 12) {
        let fresh = Set(session.filter { !$0.isReview && $0.kind == .intro }.map(\.item.tid))
        let start = max(p.nextItem, (p.placementDay - 1) * perDay)
        p.nextItem = start + fresh.count
        if !p.completedDates.contains(today) { p.completedDates.append(today) }
    }

    // MARK: Placement

    /// Jours sondes, du plus facile au plus difficile. 3 phrases par palier.
    static func placementProbes(_ course: TrilingoCourse) -> [Int] {
        [5, 20, 45, 80, 120, 170].filter { $0 <= course.days.count }
    }

    /// Jour de depart: dernier palier reussi (2 sur 3 au moins), en s'arretant au
    /// premier echec. Aucun palier reussi: jour 1.
    static func placementStart(results: [Int: Int], probes: [Int]) -> Int {
        var start = 1
        for d in probes {
            guard let ok = results[d] else { break }
            if ok >= 2 { start = d } else { break }
        }
        return start
    }

    static func level(_ course: TrilingoCourse, day: Int) -> String {
        course.days.indices.contains(day - 1) ? course.days[day - 1].level : (course.days.last?.level ?? "A1")
    }

    // MARK: Rappels

    /// Dates des rappels des 7 prochains jours a l'heure choisie. Aujourd'hui est
    /// saute si la seance est faite ou si l'heure est passee: jamais de rappel inutile.
    static func reminderDates(now: Date, hour: Int, minute: Int, doneToday: Bool, timeZone: TimeZone = .current) -> [Date] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        return (0..<7).compactMap { d -> Date? in
            guard let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)),
                  let at = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            if d == 0 && (doneToday || at <= now) { return nil }
            return at
        }
    }
}

/// Generateur pseudo-aleatoire a graine: seances reproductibles dans les tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
