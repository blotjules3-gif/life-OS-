import Foundation

// Instantanes lus par les widgets, ecrits par l'app (`WidgetPublisher`).
// Compile dans l'app ET dans l'extension : les deux decodent les memes structures.
//
// Regles :
// - Chaque instantane porte son jour metier (`day`) et sa date de derniere
//   modification (`updatedAt`). Un instantane d'un autre jour n'est jamais montre
//   comme celui d'aujourd'hui.
// - L'app n'ecrit que si la VALEUR change (signature sans `updatedAt`), et ne
//   recharge que les widgets concernes.
// - Les fonctions de selection (taches du jour, agenda, fenetre de jeune...) sont
//   pures et partagees : le widget les rejoue a minuit sans attendre l'app.

// MARK: - Identifiants des widgets (ne jamais renommer un `kind` existant)

enum WidgetKinds {
    static let tabata = "TabataWidget"
    static let hydration = "HydrationWidget"
    static let gym = "GymFocusWidget"
    static let sleep = "SleepWidget"
    static let fasting = "FastingWidget"
    static let habits = "HabitsWidget"
    static let interactiveHabits = "InteractiveHabitsWidget"
    static let energy = "EnergyScoreWidget"
    static let foodScan = "com.blotjules.lifeos.foodscan.widget"
    static let coach = "com.blotjules.lifeos.coach.quickask"
    static let tasks = "LifeOSTasksWidget"
    static let agenda = "LifeOSAgendaWidget"
    static let nutrition = "LifeOSNutritionWidget"
}

// MARK: - Liens profonds (memes chaines que le routeur de l'app)

enum WidgetLink {
    static func url(_ host: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents()
        c.scheme = "lifeos"; c.host = host
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url ?? URL(string: "lifeos://\(host)")!
    }
    static var water: URL { url("water") }
    static var gym: URL { url("gym") }
    static var sleep: URL { url("sleep") }
    static var fasting: URL { url("fasting") }
    static var tabata: URL { url("tabata") }
    static var tasks: URL { url("tasks") }
    static func task(_ uid: String) -> URL { url("task", ["uid": uid]) }
    static var agenda: URL { url("agenda") }
    static var habits: URL { url("habits") }
    static var nutrition: URL { url("nutrition") }
    static var scanFood: URL { url("scan-food") }
    static var briefing: URL { url("briefing") }
    static func coach(prefill: String? = nil) -> URL { url("coach", prefill.map { ["prefill": $0] } ?? [:]) }
}

// MARK: - Stockage avec signature de valeur

protocol StampedSnapshot: Codable, Equatable {
    var day: String { get set }
    var updatedAt: Date { get set }
}

enum WidgetSnapshotStore {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; e.outputFormatting = [.sortedKeys]; return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }

    /// Signature de la valeur : l'instantane encode avec `updatedAt` neutralise.
    static func signature<T: StampedSnapshot>(_ value: T) -> Data? {
        var v = value
        v.updatedAt = Date(timeIntervalSince1970: 0)
        return try? encoder().encode(v)
    }

    static func read<T: StampedSnapshot>(_ type: T.Type, key: String, from d: UserDefaults? = LifeOSGroup.defaults) -> T? {
        guard let data = d?.data(forKey: key) else { return nil }
        return try? decoder().decode(T.self, from: data)
    }

    /// Ecrit seulement si la valeur a change. Rend `true` si quelque chose a ete ecrit.
    @discardableResult
    static func write<T: StampedSnapshot>(_ value: T, key: String, to d: UserDefaults? = LifeOSGroup.defaults) -> Bool {
        guard let d, let sig = signature(value) else { return false }
        if d.data(forKey: key + ".sig") == sig { return false }
        guard let data = try? encoder().encode(value) else { return false }
        d.set(data, forKey: key)
        d.set(sig, forKey: key + ".sig")
        return true
    }

    /// Mise a jour immediate depuis le widget (retour visuel) : on ecrit sans toucher
    /// a la signature, pour que la prochaine publication de l'app reecrive la verite.
    static func overwrite<T: StampedSnapshot>(_ value: T, key: String, to d: UserDefaults? = LifeOSGroup.defaults) {
        guard let d, let data = try? encoder().encode(value) else { return }
        d.set(data, forKey: key)
        d.removeObject(forKey: key + ".sig")
    }
}

enum WidgetDay {
    static func stamp(_ date: Date = .now, timeZone: TimeZone = .current) -> String {
        HabitOps.businessDay(date, timeZone: timeZone)
    }
    static func isToday(_ day: String?, now: Date = .now, timeZone: TimeZone = .current) -> Bool {
        day == stamp(now, timeZone: timeZone)
    }
}

