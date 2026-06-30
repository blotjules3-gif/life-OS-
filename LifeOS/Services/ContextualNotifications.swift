import Foundation
import UserNotifications

final class ContextualNotifications {
    static let shared = ContextualNotifications()
    private init() {}

    private let prefix = "lifeos.ctx."

    func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let oldIDs = requests
                .filter { $0.identifier.hasPrefix(self.prefix) }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)
            DispatchQueue.main.async { self.scheduleAll() }
        }
    }

    // MARK: - Lecture des préférences

    private let ud = UserDefaults.standard

    private func modules() -> Set<String> {
        let raw = ud.string(forKey: "recommendedModules") ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    private func has(_ module: String) -> Bool { modules().contains(module) }

    private func enabled(_ key: String) -> Bool {
        ud.object(forKey: key) as? Bool ?? false
    }

    private func hour(_ key: String, fallback: Int = -1) -> Int {
        let v = ud.integer(forKey: key)
        return v > 0 ? v : fallback
    }

    private func min(_ key: String) -> Int {
        ud.integer(forKey: key)
    }

    // Calcule h:m en avançant ou reculant de `offset` minutes
    private func offset(h: Int, m: Int, by offsetMin: Int) -> (Int, Int) {
        let total = ((h * 60 + m + offsetMin) % 1440 + 1440) % 1440
        return (total / 60, total % 60)
    }

    // MARK: - Planification principale

    private func scheduleAll() {
        let mods = modules()

        // ── SOMMEIL ──────────────────────────────────────────────────────────
        if mods.contains("sleep") {

            // Bilan matin (réveil + 20min) — seulement si l'utilisateur a configuré son réveil
            let wakeH = hour("wakeupHour")
            let wakeM = min("wakeupMinute")
            if wakeH >= 0 && enabled("notif_sleep_morning_enabled") {
                let (h, m) = offset(h: wakeH, m: wakeM, by: 20)
                schedule(id: "sleep_morning",
                         title: "Bilan du matin",
                         body: "Comment as-tu dormi ? Lance ton score d'énergie.",
                         hour: h, minute: m)
            }

            // Rappel coucher (coucher - 30min) — seulement si l'utilisateur a configuré
            let bedH = hour("bedHour")
            let bedM = min("bedMinute")
            if bedH >= 0 && enabled("notif_sleep_bedtime_enabled") {
                let (h, m) = offset(h: bedH, m: bedM, by: -30)
                schedule(id: "sleep_bedtime",
                         title: "Prépare-toi à dormir",
                         body: "Écrans off dans 30min — ton corps a besoin de décompresser.",
                         hour: h, minute: m)
            }
        }

        // ── FITNESS ───────────────────────────────────────────────────────────
        if mods.contains("fitness") && enabled("notif_fitness_enabled") {
            let sportH = hour("sportHour")
            if sportH >= 0 {
                let advMin = ud.integer(forKey: "notif_fitness_advance_min")
                let advance = advMin > 0 ? advMin : 15
                let (h, m) = offset(h: sportH, m: 0, by: -advance)

                let daysRaw = ud.string(forKey: "fitness_days") ?? ""
                if daysRaw.isEmpty {
                    // Pas de jours configurés → notif quotidienne
                    schedule(id: "fitness_reminder",
                             title: "C'est l'heure de bouger",
                             body: "Ta séance t'attend — \(advance)min pour te préparer.",
                             hour: h, minute: m)
                } else {
                    // Notif uniquement les jours configurés (1=lun, 7=dim)
                    let days = daysRaw.split(separator: ",").compactMap { Int($0) }
                    for day in days {
                        scheduleWeekday(id: "fitness_day\(day)",
                                        title: "C'est l'heure de bouger",
                                        body: "Ta séance t'attend — \(advance)min pour te préparer.",
                                        hour: h, minute: m, weekday: day)
                    }
                }
            }
        }

        // ── NUTRITION ─────────────────────────────────────────────────────────
        if mods.contains("nutrition") && enabled("notif_nutrition_log_enabled") {
            let fastingEnabled = ud.bool(forKey: "nutrition_fasting_enabled")

            // Petit-déjeuner (seulement si pas en jeûne)
            let breakfastH = hour("nutrition_breakfast_hour")
            if breakfastH >= 0 && !fastingEnabled {
                let (h, m) = offset(h: breakfastH, m: 0, by: -10)
                schedule(id: "nutrition_breakfast",
                         title: "Petit-déjeuner",
                         body: "Note ton repas du matin pour suivre tes calories.",
                         hour: h, minute: m)
            }

            // Déjeuner
            let lunchH = hour("nutrition_lunch_hour")
            if lunchH >= 0 {
                let (h, m) = offset(h: lunchH, m: 0, by: -10)
                schedule(id: "nutrition_lunch",
                         title: "Déjeuner",
                         body: "Pense à noter ton repas.",
                         hour: h, minute: m)
            }

            // Dîner
            let dinnerH = hour("nutrition_dinner_hour")
            if dinnerH >= 0 {
                let (h, m) = offset(h: dinnerH, m: 0, by: -10)
                schedule(id: "nutrition_dinner",
                         title: "Dîner",
                         body: "Dernière ligne droite — note ton repas du soir.",
                         hour: h, minute: m)
            }

            // Bilan nutrition (heure configurable)
            let reviewH = hour("notif_nutrition_review_hour")
            if reviewH >= 0 {
                schedule(id: "nutrition_review",
                         title: "Bilan nutrition du jour",
                         body: "Vérifie tes calories et tes protéines.",
                         hour: reviewH, minute: 0)
            }
        }

        // ── MENTAL ────────────────────────────────────────────────────────────
        if mods.contains("mind") {

            // Session méditation / recentrage
            let sessionH = hour("mind_session_hour")
            if sessionH >= 0 {
                schedule(id: "mind_session",
                         title: "Ta session bien-être",
                         body: "5 minutes pour toi — respiration, méditation, journaling.",
                         hour: sessionH, minute: 0)
            }

            // Check-in humeur
            if enabled("notif_mind_mood_enabled") {
                let moodH = hour("mind_mood_hour")
                if moodH >= 0 {
                    schedule(id: "mind_mood",
                             title: "Comment tu te sens ?",
                             body: "Note ton humeur du jour.",
                             hour: moodH, minute: 0)
                }
            }
        }

        // ── PRODUCTIVITÉ ──────────────────────────────────────────────────────
        if mods.contains("productivity") {

            // Bilan du matin (début de journée)
            if enabled("notif_productivity_morning_enabled") {
                let startH = hour("productivity_start_hour")
                if startH >= 0 {
                    let (h, m) = offset(h: startH, m: 0, by: 5)
                    schedule(id: "productivity_morning",
                             title: "3 priorités pour aujourd'hui",
                             body: "Qu'est-ce qui compte vraiment aujourd'hui ?",
                             hour: h, minute: m)
                }
            }

            // Bilan du soir (fin de journée)
            if enabled("notif_productivity_evening_enabled") {
                let endH = hour("productivity_end_hour")
                if endH >= 0 {
                    schedule(id: "productivity_evening",
                             title: "Bilan de la journée",
                             body: "Qu'est-ce que tu as accompli aujourd'hui ?",
                             hour: endH, minute: 0)
                }
            }

            // Rappel habitudes
            if enabled("notif_habits_enabled") {
                let habitsH = hour("notif_habits_hour")
                if habitsH >= 0 {
                    schedule(id: "habits_reminder",
                             title: "Tes habitudes du jour",
                             body: "Quelques secondes pour cocher ce que tu as fait.",
                             hour: habitsH, minute: 0)
                }
            }
        }

        // ── FINANCES ──────────────────────────────────────────────────────────
        if mods.contains("finance") {

            // Bilan hebdomadaire (jour + heure configurés)
            if enabled("notif_finance_weekly_enabled") {
                let weekday = ud.integer(forKey: "finance_review_weekday")
                let reviewH = hour("finance_review_hour")
                if weekday > 0 && reviewH >= 0 {
                    scheduleWeekday(id: "finance_weekly",
                                    title: "Bilan budget",
                                    body: "Prends 5min pour vérifier tes dépenses de la semaine.",
                                    hour: reviewH, minute: 0, weekday: weekday)
                }
            }
        }

        // ── INVESTISSEMENT ────────────────────────────────────────────────────
        if mods.contains("invest") {

            // Rappel DCA mensuel
            if enabled("notif_invest_dca_enabled") {
                let dcaDay = ud.integer(forKey: "invest_dca_day")
                if dcaDay > 0 {
                    scheduleMonthly(id: "invest_dca",
                                    title: "Investissement mensuel",
                                    body: "C'est le bon moment pour ton versement régulier.",
                                    day: dcaDay, hour: 9, minute: 0)
                }
            }

            // Revue portfolio hebdomadaire
            if enabled("notif_invest_weekly_enabled") {
                let weekday = ud.integer(forKey: "invest_review_weekday")
                let reviewH = hour("invest_review_hour")
                if weekday > 0 && reviewH >= 0 {
                    scheduleWeekday(id: "invest_weekly",
                                    title: "Revue portfolio",
                                    body: "Jette un œil à l'évolution de tes investissements.",
                                    hour: reviewH, minute: 0, weekday: weekday)
                }
            }
        }

        // ── CARRIÈRE ──────────────────────────────────────────────────────────
        if mods.contains("career") && enabled("notif_career_weekly_enabled") {
            let isSearching = ud.bool(forKey: "career_job_searching")
            if isSearching {
                let weekday = ud.integer(forKey: "career_review_weekday")
                if weekday > 0 {
                    scheduleWeekday(id: "career_weekly",
                                    title: "Candidatures de la semaine",
                                    body: "Tes objectifs de candidatures pour cette semaine ?",
                                    hour: 9, minute: 0, weekday: weekday)
                }
            }
        }

        // ── APPRENTISSAGE ─────────────────────────────────────────────────────
        if mods.contains("learning") && enabled("notif_learning_enabled") {
            let sessionH = hour("learning_session_hour")
            if sessionH >= 0 {
                schedule(id: "learning_daily",
                         title: "Ta session d'apprentissage",
                         body: "Quelques minutes pour progresser aujourd'hui.",
                         hour: sessionH, minute: 0)
            }
        }

        // ── CYCLE MENSTRUEL ───────────────────────────────────────────────────
        if mods.contains("cycle") {

            // Tracking quotidien
            if enabled("notif_cycle_daily_enabled") {
                let trackH = hour("cycle_track_hour")
                if trackH >= 0 {
                    schedule(id: "cycle_daily",
                             title: "Suivi cycle",
                             body: "Note tes symptômes du jour.",
                             hour: trackH, minute: 0)
                }
            }
        }

        // ── MAISON ────────────────────────────────────────────────────────────
        if mods.contains("home") {

            // Ménage hebdomadaire
            if enabled("notif_home_cleaning_enabled") {
                let weekday = ud.integer(forKey: "home_cleaning_weekday")
                let cleanH = hour("home_cleaning_hour")
                if weekday > 0 && cleanH >= 0 {
                    scheduleWeekday(id: "home_cleaning",
                                    title: "Session ménage",
                                    body: "1h aujourd'hui pour que ta semaine soit tranquille.",
                                    hour: cleanH, minute: 0, weekday: weekday)
                }
            }

            // Courses
            if enabled("notif_home_groceries_enabled") {
                let weekday = ud.integer(forKey: "home_groceries_weekday")
                if weekday > 0 {
                    scheduleWeekday(id: "home_groceries",
                                    title: "Liste de courses",
                                    body: "Ta liste est prête — c'est le bon moment pour faire les courses.",
                                    hour: 10, minute: 0, weekday: weekday)
                }
            }
        }

        // ── ADMIN ─────────────────────────────────────────────────────────────
        if mods.contains("admin") && enabled("notif_admin_enabled") {
            let weekday = ud.integer(forKey: "admin_session_weekday")
            let adminH = hour("admin_session_hour")
            if weekday > 0 && adminH >= 0 {
                scheduleWeekday(id: "admin_session",
                                title: "Session admin",
                                body: "Paperasse, documents, démarches — 30min suffisent.",
                                hour: adminH, minute: 0, weekday: weekday)
            }
        }

        // ── CORPS / LOOKS ─────────────────────────────────────────────────────
        if mods.contains("looks") {

            let hasMorning = ud.bool(forKey: "looks_has_morning_routine")
            let morningH = hour("looks_morning_hour")
            if hasMorning && morningH >= 0 {
                schedule(id: "looks_morning",
                         title: "Routine du matin",
                         body: "Prends soin de toi — ta routine en quelques minutes.",
                         hour: morningH, minute: 0)
            }

            let hasEvening = ud.bool(forKey: "looks_has_evening_routine")
            let eveningH = hour("looks_evening_hour")
            if hasEvening && eveningH >= 0 {
                schedule(id: "looks_evening",
                         title: "Routine du soir",
                         body: "La constance fait tout — ta routine soir.",
                         hour: eveningH, minute: 0)
            }
        }

        // ── SOCIAL ────────────────────────────────────────────────────────────
        if mods.contains("social") && enabled("notif_social_enabled") {
            let weekday = ud.integer(forKey: "social_contact_weekday")
            if weekday > 0 {
                scheduleWeekday(id: "social_reminder",
                                title: "Garde le contact",
                                body: "Un message à un ami ou à ta famille aujourd'hui ?",
                                hour: 18, minute: 0, weekday: weekday)
            }
        }
    }

    // MARK: - Helpers de planification

    private func schedule(id: String, title: String, body: String, hour: Int, minute: Int) {
        guard hour >= 0, hour < 24 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.interruptionLevel = .active
        var comps = DateComponents()
        comps.hour   = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "\(prefix)\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func scheduleWeekday(id: String, title: String, body: String, hour: Int, minute: Int, weekday: Int) {
        guard hour >= 0, hour < 24, weekday >= 1, weekday <= 7 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.interruptionLevel = .active
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour    = hour
        comps.minute  = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "\(prefix)\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func scheduleMonthly(id: String, title: String, body: String, day: Int, hour: Int, minute: Int) {
        guard hour >= 0, hour < 24, day >= 1, day <= 31 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.interruptionLevel = .active
        var comps = DateComponents()
        comps.day    = day
        comps.hour   = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "\(prefix)\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
