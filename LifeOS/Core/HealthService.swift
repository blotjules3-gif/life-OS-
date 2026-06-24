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

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { set.insert(steps) }
        if let hr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { set.insert(hr) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { set.insert(hrv) }
        set.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        return set
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
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

    func restingHeartRate() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        return await mostRecent(type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func hrv() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        return await mostRecent(type, unit: .secondUnit(with: .milli))
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
