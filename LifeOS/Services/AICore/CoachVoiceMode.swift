import Combine
import Foundation

/// Mode conversation vocale continue : STT → send → TTS → STT → …
///
/// L'user parle, LifeOS transcrit, envoie au coach, lit la réponse à voix
/// haute, puis réécoute automatiquement. Boucle jusqu'à ce que l'user quitte
/// le mode manuellement.
///
/// V1 minimale (Loop 16) : toggle UI + hook auto-speak après chaque réponse
/// coach + relance STT après speak. Pas d'audio ducking parfait, pas de wake
/// word — l'user gère les tours de parole avec le bouton.
///
/// Persistance : préférence UserDefaults, désactivé par défaut.
@MainActor
final class CoachVoiceMode: ObservableObject {
    static let shared = CoachVoiceMode()

    private let enabledKey = "coach.voice.mode.enabled"

    /// Actif si l'user l'a activé via le toggle chat. Publié pour que la vue
    /// puisse afficher un indicateur visuel (icône mic en headband).
    @Published var isActive: Bool {
        didSet { UserDefaults.standard.set(isActive, forKey: enabledKey) }
    }

    private init() {
        isActive = UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// À appeler par `AIAssistantView` quand une réponse coach vient d'être
    /// affichée. Auto-speak la réponse via `CoachSpeech` si le mode est on.
    /// Retourne un bool indiquant si le TTS a été déclenché — le caller peut
    /// enchaîner sur STT après le `speakingID` retombe à nil.
    @discardableResult
    func handleAssistantReply(text: String, messageID: UUID) -> Bool {
        guard isActive else { return false }
        // Nettoie le texte pour la voix (retire markdown éventuel) — CoachSpeech
        // ne le fait pas, on s'appuie sur `CoachTextCleaner` amont si dispo.
        CoachSpeech.shared.toggle(text: text, id: messageID)
        return true
    }

    /// Reset (utilisé par DataEraser).
    func reset() {
        isActive = false
        UserDefaults.standard.removeObject(forKey: enabledKey)
    }
}
