import Foundation
import UserNotifications

// Détecte le décrochage utilisateur et répond sans culpabiliser — toujours simplifier.

final class EngagementTracker {
    static let shared = EngagementTracker()
    private init() {}

    private let lastOpenKey       = "lifeos.engagement.lastOpen"
    private let consecutiveKey    = "lifeos.engagement.consecutive"
    private let totalDaysKey      = "lifeos.engagement.totalDays"
    private let reengagedKey      = "lifeos.engagement.reengaged"

    // Appelé à chaque ouverture de l'app (foreground)
    func recordOpen() {
        let now = Date()
        let lastOpen = UserDefaults.standard.object(forKey: lastOpenKey) as? Date

        var consecutive = UserDefaults.standard.integer(forKey: consecutiveKey)
        var totalDays   = UserDefaults.standard.integer(forKey: totalDaysKey)

        if let last = lastOpen {
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: last, to: now).day ?? 0
            if days == 0 {
                // Même jour — rien à incrémenter
            } else if days == 1 {
                consecutive += 1
                totalDays   += 1
            } else {
                // Absence détectée
                consecutive = 1
                totalDays  += 1
                scheduleReengagementIfNeeded(daysMissed: days)
            }
        } else {
            consecutive = 1
            totalDays   = 1
        }

        UserDefaults.standard.set(now,        forKey: lastOpenKey)
        UserDefaults.standard.set(consecutive, forKey: consecutiveKey)
        UserDefaults.standard.set(totalDays,   forKey: totalDaysKey)

        // Annule toute notif de relance programmée — l'utilisateur est revenu
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["lifeos.reengage.day3", "lifeos.reengage.day7"]
        )
    }

    // Nombre de jours depuis la dernière ouverture (0 = aujourd'hui)
    var daysSinceLastOpen: Int {
        guard let last = UserDefaults.standard.object(forKey: lastOpenKey) as? Date else { return 0 }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
    }

    var consecutiveDays: Int { UserDefaults.standard.integer(forKey: consecutiveKey) }
    var totalDays: Int       { UserDefaults.standard.integer(forKey: totalDaysKey) }

    // Message de retour adapté — jamais culpabilisant
    var reengagementMessage: String? {
        let days = daysSinceLastOpen
        guard days >= 2 else { return nil }
        switch days {
        case 2:  return "Ça fait 2 jours. Pas de rattrapage — on reprend là où tu en es."
        case 3:  return "3 jours d'absence. L'important c'est de revenir, pas de tout refaire."
        case 4, 5: return "Ça fait \(days) jours. Commence par une seule chose aujourd'hui."
        case 6, 7: return "Une semaine. Zéro pression — qu'est-ce qui t'a bloqué ? Je peux adapter."
        default:   return "Bienvenue de retour. On recommence doucement, à ton rythme."
        }
    }

    // Suggestion d'action simple quand l'utilisateur revient
    var simplificationSuggestion: String? {
        let days = daysSinceLastOpen
        guard days >= 3 else { return nil }
        if days >= 7 {
            return "Si tu as moins de 4 habitudes actives, tu tiendras mieux sur la durée."
        }
        return "Commence par valider une seule habitude aujourd'hui."
    }

    // MARK: - Private

    private func scheduleReengagementIfNeeded(daysMissed: Int) {
        guard daysMissed >= 2 else { return }

        // J+3 : notification douce
        scheduleLocal(
            id: "lifeos.reengage.day3",
            title: "Tu nous manques",
            body: "Ça fait quelques jours. Pas besoin de tout rattraper — juste une minute suffit.",
            delayDays: 1
        )

        // J+7 : si toujours absent, proposer de simplifier
        if daysMissed >= 5 {
            scheduleLocal(
                id: "lifeos.reengage.day7",
                title: "On s'adapte à toi",
                body: "L'objectif c'est de durer, pas de tout faire. Reviens à ton rythme.",
                delayDays: 2
            )
        }
    }

    private func scheduleLocal(id: String, title: String, body: String, delayDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.interruptionLevel = .passive  // discret

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(delayDays * 86400),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
