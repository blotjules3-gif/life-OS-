import Foundation

/// Statistiques de cycle calculees a partir des jours de flux enregistres.
///
/// Le defaut corrige: l'ecran Historique mesurait l'ecart entre deux ENTREES
/// consecutives avec flux, puis ne gardait que les ecarts de plus de 20 jours.
/// Or on enregistre son flux plusieurs jours de suite. Les cinq derniers
/// ecarts valaient donc 1 jour, tous rejetes, et "Durée moyenne" ne
/// s'affichait jamais pour quelqu'un qui remplit l'app tous les jours,
/// c'est a dire l'utilisatrice la plus assidue.
///
/// La bonne unite n'est pas le jour enregistre, c'est le REGLE: on regroupe
/// les jours qui se suivent, puis on mesure d'un debut de regles au suivant.
enum CycleStats {

    struct Summary: Equatable {
        /// Duree moyenne en jours, sur les cycles retenus.
        let averageDays: Double
        /// Nombre de cycles ayant servi au calcul, affiche pour que la
        /// moyenne soit lisible: une moyenne sur un cycle ne veut rien dire.
        let cycleCount: Int
        /// Ecart entre le cycle le plus court et le plus long.
        let shortestDays: Int
        let longestDays: Int

        var isRegular: Bool { longestDays - shortestDays <= 7 }
    }

    /// Un trou d'un jour ne coupe pas les regles en deux: on oublie de
    /// remplir. Deux jours de silence, en revanche, sont une interruption.
    static let maxGapWithinPeriod = 2

    /// Bornes de plausibilite. En dehors, c'est une saisie fausse ou une
    /// longue interruption d'usage, pas un cycle: la moyenne ne doit pas
    /// etre tiree par un "cycle" de six mois.
    static let plausibleRange = 15...60

    /// Nombre de cycles pris en compte, les plus recents.
    static let window = 6

    /// Premiers jours de chaque episode de regles, du plus ancien au plus
    /// recent.
    static func periodStarts(flowDays: [Date], calendar: Calendar = .current) -> [Date] {
        let days = Set(flowDays.map { calendar.startOfDay(for: $0) }).sorted()
        guard var previous = days.first else { return [] }
        var starts: [Date] = [previous]
        for day in days.dropFirst() {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap > maxGapWithinPeriod { starts.append(day) }
            previous = day
        }
        return starts
    }

    /// Duree moyenne du cycle, ou `nil` s'il n'y a pas encore de quoi la dire.
    static func summary(flowDays: [Date], calendar: Calendar = .current) -> Summary? {
        summary(starts: periodStarts(flowDays: flowDays, calendar: calendar), calendar: calendar)
    }

    /// Meme calcul a partir de debuts de regles deja connus (episodes avec
    /// bornes explicites): les 6 derniers cycles plausibles.
    static func summary(starts: [Date], calendar: Calendar = .current) -> Summary? {
        summary(lengths: cycleLengths(starts: starts, calendar: calendar).map(\.days), limit: window)
    }

    /// Resume d'une liste de durees (les `limit` dernieres, toutes si nil).
    static func summary(lengths: [Int], limit: Int? = nil) -> Summary? {
        let recent = limit.map { Array(lengths.suffix($0)) } ?? lengths
        guard let low = recent.min(), let high = recent.max() else { return nil }
        return Summary(
            averageDays: Double(recent.reduce(0, +)) / Double(recent.count),
            cycleCount: recent.count,
            shortestDays: low,
            longestDays: high
        )
    }

    /// Cycles mesures d'un debut au suivant, seulement les plausibles.
    static func cycleLengths(starts: [Date], calendar: Calendar = .current) -> [(start: Date, days: Int)] {
        let sorted = starts.map { calendar.startOfDay(for: $0) }.sorted()
        var out: [(start: Date, days: Int)] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            // En jours de calendrier, jamais en secondes: aux changements
            // d'heure un cycle de 28 jours ne fait pas 28 x 86400 secondes.
            let d = calendar.dateComponents([.day], from: a, to: b).day ?? 0
            if plausibleRange.contains(d) { out.append((a, d)) }
        }
        return out
    }
}


