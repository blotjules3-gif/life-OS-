import Foundation
import HealthKit

/// Pont vers Apple Santé. Alimente : compteur de pas, score de récupération (HRV + FC repos),
/// et durée de sommeil.
///
/// ⚠️ Pour que les lectures fonctionnent sur l'appareil, active la capability **HealthKit**
/// dans Xcode (cible LifeOS → Signing & Capabilities → + Capability → HealthKit).
/// Sans ça le code compile mais l'autorisation échoue à l'exécution (on retombe alors
/// sur la saisie manuelle, gérée par chaque module).
@Observable
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private(set) var authorized = false

    private init() {}

    // MARK: - Step cache (TTL 5 min — évite les requêtes HealthKit répétées)

    private var cachedSteps: Int = 0
    private var cachedStepsDate: Date = .distantPast

    /// Returns cached step count if fresh (< 5 min), otherwise re-queries HealthKit.
    func cachedStepsToday() async -> Int {
        if Date().timeIntervalSince(cachedStepsDate) < 300 { return cachedSteps }
        let fresh = await stepsToday()
        cachedSteps = fresh
        cachedStepsDate = .now
        return fresh
    }

    private var cachedCalories: Double = 0
    private var cachedCaloriesDate: Date = .distantPast

    func cachedActiveCaloriesToday() async -> Double {
        if Date().timeIntervalSince(cachedCaloriesDate) < 300 { return cachedCalories }
        let fresh = await activeCaloriesToday()
        cachedCalories = fresh
        cachedCaloriesDate = .now
        return fresh
    }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { set.insert(steps) }
        if let hr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { set.insert(hr) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { set.insert(hrv) }
        if let cal = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { set.insert(cal) }
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { set.insert(mass) }
        set.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        return set
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
            // Marqueur pour HealthAutoSync : le prompt a déjà été montré en contexte,
            // la sync silencieuse peut tourner sans déclencher de popup.
            UserDefaults.standard.set(true, forKey: "healthAuthRequested")
            return true
        } catch {
            return false
        }
    }

    /// Total de pas pour aujourd'hui.
    func stepsToday() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        return await Int(sumToday(type, unit: .count()))
    }

    /// Total de pas pour hier.
    func stepsYesterday() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let start = cal.startOfDay(for: yesterday)
        let end = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            store.execute(q)
        }
    }

    func restingHeartRate() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        return await mostRecent(type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func hrv() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        return await mostRecent(type, unit: .secondUnit(with: .milli))
    }

    func activeCaloriesToday() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        return await sumToday(type, unit: .kilocalorie())
    }

    /// Durée de sommeil de la nuit dernière (fenêtre 18h veille → 12h aujourd'hui), en heures.
    func sleepHoursLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let windowStart = startOfDay.addingTimeInterval(-6 * 3600)   // 18h la veille
        let windowEnd = startOfDay.addingTimeInterval(12 * 3600)     // midi aujourd'hui
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let seconds: Double = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let total = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: total)
            }
            store.execute(q)
        }
        return seconds > 0 ? seconds / 3600 : nil
    }

    /// Dernier poids enregistré dans Apple Santé.
    func latestBodyMass() async -> (kg: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.endDate))
            }
            store.execute(q)
        }
    }

    /// Number of workouts logged in Apple Santé over the last 7 days.
    func workoutsThisWeek() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let type = HKObjectType.workoutType()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.count ?? 0)
            }
            store.execute(q)
        }
    }

    // MARK: - Requêtes bas niveau

    private func sumToday(_ type: HKQuantityType, unit: HKUnit) async -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func mostRecent(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(q)
        }
    }
}
