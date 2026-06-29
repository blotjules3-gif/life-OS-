import Foundation
import UserNotifications

// Propose chaque semaine un nouveau module pertinent pour l'utilisateur.

final class WeeklyModuleSuggester {
    static let shared = WeeklyModuleSuggester()
    private init() {}

    private let lastDateKey      = "lifeos.weekly.lastSuggestionDate"
    private let suggestedKey     = "lifeos.weekly.suggestedModule"
    private let dismissedKey     = "lifeos.weekly.dismissedModules"

    // Appeler à chaque ouverture de l'app. Retourne nil si pas encore le moment.
    func currentSuggestion() -> AppCategory? {
        guard shouldSuggest() else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: suggestedKey),
              let cat = AppCategory(rawValue: raw) else {
            refreshSuggestion()
            return UserDefaults.standard.string(forKey: suggestedKey).flatMap { AppCategory(rawValue: $0) }
        }
        return cat
    }

    func dismiss(_ module: AppCategory) {
        var dismissed = dismissedModules()
        dismissed.insert(module.rawValue)
        UserDefaults.standard.set(Array(dismissed), forKey: dismissedKey)
        UserDefaults.standard.removeObject(forKey: suggestedKey)
        UserDefaults.standard.set(Date(), forKey: lastDateKey)
    }

    func accept(_ module: AppCategory) {
        // Ajouter le module aux modules recommandés
        var active = activeModules()
        active.insert(module.rawValue)
        UserDefaults.standard.set(Array(active).joined(separator: ","), forKey: "recommendedModules")
        UserDefaults.standard.removeObject(forKey: suggestedKey)
        UserDefaults.standard.set(Date(), forKey: lastDateKey)
        ContextualNotifications.shared.reschedule()
    }

    func scheduleWeeklyNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Nouveau module ?"
        if let title = suggestion()?.title, !title.isEmpty {
            content.body = "Et si tu explorais « \(title) » cette semaine ?"
        } else {
            content.body = "Tu veux ajouter un nouvel aspect à ta vie cette semaine ?"
        }
        content.sound = .default
        content.interruptionLevel = .passive

        // Chaque lundi à 10h (décalé par rapport aux pending_habits à 9h — évite la collision)
        var comps = DateComponents()
        comps.weekday = 2  // Lundi
        comps.hour = 10
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "lifeos.weekly.module",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Private

    private func shouldSuggest() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastDateKey) as? Date else {
            refreshSuggestion()
            return true
        }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if days >= 7 { refreshSuggestion(); return true }
        return UserDefaults.standard.string(forKey: suggestedKey) != nil
    }

    private func refreshSuggestion() {
        let active    = activeModules()
        let dismissed = dismissedModules()
        let profile   = LifeProfile(rawValue: UserDefaults.standard.string(forKey: "lifeProfile") ?? "")

        // Priorité 1 : modules du profil pas encore actifs
        var candidates = (profile?.priorityModules ?? [])
            .filter { !active.contains($0.rawValue) && !dismissed.contains($0.rawValue) }

        // Priorité 2 : autres modules non actifs, non rejetés
        if candidates.isEmpty {
            candidates = AppCategory.allCases
                .filter { !active.contains($0.rawValue) && !dismissed.contains($0.rawValue) && $0 != .cycle }
        }

        if let pick = candidates.first {
            UserDefaults.standard.set(pick.rawValue, forKey: suggestedKey)
            UserDefaults.standard.set(Date(), forKey: lastDateKey)
        }
    }

    private func suggestion() -> AppCategory? {
        UserDefaults.standard.string(forKey: suggestedKey).flatMap { AppCategory(rawValue: $0) }
    }

    private func activeModules() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: "recommendedModules") ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    private func dismissedModules() -> Set<String> {
        let arr = UserDefaults.standard.array(forKey: dismissedKey) as? [String] ?? []
        return Set(arr)
    }
}
