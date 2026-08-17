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
        let lifeProfile = ud.string(forKey: "lifeProfile") ?? ""
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
        let energyLabel = ud.string(forKey: "todayEnergyLabel") ?? ""
        if energyScore > 0 {
            lines.append(energyLabel.isEmpty
                ? "Score énergie: \(energyScore)/100"
                : "Score énergie: \(energyScore)/100 (\(energyLabel))")
        }

        // ── Moyenne sommeil 7j (publiée par SleepWidgetSyncer) ──────────────
        let sleepAvg7d = grp.double(forKey: "sleep_avg_hours_7d")
        if sleepAvg7d > 0 {
            lines.append("Sommeil moyen 7j: \(String(format: "%.1f", sleepAvg7d))h/nuit")
        }

        // ── Mémoire long terme du coach (publiée par MemoryWidgetSyncer) ────
        // Ce que l'utilisateur t'a dit dans le passé. Priorité aux mémoires
        // pinnées, puis les plus récentes. Injectées dans chaque prompt pour
        // que le coach reste cohérent avec ce qu'il "sait" de l'utilisateur.
        if let memData = grp.data(forKey: "memory_top_10"),
           let mems = try? JSONSerialization.jsonObject(with: memData) as? [[String: Any]],
           !mems.isEmpty {
            lines.append("")
            lines.append("Mémoire du coach (ce que l'utilisateur t'a dit) :")
            for m in mems {
                let content = m["content"] as? String ?? ""
                let category = m["category"] as? String ?? ""
                let pinned = (m["isPinned"] as? Bool ?? false) ? " ★" : ""
                if !content.isEmpty {
                    lines.append("- [\(category)]\(pinned) \(content)")
                }
            }
        }

        // ── Fenêtre de coucher cible (contexte pour reco couchée/réveil) ────
        let bedH = ud.integer(forKey: "bedHour")
        let bedM = ud.integer(forKey: "bedMinute")
        let wakeH = ud.integer(forKey: "wakeupHour")
        let wakeM = ud.integer(forKey: "wakeupMinute")
        if bedH > 0 || wakeH > 0 {
            var parts: [String] = []
            if bedH > 0 { parts.append(String(format: "coucher %02d:%02d", bedH, bedM)) }
            if wakeH > 0 { parts.append(String(format: "réveil %02d:%02d", wakeH, wakeM)) }
            lines.append("Fenêtre sommeil cible: \(parts.joined(separator: " → "))")
        }

        // ── Humeur récente (3 derniers jours, si publiée en App Group) ──────
        if let moodData = grp.data(forKey: "mood_recent_7d"),
           let moods = try? JSONSerialization.jsonObject(with: moodData) as? [Int],
           !moods.isEmpty {
            let recent = moods.prefix(3).map(String.init).joined(separator: ", ")
            let avg = Double(moods.reduce(0, +)) / Double(moods.count)
            lines.append("Humeur récente: \(recent) (moy \(String(format: "%.1f", avg))/5)")
        }

        // ── Objectifs actifs (simplification via goalEndDatesRaw) ───────────
        let goalRaw = ud.string(forKey: "goalEndDatesRaw") ?? ""
        if !goalRaw.isEmpty {
            let activeGoalsCount = goalRaw.split(separator: ",").count
            if activeGoalsCount > 0 { lines.append("Objectifs actifs: \(activeGoalsCount)") }
        }

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

        // ── Analyse cross-modules (le vrai différenciateur LifeOS) ──────────
        // Croise les signaux des 15 modules pour produire des insights que
        // le coach peut restituer avec des recommandations concrètes.
        let insights = Self.crossModuleInsights(
            sleepH: sleepH,
            sleepQ: sleepQ,
            energyScore: energyScore,
            kcalToday: kcalToday,
            kcalGoal: kcalGoal,
            proteinToday: proteinToday,
            proteinGoal: proteinGoal,
            waterToday: waterToday,
            waterGoal: waterGoal,
            fitSummary: fitSummary,
            avgStreak: avgStreak,
            hasCycle: hasCycle
        )
        if !insights.isEmpty {
            lines.append("")
            lines.append("Analyse cross-modules:")
            for i in insights { lines.append("- \(i)") }
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
        // Filet de sécurité : le backend limite user_context à 20000 chars.
        // On tronque à 19500 pour garder une marge et éviter les 422 même si
        // le backend n'est pas encore redéployé avec la nouvelle limite.
        let maxLen = 19500
        if context.count > maxLen {
            let idx = context.index(context.startIndex, offsetBy: maxLen)
            context = String(context[..<idx])
        }
        return context
    }

    /// Insights cross-modules : croise les signaux santé/nutrition/fitness pour
    /// produire des observations exploitables par le coach. Chaque insight est
    /// une phrase courte, factuelle, prête à être restituée dans une réponse.
    ///
    /// Règles :
    /// - Chaque insight = une combinaison d'au moins 2 signaux
    /// - Neutre et descriptif (le coach fait la reco lui-même)
    /// - Max ~5 insights pour ne pas noyer le prompt
    private static func crossModuleInsights(
        sleepH: Int, sleepQ: Int, energyScore: Int,
        kcalToday: Int, kcalGoal: Int,
        proteinToday: Int, proteinGoal: Int,
        waterToday: Int, waterGoal: Int,
        fitSummary: String, avgStreak: Int, hasCycle: Bool
    ) -> [String] {
        var out: [String] = []

        // Sommeil insuffisant + entraînement récent = récup compromise
        if sleepH > 0, sleepH < 6, fitSummary.contains("séries") {
            out.append("Nuit courte (\(sleepH)h) avec entraînement récent — récup limitée.")
        }
        // Bon sommeil + faible énergie = ailleurs (nutrition ? hydratation ?)
        if sleepH >= 7, sleepQ >= 4, energyScore > 0, energyScore < 60 {
            out.append("Sommeil bon mais énergie basse — regarder nutrition/hydratation.")
        }
        // Déficit calorique important + entraînement = risque récup
        if kcalGoal > 0, kcalToday > 0, kcalToday < kcalGoal - 500, fitSummary.contains("séries") {
            let deficit = kcalGoal - kcalToday
            out.append("Déficit \(deficit) kcal aujourd'hui avec séance récente — risque récup.")
        }
        // Protéines très basses + muscu = objectif hypertrophie compromis
        if proteinGoal > 0, proteinToday > 0, proteinToday < proteinGoal / 2, fitSummary.contains("séries") {
            out.append("Protéines à \(proteinToday)/\(proteinGoal)g avec entraînement — synthèse compromise.")
        }
        // Hydratation faible + fatigue
        if waterGoal > 0, waterToday > 0, waterToday < waterGoal / 2, energyScore > 0, energyScore < 60 {
            out.append("Hydratation à \(waterToday)/\(waterGoal)ml avec énergie basse — corrélation probable.")
        }
        // Streak fort = capital motivation
        if avgStreak >= 14 {
            out.append("Streak habitudes \(avgStreak)j — momentum solide, ne pas casser.")
        }
        // Cycle × énergie
        if hasCycle {
            let phase = CycleContext.shared.currentPhase
            if phase == .luteal, energyScore > 0, energyScore < 50 {
                out.append("Phase lutéale + énergie basse — normale, éviter les charges max.")
            }
        }
        return Array(out.prefix(5))
    }
}
