import Foundation
import SwiftData

// Modeles et logique pure des outils Mental (Breathwerk, Headplace, Endlo, Daylia, Fabuleux).
// Toutes les nouvelles proprietes ont une valeur par defaut: le magasin peut migrer
// sans etape manuelle. Les identifiants sont des String remplies dans init
// (jamais une valeur par defaut partagee par plusieurs lignes).

// MARK: - Jour calendaire

enum MindDay {
    /// "yyyy-MM-dd" dans le calendrier donne. Calcule a partir des composantes,
    /// pas d'un DateFormatter: identique d'un appareil a l'autre et dans les tests.
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum MindStats {
    /// Jours consecutifs avec au moins une seance, en finissant aujourd'hui ou hier
    /// (une serie n'est pas cassee tant que la journee n'est pas finie).
    static func streak(dates: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { MindDay.key($0, calendar: calendar) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(MindDay.key(cursor, calendar: calendar)) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(MindDay.key(y, calendar: calendar)) else { return 0 }
            cursor = y
        }
        var count = 0
        while days.contains(MindDay.key(cursor, calendar: calendar)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// Nombre de jours distincts avec une entree dans la semaine de `now`.
    static func daysThisWeek(dates: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return Set(dates.filter { week.contains($0) }.map { MindDay.key($0, calendar: calendar) }).count
    }
}

// MARK: - Breathwerk

enum BreathPhaseKind: String, Codable, CaseIterable, Identifiable {
    case inhale, topUp, holdFull, exhale, holdEmpty
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inhale: return "Inspire"
        case .topUp: return "Inspire encore"
        case .holdFull: return "Retiens"
        case .exhale: return "Expire"
        case .holdEmpty: return "Retiens à vide"
        }
    }
    /// Echelle du cercle a la FIN de la phase (le cercle reste sur place pendant une retention).
    var targetScale: Double? {
        switch self {
        case .inhale: return 0.9
        case .topUp: return 1.0
        case .exhale: return 0.5
        case .holdFull, .holdEmpty: return nil
        }
    }
}

struct BreathPhase: Equatable, Hashable {
    var kind: BreathPhaseKind
    var seconds: Int