// MARK: - Regles avec bornes explicites

/// Un jour vu par le calcul des regles.
struct CycleDayMark: Equatable {
    var date: Date
    var flow: Int
    var isStart: Bool = false
    var isEnd: Bool = false

    /// Un jour marque debut ou fin compte comme jour de regles meme sans flux.
    var isBleeding: Bool { flow > 0 || isStart || isEnd }
}

/// Un episode de regles, du premier au dernier jour.
struct CycleEpisode: Equatable {
    let start: Date
    let end: Date
    /// Termine: fin marquee, regles suivantes deja la, ou plus de flux note
    /// depuis plus de `maxGapWithinPeriod` jours. Seuls les episodes termines
    /// entrent dans la duree moyenne des regles.
    let isComplete: Bool
    let explicitEnd: Bool

    func days(calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }
}

extension CycleStats {

    /// Regroupe les jours en regles. Regles du calcul:
    /// - un jour marque "premier jour" ouvre toujours de nouvelles regles;
    /// - un jour marque "dernier jour" les ferme;
    /// - sinon un trou de plus de 2 jours separe deux episodes;
    /// - du flux non marque moins de 15 jours apres le debut des regles
    ///   precedentes (ou juste apres une fin marquee) est un saignement
    ///   intermediaire, pas de nouvelles regles: il ne deplace pas le cycle.
    static func episodes(_ marks: [CycleDayMark], today: Date = .now,
                         calendar: Calendar = .current) -> [CycleEpisode] {
        // Un jour = une marque (deux entrees le meme jour se fusionnent).
        var byDay: [Date: CycleDayMark] = [:]
        for m in marks where m.isBleeding {
            let d = calendar.startOfDay(for: m.date)
            var cur = byDay[d] ?? CycleDayMark(date: d, flow: 0)
            cur.flow = max(cur.flow, m.flow)
            cur.isStart = cur.isStart || m.isStart
            cur.isEnd = cur.isEnd || m.isEnd
            byDay[d] = cur
        }
        let days = byDay.keys.sorted()
        func gap(_ a: Date, _ b: Date) -> Int { calendar.dateComponents([.day], from: a, to: b).day ?? 0 }

        var raw: [(start: Date, end: Date, closed: Bool)] = []
        for day in days {
            let m = byDay[day]!
            if var cur = raw.last {
                let extendsCurrent = !cur.closed && !m.isStart && gap(cur.end, day) <= maxGapWithinPeriod
                if extendsCurrent {
                    cur.end = day
                    cur.closed = m.isEnd
                    raw[raw.count - 1] = cur
                    continue
                }
                if !m.isStart && gap(cur.start, day) < plausibleRange.lowerBound {
                    continue // saignement intermediaire
                }
            }
            raw.append((day, day, m.isEnd))
        }
        let todayStart = calendar.startOfDay(for: today)
        return raw.enumerated().map { i, r in
            let finished = r.closed || i < raw.count - 1 || gap(r.end, todayStart) > maxGapWithinPeriod
            return CycleEpisode(start: r.start, end: r.end, isComplete: finished, explicitEnd: r.closed)
        }
    }

    /// Duree moyenne des regles sur les episodes termines (6 derniers),
    /// `nil` sous 2 episodes: une seule valeur n'est pas une moyenne.
    static func averagePeriodLength(_ episodes: [CycleEpisode], calendar: Calendar = .current) -> Double? {
        let lengths = episodes.filter(\.isComplete).map { $0.days(calendar: calendar) }
            .filter { (1...15).contains($0) }.suffix(window)
        guard lengths.count >= 2 else { return nil }
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }
}

// MARK: - Previsions

/// Prevision unique, lue par le suivi, le calendrier, les stats, les rappels
/// et le coach. Avant: le suivi tournait sur la duree reglee a la main
/// pendant que l'historique affichait une autre moyenne.
struct CyclePrediction: Equatable {
    enum Basis: Equatable {
        case history(cycles: Int)   // moyenne des cycles notes
        case setting                // duree reglee, moins de 2 cycles notes
    }

    /// Fourchette par defaut tant que l'historique ne donne pas la sienne.
    static let defaultSpread = 3
    static let minCyclesForHistory = 2