// MARK: - Taches

struct TasksSnapshot: StampedSnapshot {
    struct Item: Codable, Equatable, Identifiable {
        let id: String          // TodoItem.uid
        var title: String
        var due: Date?
        /// Echeance sans heure (pile a minuit).
        var dateOnly: Bool
        var priority: Int
        var done: Bool
        var completedAt: Date?
        var project: String
        var recurring: Bool
    }
    static let key = "widget_tasks_v1"
    var version = 1
    var day: String
    var updatedAt: Date
    /// Taches ouvertes jusqu'a J+7 (retard compris) et taches faites aujourd'hui.
    var items: [Item]
    /// Taches ouvertes au total dans cette fenetre (avant la coupe a `items`).
    var openCount: Int
}

/// Ce que montrent les widgets de taches, calcule au rendu : a minuit, les retards
/// et le "jour" changent sans attendre l'app.
enum TaskSelection {
    static let maxItems = 40

    static func isDateOnly(_ d: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.hour, .minute, .second], from: d)
        return c.hour == 0 && c.minute == 0 && c.second == 0
    }

    /// Meme regle que l'app : une date sans heure n'est en retard qu'au lendemain.
    static func isOverdue(_ i: TasksSnapshot.Item, now: Date, calendar: Calendar = .current) -> Bool {
        guard !i.done, let due = i.due else { return false }
        return i.dateOnly ? due < calendar.startOfDay(for: now) : due < now
    }

    static func isDueToday(_ i: TasksSnapshot.Item, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due = i.due else { return false }
        return calendar.isDate(due, inSameDayAs: now)
    }

    /// Ordre de l'app : priorite la plus haute, puis echeance la plus proche.
    static func precedes(_ a: TasksSnapshot.Item, _ b: TasksSnapshot.Item) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        switch (a.due, b.due) {
        case let (x?, y?): return x != y ? x < y : a.id < b.id
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.id < b.id
        }
    }

    /// Aujourd'hui : retards + echeances du jour, ouvertes d'abord (retards en tete),
    /// puis celles faites aujourd'hui.
    static func today(_ items: [TasksSnapshot.Item], now: Date = .now, calendar: Calendar = .current) -> [TasksSnapshot.Item] {
        let open = items.filter { !$0.done && (isOverdue($0, now: now, calendar: calendar) || isDueToday($0, now: now, calendar: calendar)) }
        let overdue = open.filter { isOverdue($0, now: now, calendar: calendar) }.sorted(by: precedes)
        let todayOnly = open.filter { !isOverdue($0, now: now, calendar: calendar) }.sorted(by: precedes)
        let doneToday = items.filter { $0.done && ($0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return overdue + todayOnly + doneToday
    }

    /// Les 7 jours suivants (apres aujourd'hui), par echeance.
    static func upcoming(_ items: [TasksSnapshot.Item], now: Date = .now, calendar: Calendar = .current) -> [TasksSnapshot.Item] {
        let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) ?? now
        return items.filter { !$0.done && ($0.due.map { $0 >= start && $0 < end } ?? false) }
            .sorted { ($0.due ?? .distantFuture, $0.id) < ($1.due ?? .distantFuture, $1.id) }
    }

    /// Prochaine chose a faire : le premier element ouvert d'aujourd'hui, sinon des 7 jours.
    static func next(_ items: [TasksSnapshot.Item], now: Date = .now, calendar: Calendar = .current) -> TasksSnapshot.Item? {
        today(items, now: now, calendar: calendar).first { !$0.done } ?? upcoming(items, now: now, calendar: calendar).first
    }

    static func openTodayCount(_ items: [TasksSnapshot.Item], now: Date = .now, calendar: Calendar = .current) -> Int {
        today(items, now: now, calendar: calendar).filter { !$0.done }.count
    }

    /// Coupe a publier : retards et jour d'abord, puis la semaine, puis les faites du jour.
    static func trimmed(_ items: [TasksSnapshot.Item], now: Date = .now, calendar: Calendar = .current, limit: Int = maxItems) -> [TasksSnapshot.Item] {
        let t = today(items, now: now, calendar: calendar)
        let open = t.filter { !$0.done }
        let up = upcoming(items, now: now, calendar: calendar)
        let done = t.filter(\.done)
        var out: [TasksSnapshot.Item] = []
        for i in open + up + done where out.count < limit && !out.contains(where: { $0.id == i.id }) { out.append(i) }
        return out
    }

    /// Retour visuel immediat apres un appui dans le widget.
    static func applying(_ op: WidgetOp, to snap: TasksSnapshot, now: Date = .now) -> TasksSnapshot {
        guard op.kind == .task else { return snap }
        var s = snap
        s.items = s.items.compactMap { i in
            guard i.id == op.targetID else { return i }
            var i = i
            switch op.action {
            case .complete:
                // Une tache recurrente passe a sa prochaine occurrence : elle quitte la liste du jour.
                if i.recurring { return nil }
                i.done = true; i.completedAt = now
            case .uncomplete:
                i.done = false; i.completedAt = nil
            case .add: break
            }
            return i
        }
        return s
    }
}

