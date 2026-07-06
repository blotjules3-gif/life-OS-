import Foundation

// Builds a plain-text snapshot of the user's current state, injected into
// every AI message so the model always knows what the user did today.
@MainActor
final class UserContextBuilder {
    static let shared = UserContextBuilder()
    private init() {}

    private static let group = UserDefaults(suiteName: "group.lifeos.app")

    /// Construit le snapshot utilisateur + l'expertise coach.
    /// - Parameter message: message courant de l'utilisateur (optionnel). S'il est fourni
    ///   on ne prend QUE les blocs d'expertise détectés dedans (économie de tokens).
    ///   Sinon on retombe sur un dispatch par modules actifs.
    func build(message: String? = nil) -> String {
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

        // ── Profil sportif renseigné manuellement ────────────────────────────
        let weightKg = ud.double(forKey: "userWeightKg")
        let heightCm = ud.double(forKey: "userHeightCm")
        let level = ud.string(forKey: "userStrengthLevel") ?? ""
        let bench = ud.double(forKey: "userBench1RM")
        let squat = ud.double(forKey: "userSquat1RM")
        let deadlift = ud.double(forKey: "userDeadlift1RM")
        let trainingYears = ud.integer(forKey: "userTrainingYears")
        let weeklyFreq = ud.integer(forKey: "userWeeklyFrequency")
        if weightKg > 0 { lines.append("Poids: \(String(format: "%.1f", weightKg)) kg") }
        if heightCm > 0 { lines.append("Taille: \(Int(heightCm)) cm") }
        if !level.isEmpty { lines.append("Niveau muscu: \(level)") }
        if trainingYears > 0 { lines.append("Années d'entraînement: \(trainingYears)") }
        if weeklyFreq > 0 { lines.append("Fréquence hebdo cible: \(weeklyFreq) séances") }
        var prs: [String] = []
        if bench > 0    { prs.append("Bench \(Int(bench)) kg") }
        if squat > 0    { prs.append("Squat \(Int(squat)) kg") }
        if deadlift > 0 { prs.append("Deadlift \(Int(deadlift)) kg") }
        if !prs.isEmpty { lines.append("PR (1RM estimé): \(prs.joined(separator: ", "))") }
        // Ratios force/poids si dispo
        if weightKg > 0 {
            var ratios: [String] = []
            if bench > 0    { ratios.append(String(format: "Bench ×%.2f", bench/weightKg)) }
            if squat > 0    { ratios.append(String(format: "Squat ×%.2f", squat/weightKg)) }
            if deadlift > 0 { ratios.append(String(format: "Deadlift ×%.2f", deadlift/weightKg)) }
            if !ratios.isEmpty { lines.append("Ratios force/poids: \(ratios.joined(separator: ", "))") }
        }

        // ── Séances muscu récentes (via shared defaults) ─────────────────────
        let fitSummary = grp.string(forKey: "fitness_summary_7d") ?? ""
        if !fitSummary.isEmpty {
            lines.append(fitSummary)
        }
        let fitLastExercises = grp.string(forKey: "fitness_last_exercises") ?? ""
        if !fitLastExercises.isEmpty {
            lines.append("Exos travaillés (7 j): \(fitLastExercises)")
        }
        let fitTopLift = grp.string(forKey: "fitness_top_lift") ?? ""
        if !fitTopLift.isEmpty {
            lines.append("PR récent: \(fitTopLift)")
        }

        var context = lines.joined(separator: "\n")
        // Priorité 1 : si l'utilisateur a envoyé un message, topic-detection ciblée.
        // Priorité 2 : fallback sur les modules actifs.
        let expertise: String
        if let m = message, !m.trimmingCharacters(in: .whitespaces).isEmpty {
            let topics = CoachExpertise.detectTopics(in: m)
            if !topics.isEmpty {
                var enriched = topics
                if hasCycle { enriched.insert("cycle") }
                expertise = CoachExpertise.blocks(forTopics: enriched)
            } else {
                expertise = CoachExpertise.combinedBlocks(
                    activeModules: activeModules,
                    includeCycle: hasCycle
                )
            }
        } else {
            expertise = CoachExpertise.combinedBlocks(
                activeModules: activeModules,
                includeCycle: hasCycle
            )
        }
        if !expertise.isEmpty {
            context += "\n\n" + expertise
        }
        return context
    }
}