    /// Format stocke: "inhale:4,holdFull:7,exhale:8". Les morceaux illisibles sont ignores.
    static func encode(_ phases: [BreathPhase]) -> String {
        phases.map { "\($0.kind.rawValue):\($0.seconds)" }.joined(separator: ",")
    }
    static func decode(_ raw: String) -> [BreathPhase] {
        raw.split(separator: ",").compactMap { part in
            let bits = part.split(separator: ":")
            guard bits.count == 2, let kind = BreathPhaseKind(rawValue: String(bits[0])),
                  let s = Int(bits[1]), s > 0 else { return nil }
            return BreathPhase(kind: kind, seconds: min(s, 60))
        }
    }
}

/// Techniques connues, decrites uniquement par leur rythme. Aucune promesse de bienfait.
enum BreathTechnique: String, CaseIterable, Identifiable {
    case coherence, box, relax478, sigh
    var id: String { "builtin.\(rawValue)" }
    var name: String {
        switch self {
        case .coherence: return "Cohérence cardiaque 5-5"
        case .box: return "Respiration carrée 4-4-4-4"
        case .relax478: return "Respiration 4-7-8"
        case .sigh: return "Soupir physiologique"
        }
    }
    var summary: String {
        switch self {
        case .coherence: return "Inspire 5 s, expire 5 s : environ 6 respirations par minute."
        case .box: return "Inspire, retiens, expire, retiens : 4 s chacun."
        case .relax478: return "Inspire 4 s, retiens 7 s, expire 8 s."
        case .sigh: return "Deux inspirations par le nez (une longue, une courte), puis une longue expiration par la bouche."
        }
    }
    var keywords: String {
        switch self {
        case .coherence: return "coherence cardiaque 5-5 365 rythme"
        case .box: return "box carree navy 4-4-4-4"
        case .relax478: return "4-7-8 relax sommeil"
        case .sigh: return "soupir physiologique double inspiration"
        }
    }
    var phases: [BreathPhase] {
        switch self {
        case .coherence: return [.init(kind: .inhale, seconds: 5), .init(kind: .exhale, seconds: 5)]
        case .box: return [.init(kind: .inhale, seconds: 4), .init(kind: .holdFull, seconds: 4),
                           .init(kind: .exhale, seconds: 4), .init(kind: .holdEmpty, seconds: 4)]
        case .relax478: return [.init(kind: .inhale, seconds: 4), .init(kind: .holdFull, seconds: 7),
                                .init(kind: .exhale, seconds: 8)]
        case .sigh: return [.init(kind: .inhale, seconds: 2), .init(kind: .topUp, seconds: 1),
                            .init(kind: .exhale, seconds: 6)]
        }
    }
}

/// Technique creee par l'utilisateur: ses phases, et un nombre de rondes (0 = duree libre).
@Model final class BreathPattern {
    var uid: String = ""
    var name: String = ""
    var phasesRaw: String = ""
    var rounds: Int = 0
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    init(name: String, phases: [BreathPhase], rounds: Int = 0) {
        self.uid = UUID().uuidString
        self.name = name
        self.phasesRaw = BreathPhase.encode(phases)
        self.rounds = rounds
        self.createdAt = Date()
    }
    var phases: [BreathPhase] {
        get { BreathPhase.decode(phasesRaw) }
        set { phasesRaw = BreathPhase.encode(newValue) }
    }
    var key: String { "custom.\(uid)" }
}

@Model final class BreathSessionLog {
    var date: Date = Date()
    var patternKey: String = ""
    var patternName: String = ""
    var activeSeconds: Int = 0
    var rounds: Int = 0
    var completed: Bool = false
    init(date: Date = Date(), patternKey: String, patternName: String, activeSeconds: Int, rounds: Int, completed: Bool) {
        self.date = date; self.patternKey = patternKey; self.patternName = patternName
        self.activeSeconds = activeSeconds; self.rounds = rounds; self.completed = completed
    }
}

/// Deroule d'une seance de respiration, en temps ACTIF (les pauses ne comptent pas).
///
/// La phase se deduit du temps actif ecoule: une pause fige le temps, la reprise
/// repart dans la meme phase avec le temps qui lui restait. Aucune phase n'est
/// sautee. `finished` ne passe a vrai qu'une fois: l'evenement de fin, donc
/// l'ecriture dans l'historique, ne peut arriver qu'une seule fois.
struct BreathRun: Equatable {
    struct Position: Equatable { var round: Int; var index: Int }
    enum Event: Equatable { case phase(BreathPhase, round: Int), finished }

    let phases: [BreathPhase]
    let totalSeconds: Double
    private(set) var accumulated: Double = 0
    private(set) var runningSince: Date?
    private(set) var position: Position?
    private(set) var finished = false

    init(phases: [BreathPhase], rounds: Int, minutes: Int) {
        let p = phases.isEmpty ? BreathTechnique.coherence.phases : phases
        self.phases = p
        let cycle = Double(p.reduce(0) { $0 + $1.seconds })
        if rounds > 0 {
            totalSeconds = cycle * Double(rounds)
        } else {
            // Duree libre: arrondie au cycle complet pour ne pas couper une expiration.
            let wanted = Double(max(1, minutes) * 60)
            totalSeconds = (wanted / cycle).rounded(.up) * cycle
        }
    }

    var cycleSeconds: Double { Double(phases.reduce(0) { $0 + $1.seconds }) }
    var isPaused: Bool { runningSince == nil && !finished && position != nil }
    var totalRounds: Int { Int((totalSeconds / cycleSeconds).rounded()) }

    func elapsed(at now: Date) -> Double {
        let live = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(totalSeconds, accumulated + live)
    }

