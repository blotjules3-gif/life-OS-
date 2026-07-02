import Foundation
import SwiftData

/// Remplit automatiquement sommeil et poids depuis Apple Santé à chaque retour
/// au premier plan — zéro saisie manuelle quand les données existent déjà.
enum HealthAutoSync {

    @MainActor
    static func syncNow(_ ctx: ModelContext) async {
        // Jamais de prompt HealthKit ici : on ne synchronise que si un module
        // a déjà demandé l'autorisation en contexte (flag posé par HealthService).
        guard HealthService.shared.isAvailable,
              UserDefaults.standard.bool(forKey: "healthAuthRequested") else { return }
        _ = await HealthService.shared.requestAuthorization()
        await syncSleep()
        await syncWeight(ctx)
    }

    // MARK: - Sommeil

    @MainActor
    private static func syncSleep() async {
        let ud = UserDefaults.standard
        // La saisie manuelle du matin reste prioritaire : on ne remplit que si
        // l'utilisateur n'a pas fait son check-in aujourd'hui.
        let lastCheck = Date(timeIntervalSince1970: ud.double(forKey: "lastSleepCheckDate"))
        guard !Calendar.current.isDateInToday(lastCheck) else { return }
        guard let hours = await HealthService.shared.sleepHoursLastNight(), hours > 0.5 else { return }
        ud.set(Int(hours.rounded()), forKey: "lastSleepHours")
    }

    // MARK: - Poids

    @MainActor
    private static func syncWeight(_ ctx: ModelContext) async {
        guard let sample = await HealthService.shared.latestBodyMass() else { return }
        var descriptor = FetchDescriptor<VitalRecord>(
            predicate: #Predicate { $0.type == "poids" },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let latest = try? ctx.fetch(descriptor).first
        // N'insère que si l'échantillon Santé est plus récent que le dernier relevé
        // (manuel ou déjà synchronisé) — pas de doublons.
        if let latest, latest.date >= sample.date { return }
        let record = VitalRecord(
            date: sample.date,
            type: "poids",
            value: (sample.kg * 10).rounded() / 10,
            unit: "kg",
            notes: "Apple Santé"
        )
        ctx.insert(record)
        do { try ctx.save() } catch { print("[HealthAutoSync] save failed: \(error)") }
    }
}
