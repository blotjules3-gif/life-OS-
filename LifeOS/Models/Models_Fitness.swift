import Foundation
import SwiftData

// MARK: - Modèles Sport (Hevvy, GOMOB, TabaTime, Streakz)
//
// Tout ce que l'utilisateur crée lui-même : exercices perso, mensurations,
// routines de mobilité, préréglages Tabata, et l'historique des séances
// Tabata et mobilité. Aucun contenu inventé : les noms, durées et valeurs
// viennent de la saisie. Les UUID n'ont pas de valeur par défaut : ils sont
// posés dans l'init (modèles neufs, aucune ligne existante à migrer).

// MARK: Hevvy : exercices perso

@Model final class CustomExercise {
    var id: UUID
    var name: String = ""
    /// Groupe musculaire, une des valeurs de `ExerciseLibrary.muscleGroups`.
    var muscleGroup: String = "Autre"
    /// Matériel, valeur brute de `ExerciseEquipment`.
    var equipment: String = ExerciseEquipment.other.rawValue
    var createdAt: Date = Date()

    init(name: String, muscleGroup: String, equipment: ExerciseEquipment, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment.rawValue
        self.createdAt = createdAt
    }
}

enum ExerciseEquipment: String, CaseIterable, Identifiable, Codable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .barbell:    return "Barre"
        case .dumbbell:   return "Haltères"
        case .machine:    return "Machine"
        case .cable:      return "Poulie"
        case .bodyweight: return "Poids du corps"
        case .kettlebell: return "Kettlebell"
        case .band:       return "Élastique"
        case .other:      return "Autre"
        }
    }
}

// MARK: Hevvy : mensurations

@Model final class BodyMeasurement {
    var id: UUID
    var date: Date = Date()
    /// Valeur brute de `MeasurementKind`.
    var kind: String = MeasurementKind.weight.rawValue
    /// Valeur telle que saisie, dans l'unité choisie : on ne convertit jamais
    /// à l'écriture, donc rien ne se perd en arrondi kg/lb ou cm/in.
    var value: Double = 0
    /// Valeur brute de `MeasureUnit`.
    var unit: String = MeasureUnit.kg.rawValue

    init(date: Date = .now, kind: MeasurementKind, value: Double, unit: MeasureUnit) {
        self.id = UUID()
        self.date = date
        self.kind = kind.rawValue
        self.value = value
        self.unit = unit.rawValue
    }
}

enum MeasureUnit: String, CaseIterable, Identifiable, Codable {
    case kg, lb, cm, inch = "in", percent = "%"
    var id: String { rawValue }
    var label: String { self == .inch ? "in" : rawValue }
    enum Family { case mass, length, ratio }
    var family: Family {
        switch self {
        case .kg, .lb: return .mass
        case .cm, .inch: return .length
        case .percent: return .ratio
        }
    }
}

enum MeasurementKind: String, CaseIterable, Identifiable, Codable {
    case weight, bodyFat, neck, shoulders, chest, waist, hips, arms, forearms, thighs, calves
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weight:    return "Poids"
        case .bodyFat:   return "Masse grasse"
        case .neck:      return "Cou"
        case .shoulders: return "Épaules"
        case .chest:     return "Poitrine"
        case .waist:     return "Taille"
        case .hips:      return "Hanches"
        case .arms:      return "Bras"
        case .forearms:  return "Avant-bras"
        case .thighs:    return "Cuisses"
        case .calves:    return "Mollets"
        }
    }
    var units: [MeasureUnit] {
        switch self {
        case .weight:  return [.kg, .lb]
        case .bodyFat: return [.percent]
        default:       return [.cm, .inch]
        }
    }
}

// MARK: GOMOB : routines perso et historique

/// Une étape d'une routine perso : nom saisi et durée en secondes.
struct MobilityStepSpec: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var seconds: Int
}

@Model final class MobilityRoutine {
    var id: UUID
    var name: String = ""
    var createdAt: Date = Date()
    /// Étapes ordonnées, en JSON : l'ordre fait partie de la routine.
    var stepsData: Data = Data()

    init(name: String, steps: [MobilityStepSpec], createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.stepsData = (try? JSONEncoder().encode(steps)) ?? Data()
    }

