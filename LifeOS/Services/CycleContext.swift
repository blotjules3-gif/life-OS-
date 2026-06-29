import Foundation
import Combine
import UserNotifications

enum CyclePhase: String {
    case menstrual   // jours 1–5
    case follicular  // jours 6–13
    case ovulatory   // jours 14–16
    case luteal      // jours 17–fin

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

    func refresh() {
        guard let last = lastPeriodDate else { return }
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.startOfDay(for: last)
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
        let len = avgCycleLength
        let day = (elapsed % len) + 1

        dayOfCycle = day
        daysUntilPeriod = max(0, len - elapsed % len)

        switch day {
        case 1...5:    currentPhase = .menstrual
        case 6...13:   currentPhase = .follicular
        case 14...16:  currentPhase = .ovulatory
        default:       currentPhase = .luteal
        }

        isOvulationWindow = (14...16).contains(day)
        isPMSWindow = day >= (len - 7)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
