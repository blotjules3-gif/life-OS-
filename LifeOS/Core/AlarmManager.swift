import Foundation
import AVFoundation
import AudioToolbox
import UserNotifications
import ActivityKit

// MARK: - Gestionnaire central du réveil

@MainActor
final class AlarmManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AlarmManager()

    @Published var isRinging = false
    @Published var showAlarmScreen = false
    @Published var showBriefing = false
    @Published var isSpeaking = false
    @Published var secondsLeft = 10

    private var ringingActive = false
    private var autoStopWorkItem: DispatchWorkItem?
    private var voiceWorkItem: DispatchWorkItem?
    private var countdownTimer: Timer?
    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Déclenchement alarme

    func triggerAlarm() {
        guard !isRinging else { return }
        isRinging = true
        ringingActive = true
        secondsLeft = 10
        showAlarmScreen = true

        configureAudioSession()
        playBeepCycle()
        startCountdown()

        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.start()
        }
        scheduleWakeUpVoice()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func playBeepCycle() {
        guard ringingActive else { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(1005)) { [weak self] in
            guard let self, self.ringingActive else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.playBeepCycle()
            }
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.secondsLeft > 1 {
                    self.secondsLeft -= 1
                } else {
                    self.stopAndShowBriefing()
                }
            }
        }
    }

    // MARK: - Arrêt / snooze

    func stopRinging() {
        ringingActive = false   // interrompt la boucle de bips (completion guard)
        isRinging = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        autoStopWorkItem?.cancel()
        autoStopWorkItem = nil
        voiceWorkItem?.cancel()
        voiceWorkItem = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stopAndShowBriefing() {
        stopRinging()
        showAlarmScreen = false
        showBriefing = true
    }

    func snooze(minutes: Int) {
        stopSpeaking()           // stop TTS if playing (user is snoozing back)
        stopRinging()
        showAlarmScreen = false
        NotificationManager.shared.scheduleAfter(
            id: "lifeos.wakeup.snooze",
            title: "Rappel — Réveil",
            body: "C'est reparti ! Ta journée t'attend.",
            seconds: TimeInterval(minutes * 60)
        )
        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.end()
        }
    }

    func dismissBriefing() {
        stopSpeaking()
        showBriefing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.end()
        }
    }

    // MARK: - Synthèse vocale (AVSpeechSynthesizer)

    func speakDailyPlan(userName: String, modules: [AppCategory], waterGoal: Int, kcalGoal: Int) {
        stopSpeaking()

        let hour = Calendar.current.component(.hour, from: .now)
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Bonjour"
        case 12..<18: greeting = "Bon après-midi"
        default: greeting = "Bonsoir"
        }

        var parts: [String] = [
            "\(greeting)\(userName.isEmpty ? "" : ", \(userName)") !",
            "Il est \(timeSpoken()) et voici ton plan pour aujourd'hui."
        ]

        for mod in modules.prefix(5) {
            switch mod {
            case .nutrition:
                parts.append("Nutrition : objectif \(waterGoal) millilitres d'eau et \(kcalGoal) calories.")
            case .fitness:
                parts.append("Sport : prévois une séance d'activité physique.")
            case .sleep:
                parts.append("Sommeil : évalue ta nuit pour optimiser ta récupération.")
            case .mind:
                parts.append("Mental : prends cinq minutes de méditation ou de respiration.")
            case .productivity:
                parts.append("Productivité : définis ta tâche prioritaire du jour.")
            case .finance:
                parts.append("Finances : vérifie ton budget et tes dépenses.")
            case .invest:
                parts.append("Investissement : consulte l'état de ton portefeuille.")
            case .learning:
                parts.append("Apprentissage : avance dans ton programme de formation.")
            case .career:
                parts.append("Carrière : une action importante pour ton développement professionnel.")
            case .looks:
                parts.append("Apparence : suis ta routine beauté et soin du corps.")
            default:
                break
            }
        }

        parts.append("Allez, tu assures ! Bonne journée.")

        let text = parts.joined(separator: " ")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.3

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func timeSpoken() -> String {
        let h = Calendar.current.component(.hour, from: .now)
        let m = Calendar.current.component(.minute, from: .now)
        if m == 0 { return "\(h) heures" }
        if m == 1 { return "\(h) heures une" }
        return "\(h) heures \(m)"
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
