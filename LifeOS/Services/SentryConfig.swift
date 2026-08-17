import Foundation

/// Configuration Sentry — préparée pour activation immédiate quand
/// le SDK sera ajouté (File → Add Packages → sentry-cocoa).
///
/// **État actuel** : structure prête, appel neutralisé (no-op).
/// Aucun impact sur la compilation ou le runtime tant que le SDK n'est pas ajouté.
///
/// **Pour activer** :
/// 1. Xcode → File → Add Package Dependencies → https://github.com/getsentry/sentry-cocoa
/// 2. Ajouter la clé `SENTRY_DSN_IOS` dans `Config.xcconfig` (voir Config.xcconfig.example)
/// 3. Ajouter la clé `SENTRY_DSN_IOS` dans `Info.plist` avec la valeur `$(SENTRY_DSN_IOS)`
/// 4. Dé-commenter le bloc `#if canImport(Sentry)` ci-dessous
/// 5. Appeler `SentryConfig.start()` dans `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
///
/// **Documentation complète** : docs/observability/SENTRY_SETUP.md
enum SentryConfig {

    /// Démarre Sentry si le SDK est disponible et si le DSN est configuré.
    /// No-op sinon (aucun risque de crash à l'appel).
    static func start() {
        #if canImport(Sentry)
        // Décommenter après avoir ajouté le package Sentry
        /*
        import Sentry

        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_IOS") as? String,
              !dsn.isEmpty,
              dsn.hasPrefix("https://") else {
            AppLog.general.info("Sentry non configuré : SENTRY_DSN_IOS absent ou invalide")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.tracesSampleRate = 0.1
            options.profilesSampleRate = 0.05
            options.enableAppHangTracking = true
            options.enableAutoPerformanceTracing = true
            options.attachStacktrace = true
            options.sendDefaultPii = false
            options.beforeSend = { event in
                // Filtre : ne pas envoyer les erreurs APNs sur simulateur
                if let msg = event.message?.formatted,
                   msg.contains("APNs registration failed") {
                    return nil
                }
                return event
            }
        }

        AppLog.general.info("Sentry initialisé")
        */
        #else
        AppLog.general.debug("Sentry SDK non installé — SentryConfig.start() no-op")
        #endif
    }

    /// Escalade manuelle d'une erreur vers Sentry — à utiliser dans les catch
    /// critiques après un `AppLog.data.error(...)` classique.
    /// No-op tant que le SDK n'est pas ajouté.
    static func capture(error: Error, context: String? = nil) {
        #if canImport(Sentry)
        /*
        import Sentry
        SentrySDK.capture(error: error) { scope in
            if let context {
                scope.setContext(value: ["operation": context], key: "app")
            }
        }
        */
        #endif
        // No-op — trace locale via AppLog uniquement pour l'instant
        AppLog.general.error("SentryConfig.capture (no-op): \(error.localizedDescription, privacy: .public) — context: \(context ?? "-", privacy: .public)")
    }
}
