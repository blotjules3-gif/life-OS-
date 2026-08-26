import Foundation
import UserNotifications

/// Planifie les notifications système pour un `CustomReminder` selon sa
/// fréquence (daily / everyXHours / multipleTimes), sa fenêtre horaire et
/// ses jours actifs.
///
/// **Contraintes iOS** : max 64 notifications en attente au total sur l'app.
/// Un rappel `everyXHours` de 8h à 20h × 7 jours = 6 heures × 7 = 42 notifs
/// juste pour lui. Le scheduler cap à 40 notifs max par rappel + priorise
/// les jours actifs.
///
/// **Identifier pattern** : `custom.<uuid>.<weekday>.<hour>` pour chaque
/// occurrence — `cancel()` retire toutes les variantes d'un rappel.
@MainActor
enum SmartReminderScheduler {

    /// Cap global par rappel (protection quota iOS 64).
    private static let maxNotifsPerReminder = 40

    /// Retire toutes les notifs existantes pour ce rappel + reprogramme selon
    /// sa config actuelle. À appeler après create/update/toggle.
    static func reschedule(_ reminder: CustomReminder) {
        cancel(reminder)
        guard reminder.enabled else { return }

        // Vérif master mute
        let muted = UserDefaults.standard.bool(forKey: "notifMasterMute")
        guard !muted else { return }

        let ids = plannedIdentifiers(for: reminder)
        let title = reminder.title.isEmpty ? "Rappel" : reminder.title
        let body = reminder.message.isEmpty ? "C'est l'heure !" : reminder.message

        for spec in ids.prefix(maxNotifsPerReminder) {
            schedule(id: spec.identifier,
                     title: title,
                     body: body,
                     weekday: spec.calendarWeekday,
                     hour: spec.hour,
                     minute: spec.minute)
        }

        // Confirmation +90min si activée (uniquement pour daily — sinon spam)
        if reminder.confirm && reminder.frequency == .daily {
            let total = reminder.hour * 60 + reminder.minute + 90
            NotificationManager.shared.scheduleDailyAction(
                id: baseIdentifier(reminder) + ".confirm",
                title: "Petite vérif",
                body: "Tu as bien fait : \(title) ?",
                hour: (total / 60) % 24, minute: total % 60,
                categoryId: "LIFEOS_CONFIRM",
                userInfo: ["confirmKey": baseIdentifier(reminder), "confirmLabel": title]
            )
        }
    }

    /// Retire toutes les notifs planifiées pour ce rappel. Idempotent.
    static func cancel(_ reminder: CustomReminder) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let prefix = baseIdentifier(reminder)
            let toCancel = requests
                .map(\.identifier)
                .filter { $0 == prefix || $0.hasPrefix(prefix + ".") }
            if !toCancel.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toCancel)
            }
        }
    }

    /// Reschedule tous les rappels actifs — utile après un master mute off ou
    /// un changement de fuseau horaire.
    static func rescheduleAll(_ reminders: [CustomReminder]) {
        for r in reminders { reschedule(r) }
    }

    // MARK: - Planning

    struct NotifSpec {
        let identifier: String
        let calendarWeekday: Int   // 1=Dim ... 7=Sam
        let hour: Int
        let minute: Int
    }

    /// Retourne tous les couples (weekday, hour) que ce rappel devrait
    /// déclencher selon sa fréquence + fenêtre + jours actifs.
    static func plannedIdentifiers(for r: CustomReminder) -> [NotifSpec] {
        let base = baseIdentifier(r)
        let activeWeekdayIndices = (0...6).filter { WeekdayMask.isActive(r.weekdayMask, weekdayIndex: $0) }
        guard !activeWeekdayIndices.isEmpty else { return [] }

        let hours = plannedHours(for: r)
        guard !hours.isEmpty else { return [] }

        var specs: [NotifSpec] = []
        for weekdayIdx in activeWeekdayIndices {
            let calendarWeekday = WeekdayMask.calendarWeekdayFromIndex(weekdayIdx)
            for hm in hours {
                let id = "\(base).\(calendarWeekday).\(hm.hour).\(hm.minute)"
                specs.append(NotifSpec(
                    identifier: id,
                    calendarWeekday: calendarWeekday,
                    hour: hm.hour,
                    minute: hm.minute
                ))
            }
        }
        return specs
    }

    /// Calcule la liste des couples (hour, minute) selon la fréquence.
    private static func plannedHours(for r: CustomReminder) -> [(hour: Int, minute: Int)] {
        switch r.frequency {
        case .daily:
            return [(r.hour, r.minute)]

        case .everyXHours:
            let interval = max(1, min(12, r.intervalHours))
            let start = max(0, min(23, r.windowStartHour))
            let end = max(start, min(23, r.windowEndHour))
            var out: [(Int, Int)] = []
            var h = start
            while h <= end {
                out.append((h, 0))
                h += interval
            }
            return out

        case .multipleTimes:
            return r.specificHours.map { ($0, 0) }
        }
    }

    /// Prefix identifier pour matcher toutes les notifs d'un rappel.
    /// Utilise `stableID` (UUID persisté) — pas `persistentModelID.hashValue`
    /// qui n'est PAS stable entre relaunches Swift (fix B1 audit Loop 22).
    ///
    /// F03 audit forensique — pour les rappels créés AVANT Loop 22 (donc sans
    /// `stableID` persisté en storage), on assigne + persiste à la première
    /// lecture pour éviter la génération d'un nouveau UUID à chaque relaunch.
    static func baseIdentifier(_ r: CustomReminder) -> String {
        if r.stableID.isEmpty {
            r.stableID = UUID().uuidString
            try? r.modelContext?.save()
        }
        return "custom.\(r.stableID)"
    }

    // MARK: - Low-level schedule

    private static func schedule(id: String, title: String, body: String,
                                 weekday: Int, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
