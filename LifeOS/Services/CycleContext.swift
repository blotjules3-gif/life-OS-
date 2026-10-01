import Foundation
import Combine
import SwiftData
import UserNotifications

enum CyclePhase: String {
    case menstrual   // jours 1 a 5
    case follicular  // jusqu'a la veille de la fenetre d'ovulation
    case ovulatory   // ovulation (duree - 14) ± 1 jour, voir CycleMath
    case luteal      // apres, jusqu'aux regles

    var label: String {
        switch self {
        case .menstrual:  return "Menstruelle"
        case .follicular: return "Folliculaire"
        case .ovulatory:  return "Ovulation"
        case .luteal:     return "Lutéale"
        }
    }

    var colorHex: Int {
        switch self {
        case .menstrual:  return 0xC0392B
        case .follicular: return 0x4CC38A
        case .ovulatory:  return 0xE0A23C
        case .luteal:     return 0x9B6CF1
        }
    }

    var energyDescription: String {
        switch self {
        case .menstrual:  return "Énergie basse : privilégie le repos"
        case .follicular: return "Énergie montante : idéal pour de nouveaux défis"
        case .ovulatory:  return "Énergie au pic : profites-en au maximum"
        case .luteal:     return "Énergie déclinante : écoute ton corps"
        }
    }

    var fitnessAdvice: String {
        switch self {
        case .menstrual:  return "Yoga, marche, natation douce"
        case .follicular: return "HIIT, musculation, nouveaux PRs"
        case .ovulatory:  return "Séances intenses, compétitions"
        case .luteal:     return "Force modérée, Pilates, pas de HIIT"
        }
    }

    var keyNutrients: [String] {
        switch self {
        case .menstrual:  return ["Fer", "Oméga-3", "Magnésium", "Vitamine C"]
        case .follicular: return ["Légumes crucifères", "Protéines", "Zinc"]
        case .ovulatory:  return ["Vitamine E", "Hydratation", "Antioxydants"]
        case .luteal:     return ["Magnésium", "Calcium", "Vitamine B6", "Glucides complexes"]
        }
    }

    // Offset calorique recommandé par rapport à la base
    var calorieOffset: Int {
        switch self {
        case .luteal:    return 200
        default:         return 0
        }
    }
}

@MainActor
final class CycleContext: ObservableObject {
    static let shared = CycleContext()

    @Published private(set) var currentPhase: CyclePhase = .follicular
    @Published private(set) var dayOfCycle: Int = 1
    @Published private(set) var daysUntilPeriod: Int = 14
    @Published private(set) var isOvulationWindow: Bool = false
    @Published private(set) var isPMSWindow: Bool = false
    /// Prevision commune (suivi, calendrier, stats, coach). Nil tant
    /// qu'aucun debut n'est connu.
    @Published private(set) var prediction: CyclePrediction?

    var suggestedCalorieOffset: Int { currentPhase.calorieOffset }
    var keyNutrients: [String] { currentPhase.keyNutrients }

    private var ud: UserDefaults { .standard }

    /// Debut du cycle en cours: le debut CALCULE (regles notees + date
    /// declaree). Ecrire ici revient a declarer une date.
    var lastPeriodDate: Date? {
        get {
            let ts = ud.double(forKey: AppStorageKeys.cycleStartDate)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            ud.set(newValue?.timeIntervalSince1970 ?? 0, forKey: CycleKeys.manualStart)
            refresh()
        }
    }

    /// Duree REGLEE (repli quand moins de 2 cycles sont notes).
    var avgCycleLength: Int {
        get { ud.integer(forKey: AppStorageKeys.cycleLengthDays).nonZero ?? 28 }
        set {
            ud.set(newValue, forKey: AppStorageKeys.cycleLengthDays)
            refresh()
        }
    }

    /// Duree reellement utilisee pour les previsions.
    var predictionLength: Int { prediction?.lengthDays ?? avgCycleLength }

