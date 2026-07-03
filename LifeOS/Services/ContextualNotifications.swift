import Foundation
import UserNotifications

final class ContextualNotifications {
    static let shared = ContextualNotifications()
    private init() {}

    private let prefix = "lifeos.ctx."
    private let ud = UserDefaults.standard

    // MARK: - Entrée publique

    func reschedule() {
<<<<<<< HEAD
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let old = requests.filter { $0.identifier.hasPrefix(self.prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: old)
            DispatchQueue.main.async { self.scheduleAll() }
=======
        cancelAll()

        let modules = activeModules()
        let wakeupHour = UserDefaults.standard.integer(forKey: "wakeupHour")
        let wakeupMin  = UserDefaults.standard.integer(forKey: "wakeupMinute")
        let wakeupTotal = wakeupHour * 60 + wakeupMin

        // — Après réveil (wakeup + 20 min) —
        // Pose la question qualité de sommeil si le module Sleep ou bilan matin est actif
        if modules.contains("sleep") || modules.contains("fitness") || modules.isEmpty {
            let afterWake = (wakeupTotal + 20) % (24 * 60)
            scheduleDaily(
                id: "morning_checkin",
                title: "Bilan du matin",
                body: "Comment as-tu dormi ? Remplis ton bilan pour calculer ton Score d'Énergie.",
                hour: afterWake / 60,
                minute: afterWake % 60
            )
        }

        // — Avant déjeuner (12h15) —
        if modules.contains("nutrition") {
            scheduleDaily(
                id: "lunch_reminder",
                title: "C'est bientôt l'heure du déjeuner",
                body: "Pense à noter ton repas pour suivre tes objectifs nutrition.",
                hour: 12, minute: 15
            )
        }

        // — Hydratation (20h) —
        if modules.contains("nutrition") || modules.isEmpty {
            scheduleDaily(
                id: "water_evening",
                title: "Hydratation",
                body: "Combien d'eau as-tu bu aujourd'hui ? Rappel d'atteindre ton objectif.",
                hour: 20, minute: 0
            )
        }

        // — Avant dîner (19h15) —
        if modules.contains("nutrition") {
            scheduleDaily(
                id: "dinner_reminder",
                title: "Soirée qui approche",
                body: "Pense à noter ton dîner ce soir pour rester dans tes objectifs.",
                hour: 19, minute: 15
            )
        }

        // — Sport (18h si module fitness actif) —
        if modules.contains("fitness") {
            let sportHour = UserDefaults.standard.integer(forKey: "sportHour")
            let h = sportHour > 0 ? sportHour : 18
            scheduleDaily(
                id: "sport_reminder",
                title: "Heure du sport",
                body: "Prépare ta séance. N'oublie pas de me dire comment elle s'est passée.",
                hour: h, minute: 0
            )
        }

        // — Habitudes (20h30) — toujours actif si au moins 1 habitude
        scheduleDaily(
            id: "habits_evening",
            title: "Tes habitudes du jour",
            body: "As-tu complété tes habitudes aujourd'hui ? Quelques minutes peuvent faire la différence.",
            hour: 20, minute: 30
        )

        // — Rituels du soir calés sur l'heure de coucher —
        let bedHour = UserDefaults.standard.integer(forKey: "bedHour")
        let bedMin  = UserDefaults.standard.integer(forKey: "bedMinute")
        let bedTotal = (bedHour > 0 ? bedHour : 23) * 60 + bedMin
        func beforeBed(_ mins: Int) -> Int { ((bedTotal - mins) + 24 * 60) % (24 * 60) }

        // Skincare — 1 h avant le coucher (si l'utilisateur a activé les rappels routine).
        if UserDefaults.standard.bool(forKey: "skincareReminders") {
            let t = beforeBed(60)
            scheduleDaily(
                id: "skincare_evening",
                title: "Skincare du soir ✨",
                body: "Nettoyant + soin avant de dormir — 5 min pour ta peau.",
                hour: t / 60, minute: t % 60
            )
        }

        // Compléments — 30 min avant le coucher (magnésium, zinc, oméga…).
        if modules.contains("nutrition") || modules.contains("fitness") || modules.contains("looks") || modules.isEmpty {
            let t = beforeBed(30)
            scheduleDaily(
                id: "supplements_evening",
                title: "Compléments 💊",
                body: "Avant de dormir : pense à tes compléments du soir (magnésium, oméga…).",
                hour: t / 60, minute: t % 60
            )
        }

        // Préparation au sommeil — 15 min avant (coupe les écrans).
        if modules.contains("sleep") {
            let t = beforeBed(15)
            scheduleDaily(
                id: "bedtime_reminder",
                title: "Bientôt l'heure de dormir 🌙",
                body: "Coupe les écrans, tamise la lumière — prépare une bonne nuit.",
                hour: t / 60, minute: t % 60
            )
        }

        // — Point de mi-journée (13h) : rappel des objectifs du jour —
        scheduleDaily(
            id: "midday_objectives",
            title: "Point de mi-journée 🎯",
            body: "Où en es-tu sur tes objectifs du jour ? Un coup d'œil pour rester sur les rails.",
            hour: 13, minute: 0
        )

        // — Mind / Méditation (8h) —
        if modules.contains("mind") {
            let meditHour = wakeupTotal + 60  // 1h après réveil
            let mh = (meditHour % (24 * 60)) / 60
            let mm = meditHour % 60
            scheduleDaily(
                id: "mind_morning",
                title: "5 minutes de calme",
                body: "Commence ta journée avec une courte séance de respiration ou méditation.",
                hour: mh, minute: mm
            )
        }

        // — Productivité (9h) —
        if modules.contains("productivity") {
            scheduleDaily(
                id: "productivity_morning",
                title: "Ta priorité du jour",
                body: "Quelle est la tâche la plus importante à accomplir aujourd'hui ?",
                hour: 9, minute: 0
            )
>>>>>>> origin/pote
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
            // La notif PMS est planifiée via NotificationManager.scheduleCyclePMS()
        }

        // ── MÉDICAL ───────────────────────────────────────────────────────────
        if mods.contains("medical") {
            if ud.bool(forKey: "medical_med_morning_enabled"),
               enabled("notif_medical_morning_enabled"),
               let h = notifHour("notif_medical_morning_hour") {
                daily(id: "medical_morning",
                      title: "Médicaments du matin",
                      body: "N'oublie pas tes médicaments du matin.",
                      hour: h, minute: 0)
            }
            if ud.bool(forKey: "medical_med_noon_enabled"),
               enabled("notif_medical_noon_enabled"),
               let h = notifHour("notif_medical_noon_hour") {
                daily(id: "medical_noon",
                      title: "Médicaments du midi",
                      body: "N'oublie pas tes médicaments de midi.",
                      hour: h, minute: 0)
            }
            if ud.bool(forKey: "medical_med_evening_enabled"),
               enabled("notif_medical_evening_enabled"),
               let h = notifHour("notif_medical_evening_hour") {
                daily(id: "medical_evening",
                      title: "Médicaments du soir",
                      body: "N'oublie pas tes médicaments du soir.",
                      hour: h, minute: 0)
            }
            if enabled("notif_medical_vitals_enabled"),
               let h = notifHour("notif_medical_vitals_hour") {
                daily(id: "medical_vitals",
                      title: "Mesure tes constantes",
                      body: "Tension, poids, glycémie — prends 2 minutes.",
                      hour: h, minute: 0)
            }
        }

        // ── MOBILITÉ ──────────────────────────────────────────────────────────
        if mods.contains("mobility") {
            if enabled("notif_mobility_departure_enabled"),
               let h = notifHour("notif_mobility_departure_hour") {
                daily(id: "mobility_departure",
                      title: "C'est l'heure de partir",
                      body: "Prépare-toi pour prendre la route.",
                      hour: h, minute: 0)
            }
            if enabled("notif_mobility_fuel_enabled"),
               let wd = intVal("mobility_fuel_weekday"),
               let h = notifHour("notif_mobility_fuel_hour") {
                weekday(id: "mobility_fuel",
                        title: "Rappel carburant",
                        body: "Pense à faire le plein cette semaine.",
                        hour: h, minute: 0, weekday: wd)
            }
        }

        // ── COMPLÉMENTS ALIMENTAIRES (dans nutrition) ─────────────────────────
        if mods.contains("nutrition") && ud.bool(forKey: "nutrition_supplements_enabled") {
            if ud.bool(forKey: "supplement_morning_enabled"),
               enabled("notif_supplement_morning_enabled"),
               let h = notifHour("notif_supplement_morning_hour") {
                daily(id: "supplement_morning",
                      title: "Compléments du matin",
                      body: "Prends tes compléments alimentaires du matin.",
                      hour: h, minute: 0)
            }
            if ud.bool(forKey: "supplement_evening_enabled"),
               enabled("notif_supplement_evening_enabled"),
               let h = notifHour("notif_supplement_evening_hour") {
                daily(id: "supplement_evening",
                      title: "Compléments du soir",
                      body: "Prends tes compléments alimentaires du soir.",
                      hour: h, minute: 0)
            }
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
