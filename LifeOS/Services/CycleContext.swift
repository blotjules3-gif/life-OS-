import Foundation
import Combine
import UserNotifications

enum CyclePhase: String {
    case menstrual   // jours 1–5
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
        case .menstrual:  return "Énergie basse — privilégie le repos"
        case .follicular: return "Énergie montante — idéal pour de nouveaux défis"
        case .ovulatory:  return "Énergie au pic — profites-en au maximum"
        case .luteal:     return "Énergie déclinante — écoute ton corps"
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

    var suggestedCalorieOffset: Int { currentPhase.calorieOffset }
    var keyNutrients: [String] { currentPhase.keyNutrients }

    // Clés alignées avec CycleTrackerView (@AppStorage)
    private let startTSKey     = "cycleStartDate"    // Double timestamp
    private let cycleLengthKey = "cycleLengthDays"   // Int

    var lastPeriodDate: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: startTSKey)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: startTSKey)
            refresh()
        }
    }

    var avgCycleLength: Int {
        get { UserDefaults.standard.integer(forKey: cycleLengthKey).nonZero ?? 28 }
        set {
            UserDefaults.standard.set(newValue, forKey: cycleLengthKey)
            refresh()
        }
    }

    private init() { refresh() }

    /// Jours de retard sur les regles attendues (0 = pas en retard).
    @Published private(set) var lateDays: Int = 0
    /// Vrai quand les regles attendues ne sont pas encore notees: on ne
    /// predit plus un cycle suivant invente, on le dit.
    @Published private(set) var isLate: Bool = false

    func refresh() {
        guard let last = lastPeriodDate else { return }
        let len = avgCycleLength
        let snap = CycleMath.snapshot(start: last, today: .now, length: len)

        dayOfCycle = snap.dayOfCycle
        daysUntilPeriod = snap.daysUntilPeriod
        lateDays = snap.lateDays
        isLate = snap.isLate
        currentPhase = snap.phase
        isOvulationWindow = snap.isOvulationWindow
        isPMSWindow = snap.isPMSWindow

        let center = UNUserNotificationCenter.current()
        let ids = ["lifeos.cycle.period_warning", "lifeos.cycle.ovulation", "lifeos.cycle.pms"]
        guard !snap.isLate else {
            // En retard: les rappels "regles dans 3 jours" du cycle suivant
            // seraient calcules sur un debut qu'on ne connait pas encore.
            center.removePendingNotificationRequests(withIdentifiers: ids)
            return
        }
        NotificationManager.shared.scheduleCycleNotifications(lastPeriodDate: last, cycleDays: len)
        // Le gestionnaire place l'ovulation au jour 14 quelle que soit la
        // duree: on la replace au bon jour (14 jours avant les regles).
        center.removePendingNotificationRequests(withIdentifiers: ["lifeos.cycle.ovulation"])
        let cal = Calendar.current
        let ov = CycleMath.ovulationDay(length: len)
        let inDays = snap.dayOfCycle < ov ? ov - snap.dayOfCycle : len - snap.dayOfCycle + ov
        if let day = cal.date(byAdding: .day, value: inDays, to: cal.startOfDay(for: .now)) {
            NotificationManager.shared.schedule(
                id: "lifeos.cycle.ovulation",
                title: "Fenêtre d'ovulation",
                body: "Énergie au pic — idéal pour tes séances les plus intenses.",
                at: cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day)
        }
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
