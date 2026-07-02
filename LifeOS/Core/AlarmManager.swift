import Foundation
import AVFoundation
import AudioToolbox
import UserNotifications
import ActivityKit
import UIKit

// MARK: - Gestionnaire central du réveil

enum AlarmPhase: Equatable {
    case idle
    case ringing(secondsLeft: Int)
    case sleepCheck
    case briefing
}

@MainActor
final class AlarmManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AlarmManager()

    @Published var phase: AlarmPhase = .idle
    @Published var isSpeaking = false

    var isRinging: Bool {
        if case .ringing = phase { return true }
        return false
    }
    var showAlarmScreen: Bool { isRinging }
    var showSleepCheck: Bool  { phase == .sleepCheck }
    var showBriefing: Bool    { phase == .briefing }
    var secondsLeft: Int {
        if case .ringing(let s) = phase { return s }
        return 0
    }

    private var ringingActive = false
    private var pendingVoiceOnUnlock = false
    private var autoStopWorkItem: DispatchWorkItem?
    private var voiceWorkItem: DispatchWorkItem?
    private var countdownTimer: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    private var becameActiveObserver: NSObjectProtocol?

    private override init() {
        super.init()
        synthesizer.delegate = self
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleAppBecameActive() }
        }
    }

    private func handleAppBecameActive() {
        guard pendingVoiceOnUnlock, ringingActive else { return }
        pendingVoiceOnUnlock = false
        speakWakeUpMessage()
    }

    // MARK: - Déclenchement alarme

    func triggerAlarm() {
        guard !isRinging else { return }
        ringingActive = true
        phase = .ringing(secondsLeft: 10)

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

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
                if case .ringing(let s) = self.phase, s > 1 {
                    self.phase = .ringing(secondsLeft: s - 1)
                } else {
                    self.stopAndShowBriefing()
                }
            }
        }
    }

    // MARK: - Arrêt / snooze

    func stopRinging() {
        ringingActive = false
        pendingVoiceOnUnlock = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        autoStopWorkItem?.cancel()
        autoStopWorkItem = nil
        voiceWorkItem?.cancel()
        voiceWorkItem = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if phase == .ringing(secondsLeft: secondsLeft) { phase = .idle }
    }

    func stopAndShowBriefing() {
        ringingActive = false
        pendingVoiceOnUnlock = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        autoStopWorkItem?.cancel()
        autoStopWorkItem = nil
        voiceWorkItem?.cancel()
        voiceWorkItem = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .sleepCheck
        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.update(phase: .briefing, message: "Bilan du matin en cours…")
        }
    }

    func sleepCheckDone() {
        phase = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.phase = .briefing
            if #available(iOS 16.1, *) {
                AlarmLiveActivityManager.shared.update(phase: .briefing, message: "Briefing quotidien en cours…")
            }
        }
    }

    func snooze(minutes: Int) {
        stopSpeaking()
        stopRinging()
        phase = .idle
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
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.end()
        }
    }

    // MARK: - Message vocal au réveil

    private func scheduleWakeUpVoice() {
        voiceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.attemptWakeUpVoice() }
        }
        voiceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func attemptWakeUpVoice() {
        guard ringingActive else { return }
        speakWakeUpMessage()
    }

    private func speakWakeUpMessage() {
        guard ringingActive else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let text = buildWakeUpText()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)

        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.update(phase: .speakingMessage, message: text)
        }
    }

    private func buildWakeUpText() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Bonjour"
        case 12..<18: greeting = "Bon après-midi"
        default: greeting = "Bonsoir"
        }

        let sleepQuality = UserDefaults.standard.integer(forKey: "lastSleepQuality")
        let sleepHours = UserDefaults.standard.integer(forKey: "lastSleepHours")
        let sleepIntro: String
        switch sleepQuality {
        case 5: sleepIntro = "Excellente nuit ! \(sleepHours > 0 ? "\(sleepHours) heures de sommeil, " : "")tu es au top ce matin."
        case 4: sleepIntro = "Bonne nuit. Tu es bien reposé."
        case 3: sleepIntro = sleepHours > 0 ? "Nuit correcte avec \(sleepHours) heures de sommeil." : "Nuit correcte."
        case 2: sleepIntro = "Tu n'as pas bien dormi — prends soin de toi aujourd'hui."
        case 1: sleepIntro = "Nuit difficile. Hydrate-toi bien et écoute ton corps."
        default: sleepIntro = ""
        }

        var parts: [String] = ["\(greeting) ! Il est \(timeSpoken())."]
        if !sleepIntro.isEmpty { parts.append(sleepIntro) }

        let rawModules = UserDefaults.standard.string(forKey: "recommendedModules") ?? ""
        let modules = rawModules.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }

        for mod in modules.prefix(3) {
            switch mod {
            case .fitness:      parts.append("Ta séance de sport t'attend.")
            case .nutrition:    parts.append("Pense à bien t'hydrater dès maintenant.")
            case .mind:         parts.append("Commence par quelques minutes de calme.")
            case .productivity: parts.append("Définis ta tâche prioritaire du jour.")
            case .sleep:        parts.append("Note ta qualité de sommeil pour optimiser ta récupération.")
            case .finance:      parts.append("Jette un œil rapide à tes dépenses d'hier.")
            case .invest:       parts.append("Consulte l'état de tes investissements.")
            case .learning:     parts.append("Avance dans ton programme d'apprentissage.")
            case .career:       parts.append("Une action pour ta carrière, aujourd'hui.")
            case .looks:        parts.append("Prends soin de toi — ta routine beauté t'attend.")
            default: break
            }
        }

        if modules.isEmpty {
            parts.append("C'est l'heure de te lever — ta journée commence maintenant.")
        } else {
            parts.append("Allez, bonne journée !")
        }

        return parts.joined(separator: " ")
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

        let sleepQuality = UserDefaults.standard.integer(forKey: "lastSleepQuality")
        let sleepHours = UserDefaults.standard.integer(forKey: "lastSleepHours")
        let sleepLine: String
        switch sleepQuality {
        case 5: sleepLine = "Tu as excellemment dormi\(sleepHours > 0 ? " — \(sleepHours) heures" : ""). Profites-en."
        case 4: sleepLine = "Bonne nuit derrière toi. Tu es en forme."
        case 3: sleepLine = "Nuit correcte. On y va."
        case 2: sleepLine = "Tu n'as pas très bien dormi — reste à l'écoute de ton énergie."
        case 1: sleepLine = "Nuit difficile. Sois indulgent avec toi-même aujourd'hui."
        default: sleepLine = "Il est \(timeSpoken()) et voici ton plan."
        }

        var parts: [String] = [
            "\(greeting)\(userName.isEmpty ? "" : ", \(userName)") !",
            sleepLine
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

    func speakText(_ text: String) {
        stopSpeaking()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.3
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
        Task { @MainActor in
            self.isSpeaking = false
            if #available(iOS 16.1, *), self.ringingActive {
                AlarmLiveActivityManager.shared.update(
                    phase: .waitingUnlock,
                    message: "Déverouille ton téléphone pour le briefing visuel complet."
                )
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