    /// Phase a un temps actif donne. Pure.
    func position(atElapsed t: Double) -> (Position, phaseRemaining: Double) {
        let cycle = cycleSeconds
        let clamped = min(max(0, t), max(0, totalSeconds - 0.0001))
        let round = Int(clamped / cycle)
        var inCycle = clamped - Double(round) * cycle
        for (i, ph) in phases.enumerated() {
            if inCycle < Double(ph.seconds) { return (Position(round: round, index: i), Double(ph.seconds) - inCycle) }
            inCycle -= Double(ph.seconds)
        }
        return (Position(round: round, index: phases.count - 1), 0)
    }

    mutating func start(at now: Date) -> [Event] {
        accumulated = 0; finished = false; runningSince = now; position = nil
        return tick(at: now)
    }

    mutating func pause(at now: Date) {
        guard let since = runningSince, !finished else { return }
        accumulated = min(totalSeconds, accumulated + max(0, now.timeIntervalSince(since)))
        runningSince = nil
    }

    mutating func resume(at now: Date) {
        guard runningSince == nil, !finished, position != nil else { return }
        runningSince = now
    }

    mutating func tick(at now: Date) -> [Event] {
        guard !finished, runningSince != nil else { return [] }
        let t = elapsed(at: now)
        if t >= totalSeconds {
            accumulated = totalSeconds; runningSince = nil; finished = true
            return [.finished]
        }
        let (pos, _) = position(atElapsed: t)
        guard pos != position else { return [] }
        position = pos
        return [.phase(phases[pos.index], round: pos.round)]
    }

    /// Rondes entierement terminees au temps actif courant.
    func completedRounds(at now: Date) -> Int { Int(elapsed(at: now) / cycleSeconds) }
}

enum BreathLibrary {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        let summary: String
        let phases: [BreathPhase]
        let rounds: Int
        let keywords: String
        let isCustom: Bool
    }

    static func items(custom: [BreathPattern]) -> [Item] {
        BreathTechnique.allCases.map {
            Item(id: $0.id, name: $0.name, summary: $0.summary, phases: $0.phases, rounds: 0, keywords: $0.keywords, isCustom: false)
        } + custom.sorted { $0.createdAt < $1.createdAt }.map {
            Item(id: $0.key, name: $0.name, summary: rhythm($0.phases), phases: $0.phases, rounds: $0.rounds, keywords: "", isCustom: true)
        }
    }

    static func rhythm(_ phases: [BreathPhase]) -> String {
        phases.map { "\($0.kind.label) \($0.seconds) s" }.joined(separator: ", ")
    }

    /// Recherche sans accents ni casse, sur le nom, le rythme et les mots cles.
    /// Les favoris passent devant, puis l'ordre d'origine.
    static func filter(_ items: [Item], query: String, favorites: Set<String>) -> [Item] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        let hits = q.isEmpty ? items : items.filter { fold("\($0.name) \($0.summary) \($0.keywords)").contains(q) }
        return hits.enumerated().sorted { a, b in
            let fa = favorites.contains(a.element.id), fb = favorites.contains(b.element.id)
            return fa != fb ? fa : a.offset < b.offset
        }.map(\.element)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Favoris stockes en une chaine "id1|id2".
    static func decodeFavorites(_ raw: String) -> Set<String> { Set(raw.split(separator: "|").map(String.init)) }
    static func encodeFavorites(_ set: Set<String>) -> String { set.sorted().joined(separator: "|") }
}

// MARK: - Headplace

@Model final class MeditationTimerPreset {
    var uid: String = ""
    var name: String = ""
    var minutes: Int = 10
    /// 0 = pas de cloche intermediaire.
    var intervalMinutes: Int = 0
    var startBell: Bool = true
    var endBell: Bool = true
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    init(name: String, minutes: Int, intervalMinutes: Int = 0, startBell: Bool = true, endBell: Bool = true) {
        self.uid = UUID().uuidString
        self.name = name; self.minutes = minutes; self.intervalMinutes = intervalMinutes
        self.startBell = startBell; self.endBell = endBell
        self.createdAt = Date()
    }
}

