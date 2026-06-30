import Foundation

// Builds a plain-text snapshot of the user's current state, injected into
// every AI message so the model always knows what the user did today.
@MainActor
final class UserContextBuilder {
    static let shared = UserContextBuilder()
    private init() {}

    private static let group = UserDefaults(suiteName: "group.lifeos.app")

    func build() -> String {
        var lines: [String] = []
        let ud = UserDefaults.standard
        guard let grp = Self.group else { return lines.joined(separator: "\n") }

        // ── Current date/time ────────────────────────────────────────────────
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        lines.append("Date: \(fmt.string(from: .now))")

        // ── Profile ──────────────────────────────────────────────────────────
        let name = ud.string(forKey: "userName") ?? ""
        let gender = ud.string(forKey: "userGender") ?? ""
        let lifeProfile = ud.string(forKey: "userLifeProfile") ?? ""
        let activeModules = ud.string(forKey: "activeModules") ?? ""
        if !name.isEmpty       { lines.append("Prénom: \(name)") }
        if !gender.isEmpty     { lines.append("Genre: \(gender)") }
        if !lifeProfile.isEmpty { lines.append("Profil: \(lifeProfile)") }
        if !activeModules.isEmpty { lines.append("Modules actifs: \(activeModules)") }

        // ── Cycle ────────────────────────────────────────────────────────────
        let hasCycle = ud.bool(forKey: "userHasCycle")
        if hasCycle {
            let ctx = CycleContext.shared
            lines.append("Phase cycle: \(ctx.currentPhase.label) (J\(ctx.dayOfCycle), encore \(ctx.daysUntilPeriod)j)")
            lines.append("Énergie: \(ctx.currentPhase.energyDescription)")
            if ctx.isOvulationWindow { lines.append("Fenêtre ovulation: oui") }
            if ctx.isPMSWindow       { lines.append("Fenêtre SPM: oui") }
        }

        // ── Objectifs ────────────────────────────────────────────────────────
        let kcalGoal    = ud.integer(forKey: "kcalGoal")
        let proteinGoal = ud.integer(forKey: "proteinGoal")
        let waterGoal   = ud.integer(forKey: "waterGoal")
        if kcalGoal    > 0 { lines.append("Objectif kcal: \(kcalGoal) kcal/j") }
        if proteinGoal > 0 { lines.append("Objectif protéines: \(proteinGoal) g/j") }
        if waterGoal   > 0 { lines.append("Objectif eau: \(waterGoal) ml/j") }

        // ── Habitudes aujourd'hui (depuis widget_habits dans App Group) ───────
        if let data = grp.data(forKey: "widget_habits"),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let total = entries.count
            let done  = entries.filter { $0["done"] as? Bool == true }.count
            if total > 0 { lines.append("Habitudes: \(done)/\(total) faites aujourd'hui") }
        }

        // ── Nutrition aujourd'hui ─────────────────────────────────────────────
        let kcalToday   = grp.integer(forKey: "today_kcal")
        let proteinToday = grp.integer(forKey: "today_protein_g")
        let waterToday  = grp.integer(forKey: "today_water_ml")
        if kcalToday   > 0 { lines.append("Kcal aujourd'hui: \(kcalToday) kcal") }
        if proteinToday > 0 { lines.append("Protéines aujourd'hui: \(proteinToday) g") }
        if waterToday  > 0 { lines.append("Eau aujourd'hui: \(waterToday) ml") }

        // ── Humeur & énergie ─────────────────────────────────────────────────
        let mood = grp.integer(forKey: "today_mood")
        if mood > 0 { lines.append("Humeur aujourd'hui: \(mood)/5") }

        let sleepH = grp.double(forKey: "last_sleep_hours")
        let sleepQ = grp.integer(forKey: "last_sleep_quality")
        if sleepH > 0 { lines.append("Sommeil nuit dernière: \(String(format: "%.1f", sleepH))h (qualité \(sleepQ)/5)") }

        // ── Jeûne en cours ───────────────────────────────────────────────────
        let fastingStart = grp.double(forKey: "fasting_start_ts")
        if fastingStart > 0 {
            let elapsed = Date().timeIntervalSince1970 - fastingStart
            let h = Int(elapsed / 3600)
            let m = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
            lines.append("Jeûne en cours: \(h)h\(m)min")
        }

        // ── Score énergie ─────────────────────────────────────────────────────
        let energyScore = grp.integer(forKey: "today_energy_score")
        if energyScore > 0 { lines.append("Score énergie: \(energyScore)/100") }

        // ── Streak moyen habitudes ─────────────────────────────────────────────
        let avgStreak = grp.integer(forKey: "habits_avg_streak")
        if avgStreak > 0 { lines.append("Streak moyen habitudes: \(avgStreak) jours") }

        return lines.joined(separator: "\n")
    }
}
