import Foundation

/// Registre central des clés `@AppStorage` utilisées à travers l'app.
///
/// Pourquoi : avant, la même clé (par exemple "appTheme") était ré-écrite littéralement
/// dans 11 fichiers. Un typo → un bug silencieux. Renommer → 11 refactos manuels.
///
/// Usage :
/// ```swift
/// @AppStorage(AppStorageKeys.appTheme) private var themeRaw = "classic"
/// @AppStorage(AppStorageKeys.userWeightKg) private var weight: Double = 0
/// ```
///
/// Règle : toute nouvelle clé `@AppStorage` doit passer par ce registre.
enum AppStorageKeys {

    // MARK: - Identité & profil
    static let userName            = "userName"
    static let userGender          = "userGender"
    static let userLifeProfile     = "lifeProfile"
    static let userHasCycle        = "userHasCycle"
    static let appTheme            = "appTheme"

    // MARK: - Profil sportif (fitness)
    static let userWeightKg        = "userWeightKg"
    static let userHeightCm        = "userHeightCm"
    static let userStrengthLevel   = "userStrengthLevel"
    static let userBench1RM        = "userBench1RM"
    static let userSquat1RM        = "userSquat1RM"
    static let userDeadlift1RM     = "userDeadlift1RM"
    static let userTrainingYears   = "userTrainingYears"
    static let userWeeklyFrequency = "userWeeklyFrequency"

    // MARK: - Objectifs quotidiens
    static let stepGoal            = "stepGoal"
    static let waterGoal           = "waterGoal"
    static let kcalGoal            = "kcalGoal"
    static let proteinGoal         = "proteinGoal"
    static let glassesGoal         = "glassesGoal"
    static let focusMinGoal        = "focusMinGoal"
    static let socialMaxMin        = "socialMaxMin"
    static let budgetGoal          = "budgetGoal"
    static let fastTarget          = "fastTarget"

    // MARK: - Réveil / sommeil
    static let wakeupEnabled       = "wakeupEnabled"
    static let wakeupHour          = "wakeupHour"
    static let wakeupMinute        = "wakeupMinute"
    static let bedHour             = "bedHour"
    static let bedMinute           = "bedMinute"
    static let sportHour           = "sportHour"

    // MARK: - Modules & UI
    static let recommendedModules  = "recommendedModules"
    static let activeModules       = "activeModules"
    static let profileHiddenRaw    = "profileHiddenRaw"
    static let profilePinnedRaw    = "profilePinnedRaw"
    static let hiddenGoalIDsRaw    = "hiddenGoalIDsRaw"
    static let goalEndDatesRaw     = "goalEndDatesRaw"

    // MARK: - Coach
    static let fitnessCoachIntroShown = "fitnessCoachIntroShown"

    // MARK: - Sommeil / énergie live
    static let lastSleepHours      = "lastSleepHours"
    static let lastSleepQuality    = "lastSleepQuality"
    static let todayEnergyScore    = "todayEnergyScore"
}
