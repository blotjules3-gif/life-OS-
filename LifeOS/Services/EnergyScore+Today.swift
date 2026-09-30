import Foundation
import SwiftData

/// Lecture des donnees du jour pour le Score d'Energie.
///
/// Separe du calcul lui meme, qui ne depend que de Foundation: le calcul et le
/// tri des donnees du jour s'executent et se testent sans simulateur.
///
/// Defauts corriges le 28 septembre:
///   - le dernier sommeil etait lu sans regarder sa date: la saisie d'hier
///     comptait pour aujourd'hui si la remise a zero de minuit n'avait pas tourne;
///   - toutes les habitudes comptaient, meme celles pas prevues ce jour la: un
///     jour de repos faisait baisser le score;
///   - "la derniere humeur du jour" prenait une humeur quelconque du jour.
/// Le score affiche dit maintenant ce qu'il a lu, de quand, et ce qui manque.
extension EnergyScore {

    struct HabitDay: Equatable {
        let plannedToday: Bool
        let doneToday: Bool
    }

    /// Donnees brutes, avec leurs dates, avant tri.
    struct Raw {
        var sleepHours: Double?
        var sleepQuality: Int?
        var sleepRecordedAt: Date?
        var moods: [(date: Date, score: Int)] = []
        var waters: [(date: Date, ml: Int)] = []
        var habits: [HabitDay] = []
        var fatigue: Int?
    }

    /// Une entree du score, telle qu'on la montre.
    struct Part: Equatable, Identifiable {
        var id: String { name }
        let name: String
        let detail: String
        let used: Bool
    }

    struct Explained: Equatable {
        let result: Result
        let parts: [Part]
        /// Assez de criteres pour afficher un chiffre.
        var isShown: Bool { result.coverage >= EnergyScore.minimumCoverage }
    }

    static func explain(_ raw: Raw, goals: Goals, now: Date = .now, calendar cal: Calendar = .current) -> Explained {
        var input = Input()
        var parts: [Part] = []

        // Sommeil: seulement une saisie faite aujourd'hui (le check du matin).
        if let at = raw.sleepRecordedAt, cal.isDate(at, inSameDayAs: now),
           raw.sleepHours != nil || raw.sleepQuality != nil {
            input.sleepHours = raw.sleepHours
            input.sleepQuality = raw.sleepQuality
            var bits: [String] = []
            if let h = raw.sleepHours { bits.append(String(format: "%.1f h sur %.1f h visées", h, goals.sleepHours)) }
            if let q = raw.sleepQuality { bits.append("qualité \(q)/5") }
            parts.append(Part(name: "Sommeil", detail: bits.joined(separator: ", ") + ", saisi à \(at.formatted(date: .omitted, time: .shortened))", used: true))
        } else if let at = raw.sleepRecordedAt, raw.sleepHours != nil || raw.sleepQuality != nil {
            parts.append(Part(name: "Sommeil", detail: "dernière saisie le \(at.formatted(date: .abbreviated, time: .omitted)), trop ancienne pour aujourd'hui", used: false))
        } else {
            parts.append(Part(name: "Sommeil", detail: "pas encore saisi aujourd'hui", used: false))
        }

        // Humeur: la plus recente du jour.
        if let m = raw.moods.filter({ cal.isDate($0.date, inSameDayAs: now) }).max(by: { $0.date < $1.date }) {
            input.mood = m.score
            parts.append(Part(name: "Humeur", detail: "\(m.score)/5 à \(m.date.formatted(date: .omitted, time: .shortened))", used: true))
        } else {
            parts.append(Part(name: "Humeur", detail: "pas encore notée aujourd'hui", used: false))
        }

        // Eau du jour.
        let ml = raw.waters.filter { cal.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.ml }
        if ml > 0 {
            input.waterML = ml
            parts.append(Part(name: "Eau", detail: "\(ml) ml sur \(goals.waterML) ml visés", used: true))
        } else {
            parts.append(Part(name: "Eau", detail: "rien noté aujourd'hui", used: false))
        }

        // Habitudes PREVUES aujourd'hui. Aucune prevue: le critere sort du calcul,
        // un jour de repos ne coute rien.
        let planned = raw.habits.filter(\.plannedToday)
        if !planned.isEmpty {
            let done = planned.filter(\.doneToday).count
            input.habitsDone = done
            input.habitsTotal = planned.count
            parts.append(Part(name: "Habitudes", detail: "\(done) sur \(planned.count) prévues aujourd'hui", used: true))
        } else if !raw.habits.isEmpty {
            parts.append(Part(name: "Habitudes", detail: "aucune prévue aujourd'hui, pas comptées", used: false))
        }

        if let f = raw.fatigue {
            input.fatigue = f
            parts.append(Part(name: "Fatigue", detail: "\(f)/5", used: true))
        }

        return Explained(result: compute(input, goals: goals), parts: parts)
    }

    // MARK: - Lecture SwiftData

    static func goalsFromSettings(_ ud: UserDefaults = .standard) -> Goals {
        var g = Goals.standard
        let w = ud.integer(forKey: AppStorageKeys.waterGoal)
        if w > 0 { g.waterML = w }
        let h = ud.double(forKey: AppStorageKeys.sleepGoalHours)
        if h > 0 { g.sleepHours = h }
        return g
    }

    @MainActor
    static func raw(_ ctx: ModelContext, fatigue: Int? = nil, now: Date = .now) -> Raw {
        let ud = UserDefaults.standard
        let hours = ud.double(forKey: "lastSleepHours")
        let quality = ud.integer(forKey: "lastSleepQuality")
        let at = ud.double(forKey: "lastSleepCheckDate")
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? [])
            .filter { !$0.isPending && !$0.isArchived }
            .map { h in HabitDay(plannedToday: h.isActive(on: now),
                                 doneToday: h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: now) }) }
        return Raw(
            sleepHours: hours > 0 ? hours : nil,
            sleepQuality: quality > 0 ? quality : nil,
            sleepRecordedAt: at > 0 ? Date(timeIntervalSince1970: at) : nil,
            moods: ((try? ctx.fetch(FetchDescriptor<MoodEntry>())) ?? []).map { ($0.date, $0.score) },
            waters: ((try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? []).map { ($0.date, $0.amountML) },
            habits: habits,
            fatigue: fatigue)
    }

    /// Score du jour avec ses entrees, ou nil s'il y a trop peu de donnees.
    @MainActor
    static func todayExplained(_ ctx: ModelContext, fatigue: Int? = nil) -> Explained? {
        let e = explain(raw(ctx, fatigue: fatigue), goals: goalsFromSettings())
        return e.isShown ? e : nil
    }

    /// Trop peu de criteres renseignes: rien plutot qu'un chiffre qui dirait
    /// n'importe quoi, dans le widget comme dans l'app.
    @MainActor
    static func today(_ ctx: ModelContext, fatigue: Int? = nil) -> Result? {
        todayExplained(ctx, fatigue: fatigue)?.result
    }
}
