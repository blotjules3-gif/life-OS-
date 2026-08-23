import Foundation
import UserNotifications

/// Planifie 2 notifications quotidiennes pour créer un rythme d'engagement
/// coach : bilan du matin (8h) et bilan du soir (21h).
///
/// - Matin : "Bonjour, ton sommeil : Xh. Ton énergie estimée : Y/100."
///   Le contenu est calculé à l'exécution du trigger (via `userInfo` static),
///   la notif système montre un placeholder qui redirige vers le chat où le
///   coach régénère un message complet avec le contexte à jour.
///
/// - Soir : "Récap de ta journée — X habitudes, Y kcal."
///
/// Chaque tap ouvre le chat avec un prefill approprié → le coach répond
/// avec toutes les données actuelles (pas un texte figé de la veille).
///
/// Anti-spam : reconfigure à chaque appel de `scheduleAll` (idempotent, iOS
/// remplace les notifications avec le même identifier).
@MainActor
enum CoachDailyBilan {

    private static let morningID = "coach.bilan.morning"
    private static let eveningID = "coach.bilan.evening"

    /// Planifie les 2 notifs répétitives. À appeler au boot (LifeOSApp) et
    /// après un changement des préférences de rappel.
    static func scheduleAll() {
        scheduleMorning()
        scheduleEvening()
    }

    /// Retire les 2 notifs — utilisé si l'user désactive les bilans.
    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [morningID, eveningID]
        )
    }

    // MARK: - Notifications

    private static func scheduleMorning() {
        let content = UNMutableNotificationContent()
        content.title = "Ton bilan du matin"
        content.body = "Ouvre le chat pour voir ton sommeil et ton énergie du jour."
        content.sound = .default
        content.threadIdentifier = "coach.bilan"
        content.userInfo = [
            "lifeos.deeplink": "lifeos://coach?prefill=Fais%20le%20bilan%20de%20ma%20nuit%20et%20suggère-moi%20une%20priorité%20pour%20aujourd%27hui.",
            "lifeos.signal": "daily_morning"
        ]

        var comps = DateComponents()
        comps.hour = 8
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: morningID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func scheduleEvening() {
        let content = UNMutableNotificationContent()
        content.title = "Ton récap du soir"
        content.body = "Comment s'est passée ta journée ? On fait le point ?"
        content.sound = .default
        content.threadIdentifier = "coach.bilan"
        content.userInfo = [
            "lifeos.deeplink": "lifeos://coach?prefill=Fais%20le%20récap%20de%20ma%20journée%20:%20habitudes%2C%20énergie%2C%20progrès.",
            "lifeos.signal": "daily_evening"
        ]

        var comps = DateComponents()
        comps.hour = 21
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