    private init() { refresh() }

    /// Jours de retard sur les regles attendues (0 = pas en retard).
    @Published private(set) var lateDays: Int = 0
    /// Vrai quand les regles attendues ne sont pas encore notees: on ne
    /// predit plus un cycle suivant invente, on le dit.
    @Published private(set) var isLate: Bool = false

    /// Ligne pour le coach, avec la meme prevision que l'ecran.
    var coachLine: String {
        guard prediction?.lastStart != nil else { return "" }
        let basis: String
        switch prediction?.basis {
        case .history(let n)?: basis = "moyenne de \(n) cycles notés"
        default:               basis = "durée réglée"
        }
        let state = isLate ? "règles attendues depuis \(lateDays) j" : "règles dans \(daysUntilPeriod) j"
        return "Phase cycle: \(currentPhase.label) (J\(dayOfCycle), \(state), prévisions sur \(predictionLength) j, \(basis))"
    }

    /// Recalcule tout. `entries` vient des ecrans (@Query); sans elles, on lit
    /// la base partagee si elle contient bien les entrees de cycle.
    func refresh(entries: [CycleEntrySnapshot]? = nil, now: Date = .now) {
        let list = entries ?? fetchEntries()
        let manual = CycleMath.adoptManualStart(defaults: ud)
        let setPeriod = ud.integer(forKey: CycleKeys.periodLength).nonZero ?? 5
        let analysis = CycleAnalytics.analyze(entries: list, manualStart: manual, setLength: avgCycleLength,
                                              setPeriodLength: setPeriod, today: now)
        let p = analysis.prediction
        prediction = p.lastStart == nil ? nil : p

        // Le debut calcule et la duree utilisee sont ecrits pour LifeBrain et
        // l'onboarding, qui lisent les reglages et non la base.
        let startTS = p.lastStart?.timeIntervalSince1970 ?? 0
        ud.set(startTS, forKey: AppStorageKeys.cycleStartDate)
        ud.set(startTS, forKey: CycleKeys.startWritten)
        ud.set(p.lastStart == nil ? 0 : p.lengthDays, forKey: CycleKeys.predictionLength)

        let center = UNUserNotificationCenter.current()
        guard let snap = analysis.snapshot else {
            center.removePendingNotificationRequests(withIdentifiers: CycleReminderKind.allCases.map(\.notificationID))
            return
        }
        dayOfCycle = snap.dayOfCycle
        daysUntilPeriod = snap.daysUntilPeriod
        lateDays = snap.lateDays
        isLate = snap.isLate
        currentPhase = snap.phase
        isOvulationWindow = snap.isOvulationWindow
        isPMSWindow = snap.isPMSWindow

        // Rappels: tout est retire puis repose selon le plan (mode, rappels
        // coupes, retard). En retard, le plan est vide: les rappels du cycle
        // suivant seraient calcules sur un debut qu'on ne connait pas encore.
        center.removePendingNotificationRequests(withIdentifiers: CycleReminderKind.allCases.map(\.notificationID))
        let plan = CycleReminders.plan(snapshot: snap, prediction: p, mode: CycleMode.stored(ud),
                                       disabled: CycleReminderKind.disabled(ud), now: now)
        for r in plan {
            NotificationManager.shared.schedule(id: r.kind.notificationID, title: r.title, body: r.body, at: r.date)
        }
    }

    private func fetchEntries() -> [CycleEntrySnapshot] {
        guard let ctx = SharedModelContextProvider.shared.context,
              // Un container de test sans CycleEntry planterait au fetch.
              ctx.container.schema.entities.contains(where: { $0.name == "CycleEntry" }),
              let rows = try? ctx.fetch(FetchDescriptor<CycleEntry>()) else { return [] }
        return rows.map(\.snapshot)
    }
}

/// Rappels du cycle, calcules sans effet de bord.
enum CycleReminders {
    struct Planned: Equatable {
        let kind: CycleReminderKind
        let title: String
        let body: String
        let date: Date
    }