// MARK: - Agenda

struct AgendaSnapshot: StampedSnapshot {
    enum Source: String, Codable { case task, event, gym, supplement, social }
    struct Item: Codable, Equatable, Identifiable {
        let id: String
        var title: String
        var detail: String
        var start: Date?
        var end: Date?
        var allDay: Bool
        var source: Source
        /// Lien profond de l'element (texte d'URL lifeos://...).
        var link: String
    }
    static let key = "widget_agenda_v1"
    var version = 1
    var day: String
    var updatedAt: Date
    var items: [Item]
    /// Acces au calendrier accorde (sinon les evenements ne sont pas lus, et le widget le dit).
    var calendarAccess: Bool

    /// Elements d'un jour : avec heure par ordre de debut, puis "toute la journee".
    static func items(on day: Date, from items: [Item], calendar: Calendar = .current) -> [Item] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let onDay = items.filter { i in
            guard let s = i.start else { return false }
            let e = i.end ?? s
            return s < dayEnd && e >= dayStart
        }
        let timed = onDay.filter { !$0.allDay }.sorted { ($0.start ?? .distantPast, $0.id) < ($1.start ?? .distantPast, $1.id) }
        let allDay = onDay.filter(\.allDay).sorted { $0.title < $1.title }
        return timed + allDay
    }

    /// Ce qui reste a venir aujourd'hui (fin pas encore passee), puis le "toute la journee".
    static func remaining(_ items: [Item], now: Date = .now, calendar: Calendar = .current) -> [Item] {
        Self.items(on: now, from: items, calendar: calendar).filter { $0.allDay || ($0.end ?? $0.start ?? now) >= now }
    }

    static func next(_ items: [Item], now: Date = .now, calendar: Calendar = .current) -> Item? {
        remaining(items, now: now, calendar: calendar).first { !$0.allDay } ?? remaining(items, now: now, calendar: calendar).first
    }
}

// MARK: - Nutrition

struct NutritionGoals: Codable, Equatable {
    var kcal: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    /// Vrai pour chaque objectif que l'utilisateur n'a pas regle : valeur par defaut
    /// de l'app (2200 kcal, 150 g, 250 g, 70 g), signalee comme telle.
    var kcalIsDefault: Bool
    var macrosAreDefault: Bool

    static let defaults = (kcal: 2200, protein: 150, carbs: 250, fat: 70)

    /// Objectifs a afficher. `nil` ou <= 0 = pas regle : valeur par defaut de l'app.
    static func resolve(kcal: Int?, protein: Int?, carbs: Int?, fat: Int?) -> NutritionGoals {
        func ok(_ v: Int?) -> Int? { v.flatMap { $0 > 0 ? $0 : nil } }
        return NutritionGoals(kcal: ok(kcal) ?? defaults.kcal,
                              protein: ok(protein) ?? defaults.protein,
                              carbs: ok(carbs) ?? defaults.carbs,
                              fat: ok(fat) ?? defaults.fat,
                              kcalIsDefault: ok(kcal) == nil,
                              macrosAreDefault: ok(protein) == nil && ok(carbs) == nil && ok(fat) == nil)
    }
}

struct NutritionSnapshot: StampedSnapshot {
    static let key = "widget_nutrition_v1"
    var version = 1
    var day: String
    var updatedAt: Date
    var kcal: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var entries: Int
    var goals: NutritionGoals

    /// Valeurs du jour pour l'affichage : un instantane d'un autre jour = rien mange
    /// enregistre aujourd'hui (jamais les chiffres d'hier).
    func current(now: Date = .now, timeZone: TimeZone = .current) -> NutritionSnapshot {
        guard !WidgetDay.isToday(day, now: now, timeZone: timeZone) else { return self }
        var s = self
        s.day = WidgetDay.stamp(now, timeZone: timeZone)
        s.kcal = 0; s.protein = 0; s.carbs = 0; s.fat = 0; s.entries = 0
        return s
    }

    static func ratio(_ value: Double, _ goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return max(0, min(1, value / Double(goal)))
    }
}

// MARK: - Sommeil