/// Fichier audio importe par l'utilisateur (Fichiers), copie dans le dossier de l'app.
@Model final class MeditationAudio {
    var uid: String = ""
    var title: String = ""
    var fileName: String = ""
    var durationSeconds: Double = 0
    /// Position ou reprendre la lecture.
    var resumePosition: Double = 0
    var isFavorite: Bool = false
    var importedAt: Date = Date()
    init(title: String, fileName: String, durationSeconds: Double) {
        self.uid = UUID().uuidString
        self.title = title; self.fileName = fileName; self.durationSeconds = durationSeconds
        self.importedAt = Date()
    }
}

@Model final class MeditationLog {
    var date: Date = Date()
    /// "minuteur" ou "audio".
    var kind: String = "minuteur"
    var title: String = ""
    var seconds: Int = 0
    var completed: Bool = false
    var sourceKey: String = ""
    init(date: Date = Date(), kind: String, title: String, seconds: Int, completed: Bool, sourceKey: String = "") {
        self.date = date; self.kind = kind; self.title = title; self.seconds = seconds
        self.completed = completed; self.sourceKey = sourceKey
    }
}

enum MeditationLogic {
    /// Seance en cours, gardee hors du moteur pour pouvoir l'inscrire dans
    /// l'historique meme si elle se termine app fermee.
    struct StoredRun: Codable, Equatable {
        var title: String
        var sourceKey: String
        var totalSeconds: Int
        var deadline: Date
        var intervalMinutes: Int
        var endBell: Bool
    }

    /// Une seance stockee dont l'echeance est passee et que le moteur ne fait plus
    /// tourner est terminee: on l'inscrit une fois, puis on l'efface.
    static func isFinished(_ run: StoredRun?, engineRunning: Bool, now: Date) -> Bool {
        guard let run, !engineRunning else { return false }
        return now >= run.deadline
    }

    /// Moments (en secondes depuis le debut) ou sonne la cloche intermediaire.
    /// Jamais sur la fin elle-meme (la cloche de fin s'en charge).
    static func intervalOffsets(totalSeconds: Int, intervalMinutes: Int) -> [Int] {
        guard intervalMinutes > 0 else { return [] }
        let step = intervalMinutes * 60
        return Array(stride(from: step, to: totalSeconds, by: step))
    }

    struct LibraryItem: Identifiable, Equatable {
        let id: String
        let title: String
        let minutes: Int
        let isFavorite: Bool
        let isAudio: Bool
    }

    /// Recherche dans la bibliotheque de l'utilisateur (titre) + duree maximale.
    static func filter(_ items: [LibraryItem], query: String, maxMinutes: Int?) -> [LibraryItem] {
        let q = BreathLibrary.fold(query.trimmingCharacters(in: .whitespaces))
        return items.filter { item in
            (q.isEmpty || BreathLibrary.fold(item.title).contains(q))
                && (maxMinutes.map { item.minutes <= $0 } ?? true)
        }.sorted { a, b in a.isFavorite != b.isFavorite ? a.isFavorite : a.title < b.title }
    }

    /// Recommandation du jour, tiree de TON historique: la source la plus utilisee
    /// a cette heure de la journee (plus ou moins 2 h), sinon la plus utilisee tout court.
    /// Aucune seance passee = aucune recommandation (pas de contenu invente).
    static func recommend(logs: [(sourceKey: String, date: Date)], available: Set<String>,
                          now: Date, calendar: Calendar = .current) -> String? {
        let usable = logs.filter { !$0.sourceKey.isEmpty && available.contains($0.sourceKey) }
        guard !usable.isEmpty else { return nil }
        let hour = calendar.component(.hour, from: now)
        func circularGap(_ h: Int) -> Int { let d = abs(h - hour); return min(d, 24 - d) }
        let near = usable.filter { circularGap(calendar.component(.hour, from: $0.date)) <= 2 }
        let pool = near.isEmpty ? usable : near
        let counts = Dictionary(grouping: pool, by: \.sourceKey).mapValues(\.count)
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }
}

// MARK: - Endlo

