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

        // Loop 8 — publier le breakdown détaillé (deep/REM/awakenings/bedtime)
        // dans App Group pour lecture par UserContextBuilder au prochain send().
        if let breakdown = await HealthService.shared.sleepBreakdownLastNight() {
            let bedtimeStr: String?
            if let b = breakdown.bedtime {
                let f = DateFormatter()
                f.locale = Locale(identifier: "fr_FR")
                f.dateFormat = "HH'h'mm"
                bedtimeStr = f.string(from: b)
            } else {
                bedtimeStr = nil
            }
            var payload: [String: Any] = [
                "deep": (breakdown.deepHours * 10).rounded() / 10,
                "rem": (breakdown.remHours * 10).rounded() / 10,
                "core": (breakdown.coreHours * 10).rounded() / 10,
                "awakenings": breakdown.awakenings,
            ]
            if let b = bedtimeStr { payload["bedtime"] = b }
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let grp = UserDefaults(suiteName: "group.lifeos.app") {
                grp.set(data, forKey: "sleep_breakdown_last_night")
            }
        }
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
        do { try ctx.save() } catch { AppLog.data.error("HealthAutoSync save failed: \(error.localizedDescription, privacy: .public)") }
    }
}
