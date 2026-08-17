import XCTest
@testable import LifeOS

final class AppStorageKeysTests: XCTestCase {

    /// Garantit qu'aucune clé n'est renommée par erreur — les valeurs
    /// String sont écrites dans les UserDefaults des utilisateurs existants,
    /// un renommage = perte de donnée.
    ///
    /// Ce test est un snapshot : si une clé est renommée volontairement,
    /// il faut ajouter le nouveau nom ici ET écrire du code de migration.
    func testCriticalKeys_matchExpectedStringValues() {
        XCTAssertEqual(AppStorageKeys.appTheme, "appTheme")
        XCTAssertEqual(AppStorageKeys.userName, "userName")
        XCTAssertEqual(AppStorageKeys.userGender, "userGender")
        XCTAssertEqual(AppStorageKeys.onboardingDone, "onboardingDone")
        XCTAssertEqual(AppStorageKeys.recommendedModules, "recommendedModules")
        XCTAssertEqual(AppStorageKeys.wakeupHour, "wakeupHour")
        XCTAssertEqual(AppStorageKeys.wakeupMinute, "wakeupMinute")
        XCTAssertEqual(AppStorageKeys.kcalGoal, "kcalGoal")
        XCTAssertEqual(AppStorageKeys.waterGoal, "waterGoal")
        XCTAssertEqual(AppStorageKeys.stepGoal, "stepGoal")
        XCTAssertEqual(AppStorageKeys.cloudKitEnabled, "cloudKitEnabled")
        XCTAssertEqual(AppStorageKeys.userBench1RM, "userBench1RM")
        XCTAssertEqual(AppStorageKeys.userSquat1RM, "userSquat1RM")
        XCTAssertEqual(AppStorageKeys.userDeadlift1RM, "userDeadlift1RM")
    }

    /// Vérifie que les clés notifs avec point (`notifEnabled.bedtime`) sont
    /// bien préservées telles quelles (format spécial hérité).
    func testNotificationKeys_preservedWithDots() {
        XCTAssertEqual(AppStorageKeys.notifEnabledBedtime, "notifEnabled.bedtime")
        XCTAssertEqual(AppStorageKeys.notifEnabledHabits, "notifEnabled.habits")
        XCTAssertEqual(AppStorageKeys.notifEnabledMorning, "notifEnabled.morning")
        XCTAssertEqual(AppStorageKeys.notifEnabledNutrition, "notifEnabled.nutrition")
        XCTAssertEqual(AppStorageKeys.notifEnabledSport, "notifEnabled.sport")
    }
}