@Model final class SoundMixPreset {
    var uid: String = ""
    var name: String = ""
    var kindA: String = "pink"
    var levelA: Double = 0.8
    /// Vide = une seule couche.
    var kindB: String = ""
    var levelB: Double = 0.4
    var timerMinutes: Int = 0
    var fadeSeconds: Int = 8
    var createdAt: Date = Date()
    init(name: String, kindA: String, levelA: Double, kindB: String, levelB: Double, timerMinutes: Int, fadeSeconds: Int) {
        self.uid = UUID().uuidString
        self.name = name; self.kindA = kindA; self.levelA = levelA
        self.kindB = kindB; self.levelB = levelB
        self.timerMinutes = timerMinutes; self.fadeSeconds = fadeSeconds
        self.createdAt = Date()
    }
}

enum EndloLogic {
    /// Pas de gain par echantillon pour un fondu lineaire de `fadeSeconds`.
    static func fadeStep(fadeSeconds: Double, sampleRate: Double) -> Float {
        guard fadeSeconds > 0, sampleRate > 0 else { return 1 }
        return Float(1.0 / (fadeSeconds * sampleRate))
    }

    /// Avance le gain d'un pas vers la cible, sans la depasser.
    static func advance(gain: Float, target: Float, step: Float) -> Float {
        if gain < target { return min(target, gain + step) }
        if gain > target { return max(target, gain - step) }
        return gain
    }

    /// Melange de deux couches. La somme est bornee pour ne jamais saturer.
    static func mix(_ a: Float, _ b: Float, levelA: Float, levelB: Float) -> Float {
        max(-1, min(1, a * levelA + b * levelB))
    }

    /// Lancement auto de la seance programmee: seulement si on ouvre l'outil dans
    /// les `window` minutes qui suivent l'heure prevue, une fois par jour, et si
    /// rien ne joue deja. iOS n'autorise pas une app a demarrer du son seule:
    /// c'est la notification, touchee, qui ouvre l'outil.
    static func shouldAutoStart(enabled: Bool, hour: Int, minute: Int, lastAutoStartDay: String,
                                isPlaying: Bool, now: Date, window: Int = 30,
                                calendar: Calendar = .current) -> Bool {
        guard enabled, !isPlaying else { return false }
        let today = MindDay.key(now, calendar: calendar)
        guard lastAutoStartDay != today,
              let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return false }
        let delta = now.timeIntervalSince(scheduled)
        return delta >= 0 && delta <= Double(window * 60)
    }

    /// Mode suggere selon l'heure (seule entree adaptative utilisee: l'horloge).
    static func suggestedModeRaw(hour: Int) -> String {
        switch hour {
        case 5..<18: return "focus"
        case 18..<21: return "detente"
        default: return "sommeil"
        }
    }
}

// MARK: - Daylia

@Model final class MoodActivity {
    var uid: String = ""
    var name: String = ""
    var emoji: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    init(name: String, emoji: String = "") {
        self.uid = UUID().uuidString
        self.name = name; self.emoji = emoji; self.createdAt = Date()
    }
}

/// Humeur nommee par l'utilisateur, rattachee a un niveau 1 a 5 (le niveau sert aux moyennes).
@Model final class MoodCustomMood {
    var uid: String = ""
    var name: String = ""
    var emoji: String = ""
    var score: Int = 3
    var createdAt: Date = Date()
    init(name: String, emoji: String, score: Int) {
        self.uid = UUID().uuidString
        self.name = name; self.emoji = emoji; self.score = min(5, max(1, score)); self.createdAt = Date()
    }
}

/// Complement d'une entree d'humeur (activites, humeur nommee, photo).
///
/// `MoodEntry` vit dans un fichier partage et n'a pas d'identifiant stable: le lien
/// se fait par la date exacte de l'entree, rendue unique a l'enregistrement
/// (`MoodAnalytics.uniqueDate`). Quand la date d'une entree change, celle du
/// complement change avec.
@Model final class MoodEntryExtra {
    var entryDate: Date = Date()
    var moodUID: String = ""
    var activityUIDsRaw: String = ""
    var photoFileName: String = ""
    init(entryDate: Date, moodUID: String = "", activityUIDs: [String] = [], photoFileName: String = "") {
        self.entryDate = entryDate; self.moodUID = moodUID
        self.activityUIDsRaw = activityUIDs.joined(separator: ",")
        self.photoFileName = photoFileName
    }
    var activityUIDs: [String] {
        get { activityUIDsRaw.split(separator: ",").map(String.init) }
        set { activityUIDsRaw = newValue.joined(separator: ",") }
    }
}

