import Foundation
import SwiftData
import UserNotifications

/// Notifications intelligentes cross-pôles — l'unfair advantage produit.
///
/// Au lieu de rappels génériques (« bois de l'eau », « médite »), on push
/// l'insight le plus pertinent du moment généré par `LifeBrain` — qui croise
/// sommeil × cycle × sport × nutrition × humeur × habitudes.
///
/// Exemple concret : « Nuit courte (5.2h) + jour de sport prévu → allège
/// ta séance et bois +500 ml pour compenser la fatigue. »
///
/// Aucune app concurrente mono-vertical (Fabulous, WHOOP, Strava, MyFitnessPal)
/// ne peut produire ce type de notif — c'est le point de différenciation
/// défendable pour Station F et pour l'App Store.
@MainActor
enum SmartNotifications {

    /// Identifiants uniques pour dédup (une notif par créneau du jour).
    private enum ID: String {
        case morning = "lifeos.smart.morning"    // ~09h
        case midday  = "lifeos.smart.midday"     // ~13h
        case evening = "lifeos.smart.evening"    // ~19h
    }

    /// Clé UserDefaults qui stocke le titre poussé aujourd'hui pour éviter
    /// de re-notifier la même chose 3 fois (matin/midi/soir).
    private static let dedupKey = "lifeos.smart.pushedTitles.today"
    private static let dedupDayKey = "lifeos.smart.pushedTitles.day"

    // MARK: - Point d'entrée

    /// À appeler au launch de l'app + à chaque foreground + par BGAppRefreshTask.
    /// Regénère les 3 notifs du jour à partir de l'état actuel de LifeBrain.
    static func refreshDaily(ctx: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "smartNotifsEnabled") else {
            // Pas encore opt-in — retour silencieux, ne pas poluer par défaut.
            return
        }
        resetDedupIfNewDay()

        let insights = LifeBrain.insights(ctx: ctx)
            .filter { $0.tone != .good || $0.priority > 60 }   // On ne pousse pas juste "tout va bien"
            .prefix(6)                                          // On garde le top 6

        // 3 créneaux ⇒ jusqu'à 3 notifs distinctes, en ordre de priorité.
        var picks: [(id: ID, hour: Int, insight: BrainInsight)] = []
        let slots: [(ID, Int)] = [(.morning, 9), (.midday, 13), (.evening, 19)]
        var alreadyUsed = Set(pushedTitlesToday())
        for (slotID, hour) in slots {
            guard let next = insights.first(where: { !alreadyUsed.contains($0.title) }) else { continue }
            picks.append((slotID, hour, next))
            alreadyUsed.insert(next.title)
        }

        // Nettoie les pending de l'app avant de re-programmer (idempotent).
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [ID.morning.rawValue, ID.midday.rawValue, ID.evening.rawValue]
        )

        for pick in picks {
            schedule(id: pick.id, hour: pick.hour, insight: pick.insight)
            markPushed(title: pick.insight.title)
        }
    }

    /// Toggle exposé aux réglages (ProfileView, NotificationSettingsSheet).
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "smartNotifsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "smartNotifsEnabled") }
    }

    // MARK: - Planif

    private static func schedule(id: ID, hour: Int, insight: BrainInsight) {
        let content = UNMutableNotificationContent()
        content.title = insight.title
        content.body = insight.detail
        content.sound = .default
        // Un insight sommeil/cycle qui recommande de skipper le gym mérite
        // de percer le mode Focus travail. Le reste reste en niveau actif standard.
        content.interruptionLevel = (insight.priority >= 80) ? .timeSensitive : .active
        content.threadIdentifier = "lifeos.smart"
        content.userInfo = [
            "kind": "smart-insight",
            "priority": insight.priority,
            "insightTitle": insight.title
        ]

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        // trigger = repeats false → sera reprogrammé demain par le prochain refresh.
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id.rawValue, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Dedup par jour

    private static func resetDedupIfNewDay() {
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let stored = UserDefaults.standard.double(forKey: dedupDayKey)
        if stored < today {
            UserDefaults.standard.set(today, forKey: dedupDayKey)
            UserDefaults.standard.set([String](), forKey: dedupKey)
        }
    }

    private static func pushedTitlesToday() -> [String] {
        (UserDefaults.standard.array(forKey: dedupKey) as? [String]) ?? []
    }

    private static func markPushed(title: String) {
        var arr = pushedTitlesToday()
        arr.append(title)
        UserDefaults.standard.set(arr, forKey: dedupKey)
    }
}
