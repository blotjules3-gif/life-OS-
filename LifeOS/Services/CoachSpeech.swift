import Foundation
import AVFoundation

/// Synthèse vocale des réponses du coach — bouton speaker inline dans les bulles.
///
/// Un seul synthétiseur partagé pour couper la lecture en cours quand
/// l'utilisateur touche le bouton d'une autre bulle. Voix française premium
/// si téléchargée, fallback voix par défaut sinon.
///
/// Toggle global : `AppStorageKeys.coachTTSEnabled`. Si off, le bouton speaker
/// n'apparaît même pas dans la vue.
@MainActor
final class CoachSpeech: NSObject, ObservableObject {
    static let shared = CoachSpeech()

    @Published private(set) var speakingID: UUID?

    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Lit `text` à haute voix pour le message d'ID donné. Si un autre message
    /// est en cours de lecture, il est interrompu. Si l'ID donné est déjà en
    /// lecture, on la stoppe (toggle).
    func toggle(text: String, id: UUID) {
        if speakingID == id {
            stop()
            return
        }
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        // Session audio catégorie playback + duckOthers pour baisser la musique
        // en cours (Spotify, podcast) le temps de la lecture puis restaurer.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            AppLog.coach.warning("CoachSpeech audio session: \(error.localizedDescription, privacy: .public)")
        }

        let utter = AVSpeechUtterance(string: text)
        utter.voice = preferredVoice()
        utter.rate = AVSpeechUtteranceDefaultSpeechRate * 0.98
        utter.pitchMultiplier = 1.0
        speakingID = id
        synth.speak(utter)
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        speakingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Voix

    /// Choisit la meilleure voix française disponible sur l'appareil.
    /// Premium/Enhanced en priorité (si téléchargée dans Réglages > Accessibilité),
    /// fallback sinon sur la voix système par défaut.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // Premium (mode "Voix améliorée" ou "Voix Siri" téléchargée)
        if let premium = voices.first(where: { $0.language == "fr-FR" && $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.language == "fr-FR" && $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "fr-FR")
    }
}

extension CoachSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingID = nil
        }
    }
}
