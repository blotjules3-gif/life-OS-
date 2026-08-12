import Foundation
import os

/// Logger structuré unique pour LifeOS.
///
/// Remplace tous les `print(...)` du code et enveloppe les `catch { print(...) }`
/// silencieux. Chaque catégorie apparaît filtrée dans Console.app et permet de
/// brancher un backend d'observation (Sentry, log drain) sans re-crawler le code.
///
/// Utilisation :
///   AppLog.data.error("save failed: \(error.localizedDescription, privacy: .public)")
///   AppLog.coach.info("prompt sent, tokens=\(count)")
///
/// Règles :
/// - Toute variable venant d'une entrée utilisateur (nom, message, etc.) doit
///   utiliser `privacy: .private` pour ne pas fuiter dans les logs système.
/// - Les erreurs techniques (codes, chemins, ids) peuvent rester `.public`.
enum AppLog {
    private static let subsystem = "com.blotjules.lifeos"

    /// Chat coach, prompts, réponses LLM, contexte utilisateur.
    static let coach   = Logger(subsystem: subsystem, category: "coach")
    /// SwiftData saves/fetches, migrations, backups.
    static let data    = Logger(subsystem: subsystem, category: "data")
    /// HealthKit, HRV, sommeil, capteurs.
    static let health  = Logger(subsystem: subsystem, category: "health")
    /// Réseau (backend FastAPI, appels HTTP, config remote).
    static let net     = Logger(subsystem: subsystem, category: "network")
    /// Notifications locales, permissions, deep links.
    static let notif   = Logger(subsystem: subsystem, category: "notifications")
    /// Alarme, live activities, réveil.
    static let alarm   = Logger(subsystem: subsystem, category: "alarm")
    /// Audio (reconnaissance vocale, TTS, soundscape).
    static let audio   = Logger(subsystem: subsystem, category: "audio")
    /// UI / navigation (deep links, ouverture modules).
    static let ui      = Logger(subsystem: subsystem, category: "ui")
    /// Fallback pour code non-catégorisé — à faire migrer progressivement.
    static let general = Logger(subsystem: subsystem, category: "general")
}
