import Foundation
import UserNotifications

/// Gestion centralisée des notifications locales (rappels hydratation, coucher, skincare,
/// échéances admin, anniversaires, maintenance, etc.).
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async -> Bool {
        #if DEBUG
        // Verification visuelle : l'alerte systeme assombrit tout l'ecran et rend le
        // rendu injugeable. Le garde est ICI et pas chez les appelants parce qu'il y en
        // a six, et en oublier un suffit a faire revenir l'alerte. Absent en Release.
        // Les noms de drapeaux vivent dans DebugLaunchFlags, un seul endroit.
        if DebugLaunchFlags.suppressesPermissionPrompts { return false }
        #endif
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
        } catch {
            // Retry without criticalAlert (requires Apple entitlement)
            return (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Identifiants du réveil. `lifeos.wakeup` reste celui du cas « tous les jours »,
    /// celui que le délégué de notifications reconnaît pour lancer l'écran de sonnerie.
    static let alarmBaseID = "lifeos.wakeup"
    static let alarmPreviewID = "lifeos.wakeup.preview"
    static let alarmSnoozeID = "lifeos.wakeup.snooze"
    static let alarmDayPrefix = "lifeos.wakeup.day"
    static let alarmPreviewDayPrefix = "lifeos.wakeup.preview.day"

    /// Un déclencheur du réveil : la sonnerie et sa notification « dans 5 minutes ».
    struct AlarmSlot: Equatable {
        let id: String
        let previewID: String
        let alarm: DateComponents
        let preview: DateComponents
    }

    /// Tous les identifiants que le réveil peut poser, pour tout annuler d'un coup.
    static var allAlarmIDs: [String] {
        [alarmBaseID, alarmPreviewID]
            + (1...7).map { "\(alarmDayPrefix)\($0)" }
            + (1...7).map { "\(alarmPreviewDayPrefix)\($0)" }
    }

    /// Jours stockés lundi = 1 … dimanche = 7 (format de WakeUpView). Sans valeur
    /// enregistrée, l'écran affiche tous les jours actifs: même défaut ici.
    static func storedWakeupDays(_ ud: UserDefaults = .standard) -> Set<Int> {
        let raw = ud.string(forKey: AppStorageKeys.wakeupRepeatDays) ?? "1,2,3,4,5,6,7"
        return Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
    }

    /// Calcule les déclencheurs. Avant, seuls heure + minute étaient programmés en
    /// répétition quotidienne: le réveil sonnait aussi les jours désactivés. Ici un
    /// déclencheur hebdomadaire par jour choisi (weekday Calendar: 1 = dimanche).
    static func alarmSlots(hour: Int, minute: Int, mondayBasedDays days: Set<Int>) -> [AlarmSlot] {
        let valid = days.filter { (1...7).contains($0) }
        guard !valid.isEmpty else { return [] }
        // Préavis 5 min avant; s'il passe avant minuit, il tombe la veille.
        var previewTotal = hour * 60 + minute - 5
        let previewIsDayBefore = previewTotal < 0
        if previewIsDayBefore { previewTotal += 24 * 60 }
        let pHour = previewTotal / 60, pMinute = previewTotal % 60

        if valid.count == 7 {
            return [AlarmSlot(id: alarmBaseID, previewID: alarmPreviewID,
                              alarm: DateComponents(hour: hour, minute: minute),
                              preview: DateComponents(hour: pHour, minute: pMinute))]
        }
        return valid.sorted().map { d in
            let weekday = d % 7 + 1                       // lun 1 → 2 … dim 7 → 1
            let previewWeekday = previewIsDayBefore ? (weekday + 5) % 7 + 1 : weekday
            return AlarmSlot(id: "\(alarmDayPrefix)\(d)", previewID: "\(alarmPreviewDayPrefix)\(d)",
                             alarm: DateComponents(hour: hour, minute: minute, weekday: weekday),
                             preview: DateComponents(hour: pHour, minute: pMinute, weekday: previewWeekday))
        }
    }

    /// Alarme réveil — time-sensitive, perce le mode Ne pas déranger, déclenche l'app au tap.
    /// `days` nil = jours enregistrés par l'écran Réveil (les autres appelants ne les passent pas).
    func scheduleAlarm(hour: Int, minute: Int, userName: String, days: Set<Int>? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.allAlarmIDs)

        for slot in Self.alarmSlots(hour: hour, minute: minute, mondayBasedDays: days ?? Self.storedWakeupDays()) {
            // Alarme principale
            let content = UNMutableNotificationContent()
            content.title = "Réveil LifeOS"
            content.body = userName.isEmpty
                ? "C'est l'heure. Lance ta journée."
                : "Bonjour \(userName) ! C'est l'heure."
            content.sound = .defaultCritical
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = "LIFEOS_ALARM"
            let trigger = UNCalendarNotificationTrigger(dateMatching: slot.alarm, repeats: true)
            center.add(UNNotificationRequest(identifier: slot.id, content: content, trigger: trigger))

            // Preview H-5 min — prépare le widget si l'app est ouverte, sinon montre une bannière
            let previewContent = UNMutableNotificationContent()
            previewContent.title = "Réveil dans 5 minutes"
            previewContent.body = "Ton briefing du matin est prêt."
            previewContent.sound = .default
            previewContent.interruptionLevel = .timeSensitive
            previewContent.categoryIdentifier = "LIFEOS_ALARM"
            previewContent.userInfo = ["type": "wakeup_preview", "alarmHour": hour, "alarmMinute": minute,
                                       "userName": userName]
            let preTrigger = UNCalendarNotificationTrigger(dateMatching: slot.preview, repeats: true)
            center.add(UNNotificationRequest(identifier: slot.previewID, content: previewContent, trigger: preTrigger))
        }
    }

    /// Couper le réveil: sonnerie, préavis « dans 5 minutes » et rappel de snooze.
    /// Avant, seul `lifeos.wakeup` était annulé et le préavis revenait chaque jour.
    func cancelAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.allAlarmIDs + [Self.alarmSnoozeID]
        )
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

    /// Planifie des rappels quotidiens bornés dans le temps jusqu'à une date de fin précise.
    func scheduleBoundedDaily(idPrefix: String, title: String, body: String, hour: Int, minute: Int, startDate: Date = Date(), endDate: Date, maxDays: Int = 30) {
        let cal = Calendar.current
        var current = max(cal.startOfDay(for: startDate), cal.startOfDay(for: Date()))
        let limit = min(cal.startOfDay(for: endDate), cal.date(byAdding: .day, value: maxDays, to: Date()) ?? endDate)
        var dayIndex = 0
        while current <= limit && dayIndex < maxDays {
            var comps = cal.dateComponents([.year, .month, .day], from: current)
            comps.hour = hour
            comps.minute = minute
            if let scheduledDate = cal.date(from: comps), scheduledDate > Date() {
                schedule(id: "\(idPrefix).d\(dayIndex)", title: title, body: body, at: scheduledDate)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
            dayIndex += 1
        }
    }

    func cancel(id: String) {
        // Couper « lifeos.wakeup » = couper tout le réveil (jours, préavis, snooze):
        // ProfileView appelle encore cancel(id:) avec cet identifiant.
        if id == Self.alarmBaseID { cancelAlarm(); return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Annule toutes les notifications en attente dont l'identifiant commence par un préfixe donné.
    func cancelWithPrefix(_ prefix: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let idsToRemove = requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
            if !idsToRemove.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: idsToRemove)
            }
        }
    }

    /// Remplace, dans l'ORDRE, toutes les notifications d'un prefixe.
    ///
    /// Avant: `cancelWithPrefix` (asynchrone) puis creation immediate avec les
    /// memes identifiants. Le rappel de suppression pouvait passer APRES la
    /// creation et effacer les nouveaux rappels. Ici on attend la liste, on
    /// retire, puis on ajoute.
    func replacePending(prefix: String, with requests: [UNNotificationRequest]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for r in requests {
            do { try await center.add(r) }
            catch { AppLog.general.error("rappel non pose \(r.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
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

        // Fenêtre ovulation : 14 jours avant les règles (phase lutéale fixe), pas le jour 14.
        let ovulationDay = CycleMath.ovulationDay(length: cycleDays)
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
