// Source de vérité pour toutes les clés UserDefaults/@AppStorage de l'app.
// Utiliser ces constantes partout plutôt que des strings littérales.
enum UDKey {
    // MARK: - Profil utilisateur
    static let userName = "userName"
    static let userGender = "userGender"
    static let userHasCycle = "userHasCycle"
    static let userHormonalContext = "userHormonalContext"
    static let onboardingDone = "onboardingDone"
    static let onboardingGoalsRaw = "onboardingGoalsRaw"
    static let appTheme = "appTheme"

    // MARK: - Objectifs santé
    static let kcalGoal = "kcalGoal"
    static let waterGoal = "waterGoal"
    static let stepGoal = "stepGoal"
    static let proteinGoal = "proteinGoal"
    static let carbGoal = "carbGoal"
    static let fatGoal = "fatGoal"
    static let glassesGoal = "glassesGoal"
    static let screenGoal = "screenGoal"
    static let budgetGoal = "budgetGoal"
    static let fastTarget = "fastTarget"

    // MARK: - Réveil & sommeil
    static let wakeupEnabled = "wakeupEnabled"
    static let wakeupHour = "wakeupHour"
    static let wakeupMinute = "wakeupMinute"
    static let wakeupMessage = "wakeupMessage"
    static let wakeupRepeatDays = "wakeupRepeatDays"
    static let snoozeMinutes = "snoozeMinutes"
    static let windDownEnabled = "windDownEnabled"
    static let windDownHour = "windDownHour"
    static let windDownMinute = "windDownMinute"
    static let bedHour = "bedHour"
    static let bedMinute = "bedMinute"
    static let lastSleepQuality = "lastSleepQuality"
    static let lastSleepHours = "lastSleepHours"

    // MARK: - Modules
    static let recommendedModules = "recommendedModules"
    static let habitModulesRaw = "habitModulesRaw"
    static let hiddenCats = "hiddenCats"
    static let catLayout = "catLayout"
    static let catAnchors = "catAnchors"
    static let catOffsets = "catOffsets"
    static let catSizes = "catSizes"
    static let bubbleImportance = "bubbleImportance"
    static let bubbleSize = "bubbleSize"
    static let bubbleWeights = "bubbleWeights"

    // MARK: - IA
    static let aiConversationID = "aiConversationID"
    static let aiFirstLaunchDone = "aiFirstLaunchDone"
    static let aiKnownModulesRaw = "aiKnownModulesRaw"

    // MARK: - Énergie & briefing
    static let todayEnergyScore = "todayEnergyScore"
    static let todayEnergyLabel = "todayEnergyLabel"
    static let lastBriefingDate = "lastBriefingDate"
    static let lastBriefingContent = "lastBriefingContent"
    static let lastWeeklyBilanDate = "lastWeeklyBilanDate"
    static let lastWeeklyBilanText = "lastWeeklyBilanText"

    // MARK: - Notifications
    static let notifMasterMute = "notifMasterMute"
    static let morningReminderOn = "morningReminderOn"
    static let morningReminderText = "morningReminderText"
    static let waterReminder = "waterReminder"
    static let postureReminder = "postureReminder"
    static let gymReminderOn = "gymReminderOn"
    static let gymReminderHour = "gymReminderHour"
    static let gymReminderMinute = "gymReminderMinute"
    static let gymConfirm = "gymConfirm"
    static let birthdayRemindersOn = "birthdayRemindersOn"
    static let sportHour = "sportHour"

    // MARK: - UI / Navigation
    static let homeShortcuts = "homeShortcuts"
    static let profileHiddenRaw = "profileHiddenRaw"
    static let profilePinnedRaw = "profilePinnedRaw"
    static let hiddenGoalIDsRaw = "hiddenGoalIDsRaw"
    static let tabCooldown = "tabCooldown"

    // MARK: - Finance & investissement
    static let fireYears = "fireYears"
    static let fireReturn = "fireReturn"
    static let fireMonthly = "fireMonthly"
    static let fxAmount = "fxAmount"
    static let fxFrom = "fxFrom"
    static let fxTo = "fxTo"
    static let splitMembers = "splitMembers"

    // MARK: - Crypto
    static let cryptoWatchlist = "crypto_watchlist"
    static let cryptoPortfolio = "crypto_portfolio"
    static let cryptoAlerts = "crypto_alerts"

    // MARK: - Sport / Productivité
    static let focusLen = "focusLen"
    static let focusMinGoal = "focusMinGoal"
    static let breakLen = "breakLen"
    static let dayStart = "dayStart"
    static let dayEnd = "dayEnd"
    static let screenToday = "screenToday"
    static let goalEndDatesRaw = "goalEndDatesRaw"
    static let skillPlanDone = "skillPlanDone"
    static let skillPlanName = "skillPlanName"
    static let skillPlanSteps = "skillPlanSteps"

    // MARK: - Skincare / Beauté
    static let skinType = "skinType"
    static let skinConcernsRaw = "skinConcernsRaw"
    static let skinTreatment = "skinTreatment"
    static let skincareAM = "skincareAM"
    static let skincarePM = "skincarePM"
    static let skincareDoneAM = "skincareDoneAM"
    static let skincareDonePM = "skincareDonePM"
    static let skincareReminders = "skincareReminders"

    // MARK: - Cycle féminin
    static let cycleStartDate = "cycleStartDate"
    static let cycleLengthDays = "cycleLengthDays"

    // MARK: - Transport / Parking
    static let parkLat = "parkLat"
    static let parkLon = "parkLon"
    static let parkDate = "parkDate"
    static let parkNote = "parkNote"
    static let mobTrips = "mobTrips"

    // MARK: - Langues / Vocabulaire
    static let langCurrent = "langCurrent"
    static let phraseLang = "phraseLang"
    static let vocabState = "vocabState"
    static let vocabStreak = "vocabStreak"
    static let vocabStreakLast = "vocabStreakLast"

    // MARK: - CV
    static let cvName = "cvName"
    static let cvTitle = "cvTitle"
    static let cvSummary = "cvSummary"
    static let cvContact = "cvContact"
    static let cvExperience = "cvExperience"
    static let cvEducation = "cvEducation"
    static let cvSkills = "cvSkills"

    // MARK: - Tabata / Minuteur
    static let tabWork = "tabWork"
    static let tabRest = "tabRest"
    static let tabRounds = "tabRounds"
    static let tabCycles = "tabCycles"
    static let tabPrepare = "tabPrepare"
    static let tabRestCycle = "tabRestCycle"

    // MARK: - Divers
    static let lifeProfile = "lifeProfile"
    static let dietFlags = "dietFlags"
    static let socialMaxMin = "socialMaxMin"
    static let tutorialDone = "tutorialDone"
}