    static func plan(snapshot: CycleMath.Snapshot, prediction: CyclePrediction, mode: CycleMode,
                     disabled: Set<CycleReminderKind>, now: Date = .now,
                     calendar: Calendar = .current) -> [Planned] {
        guard !snapshot.isLate else { return [] }
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int) -> Date? {
            guard let d = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d)
        }
        let left = snapshot.daysUntilPeriod
        var out: [Planned] = []
        if !disabled.contains(.period), left - 3 > 0, let d = day(left - 3, hour: 9) {
            out.append(Planned(kind: .period, title: "Règles dans 3 jours",
                               body: "Tes prochaines règles sont estimées dans 3 jours.", date: d))
        }
        if !disabled.contains(.pms), left - 7 > 0, let d = day(left - 7, hour: 9) {
            out.append(Planned(kind: .pms, title: "Une semaine avant tes règles",
                               body: "Fenêtre prémenstruelle estimée. Note tes symptômes si tu en as.", date: d))
        }
        if CycleReminderKind.ovulation.isAvailable(in: mode), !disabled.contains(.ovulation) {
            let target: Date? = mode == .conceiving ? prediction.fertileStart : prediction.ovulationEstimate.flatMap {
                calendar.date(byAdding: .day, value: -1, to: $0)
            }
            if let t = target, t > today, let d = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: t) {
                out.append(mode == .conceiving
                    ? Planned(kind: .ovulation, title: "Fenêtre fertile estimée",
                              body: "Début de ta fenêtre fertile estimée d'après tes cycles. Estimation, pas une ovulation confirmée.", date: d)
                    : Planned(kind: .ovulation, title: "Phase d'ovulation estimée",
                              body: "Énergie souvent au plus haut : idéal pour tes séances intenses.", date: d))
            }
        }
        return out
    }
}

/// Calculs du cycle, purs et testables.
enum CycleMath {

    struct Snapshot: Equatable {
        let dayOfCycle: Int
        let daysUntilPeriod: Int
        let lateDays: Int
        let isLate: Bool
        let phase: CyclePhase
        let isOvulationWindow: Bool
        let isPMSWindow: Bool
    }

    /// La phase luteale dure ~14 jours quelle que soit la duree du cycle:
    /// c'est la folliculaire qui s'allonge. Ovulation = duree - 14, pas 14.
    static func ovulationDay(length: Int) -> Int { max(6, length - 14) }

    static func phase(day: Int, length: Int) -> CyclePhase {
        let ov = ovulationDay(length: length)
        if day <= 5 { return .menstrual }
        if day < ov - 1 { return .follicular }
        if day <= ov + 1 { return .ovulatory }
        return .luteal
    }

    /// Avant, `elapsed % length` repartait a "Jour 1" tout seul a la fin du
    /// cycle: des regles en retard ou jamais notees devenaient un cycle
    /// invente. Passe la duree prevue, on dit le retard.
    static func snapshot(start: Date, today: Date, length: Int, calendar: Calendar = .current) -> Snapshot {
        let len = max(1, length)
        let s = calendar.startOfDay(for: start)
        let t = calendar.startOfDay(for: today)
        let elapsed = max(0, calendar.dateComponents([.day], from: s, to: t).day ?? 0)
        let day = elapsed + 1
        if elapsed >= len {
            return Snapshot(dayOfCycle: day, daysUntilPeriod: 0, lateDays: elapsed - len,
                            isLate: true, phase: .luteal, isOvulationWindow: false, isPMSWindow: true)
        }
        let ov = ovulationDay(length: len)
        return Snapshot(dayOfCycle: day,
                        daysUntilPeriod: len - elapsed,
                        lateDays: 0,
                        isLate: false,
                        phase: phase(day: day, length: len),
                        isOvulationWindow: (ov - 1...ov + 1).contains(day),
                        isPMSWindow: day >= len - 7)
    }