    var steps: [MobilityStepSpec] {
        get { (try? JSONDecoder().decode([MobilityStepSpec].self, from: stepsData)) ?? [] }
        set { stepsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model final class MobilitySession {
    var id: UUID
    /// Identifiant de la tentative : une séance ne s'enregistre qu'une fois,
    /// même si l'écran revient après un relancement.
    var runID: UUID
    var date: Date = Date()
    var routineName: String = ""
    var durationSeconds: Int = 0
    var exercisesDone: Int = 0
    var exercisesTotal: Int = 0

    init(runID: UUID, date: Date, routineName: String, durationSeconds: Int, exercisesDone: Int, exercisesTotal: Int) {
        self.id = UUID()
        self.runID = runID
        self.date = date
        self.routineName = routineName
        self.durationSeconds = durationSeconds
        self.exercisesDone = exercisesDone
        self.exercisesTotal = exercisesTotal
    }
}

// MARK: TabaTime : préréglages perso et historique

@Model final class TabataPreset {
    var id: UUID
    var name: String = ""
    var prepare: Int = 10
    var work: Int = 30
    var rest: Int = 15
    var rounds: Int = 8
    var cycles: Int = 1
    var restCycle: Int = 60
    var cooldown: Int = 0
    var createdAt: Date = Date()

    init(name: String, config: TabataConfig, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        apply(config)
    }

    var config: TabataConfig {
        TabataConfig(prepare: prepare, work: work, rest: rest, rounds: rounds,
                     cycles: cycles, restCycle: restCycle, cooldown: cooldown)
    }

    func apply(_ c: TabataConfig) {
        prepare = c.prepare; work = c.work; rest = c.rest; rounds = c.rounds
        cycles = c.cycles; restCycle = c.restCycle; cooldown = c.cooldown
    }
}

@Model final class TabataSessionLog {
    var id: UUID
    /// `TabataEngine.sessionID` : une séance finie n'est journalisée qu'une fois.
    var sessionID: UUID
    var date: Date = Date()
    var name: String = ""
    var completedRounds: Int = 0
    var totalRounds: Int = 0
    var activeSeconds: Int = 0
    var workSeconds: Int = 0

    init(sessionID: UUID, date: Date, name: String, completedRounds: Int, totalRounds: Int,
         activeSeconds: Int, workSeconds: Int) {
        self.id = UUID()
        self.sessionID = sessionID
        self.date = date
        self.name = name
        self.completedRounds = completedRounds
        self.totalRounds = totalRounds
        self.activeSeconds = activeSeconds
        self.workSeconds = workSeconds
    }
}

// MARK: - Logique pure (testée dans Lot6FitnessTests)

/// Saisie décimale française : "72,5" comme "72.5".
enum FitnessInput {
    static func decimal(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite else { return nil }
        return v
    }
}

/// Bibliothèque d'exercices : le catalogue réel déjà dans l'app + les exercices perso.
enum ExerciseLibrary {
    /// Groupes musculaires du catalogue existant, dans un ordre stable, plus "Autre".
    static let muscleGroups: [String] =
        ["Pecs", "Dos", "Épaules", "Biceps", "Triceps", "Quadriceps", "Ischios", "Mollets", "Abdos", "Cardio"]
            .filter { GymExercises.catalog[$0] != nil } + ["Autre"]

    static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// nil = nom valide. Refuse le vide et un doublon (accents et casse ignorés),
    /// sauf le nom d'origine de l'exercice qu'on modifie.
    static func validate(name: String, existing: [String], original: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Donne un nom à l'exercice." }
        guard n.count <= 60 else { return "Nom trop long (60 caractères max)." }
        let k = key(n)
        if let original, key(original) == k { return nil }
        if existing.contains(where: { key($0) == k }) { return "Cet exercice existe déjà." }
        return nil
    }

    /// Noms proposés dans l'éditeur de série : exercices perso puis déjà loggés,
    /// sans doublon (accents et casse ignorés), triés.
    static func suggestions(custom: [String], logged: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for n in custom + logged {
            let t = n.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, seen.insert(key(t)).inserted else { continue }
            out.append(t)
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Groupe d'un exercice : l'exercice perso d'abord, sinon le catalogue.
    static func group(of name: String, custom: [(name: String, group: String)]) -> String? {
        if let c = custom.first(where: { key($0.name) == key(name) }) { return c.group }
        return GymExercises.group(of: name)
    }
}

/// Conversions d'unités des mensurations.
enum FitnessUnits {
    static let lbPerKg = 2.2046226218
    static let cmPerInch = 2.54

    /// nil si les unités ne mesurent pas la même chose (kg vers cm).
    static func convert(_ v: Double, from: MeasureUnit, to: MeasureUnit) -> Double? {
        guard from.family == to.family else { return nil }
        if from == to { return v }
        switch (from, to) {
        case (.kg, .lb):   return v * lbPerKg
        case (.lb, .kg):   return v / lbPerKg
        case (.cm, .inch): return v / cmPerInch
        case (.inch, .cm): return v * cmPerInch
        default:           return nil
        }
    }
}

enum BodyMeasureLogic {
    struct Point: Equatable { let date: Date; let value: Double }

    /// Valeur saisie valide pour ce type, ou nil.
    static func parse(_ text: String, kind: MeasurementKind) -> Double? {
        guard let v = FitnessInput.decimal(text), v > 0 else { return nil }
        if kind == .bodyFat { return v < 100 ? v : nil }
        return v < 1000 ? v : nil
    }

    /// Série d'un type, du plus ancien au plus récent, convertie dans `unit`.
    /// Une ligne d'une unité incompatible est ignorée, jamais mal convertie.
    static func series(_ entries: [BodyMeasurement], kind: MeasurementKind, in unit: MeasureUnit) -> [Point] {
        entries.filter { $0.kind == kind.rawValue }
            .compactMap { e -> Point? in
                guard let u = MeasureUnit(rawValue: e.unit),
                      let v = FitnessUnits.convert(e.value, from: u, to: unit) else { return nil }
                return Point(date: e.date, value: v)
            }
            .sorted { $0.date < $1.date }
    }

    /// Écart entre la première et la dernière mesure, nil sous deux mesures.
    static func change(_ points: [Point]) -> Double? {
        guard points.count >= 2, let f = points.first, let l = points.last else { return nil }
        return l.value - f.value
    }
}

/// Export CSV des séries (RFC 4180 : virgule, guillemets doublés, point décimal).
enum SetsCSV {
    static let header = "date,exercice,type,charge_kg,repetitions,rpe,volume_kg,seance"

    static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func number(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    static func make(_ sets: [WorkoutSet], timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let rows = sets.sorted { $0.date < $1.date }.map { s -> String in
            [f.string(from: s.date), escape(s.exercise), s.kind, number(s.weightKg), String(s.reps),
             number(s.rpe), number(s.volume), s.sessionID?.uuidString ?? ""].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}

/// Règles des routines de mobilité perso.
enum MobilityRoutineRules {
    static let secondsRange = 5...600

    /// nil = routine valide.
    static func validate(name: String, steps: [MobilityStepSpec]) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Donne un nom à la routine." }
        if steps.isEmpty { return "Ajoute au moins un exercice." }
        if steps.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Chaque exercice a besoin d'un nom."
        }
        if steps.contains(where: { !secondsRange.contains($0.seconds) }) {
            return "Durée par exercice : de 5 s à 10 min."
        }
        return nil
    }

    static func totalSeconds(_ steps: [MobilityStepSpec]) -> Int { steps.reduce(0) { $0 + $1.seconds } }

    static func moved(_ steps: [MobilityStepSpec], from: IndexSet, to: Int) -> [MobilityStepSpec] {
        var s = steps
        let moving = from.sorted().map { s[$0] }
        for i in from.sorted(by: >) { s.remove(at: i) }
        let shift = from.filter { $0 < to }.count
        s.insert(contentsOf: moving, at: max(0, min(s.count, to - shift)))
        return s
    }
}

/// Progression d'une séance de mobilité, sauvegardée à chaque étape : un
/// relancement reprend à l'exercice en cours (le minuteur, lui, est relu par
/// `CountdownEngine(key: "mobility")`).
struct MobilityProgress: Codable, Equatable {
    var routineID: String
    var runID: UUID
    var index: Int
    var startedAt: Date
    /// Secondes réellement faites (exercices finis + partie faite des passés).
    var doneSeconds: Int = 0
    /// Exercices menés jusqu'au bout du minuteur.
    var doneCount: Int = 0
    /// L'exercice `index` attend "Reprendre" : son minuteur n'a pas démarré.
    var waiting: Bool = false
}

enum MobilityResume {
    static let storeKey = "mobility.progress"

    enum Point: Equatable {
        case none
        case running(Int)
        case paused(Int)
        /// L'exercice attend "Reprendre" (rien à créditer).
        case ready(Int)
        /// L'exercice précédent s'est fini app fermée : le créditer, puis attendre
        /// "Reprendre" sur celui-ci.
        case expiredThenReady(Int)
        /// Le dernier exercice s'est fini app fermée : le créditer, séance terminée.
        case finished
    }

    static func resolve(saved: MobilityProgress?, routineID: String, stepCount: Int,
                        engineRunning: Bool, engineRemaining: Int) -> Point {
        guard let saved, saved.routineID == routineID, saved.index >= 0, saved.index < stepCount else { return .none }
        if saved.waiting { return .ready(saved.index) }
        if engineRunning { return .running(saved.index) }
        if engineRemaining > 0 { return .paused(saved.index) }
        return saved.index + 1 < stepCount ? .expiredThenReady(saved.index + 1) : .finished
    }

    static func load(_ d: UserDefaults = .standard) -> MobilityProgress? {
        guard let data = d.data(forKey: storeKey) else { return nil }
        return try? JSONDecoder().decode(MobilityProgress.self, from: data)
    }
    static func save(_ p: MobilityProgress, _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(p) { d.set(data, forKey: storeKey) }
    }
    static func clear(_ d: UserDefaults = .standard) { d.removeObject(forKey: storeKey) }
}

/// Renommer un exercice perso renomme aussi ses séries déjà loggées : sinon
/// l'historique et les records se coupent en deux noms.
enum ExerciseRename {
    @discardableResult
    static func apply(from old: String, to new: String, sets: [WorkoutSet]) -> Int {
        let k = ExerciseLibrary.key(old)
        let target = new.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, k != ExerciseLibrary.key(target) || old != target else { return 0 }
        var n = 0
        for s in sets where ExerciseLibrary.key(s.exercise) == k { s.exercise = target; n += 1 }
        return n
    }
}

/// Une séance (Tabata, mobilité) ne s'écrit qu'une fois par identifiant.
enum FitnessHistory {
    static func shouldRecord(_ id: UUID, existing: [UUID]) -> Bool { !existing.contains(id) }

    /// Journal Tabata : nil si aucun effort n'a été fait (tout sauté n'est pas une séance).
    static func tabataLog(sessionID: UUID, finishedAt: Date, name: String?, completedRounds: Int,
                          totalRounds: Int, activeSeconds: Int, workSeconds: Int) -> TabataSessionLog? {
        guard completedRounds > 0, activeSeconds > 0 else { return nil }
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return TabataSessionLog(sessionID: sessionID, date: finishedAt,
                                name: n.isEmpty ? "Intervalles libres" : n,
                                completedRounds: completedRounds, totalRounds: totalRounds,
                                activeSeconds: activeSeconds, workSeconds: workSeconds)
    }
}

enum TabataPresetRules {
    static func validate(name: String, existing: [String], original: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Donne un nom au préréglage." }
        guard n.count <= 40 else { return "Nom trop long (40 caractères max)." }
        let k = ExerciseLibrary.key(n)
        if let original, ExerciseLibrary.key(original) == k { return nil }
        if existing.contains(where: { ExerciseLibrary.key($0) == k }) { return "Un préréglage porte déjà ce nom." }
        return nil
    }

    /// Bornes sûres : effort au moins 5 s, au moins un round et un cycle.
    static func sanitized(_ c: TabataConfig) -> TabataConfig {
        TabataConfig(prepare: max(0, min(c.prepare, 3600)), work: max(5, min(c.work, 3600)),
                     rest: max(0, min(c.rest, 3600)), rounds: max(1, min(c.rounds, 100)),
                     cycles: max(1, min(c.cycles, 50)), restCycle: max(0, min(c.restCycle, 3600)),
                     cooldown: max(0, min(c.cooldown, 3600)))
    }

    /// Même formule que l'écran de réglages Tabata.
    static func totalSeconds(_ c: TabataConfig) -> Int {
        let perCycle = c.work * c.rounds + c.rest * max(0, c.rounds - 1)
        return c.prepare + perCycle * c.cycles + c.restCycle * max(0, c.cycles - 1) + c.cooldown
    }
}

/// Moteur de série de Streakz : jours actifs (muscu, Tabata, mobilité), série
/// en jours, série en semaines selon un objectif hebdo (les jours de repos ne
/// cassent rien tant que l'objectif de la semaine est tenu), et carte de chaleur.
enum StreakEngine {
    /// Calendrier français : semaine du lundi.
    static var frenchCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    struct DayActivity: Equatable {
        var strength = false
        var tabata = false
        var mobility = false
        var types: Int { [strength, tabata, mobility].filter { $0 }.count }
    }

    static func activity(strength: [Date], tabata: [Date], mobility: [Date], calendar: Calendar) -> [Date: DayActivity] {
        var out: [Date: DayActivity] = [:]
        for d in strength { out[calendar.startOfDay(for: d), default: .init()].strength = true }
        for d in tabata { out[calendar.startOfDay(for: d), default: .init()].tabata = true }
        for d in mobility { out[calendar.startOfDay(for: d), default: .init()].mobility = true }
        return out
    }

    /// Jours consécutifs actifs. Aujourd'hui sans activité ne casse pas encore la série.
    static func dayStreak(_ active: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: today)
        if !active.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while active.contains(day) { n += 1; day = calendar.date(byAdding: .day, value: -1, to: day)! }
        return n
    }

    static func bestDayStreak(_ active: Set<Date>, calendar: Calendar) -> Int {
        var best = 0, run = 0
        var prev: Date?
        for d in active.sorted() {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        return best
    }

    static func weekStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func activeDaysPerWeek(_ active: Set<Date>, calendar: Calendar) -> [Date: Int] {
        var out: [Date: Int] = [:]
        for d in active { out[weekStart(d, calendar: calendar), default: 0] += 1 }
        return out
    }

    /// Semaines consécutives où l'objectif est tenu. La semaine en cours compte si
    /// l'objectif est déjà atteint ; sinon elle est "en cours" et ne casse rien.
    static func weeklyStreak(_ active: Set<Date>, target: Int, today: Date, calendar: Calendar) -> Int {
        let t = max(1, min(7, target))
        let perWeek = activeDaysPerWeek(active, calendar: calendar)
        var week = weekStart(today, calendar: calendar)
        var n = 0
        if (perWeek[week] ?? 0) >= t { n = 1 }
        week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
        while (perWeek[week] ?? 0) >= t {
            n += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
        }
        return n
    }

    static func bestWeeklyStreak(_ active: Set<Date>, target: Int, calendar: Calendar) -> Int {
        let t = max(1, min(7, target))
        let good = activeDaysPerWeek(active, calendar: calendar).filter { $0.value >= t }.keys.sorted()
        var best = 0, run = 0
        var prev: Date?
        for w in good {
            if let p = prev, calendar.date(byAdding: .weekOfYear, value: 1, to: p) == w { run += 1 } else { run = 1 }
            best = max(best, run); prev = w
        }
        return best
    }

    struct HeatCell: Equatable, Identifiable {
        let date: Date
        let types: Int
        let isFuture: Bool
        var id: Date { date }
    }

    /// `weeks` colonnes de 7 jours (lundi en haut), la dernière contient aujourd'hui.
    static func heatmap(_ activity: [Date: DayActivity], weeks: Int, today: Date, calendar: Calendar) -> [[HeatCell]] {
        let todayStart = calendar.startOfDay(for: today)
        let lastWeek = weekStart(today, calendar: calendar)
        guard let first = calendar.date(byAdding: .weekOfYear, value: -(max(1, weeks) - 1), to: lastWeek) else { return [] }
        return (0..<max(1, weeks)).map { w in
            let ws = calendar.date(byAdding: .weekOfYear, value: w, to: first)!
            return (0..<7).map { d in
                let day = calendar.date(byAdding: .day, value: d, to: ws)!
                return HeatCell(date: day, types: activity[day]?.types ?? 0, isFuture: day > todayStart)
            }
        }
    }
}

/// Rappel quotidien de Streakz.
enum StreakReminder {
    static let id = "lifeos.streakz.reminder"
    static func components(minutes: Int) -> DateComponents {
        let m = ((minutes % 1440) + 1440) % 1440
        return DateComponents(hour: m / 60, minute: m % 60)
    }
}

/// Compteur de pas : statistiques d'une fenêtre et notification d'objectif.
enum StepStats {
    struct BestDay: Equatable { let day: Date; let steps: Int }
    struct Summary: Equatable {
        let average: Int
        let goalHits: Int
        let days: Int
        let best: BestDay?
    }

    static func summary(_ days: [(day: Date, steps: Int)], goal: Int) -> Summary {
        guard !days.isEmpty else { return Summary(average: 0, goalHits: 0, days: 0, best: nil) }
        let total = days.reduce(0) { $0 + $1.steps }
        let best = days.filter { $0.steps > 0 }.max { $0.steps < $1.steps }.map { BestDay(day: $0.day, steps: $0.steps) }
        return Summary(average: total / days.count, goalHits: days.filter { $0.steps >= max(1, goal) }.count,
                       days: days.count, best: best)
    }

    /// Record gardé : le plus haut jamais vu par LifeOS. À égalité, le plus ancien reste.
    static func record(current: BestDay?, seen: [(day: Date, steps: Int)]) -> BestDay? {
        var best = current
        for d in seen where d.steps > (best?.steps ?? 0) { best = BestDay(day: d.day, steps: d.steps) }
        return best
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Une seule notification par jour, et seulement si l'objectif est atteint.
    static func shouldNotifyGoal(steps: Int, goal: Int, lastNotifiedDay: String, now: Date, calendar: Calendar = .current) -> Bool {
        goal > 0 && steps >= goal && lastNotifiedDay != dayKey(now, calendar: calendar)
    }
}
