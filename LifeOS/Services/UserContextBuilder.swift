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
        guard let grp = Self.group else { return "" }

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

        // ── Progression du jour (fait / objectif, avec %) ────────────────────
        func progress(_ done: Int, _ goal: Int, _ unit: String) -> String {
            guard goal > 0 else { return "\(done) \(unit)" }
            let pct = Int((Double(done) / Double(goal) * 100).rounded())
            return "\(done)/\(goal) \(unit) (\(pct)%)"
        }
        let kcalGoal     = ud.integer(forKey: "kcalGoal")
        let proteinGoal  = ud.integer(forKey: "proteinGoal")
        let waterGoal    = ud.integer(forKey: "waterGoal")
        let kcalToday    = grp.integer(forKey: "today_kcal")
        let proteinToday = grp.integer(forKey: "today_protein_g")
        let waterToday   = grp.integer(forKey: "today_water_ml")
        if kcalToday > 0 || kcalGoal > 0 {
            lines.append("Kcal aujourd'hui: \(progress(kcalToday, kcalGoal, "kcal"))")
        }
        if proteinToday > 0 || proteinGoal > 0 {
            lines.append("Protéines aujourd'hui: \(progress(proteinToday, proteinGoal, "g"))")
        }
        if waterToday > 0 || waterGoal > 0 {
            lines.append("Eau aujourd'hui: \(progress(waterToday, waterGoal, "ml"))")
        }

        // ── Habitudes aujourd'hui (nommées, depuis widget_habits) ────────────
        if let data = grp.data(forKey: "widget_habits"),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           !entries.isEmpty {
            let done = entries.filter { $0["done"] as? Bool == true }
            let todo = entries.filter { ($0["done"] as? Bool) != true }
            lines.append("Habitudes: \(done.count)/\(entries.count) faites aujourd'hui")
            let doneNames = done.compactMap { $0["name"] as? String }.prefix(6)
            let todoNames = todo.compactMap { $0["name"] as? String }.prefix(6)
            if !doneNames.isEmpty { lines.append("Habitudes faites: \(doneNames.joined(separator: ", "))") }
            if !todoNames.isEmpty { lines.append("Habitudes restantes: \(todoNames.joined(separator: ", "))") }
        }
        let avgStreak = grp.integer(forKey: "habits_avg_streak")
        if avgStreak > 0 { lines.append("Streak moyen habitudes: \(avgStreak) jours") }

        // ── Sommeil & énergie (clés réellement écrites par SleepCheckSheet) ──
        let sleepH = ud.integer(forKey: "lastSleepHours")
        let sleepQ = ud.integer(forKey: "lastSleepQuality")
        if sleepH > 0 {
            lines.append(sleepQ > 0
                ? "Sommeil nuit dernière: \(sleepH)h (qualité \(sleepQ)/5)"
                : "Sommeil nuit dernière: \(sleepH)h")
        }
        let energyScore = ud.integer(forKey: "todayEnergyScore")
        if energyScore > 0 { lines.append("Score énergie: \(energyScore)/100") }

        // ── Engagement (streak d'ouverture de l'app) ─────────────────────────
        let appStreak = EngagementTracker.shared.consecutiveDays
        let totalDays = EngagementTracker.shared.totalDays
        if appStreak > 1 { lines.append("Jours consécutifs dans l'app: \(appStreak)") }
        if totalDays > 0 { lines.append("Jours actifs au total: \(totalDays)") }

        // ── Défi principal en cours ──────────────────────────────────────────
        if let title = grp.string(forKey: "widget_challenge_title"), !title.isEmpty {
            let elapsed  = grp.integer(forKey: "widget_challenge_elapsed")
            let duration = grp.integer(forKey: "widget_challenge_duration")
            let streak   = grp.integer(forKey: "widget_challenge_streak")
            var line = "Défi en cours: \(title)"
            if duration > 0 { line += " — jour \(elapsed)/\(duration)" }
            if streak > 0   { line += ", streak \(streak) j" }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}