    /// Debut de cycle a retenir apres un enregistrement de flux. Avant, le
    /// debut n'etait pose que s'il n'existait pas: les regles suivantes ne
    /// le deplacaient jamais. On prend le debut des dernieres regles notees
    /// s'il tombe assez loin du debut connu pour etre un NOUVEAU cycle
    /// (sinon ce sont les memes regles, notees un jour apres).
    static func updatedStart(stored: Date?, flowDays: [Date], calendar: Calendar = .current) -> Date? {
        guard let latest = CycleStats.periodStarts(flowDays: flowDays, calendar: calendar).last else { return stored }
        guard let stored else { return latest }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: stored), to: latest).day ?? 0
        return gap >= CycleStats.plausibleRange.lowerBound ? latest : stored
    }

    /// Debut du cycle en cours a partir de la date declaree et des regles
    /// notees. A moins de 15 jours l'une de l'autre, ce sont les memes
    /// regles: on garde la plus ancienne. Sinon la plus recente gagne (des
    /// regles notees apres une date declaree, ou une date declaree sans
    /// flux note). Supprimer des regles ramene donc le debut en arriere,
    /// ce que l'ancien `updatedStart` ne savait pas faire.
    static func resolvedStart(manual: Date?, latestLogged: Date?, calendar: Calendar = .current) -> Date? {
        switch (manual.map { calendar.startOfDay(for: $0) }, latestLogged.map { calendar.startOfDay(for: $0) }) {
        case (nil, nil): return nil
        case (let m?, nil): return m
        case (nil, let l?): return l
        case (let m?, let l?):
            let gap = calendar.dateComponents([.day], from: l, to: m).day ?? 0
            if gap >= CycleStats.plausibleRange.lowerBound { return m }
            if gap <= -CycleStats.plausibleRange.lowerBound { return l }
            return min(m, l)
        }
    }

    /// Date declaree a utiliser. Si `cycleStartDate` a ete ecrite par
    /// quelqu'un d'autre que CycleContext (onboarding, ancienne version), on
    /// l'adopte comme declaration. Migration en une fois: aucune declaration
    /// stockee + un debut existant = ce debut.
    static func adoptManualStart(defaults d: UserDefaults) -> Date? {
        let current = d.double(forKey: AppStorageKeys.cycleStartDate)
        let written = d.double(forKey: CycleKeys.startWritten)
        if current > 0 && abs(current - written) > 1 {
            d.set(current, forKey: CycleKeys.manualStart)
        }
        let m = d.double(forKey: CycleKeys.manualStart)
        return m > 0 ? Date(timeIntervalSince1970: m) : nil
    }

    /// Phase du jour lue dans les reglages, avec la duree des previsions
    /// (celle du suivi), pour LifeBrain qui n'a pas acces aux ecrans.
    static func storedSnapshot(defaults d: UserDefaults = .standard, now: Date = .now,
                               calendar: Calendar = .current) -> Snapshot? {
        let ts = d.double(forKey: AppStorageKeys.cycleStartDate)
        guard ts > 0 else { return nil }
        let pl = d.integer(forKey: CycleKeys.predictionLength)
        let set = d.integer(forKey: AppStorageKeys.cycleLengthDays)
        let len = pl > 0 ? pl : (set > 0 ? set : 28)
        return snapshot(start: Date(timeIntervalSince1970: ts), today: now, length: len, calendar: calendar)
    }

    /// Symptomes des 3 derniers jours de calendrier (aujourd'hui compris).
    /// Avant: les 3 dernieres ENTREES, meme vieilles de plusieurs mois.
    static func recentSymptomCounts(_ entries: [(date: Date, symptoms: [String])],
                                    now: Date = .now, days: Int = 3,
                                    calendar: Calendar = .current) -> [(String, Int)] {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let to = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        var counts: [String: Int] = [:]
        for e in entries where e.date >= from && e.date < to {
            for s in e.symptoms { counts[s, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