struct SleepSnapshot: StampedSnapshot {
    static let key = "widget_sleep_v1"
    var version = 1
    var day: String
    var updatedAt: Date
    /// nil = reveil jamais regle dans LifeOS.
    var wakeHour: Int?
    var wakeMinute: Int?
    var wakeEnabled: Bool
    var targetHours: Double
    var targetIsDefault: Bool
    /// Derniere nuit et le jour ou elle a ete saisie ou lue dans Sante.
    var lastSleepHours: Double?
    var lastSleepDay: String?

    /// Coucher conseille : reveil moins l'objectif, a la minute pres.
    static func bedtime(wakeHour: Int, wakeMinute: Int, targetHours: Double) -> (hour: Int, minute: Int) {
        let wake = wakeHour * 60 + wakeMinute
        let total = Int((targetHours * 60).rounded())
        let bed = ((wake - total) % 1440 + 1440) % 1440
        return (bed / 60, bed % 60)
    }

    /// Nuit derniere seulement si elle date d'aujourd'hui.
    func lastNight(now: Date = .now, timeZone: TimeZone = .current) -> Double? {
        guard let h = lastSleepHours, h > 0, WidgetDay.isToday(lastSleepDay, now: now, timeZone: timeZone) else { return nil }
        return h
    }
}

// MARK: - Tabata

struct TabataSnapshot: StampedSnapshot {
    static let key = "widget_tabata_v1"
    var version = 1
    var day: String
    var updatedAt: Date
    /// Nom de la seance en cours ou de la derniere faite ; nil = intervalles libres.
    var name: String?
    /// Nombre d'exercices de cette seance (0 = intervalles libres, pas affiche).
    var exercises: Int
    var work: Int
    var rest: Int
    var rounds: Int
    var cycles: Int
    var inProgress: Bool
    var lastDone: Date?

    /// Duree totale des intervalles (sans preparation), en secondes.
    var totalSeconds: Int { max(0, (work + rest) * rounds * max(1, cycles)) }
}

// MARK: - Programme de sport de la semaine

struct GymWeekSnapshot: StampedSnapshot {
    struct Day: Codable, Equatable {
        var weekday: Int   // 1 = dimanche ... 7 = samedi
        var title: String
        var focus: String
        var isRest: Bool
    }
    static let key = "widget_gymweek_v1"
    var version = 1
    var day: String
    var updatedAt: Date
    var days: [Day]

    /// Seance du jour lue dans le programme de la semaine : juste meme si l'app n'a
    /// pas ete ouverte aujourd'hui. nil = rien de prevu ce jour-la.
    func plan(for date: Date, calendar: Calendar = .current) -> Day? {
        let wd = calendar.component(.weekday, from: date)
        return days.first { $0.weekday == wd && ($0.isRest || !$0.title.isEmpty) }
    }
}

// MARK: - Jeune

enum FastingMath {
    /// Fenetre d'alimentation d'un objectif de jeune (16 h -> 8 h). Borne a 0...24.
    static func eatingWindow(targetHours: Int) -> Int { max(0, min(24, 24 - targetHours)) }

    /// Libelle neutre "16:8". Pour un jeune de 24 h ou plus, seulement la duree.
    static func ratioLabel(targetHours: Int) -> String {
        targetHours >= 24 ? "\(targetHours) h" : "\(targetHours):\(eatingWindow(targetHours: targetHours))"
    }

    /// Phase neutre, sans promesse de sante.
    static func phase(elapsedHours: Double, targetHours: Int) -> String {
        if elapsedHours >= Double(targetHours) { return "Objectif atteint" }
        let p = targetHours > 0 ? elapsedHours / Double(targetHours) : 0
        switch p {
        case ..<0.25: return "Début du jeûne"
        case ..<0.75: return "En cours"
        default: return "Dernière ligne droite"
        }
    }
}

// MARK: - Score energie

enum EnergyKeys {
    static let value = "energyScore.value"
    static let label = "energyScore.label"
    static let colorHex = "energyScore.colorHex"
    static let updatedAt = "energyScore.updatedAt"
    static let day = "energyScore.day"
}

// MARK: - Eau : retour visuel immediat depuis le widget

enum WaterWidgetState {
    /// Ajoute `ml` a l'eau du jour affichee (repart de 0 si la valeur date d'hier).
    static func applyOptimisticAdd(_ ml: Int, defaults d: UserDefaults?, now: Date = .now) {
        guard let d else { return }
        let current = WidgetKeys.waterForToday(value: d.integer(forKey: WidgetKeys.waterToday),
                                               day: d.string(forKey: WidgetKeys.waterDay), now: now)
        d.set(current + max(0, ml), forKey: WidgetKeys.waterToday)
        d.set(WidgetKeys.dayStamp(now), forKey: WidgetKeys.waterDay)
    }
}
