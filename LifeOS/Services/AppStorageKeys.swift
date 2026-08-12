import Foundation

/// Registre central des clés `@AppStorage` / `UserDefaults` de LifeOS.
///
/// Objectif : une seule source de vérité pour tous les noms de clés persistées,
/// afin d'éviter les typos et fluidifier les recherches / renommages.
///
/// Migration progressive :
///   ✗ `@AppStorage("appTheme") private var themeRaw = "classic"`
///   ✓ `@AppStorage(AppStorageKeys.appTheme) private var themeRaw = "classic"`
///
/// Règle : **ne JAMAIS changer les valeurs String de cet enum** — elles sont
/// écrites dans le UserDefaults des utilisateurs actuels. Renommer une clé =
/// perdre la donnée. Pour évoluer, créer une nouvelle clé + code de migration.
enum AppStorageKeys {

    // MARK: - Identité / profil
    static let userName = "userName"
    static let userGender = "userGender"
    static let userAge = "userAge"
    static let userHeight = "userHeight"
    static let userHeightCm = "userHeightCm"
    static let userWeight = "userWeight"
    static let userWeightKg = "userWeightKg"
    static let userActivity = "userActivity"
    static let userGoalFit = "userGoalFit"
    static let userHasCycle = "userHasCycle"
    static let userHormonalContext = "userHormonalContext"
    static let lifeProfile = "lifeProfile"

    // MARK: - Forces (1RM)
    static let userBench1RM = "userBench1RM"
    static let userSquat1RM = "userSquat1RM"
    static let userDeadlift1RM = "userDeadlift1RM"
    static let userStrengthLevel = "userStrengthLevel"
    static let userWeeklyFrequency = "userWeeklyFrequency"
    static let userTrainingYears = "userTrainingYears"

    // MARK: - Thème & UI
    static let appTheme = "appTheme"
    static let homeShortcuts = "homeShortcuts"
    static let homeMetrics = "homeMetrics"
    static let hiddenCats = "hiddenCats"
    static let bubbleSize = "bubbleSize"
    static let bubbleImportance = "bubbleImportance"
    static let bubbleWeights = "bubbleWeights"
    static let catAnchors = "catAnchors"
    static let catColors = "catColors"
    static let catLayout = "catLayout"
    static let catOffsets = "catOffsets"
    static let catSizes = "catSizes"
    static let profileHiddenRaw = "profileHiddenRaw"
    static let profilePinnedRaw = "profilePinnedRaw"

    // MARK: - Onboarding / activation
    static let onboardingDone = "onboardingDone"
    static let onboardingGoalsRaw = "onboardingGoalsRaw"
    static let intakeShown = "intakeShown"
    static let tutorialDone = "tutorialDone"
    static let recommendedModules = "recommendedModules"
    static let habitModulesRaw = "habitModulesRaw"
    static let fitnessCoachIntroShown = "fitnessCoachIntroShown"
    static let coachDisclaimerAccepted = "coachDisclaimerAccepted"

    // MARK: - Sommeil / réveil
    static let wakeupHour = "wakeupHour"
    static let wakeupMinute = "wakeupMinute"
    static let wakeupEnabled = "wakeupEnabled"
    static let wakeupMessage = "wakeupMessage"
    static let wakeupRepeatDays = "wakeupRepeatDays"
    static let snoozeMinutes = "snoozeMinutes"
    static let bedHour = "bedHour"
    static let bedMinute = "bedMinute"
    static let sleepGoalHours = "sleepGoalHours"
    static let sleepTargetHours = "sleepTargetHours"
    static let lastSleepHours = "lastSleepHours"
    static let lastSleepQuality = "lastSleepQuality"
    static let windDownEnabled = "windDownEnabled"
    static let windDownHour = "windDownHour"
    static let windDownMinute = "windDownMinute"

    // MARK: - Nutrition
    static let kcalGoal = "kcalGoal"
    static let proteinGoal = "proteinGoal"
    static let carbGoal = "carbGoal"
    static let fatGoal = "fatGoal"
    static let waterGoal = "waterGoal"
    static let glassesGoal = "glassesGoal"
    static let fastTarget = "fastTarget"
    static let dietFlags = "dietFlags"
    static let waterReminder = "waterReminder"

    // MARK: - Fitness
    static let stepGoal = "stepGoal"
    static let sportHour = "sportHour"
    static let gymConfirm = "gymConfirm"
    static let gymReminderHour = "gymReminderHour"
    static let gymReminderMinute = "gymReminderMinute"
    static let gymReminderOn = "gymReminderOn"
    static let gwRestSecs = "gwRestSecs"