enum MoodAnalytics {
    /// Vue simplifiee d'une entree, independante de SwiftData (testable).
    struct Row: Equatable {
        var date: Date
        var score: Int
        var note: String
        var gratitude: String
        var moodName: String
        var activities: [String]   // uids
    }

    /// Date rendue unique parmi les entrees existantes (decalage d'une milliseconde
    /// si besoin): c'est la cle qui relie l'entree a son complement.
    static func uniqueDate(_ date: Date, existing: [Date]) -> Date {
        let taken = Set(existing.map { ($0.timeIntervalSinceReferenceDate * 1000).rounded() })
        var d = date
        while taken.contains((d.timeIntervalSinceReferenceDate * 1000).rounded()) { d = d.addingTimeInterval(0.001) }
        return d
    }

    static func sameInstant(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 0.0005
    }

    /// Moyenne par jour ("yyyy-MM-dd" -> moyenne). Plusieurs entrees le meme jour comptent toutes.
    static func dailyAverages(_ rows: [Row], calendar: Calendar = .current) -> [String: Double] {
        Dictionary(grouping: rows, by: { MindDay.key($0.date, calendar: calendar) })
            .mapValues { g in Double(g.reduce(0) { $0 + $1.score }) / Double(g.count) }
    }

    static func average(_ rows: [Row]) -> Double? {
        rows.isEmpty ? nil : Double(rows.reduce(0) { $0 + $1.score }) / Double(rows.count)
    }

    struct Association: Equatable {
        let activityUID: String
        let withCount: Int
        let withoutCount: Int
        let averageWith: Double
        let averageWithout: Double
        var difference: Double { averageWith - averageWithout }
    }

    /// Humeur moyenne AVEC et SANS chaque activite. Rien n'est affiche sous
    /// `minCount` entrees de chaque cote: sur trois points, un ecart ne veut rien dire.
    /// C'est une association, jamais presentee comme une cause.
    static func associations(_ rows: [Row], minCount: Int = 3) -> [Association] {
        let uids = Set(rows.flatMap(\.activities))
        return uids.compactMap { uid in
            let with = rows.filter { $0.activities.contains(uid) }
            let without = rows.filter { !$0.activities.contains(uid) }
            guard with.count >= minCount, without.count >= minCount,
                  let a = average(with), let b = average(without) else { return nil }
            return Association(activityUID: uid, withCount: with.count, withoutCount: without.count,
                               averageWith: a, averageWithout: b)
        }.sorted { abs($0.difference) > abs($1.difference) }
    }

    /// Filtres de l'historique: texte (note, gratitude, humeur), activite, niveau.
    static func filter(_ rows: [Row], query: String, activityUID: String?, score: Int?) -> [Row] {
        let q = BreathLibrary.fold(query.trimmingCharacters(in: .whitespaces))
        return rows.filter { r in
            (q.isEmpty || BreathLibrary.fold("\(r.note) \(r.gratitude) \(r.moodName)").contains(q))
                && (activityUID.map { r.activities.contains($0) } ?? true)
                && (score.map { r.score == $0 } ?? true)
        }
    }