    let basis: Basis
    let lengthDays: Int
    let shortestDays: Int
    let longestDays: Int
    let periodLengthDays: Int
    let periodLengthFromHistory: Bool
    let lastStart: Date?
    let nextStart: Date?
    let earliestStart: Date?
    let latestStart: Date?
    /// Estimation, jamais une ovulation confirmee.
    let ovulationEstimate: Date?
    let fertileStart: Date?
    let fertileEnd: Date?

    var isFromHistory: Bool { if case .history = basis { return true } else { return false } }

    static func make(starts: [Date], periodAverage: Double?, lastStart: Date?,
                     setLength: Int, setPeriodLength: Int, calendar: Calendar = .current) -> CyclePrediction {
        let hist = CycleStats.summary(starts: starts, calendar: calendar)
        let basis: Basis
        let length: Int, low: Int, high: Int
        if let h = hist, h.cycleCount >= minCyclesForHistory {
            basis = .history(cycles: h.cycleCount)
            length = Int(h.averageDays.rounded())
            low = h.shortestDays; high = h.longestDays
        } else {
            basis = .setting
            length = min(max(setLength, 15), 60)
            low = length - defaultSpread; high = length + defaultSpread
        }
        let periodLen = periodAverage.map { Int($0.rounded()) } ?? min(max(setPeriodLength, 1), 10)

        func at(_ offset: Int) -> Date? {
            lastStart.flatMap { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: $0)) }
        }
        // Jour 1 = debut des regles, donc le jour N est a N - 1 jours.
        let ovLow = CycleMath.ovulationDay(length: low), ovHigh = CycleMath.ovulationDay(length: high)
        return CyclePrediction(
            basis: basis, lengthDays: length, shortestDays: low, longestDays: high,
            periodLengthDays: periodLen, periodLengthFromHistory: periodAverage != nil,
            lastStart: lastStart.map { calendar.startOfDay(for: $0) },
            nextStart: at(length), earliestStart: at(low), latestStart: at(high),
            ovulationEstimate: at(CycleMath.ovulationDay(length: length) - 1),
            // Fenetre fertile: 5 jours avant l'ovulation estimee et le jour
            // d'apres, elargie par la fourchette des durees.
            fertileStart: at(ovLow - 1 - 5), fertileEnd: at(ovHigh - 1 + 1))
    }

    /// Jours de regles et de fenetre fertile PREVUS (jamais des jours notes)
    /// pour les `cycles` prochains cycles, a partir d'aujourd'hui.
    func predictedDays(cycles: Int = 3, today: Date = .now,
                       calendar: Calendar = .current) -> (period: Set<Date>, fertile: Set<Date>) {
        guard let last = lastStart else { return ([], []) }
        let t = calendar.startOfDay(for: today)
        var period: Set<Date> = [], fertile: Set<Date> = []
        let ovLow = CycleMath.ovulationDay(length: shortestDays), ovHigh = CycleMath.ovulationDay(length: longestDays)
        for k in 0..<max(cycles, 0) {
            guard let base = calendar.date(byAdding: .day, value: lengthDays * k, to: last),
                  let next = calendar.date(byAdding: .day, value: lengthDays, to: base) else { continue }
            for i in 0..<periodLengthDays {
                if let d = calendar.date(byAdding: .day, value: i, to: next), d >= t { period.insert(d) }
            }
            for i in (ovLow - 6)...(ovHigh) {
                if let d = calendar.date(byAdding: .day, value: i, to: base), d >= t { fertile.insert(d) }
            }
        }
        return (period, fertile.subtracting(period))
    }
}

// MARK: - Analyse complete

enum CycleRange: String, CaseIterable, Identifiable {
    case threeMonths, sixMonths, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .threeMonths: return "3 mois"
        case .sixMonths:   return "6 mois"
        case .year:        return "12 mois"
        case .all:         return "Tout"
        }
    }
    func start(today: Date = .now, calendar: Calendar = .current) -> Date? {
        let months: Int
        switch self {
        case .threeMonths: months = 3
        case .sixMonths:   months = 6
        case .year:        months = 12
        case .all:         return nil
        }
        return calendar.date(byAdding: .month, value: -months, to: calendar.startOfDay(for: today))
    }
}

