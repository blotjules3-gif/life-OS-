import Foundation
import UserNotifications

/// Gestion centralisée des notifications locales (rappels hydratation, coucher, skincare,
/// échéances admin, anniversaires, maintenance, etc.).
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
        } catch {
            // Retry without criticalAlert (requires Apple entitlement)
            return (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Alarme réveil — time-sensitive, perce le mode Ne pas déranger, déclenche l'app au tap.
    func scheduleAlarm(hour: Int, minute: Int, userName: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["lifeos.wakeup", "lifeos.wakeup.preview"]
        )

        // Alarme principale
        let content = UNMutableNotificationContent()
        content.title = "Réveil LifeOS"
        content.body = userName.isEmpty
            ? "C'est l'heure. Lance ta journée."
            : "Bonjour \(userName) ! C'est l'heure."
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "LIFEOS_ALARM"

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "lifeos.wakeup", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        // Preview H-5 min — prépare le widget si l'app est ouverte, sinon montre une bannière
        let previewContent = UNMutableNotificationContent()
        previewContent.title = "Réveil dans 5 minutes"
        previewContent.body = "Ton briefing du matin est prêt."
        previewContent.sound = .default
        previewContent.interruptionLevel = .timeSensitive
        previewContent.categoryIdentifier = "LIFEOS_ALARM"
        previewContent.userInfo = ["type": "wakeup_preview", "alarmHour": hour, "alarmMinute": minute,
                                   "userName": userName]

        var alarmComps = DateComponents()
        alarmComps.hour = hour
        alarmComps.minute = minute
        let alarmDate = Calendar.current.nextDate(after: .now, matching: alarmComps, matchingPolicy: .nextTime) ?? .now
        let previewDate = Calendar.current.date(byAdding: .minute, value: -5, to: alarmDate) ?? alarmDate
        let preComps = Calendar.current.dateComponents([.hour, .minute], from: previewDate)
        let preTrigger = UNCalendarNotificationTrigger(dateMatching: preComps, repeats: true)
        let preRequest = UNNotificationRequest(
            identifier: "lifeos.wakeup.preview",
            content: previewContent,
            trigger: preTrigger
        )
        UNUserNotificationCenter.current().add(preRequest)
    }

    /// Notification ponctuelle à une date précise.
    func schedule(id: String, title: String, body: String, at date: Date) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel quotidien récurrent (ex: hydratation, coucher progressif, mewing).
    func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel quotidien récurrent AVEC boutons d'action (catégorie) + payload.
    /// Sert aux notifs de confirmation « Tu as bien fait X ? → Oui ✓ / Pas encore ».
    func scheduleDailyAction(id: String, title: String, body: String,
                             hour: Int, minute: Int,
                             categoryId: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = userInfo
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel HEBDOMADAIRE un jour de semaine donné (1=Dim … 7=Sam), éventuellement
    /// avec catégorie d'action. Sert au programme de sport (séance du jour).
    func scheduleWeekly(id: String, title: String, body: String,
                        weekday: Int, hour: Int, minute: Int,
                        categoryId: String = "", userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if !categoryId.isEmpty { content.categoryIdentifier = categoryId }
        content.userInfo = userInfo
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel annuel récurrent (anniversaires) — se déclenche chaque année au mois/jour donné.
    func scheduleYearly(id: String, title: String, body: String,
                        month: Int, day: Int, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel après un intervalle (ex: fin de sieste, fenêtre de sommeil léger).
    func scheduleAfter(id: String, title: String, body: String, seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func scheduleWeeklyBilan() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lifeos.weekly_bilan"])
        let content = UNMutableNotificationContent()
        content.title = "Bilan de semaine"
        content.body = "Tes habitudes, ton humeur, tes objectifs — tout est là."
        content.sound = .default
        content.interruptionLevel = .active
        var comps = DateComponents()
        comps.weekday = 1 // dimanche
        comps.hour = 20
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "lifeos.weekly_bilan", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// Planifie les 3 notifications cycle depuis une date de début et une durée.
    func scheduleCycleNotifications(lastPeriodDate: Date, cycleDays: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["lifeos.cycle.period_warning", "lifeos.cycle.ovulation", "lifeos.cycle.pms"]
        )
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: lastPeriodDate)
        let elapsed = cal.dateComponents([.day], from: start, to: today).day ?? 0
        let dayInCycle = (elapsed % cycleDays) + 1
        let daysLeft = cycleDays - (elapsed % cycleDays)

        // Alerte règles J-3
        let periodWarningDate = cal.date(byAdding: .day, value: daysLeft - 3, to: today) ?? today
        if periodWarningDate > today {
            schedule(id: "lifeos.cycle.period_warning",
                     title: "Règles dans 3 jours",
                     body: "Prépare du magnésium et prévois des séances douces cette semaine.",
                     at: cal.date(bySettingHour: 9, minute: 0, second: 0, of: periodWarningDate) ?? periodWarningDate)
        }

        // Fenêtre ovulation (~jour 14)
        let ovulationDay = 14
        let daysToOvulation: Int
        if dayInCycle < ovulationDay {
            daysToOvulation = ovulationDay - dayInCycle
        } else {
            daysToOvulation = cycleDays - dayInCycle + ovulationDay
        }
        let ovulationDate = cal.date(byAdding: .day, value: daysToOvulation, to: today) ?? today
        if ovulationDate > today {
            schedule(id: "lifeos.cycle.ovulation",
                     title: "Fenêtre d'ovulation",
                     body: "Énergie au pic — idéal pour tes séances les plus intenses.",
                     at: cal.date(bySettingHour: 8, minute: 0, second: 0, of: ovulationDate) ?? ovulationDate)
        }

        // Fenêtre SPM (J-7 avant les règles)
        let pmsDate = cal.date(byAdding: .day, value: daysLeft - 7, to: today) ?? today
        if pmsDate > today {
            schedule(id: "lifeos.cycle.pms",
                     title: "Phase lutéale",
                     body: "Ta fenêtre SPM commence — magnésium le soir et séances modérées.",
                     at: cal.date(bySettingHour: 9, minute: 0, second: 0, of: pmsDate) ?? pmsDate)
        }
    }

    func schedulePendingHabitNotification(pendingCount: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lifeos.pending_habits"])
        guard pendingCount > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Habitudes en attente"
        content.body = pendingCount == 1
            ? "1 habitude proposée t'attend."
            : "\(pendingCount) habitudes proposées t'attendent."
        content.sound = .default
        content.interruptionLevel = .active
        // Une seule fois par semaine (lundi 9h) — pas tous les jours
        var comps = DateComponents()
        comps.weekday = 2 // lundi
        comps.hour = 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "lifeos.pending_habits", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