    /// Export CSV (separateur virgule, champs entre guillemets si besoin).
    static func csv(_ rows: [Row], activityNames: [String: String], calendar: Calendar = .current) -> String {
        var out = "date,heure,niveau,humeur,activites,note,gratitude\n"
        for r in rows.sorted(by: { $0.date < $1.date }) {
            let c = calendar.dateComponents([.hour, .minute], from: r.date)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let acts = r.activities.compactMap { activityNames[$0] }.joined(separator: "; ")
            out += [MindDay.key(r.date, calendar: calendar), time, String(r.score), r.moodName, acts, r.note, r.gratitude]
                .map(escape).joined(separator: ",") + "\n"
        }
        return out
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Fabuleux

enum RoutinePeriod: String, CaseIterable, Identifiable {
    case morning = "matin", evening = "soir"
    var id: String { rawValue }
    var label: String { self == .morning ? "Matin" : "Soir" }
}

@Model final class RoutineStep {
    var uid: String = ""
    var title: String = ""
    var period: String = "matin"
    var order: Int = 0
    /// Habitude empilee: cocher l'etape coche aussi cette habitude (`Habit.uid`).
    var habitUID: String = ""
    var createdAt: Date = Date()
    init(title: String, period: RoutinePeriod, order: Int, habitUID: String = "") {
        self.uid = UUID().uuidString
        self.title = title; self.period = period.rawValue; self.order = order
        self.habitUID = habitUID; self.createdAt = Date()
    }
}

/// Une etape cochee un jour donne.
@Model final class RoutineCheck {
    var stepUID: String = ""
    var day: String = ""
    var date: Date = Date()
    init(stepUID: String, day: String, date: Date = Date()) {
        self.stepUID = stepUID; self.day = day; self.date = date
    }
}

/// Reponse du jour a la question de reflexion (une par jour, modifiable).
@Model final class DailyReflection {
    var day: String = ""
    var prompt: String = ""
    var text: String = ""
    var date: Date = Date()
    init(day: String, prompt: String, text: String, date: Date = Date()) {
        self.day = day; self.prompt = prompt; self.text = text; self.date = date
    }
}

enum RoutineLogic {
    /// Jour complet = toutes les etapes de la routine (au moment du calcul) cochees ce jour-la.
    static func isComplete(stepUIDs: [String], checks: [(stepUID: String, day: String)], day: String) -> Bool {
        guard !stepUIDs.isEmpty else { return false }
        let done = Set(checks.filter { $0.day == day }.map(\.stepUID))
        return stepUIDs.allSatisfy { done.contains($0) }
    }

    /// Serie de jours complets, en finissant aujourd'hui ou hier.
    static func streak(stepUIDs: [String], checks: [(stepUID: String, day: String)],
                       now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !stepUIDs.isEmpty else { return 0 }
        let byDay = Dictionary(grouping: checks, by: \.day).mapValues { Set($0.map(\.stepUID)) }
        let fullDays = byDay.filter { _, done in stepUIDs.allSatisfy { done.contains($0) } }.keys
        // Reutilise le calcul de serie a partir de dates a midi.
        let dates: [Date] = fullDays.compactMap { key in
            let p = key.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
        }
        return MindStats.streak(dates: dates, now: now, calendar: calendar)
    }

    /// Questions de reflexion. Ce sont des questions, pas du contenu coache.
    static let prompts = [
        "Qu'est-ce qui compterait le plus aujourd'hui ?",
        "De quoi es-tu reconnaissant ce matin ?",
        "Qu'est-ce qui t'a donné de l'énergie hier ?",
        "Quelle petite chose peux-tu faire pour toi aujourd'hui ?",
        "Qu'est-ce que tu veux laisser de côté aujourd'hui ?",
        "Qu'as-tu appris cette semaine ?",
        "Comment veux-tu te sentir ce soir ?"
    ]

    static func prompt(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return prompts[day % prompts.count]
    }
}

/// Le briefing du jour, construit UNIQUEMENT a partir des enregistrements de l'app.
/// Un seul constructeur pour les deux entrees (Fabuleux et le briefing du reveil),
/// pour qu'elles disent la meme chose.
struct DayBriefing: Equatable {
    struct Task: Equatable { let title: String; let overdue: Bool; let priority: Int }
    struct Event: Equatable { let title: String; let date: Date; let location: String }
    var date: Date
    var tasks: [Task]
    var events: [Event]
    var habitsDue: Int
    var habitsDone: Int
    /// nil si la nuit n'a pas ete notee aujourd'hui.
    var sleepHours: Double?
    var sleepQuality: Int?
    var routineDone: Int
    var routineTotal: Int
}

enum DayBriefingBuilder {
    struct HabitInput { let activeToday: Bool; let archived: Bool; let doneToday: Bool }
    struct TaskInput { let title: String; let done: Bool; let due: Date?; let recurringDays: Set<Int>; let priority: Int }
    struct EventInput { let title: String; let date: Date; let location: String }

    static func make(now: Date, tasks: [TaskInput], events: [EventInput], habits: [HabitInput],
                     sleepCheckDate: Date?, sleepHours: Double, sleepQuality: Int,
                     routineDone: Int, routineTotal: Int, calendar: Calendar = .current) -> DayBriefing {
        let today = tasks.filter {
            isPriorityToday(done: $0.done, due: $0.due, recurringDays: $0.recurringDays, now: now, calendar: calendar)
        }.sorted { $0.priority > $1.priority }
        .map { t in DayBriefing.Task(title: t.title,
                                     overdue: t.recurringDays.isEmpty && (t.due.map { !calendar.isDate($0, inSameDayAs: now) && $0 < now } ?? false),
                                     priority: t.priority) }
        let todayEvents = events.filter { calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date < $1.date }
            .map { DayBriefing.Event(title: $0.title, date: $0.date, location: $0.location) }
        let due = habits.filter { $0.activeToday && !$0.archived }
        let sleepToday = sleepCheckDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        return DayBriefing(date: now, tasks: today, events: todayEvents,
                           habitsDue: due.count, habitsDone: due.filter(\.doneToday).count,
                           sleepHours: sleepToday && sleepHours > 0 ? sleepHours : nil,
                           sleepQuality: sleepToday && sleepQuality > 0 ? sleepQuality : nil,
                           routineDone: routineDone, routineTotal: routineTotal)
    }

    /// Une tache compte aujourd'hui si elle est due aujourd'hui, en retard, ou
    /// recurrente ce jour de la semaine. Une tache sans date ni recurrence n'est pas planifiee.
    static func isPriorityToday(done: Bool, due: Date?, recurringDays: Set<Int>,
                                now: Date, calendar: Calendar = .current) -> Bool {
        guard !done else { return false }
        if !recurringDays.isEmpty { return recurringDays.contains(calendar.component(.weekday, from: now)) }
        guard let due else { return false }
        return calendar.isDate(due, inSameDayAs: now) || due < now
    }

    /// Texte lu a voix haute. Il ne dit que ce que les donnees contiennent.
    static func spokenText(_ b: DayBriefing, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if b.tasks.isEmpty { parts.append("Aucune tâche planifiée aujourd'hui.") }
        else {
            let n = b.tasks.count
            parts.append(n == 1 ? "Une tâche aujourd'hui : \(b.tasks[0].title)."
                                : "\(n) tâches aujourd'hui. D'abord : \(b.tasks.prefix(3).map(\.title).joined(separator: ", ")).")
        }
        if b.events.isEmpty { parts.append("Rien à l'agenda.") }
        else {
            let first = b.events[0]
            let c = calendar.dateComponents([.hour, .minute], from: first.date)
            let time = String(format: "%d heures %02d", c.hour ?? 0, c.minute ?? 0)
            parts.append(b.events.count == 1 ? "À l'agenda : \(first.title) à \(time)."
                                             : "\(b.events.count) rendez-vous, le premier : \(first.title) à \(time).")
        }
        if b.habitsDue > 0 { parts.append("Habitudes : \(b.habitsDone) sur \(b.habitsDue).") }
        if let h = b.sleepHours {
            let hours = h.rounded() == h ? "\(Int(h))" : String(format: "%.1f", h).replacingOccurrences(of: ".", with: ",")
            parts.append("Nuit notée : \(hours) heures.")
        }
        if b.routineTotal > 0 { parts.append("Routine : \(b.routineDone) étapes sur \(b.routineTotal).") }
        return parts.joined(separator: " ")
    }
}