struct CycleRecord: Equatable {
    let start: Date
    let days: Int
    let periodDays: Int?
}

struct CycleAnalysis: Equatable {
    let episodes: [CycleEpisode]
    let prediction: CyclePrediction
    let snapshot: CycleMath.Snapshot?
    let allCycles: [CycleRecord]
    let rangeCycles: [CycleRecord]
    let rangeSummary: CycleStats.Summary?
    let rangePeriodAverage: Double?
    /// (duree, nombre de cycles) sur la periode choisie.
    let distribution: [CycleLengthBin]
}

struct CycleLengthBin: Equatable, Identifiable {
    let days: Int
    let count: Int
    var id: Int { days }
}

enum CycleAnalytics {

    /// LE calcul du cycle. Suivi, calendrier, stats, rapport, rappels et
    /// coach passent tous par ici, avec les memes entrees.
    static func analyze(entries: [CycleEntrySnapshot], manualStart: Date?, setLength: Int,
                        setPeriodLength: Int, today: Date = .now, range: CycleRange = .all,
                        calendar: Calendar = .current) -> CycleAnalysis {
        let eps = CycleStats.episodes(entries.map(\.mark), today: today, calendar: calendar)
        let starts = eps.map(\.start)
        let last = CycleMath.resolvedStart(manual: manualStart, latestLogged: starts.last, calendar: calendar)
        let prediction = CyclePrediction.make(starts: starts,
                                              periodAverage: CycleStats.averagePeriodLength(eps, calendar: calendar),
                                              lastStart: last, setLength: setLength,
                                              setPeriodLength: setPeriodLength, calendar: calendar)
        let snap = last.map { CycleMath.snapshot(start: $0, today: today, length: prediction.lengthDays, calendar: calendar) }

        let periodByStart = Dictionary(eps.map { ($0.start, $0) }, uniquingKeysWith: { a, _ in a })
        let all = CycleStats.cycleLengths(starts: starts, calendar: calendar).map { c in
            CycleRecord(start: c.start, days: c.days,
                        periodDays: periodByStart[c.start].flatMap { $0.isComplete ? $0.days(calendar: calendar) : nil })
        }
        let from = range.start(today: today, calendar: calendar)
        let inRange = all.filter { from == nil || $0.start >= from! }
        let rangeEpisodes = eps.filter { from == nil || $0.start >= from! }
        let bins = Dictionary(grouping: inRange, by: \.days).map { CycleLengthBin(days: $0.key, count: $0.value.count) }
            .sorted { $0.days < $1.days }
        return CycleAnalysis(episodes: eps, prediction: prediction, snapshot: snap,
                             allCycles: all, rangeCycles: inRange,
                             rangeSummary: CycleStats.summary(lengths: inRange.map(\.days)),
                             rangePeriodAverage: CycleStats.averagePeriodLength(rangeEpisodes, calendar: calendar),
                             distribution: bins)
    }
}

// MARK: - Symptomes: recherche, tendances, associations

struct CycleAssociation: Equatable {
    let symptom: String
    let phase: CyclePhase
    let count: Int
    let total: Int
}

struct CycleTrendPoint: Equatable, Identifiable {
    let month: Date
    let symptom: String
    let days: Int
    var id: String { "\(symptom)-\(month.timeIntervalSince1970)" }
}

