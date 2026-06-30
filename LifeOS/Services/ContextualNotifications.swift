import Foundation
import UserNotifications

final class ContextualNotifications {
    static let shared = ContextualNotifications()
    private init() {}

    private let prefix = "lifeos.ctx."
    private let ud = UserDefaults.standard

    // MARK: - Entrée publique

    func reschedule() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let old = requests.filter { $0.identifier.hasPrefix(self.prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: old)
            DispatchQueue.main.async { self.scheduleAll() }
        }
    }

    // MARK: - Helpers lecture UserDefaults

    private func modules() -> Set<String> {
        Set((ud.string(forKey: "recommendedModules") ?? "").split(separator: ",").map(String.init))
    }

    private func has(_ module: String) -> Bool { modules().contains(module) }

    /// Retourne l'heure si la clé existe et est valide (0-23), sinon nil.
    private func notifHour(_ key: String) -> Int? {
        guard ud.object(forKey: key) != nil else { return nil }
        let v = ud.integer(forKey: key)
        return (0..<24).contains(v) ? v : nil
    }

    private func notifMinute(_ key: String) -> Int {
        let v = ud.integer(forKey: key)
        return (0..<60).contains(v) ? v : 0
    }

    private func enabled(_ key: String) -> Bool {
        ud.object(forKey: key) as? Bool ?? false
    }

    private func intVal(_ key: String) -> Int? {
        guard ud.object(forKey: key) != nil else { return nil }
        let v = ud.integer(forKey: key)
        return v > 0 ? v : nil
    }

    // MARK: - Planification

    private func scheduleAll() {
        let mods = modules()

        // ── SOMMEIL ───────────────────────────────────────────────────────────
        if mods.contains("sleep") {
            if enabled("notif_sleep_morning_enabled"),
               let h = notifHour("notif_sleep_morning_hour") {
                let m = notifMinute("notif_sleep_morning_minute")
                daily(id: "sleep_morning",
                      title: "Bilan du matin",
                      body: "Comment as-tu dormi ? Lance ton score d'énergie.",
                      hour: h, minute: m)
            }

            if enabled("notif_sleep_bedtime_enabled"),
               let h = notifHour("notif_sleep_bedtime_hour") {
                let m = notifMinute("notif_sleep_bedtime_minute")
                daily(id: "sleep_bedtime",
                      title: "Prépare-toi à dormir",
                      body: "Pose les écrans et décompresse avant de te coucher.",
                      hour: h, minute: m)
            }
        }

        // ── FITNESS ───────────────────────────────────────────────────────────
        if mods.contains("fitness") && enabled("notif_fitness_enabled"),
           let h = notifHour("notif_fitness_hour") {
            let daysRaw = ud.string(forKey: "notif_fitness_days") ?? ""
            let days = daysRaw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) }
            if days.isEmpty {
                daily(id: "fitness_reminder",
                      title: "C'est l'heure de bouger",
                      body: "Ta séance t'attend.",
                      hour: h, minute: 0)
            } else {
                for day in days {
                    weekday(id: "fitness_day\(day)",
                            title: "C'est l'heure de bouger",
                            body: "Ta séance t'attend.",
                            hour: h, minute: 0, weekday: day)
                }
            }
        }

        // ── NUTRITION ─────────────────────────────────────────────────────────
        if mods.contains("nutrition") {
            let fastingOn = ud.bool(forKey: "nutrition_fasting_enabled")

            if !fastingOn,
               enabled("notif_nutrition_breakfast_enabled"),
               let h = notifHour("notif_nutrition_breakfast_hour") {
                daily(id: "nutrition_breakfast",
                      title: "Petit-déjeuner",
                      body: "Note ton repas du matin pour suivre tes calories.",
                      hour: h, minute: 0)
            }

            if enabled("notif_nutrition_lunch_enabled"),
               let h = notifHour("notif_nutrition_lunch_hour") {
                daily(id: "nutrition_lunch",
                      title: "Déjeuner",
                      body: "Pense à noter ton repas du midi.",
                      hour: h, minute: 0)
            }

            if enabled("notif_nutrition_dinner_enabled"),
               let h = notifHour("notif_nutrition_dinner_hour") {
                daily(id: "nutrition_dinner",
                      title: "Dîner",
                      body: "Dernière ligne droite — note ton repas du soir.",
                      hour: h, minute: 0)
            }

            if enabled("notif_nutrition_review_enabled"),
               let h = notifHour("notif_nutrition_review_hour") {
                daily(id: "nutrition_review",
                      title: "Bilan nutrition du jour",
                      body: "Vérifie tes calories et tes protéines.",
                      hour: h, minute: 0)
            }
        }

        // ── MENTAL ────────────────────────────────────────────────────────────
        if mods.contains("mind") {
            if enabled("notif_mind_session_enabled"),
               let h = notifHour("notif_mind_session_hour") {
                daily(id: "mind_session",
                      title: "Ta session bien-être",
                      body: "5 minutes pour toi — respiration, méditation, journaling.",
                      hour: h, minute: 0)
            }

            if enabled("notif_mind_mood_enabled"),
               let h = notifHour("notif_mind_mood_hour") {
                daily(id: "mind_mood",
                      title: "Comment tu te sens ?",
                      body: "Note ton humeur du jour.",
                      hour: h, minute: 0)
            }
        }

        // ── PRODUCTIVITÉ ──────────────────────────────────────────────────────
        if mods.contains("productivity") {
            if enabled("notif_productivity_morning_enabled"),
               let h = notifHour("notif_productivity_morning_hour") {
                daily(id: "productivity_morning",
                      title: "3 priorités pour aujourd'hui",
                      body: "Qu'est-ce qui compte vraiment aujourd'hui ?",
                      hour: h, minute: 0)
            }

            if enabled("notif_productivity_evening_enabled"),
               let h = notifHour("notif_productivity_evening_hour") {
                daily(id: "productivity_evening",
                      title: "Bilan de la journée",
                      body: "Qu'est-ce que tu as accompli aujourd'hui ?",
                      hour: h, minute: 0)
            }

            if enabled("notif_habits_enabled"),
               let h = notifHour("notif_habits_hour") {
                daily(id: "habits_reminder",
                      title: "Tes habitudes du jour",
                      body: "Quelques secondes pour cocher ce que tu as fait.",
                      hour: h, minute: 0)
            }
        }

        // ── FINANCES ──────────────────────────────────────────────────────────
        if mods.contains("finance") {
            if enabled("notif_finance_monthly_enabled"),
               let day = intVal("finance_salary_day"),
               let h = notifHour("notif_finance_monthly_hour") {
                monthly(id: "finance_monthly",
                        title: "Bilan budget mensuel",
                        body: "Prends 10min pour faire le point sur ton mois.",
                        day: day, hour: h, minute: 0)
            }

            if enabled("notif_finance_weekly_enabled"),
               let wd = intVal("finance_review_weekday"),
               let h = notifHour("notif_finance_weekly_hour") {
                weekday(id: "finance_weekly",
                        title: "Bilan budget",
                        body: "Vérifie tes dépenses de la semaine.",
                        hour: h, minute: 0, weekday: wd)
            }
        }

        // ── INVESTISSEMENT ────────────────────────────────────────────────────
        if mods.contains("invest") {
            if enabled("notif_invest_dca_enabled"),
               let day = intVal("invest_dca_day"),
               let h = notifHour("notif_invest_dca_hour") {
                monthly(id: "invest_dca",
                        title: "Investissement mensuel",
                        body: "C'est le bon moment pour ton versement régulier.",
                        day: day, hour: h, minute: 0)
            }

            if enabled("notif_invest_weekly_enabled"),
               let wd = intVal("invest_review_weekday"),
               let h = notifHour("notif_invest_weekly_hour") {
                weekday(id: "invest_weekly",
                        title: "Revue portfolio",
                        body: "Jette un œil à l'évolution de tes investissements.",
                        hour: h, minute: 0, weekday: wd)
            }
        }

        // ── CARRIÈRE ──────────────────────────────────────────────────────────
        if mods.contains("career"),
           enabled("notif_career_weekly_enabled"),
           ud.bool(forKey: "career_job_searching"),
           let wd = intVal("career_review_weekday"),
           let h = notifHour("notif_career_weekly_hour") {
            weekday(id: "career_weekly",
                    title: "Candidatures de la semaine",
                    body: "Tes objectifs de candidatures pour cette semaine ?",
                    hour: h, minute: 0, weekday: wd)
        }

        // ── APPRENTISSAGE ─────────────────────────────────────────────────────
        if mods.contains("learning"),
           enabled("notif_learning_enabled"),
           let h = notifHour("notif_learning_hour") {
            daily(id: "learning_daily",
                  title: "Ta session d'apprentissage",
                  body: "Quelques minutes pour progresser aujourd'hui.",
                  hour: h, minute: 0)
        }

        // ── CYCLE ─────────────────────────────────────────────────────────────
        if mods.contains("cycle") {
            if enabled("notif_cycle_daily_enabled"),
               let h = notifHour("notif_cycle_daily_hour") {
                daily(id: "cycle_daily",
                      title: "Suivi cycle",
                      body: "Note tes symptômes du jour.",
                      hour: h, minute: 0)
            }

            // La notif PMS est recalculée par le CycleContext quand les données changent
            // Elle est planifiée via NotificationManager.scheduleCyclePMS() séparément
        }

        // ── MAISON ────────────────────────────────────────────────────────────
        if mods.contains("home") {
            if enabled("notif_home_cleaning_enabled"),
               let wd = intVal("home_cleaning_weekday"),
               let h = notifHour("notif_home_cleaning_hour") {
                weekday(id: "home_cleaning",
                        title: "Session ménage",
                        body: "1h aujourd'hui pour que ta semaine soit tranquille.",
                        hour: h, minute: 0, weekday: wd)
            }

            if enabled("notif_home_groceries_enabled"),
               let wd = intVal("home_groceries_weekday"),
               let h = notifHour("notif_home_groceries_hour") {
                weekday(id: "home_groceries",
                        title: "Liste de courses",
                        body: "Ta liste est prête — c'est le bon moment.",
                        hour: h, minute: 0, weekday: wd)
            }
        }

        // ── ADMIN ─────────────────────────────────────────────────────────────
        if mods.contains("admin"),
           enabled("notif_admin_enabled"),
           let wd = intVal("admin_session_weekday"),
           let h = notifHour("notif_admin_hour") {
            weekday(id: "admin_session",
                    title: "Session admin",
                    body: "Paperasse, documents, démarches — 30min suffisent.",
                    hour: h, minute: 0, weekday: wd)
        }

        // ── CORPS / LOOKS ─────────────────────────────────────────────────────
        if mods.contains("looks") {
            if ud.bool(forKey: "looks_has_morning_routine"),
               enabled("notif_looks_morning_enabled"),
               let h = notifHour("notif_looks_morning_hour") {
                daily(id: "looks_morning",
                      title: "Routine du matin",
                      body: "Prends soin de toi — ta routine en quelques minutes.",
                      hour: h, minute: 0)
            }

            if ud.bool(forKey: "looks_has_evening_routine"),
               enabled("notif_looks_evening_enabled"),
               let h = notifHour("notif_looks_evening_hour") {
                daily(id: "looks_evening",
                      title: "Routine du soir",
                      body: "La constance fait tout — ta routine soir.",
                      hour: h, minute: 0)
            }
        }

        // ── SOCIAL ────────────────────────────────────────────────────────────
        if mods.contains("social"),
           enabled("notif_social_enabled"),
           let wd = intVal("social_contact_weekday"),
           let h = notifHour("notif_social_hour") {
            weekday(id: "social_reminder",
                    title: "Garde le contact",
                    body: "Un message à un ami ou à ta famille aujourd'hui ?",
                    hour: h, minute: 0, weekday: wd)
        }
    }

    // MARK: - Primitives de planification

    private func daily(id: String, title: String, body: String, hour: Int, minute: Int) {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        add(id: id, title: title, body: body, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
    }

    private func weekday(id: String, title: String, body: String, hour: Int, minute: Int, weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        var c = DateComponents(); c.weekday = weekday; c.hour = hour; c.minute = minute
        add(id: id, title: title, body: body, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
    }

    private func monthly(id: String, title: String, body: String, day: Int, hour: Int, minute: Int) {
        guard (1...31).contains(day) else { return }
        var c = DateComponents(); c.day = day; c.hour = hour; c.minute = minute
        add(id: id, title: title, body: body, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
    }

    private func add(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.interruptionLevel = .active
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "\(prefix)\(id)", content: content, trigger: trigger)
        )
    }
}
