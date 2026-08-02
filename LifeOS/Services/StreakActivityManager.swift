import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Contrôle du cycle de vie de la Live Activity « Streak habitude ».
///
/// À appeler après un check d'habitude qui atteint un milestone :
///
/// ```
/// StreakActivityManager.startIfMilestone(
///     habitName: "Méditer 10 min",
///     iconName: "figure.mind.and.body",
///     streakDays: 30,
///     doneToday: true
/// )
/// ```
///
/// Le manager n'affiche la Live Activity que si `streakDays` atteint 7, 14,
/// 30 ou 100 — les paliers qui méritent une célébration. Elle disparaît
/// automatiquement le lendemain (dismissalPolicy `.after`).
@MainActor
enum StreakActivityManager {

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    static func startIfMilestone(habitName: String, iconName: String, streakDays: Int, doneToday: Bool) {
        guard let milestone = milestoneFor(streakDays) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Une seule Live Activity Streak à la fois — on end l'ancienne si existante.
        Task { await endAll() }

        let attrs = StreakAttributes(habitName: habitName, iconName: iconName)
        let content = StreakAttributes.ContentState(
            streakDays: streakDays,
            doneToday: doneToday,
            milestone: milestone
        )

        do {
            _ = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: content, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Silencieux — l'user n'a pas besoin d'un message d'erreur pour une célébration.
        }
    }

    @available(iOS 16.1, *)
    static func update(streakDays: Int, doneToday: Bool) async {
        for activity in Activity<StreakAttributes>.activities {
            let newState = StreakAttributes.ContentState(
                streakDays: streakDays,
                doneToday: doneToday,
                milestone: milestoneFor(streakDays)
            )
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    @available(iOS 16.1, *)
    static func endAll() async {
        for activity in Activity<StreakAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }
    #endif

    // MARK: - Milestones

    private static func milestoneFor(_ days: Int) -> StreakAttributes.ContentState.Milestone? {
        switch days {
        case 7:   return .week
        case 14:  return .twoWeeks
        case 30:  return .month
        case 100: return .hundred
        default:  return nil
        }
    }
}
