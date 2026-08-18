import Foundation

/// Registre des events analytics + helpers pour le funnel Station F.
///
/// **Pourquoi** : `Analytics.log(name:props:)` accepte n'importe quelle string.
/// Sans registre central, chaque call site inventerait son nom → pas de funnel possible.
/// Cette enum garantit :
/// - Noms cohérents (jamais de typo)
/// - Découverte facile des events disponibles
/// - Helper spécifique par domaine pour lisibilité
///
/// **Convention de nommage** : `<domaine>.<action>[.<précision>]`
///   ex : `chat.message.sent`, `module.opened`, `habit.completed`
enum AnalyticsEvents {

    // MARK: - Chat coach

    static func chatMessageSent(hasContext: Bool = true, module: String? = nil) {
        var props: [String: String] = ["has_context": String(hasContext)]
        if let module { props["module"] = module }
        Analytics.log("chat.message.sent", props)
    }

    static func chatActionExecuted(type: String, module: String? = nil) {
        var props: [String: String] = ["action_type": type]
        if let module { props["module"] = module }
        Analytics.log("chat.action.executed", props)
    }

    static func chatOpened(source: String = "manual") {
        Analytics.log("chat.opened", ["source": source])
    }

    static func chatFeedback(positive: Bool) {
        Analytics.log("chat.feedback", ["positive": String(positive)])
    }

    // MARK: - Modules

    static func moduleOpened(_ module: String) {
        Analytics.log("module.opened", ["module": module])
    }

    static func moduleAdded(_ module: String, source: String = "chat") {
        Analytics.log("module.added", ["module": module, "source": source])
    }

    static func moduleRemoved(_ module: String) {
        Analytics.log("module.removed", ["module": module])
    }

    // MARK: - Habits

    static func habitCreated(module: String = "custom") {
        Analytics.log("habit.created", ["module": module])
    }

    static func habitCompleted(module: String = "custom", streak: Int = 0) {
        Analytics.log("habit.completed", ["module": module, "streak": String(streak)])
    }

    static func habitDeleted() {
        Analytics.log("habit.deleted")
    }

    // MARK: - Onboarding

    static func onboardingStarted() {
        Analytics.log("onboarding.started")
    }

    static func onboardingStepCompleted(_ step: String) {
        Analytics.log("onboarding.step.completed", ["step": step])
    }

    static func onboardingCompleted(modulesActivated: Int) {
        Analytics.log("onboarding.completed", ["modules_activated": String(modulesActivated)])
    }

    // MARK: - Data collection

    static func moodLogged(score: Int) {
        Analytics.log("mood.logged", ["score": String(score)])
    }

    static func sleepLogged(hours: Int, quality: Int) {
        Analytics.log("sleep.logged", ["hours": String(hours), "quality": String(quality)])
    }

    static func waterLogged(ml: Int) {
        Analytics.log("water.logged", ["ml": String(ml)])
    }

    static func foodLogged(kcal: Int) {
        Analytics.log("food.logged", ["kcal": String(kcal)])
    }

    // MARK: - Settings

    static func languageChanged(from: String, to: String) {
        Analytics.log("language.changed", ["from": from, "to": to])
    }

    static func themeChanged(_ theme: String) {
        Analytics.log("theme.changed", ["theme": theme])
    }

    // MARK: - Data lifecycle

    static func dataExported() {
        Analytics.log("data.exported")
    }

    static func dataErased(kind: String) {
        Analytics.log("data.erased", ["kind": kind])
    }
}