enum CycleInsights {

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Recherche sans accents ni majuscules dans symptomes, note, flux,
    /// humeur et date ecrite en toutes lettres ("mars", "12 mars").
    static func matches(_ e: CycleEntrySnapshot, query: String, calendar: Calendar = .current) -> Bool {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return true }
        let df = DateFormatter()
        df.calendar = calendar; df.timeZone = calendar.timeZone
        df.locale = Locale(identifier: "fr_FR"); df.dateFormat = "d MMMM yyyy"
        var hay = e.symptoms + [e.note, df.string(from: e.date), CycleCatalog.moodLabel(e.mood)]
        if e.flow > 0 { hay += ["flux " + CycleCatalog.flowLabel(e.flow), "règles"] }
        if e.isStart { hay.append("début des règles") }
        if e.isEnd { hay.append("fin des règles") }
        return hay.contains { fold($0).contains(q) }
    }

    /// Nombre de jours ou chaque symptome est note (un jour compte une fois).
    static func symptomCounts(_ entries: [CycleEntrySnapshot], calendar: Calendar = .current) -> [(String, Int)] {
        var days: [String: Set<Date>] = [:]
        for e in entries {
            for s in e.symptoms { days[s, default: []].insert(calendar.startOfDay(for: e.date)) }
        }
        return days.map { ($0.key, $0.value.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }

    /// Phase d'un jour passe, mesuree avec le cycle REEL quand ses regles
    /// suivantes sont notees, sinon avec la duree des previsions. Au dela de
    /// la duree (retard), la phase est inconnue: on ne l'invente pas.
    static func phase(for date: Date, starts: [Date], fallbackLength: Int,
                      calendar: Calendar = .current) -> CyclePhase? {
        let day = calendar.startOfDay(for: date)
        let sorted = starts.map { calendar.startOfDay(for: $0) }.sorted()
        guard let idx = sorted.lastIndex(where: { $0 <= day }) else { return nil }
        let start = sorted[idx]
        var length = fallbackLength
        if idx + 1 < sorted.count {
            let real = calendar.dateComponents([.day], from: start, to: sorted[idx + 1]).day ?? 0
            if CycleStats.plausibleRange.contains(real) { length = real }
        }
        let n = (calendar.dateComponents([.day], from: start, to: day).day ?? 0) + 1
        guard n <= length else { return nil }
        return CycleMath.phase(day: n, length: length)
    }

    /// Phase ou chaque symptome est le plus souvent note. C'est une
    /// association observee dans les entrees, pas une cause: l'ecran le dit.
    /// Sous `minCount` jours, rien n'est affirme.
    static func phaseAssociations(_ entries: [CycleEntrySnapshot], starts: [Date], fallbackLength: Int,
                                  minCount: Int = 3, calendar: Calendar = .current) -> [CycleAssociation] {
        var perSymptom: [String: [Date: CyclePhase]] = [:]
        for e in entries {
            guard let p = phase(for: e.date, starts: starts, fallbackLength: fallbackLength, calendar: calendar) else { continue }
            let d = calendar.startOfDay(for: e.date)
            for s in e.symptoms { perSymptom[s, default: [:]][d] = p }
        }
        var out: [CycleAssociation] = []
        for (s, days) in perSymptom where days.count >= minCount {
            let counts = Dictionary(grouping: days.values, by: { $0 }).mapValues(\.count)
            guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue })
            else { continue }
            out.append(CycleAssociation(symptom: s, phase: best.key, count: best.value, total: days.count))
        }
        return out.sorted { $0.total != $1.total ? $0.total > $1.total : $0.symptom < $1.symptom }
    }

    /// Jours notes par mois pour les symptomes donnes, mois vides compris
    /// (sinon la courbe sauterait d'un mois a l'autre comme s'il n'y avait
    /// pas eu de mois sans symptome).
    static func monthlyTrend(_ entries: [CycleEntrySnapshot], symptoms: [String], from: Date, to: Date,
                             calendar: Calendar = .current) -> [CycleTrendPoint] {
        guard let first = calendar.dateInterval(of: .month, for: from)?.start,
              let last = calendar.dateInterval(of: .month, for: to)?.start, first <= last else { return [] }
        var months: [Date] = []
        var m = first
        while m <= last, months.count < 120 {
            months.append(m)
            guard let n = calendar.date(byAdding: .month, value: 1, to: m) else { break }
            m = n
        }
        var days: [String: [Date: Set<Date>]] = [:]
        for e in entries {
            guard let month = calendar.dateInterval(of: .month, for: e.date)?.start else { continue }
            for s in e.symptoms where symptoms.contains(s) {
                days[s, default: [:]][month, default: []].insert(calendar.startOfDay(for: e.date))
            }
        }
        return symptoms.flatMap { s in
            months.map { CycleTrendPoint(month: $0, symptom: s, days: days[s]?[$0]?.count ?? 0) }
        }
    }
}