    // MARK: - Tabata
    static let tabataWork = "tabataWork"
    static let tabataRest = "tabataRest"
    static let tabCooldown = "tabCooldown"
    static let tabCycles = "tabCycles"
    static let tabPrepare = "tabPrepare"
    static let tabRest = "tabRest"
    static let tabRestCycle = "tabRestCycle"
    static let tabRounds = "tabRounds"
    static let tabSets = "tabSets"
    static let tabWork = "tabWork"

    // MARK: - Productivité / focus
    static let focusMinGoal = "focusMinGoal"
    static let focusLen = "focusLen"
    static let breakLen = "breakLen"
    static let screenGoal = "screenGoal"
    static let screenToday = "screenToday"
    static let socialMaxMin = "socialMaxMin"
    static let dayStart = "dayStart"
    static let dayEnd = "dayEnd"
    static let meditationGoalMin = "meditationGoalMin"

    // MARK: - Looks / skincare
    static let skinType = "skinType"
    static let skinConcernsRaw = "skinConcernsRaw"
    static let skinTreatment = "skinTreatment"
    static let skincareAM = "skincareAM"
    static let skincarePM = "skincarePM"
    static let skincareDoneAM = "skincareDoneAM"
    static let skincareDonePM = "skincareDonePM"
    static let skincareLevel = "skincareLevel"
    static let skincareReminders = "skincareReminders"
    static let hairColor = "hairColor"
    static let hairGoalsRaw = "hairGoalsRaw"
    static let browGoalsRaw = "browGoalsRaw"
    static let groomingRaw = "groomingRaw"
    static let smileGoalsRaw = "smileGoalsRaw"
    static let faceShape = "faceShape"
    static let postureReminder = "postureReminder"

    // MARK: - Cycle
    static let cycleStartDate = "cycleStartDate"
    static let cycleLengthDays = "cycleLengthDays"

    // MARK: - Finance / invest
    static let budgetGoal = "budgetGoal"
    static let fireMonthly = "fireMonthly"
    static let fireReturn = "fireReturn"
    static let fireYears = "fireYears"
    static let fxAmount = "fxAmount"
    static let fxFrom = "fxFrom"
    static let fxTo = "fxTo"
    static let splitMembers = "splitMembers"

    // MARK: - Career / apprentissage
    static let cvContact = "cvContact"
    static let cvEducation = "cvEducation"
    static let cvExperience = "cvExperience"
    static let cvName = "cvName"
    static let cvSkills = "cvSkills"
    static let cvSummary = "cvSummary"
    static let cvTitle = "cvTitle"
    static let skillPlanDone = "skillPlanDone"
    static let skillPlanName = "skillPlanName"
    static let skillPlanSteps = "skillPlanSteps"
    static let langCurrent = "langCurrent"
    static let phraseLang = "phraseLang"
    static let vocabState = "vocabState"
    static let vocabStreak = "vocabStreak"
    static let vocabStreakLast = "vocabStreakLast"

    // MARK: - Voyage / mobilité
    static let mobTrips = "mobTrips"
    static let parkDate = "parkDate"
    static let parkLat = "parkLat"
    static let parkLon = "parkLon"
    static let parkNote = "parkNote"
    static let trackedFlights = "trackedFlights"

    // MARK: - Coach / chat
    static let aiConversationDay = "aiConversationDay"
    static let aiConversationID = "aiConversationID"
    static let aiFirstLaunchDone = "aiFirstLaunchDone"
    static let aiKnownModulesRaw = "aiKnownModulesRaw"
    static let lastBriefingContent = "lastBriefingContent"
    static let lastBriefingDate = "lastBriefingDate"
    static let lastWeeklyBilanDate = "lastWeeklyBilanDate"
    static let lastWeeklyBilanText = "lastWeeklyBilanText"

    // MARK: - Notifications
    static let notifMasterMute = "notifMasterMute"
    static let notifEnabledBedtime = "notifEnabled.bedtime"
    static let notifEnabledHabits = "notifEnabled.habits"
    static let notifEnabledMorning = "notifEnabled.morning"
    static let notifEnabledNutrition = "notifEnabled.nutrition"
    static let notifEnabledSport = "notifEnabled.sport"
    static let notifEnabled = "notifEnabled"
    static let smartNotifsEnabled = "smartNotifsEnabled"
    static let morningReminderOn = "morningReminderOn"
    static let morningReminderText = "morningReminderText"
    static let birthdayRemindersOn = "birthdayRemindersOn"

    // MARK: - Énergie / bilan
    static let todayEnergyScore = "todayEnergyScore"
    static let todayEnergyLabel = "todayEnergyLabel"

    // MARK: - Cloud / secondary
    static let cloudKitEnabled = "cloudKitEnabled"

    // MARK: - Objectifs
    static let goalEndDatesRaw = "goalEndDatesRaw"
    static let hiddenGoalIDsRaw = "hiddenGoalIDsRaw"
}
