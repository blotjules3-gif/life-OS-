import Foundation
import Speech
import AVFoundation

/// Reconnaissance vocale en direct (français) pour les messages du chat coach.
/// Utilise SFSpeechRecognizer + AVAudioEngine — transcription partielle streamée.
@MainActor
@Observable
final class SpeechRecognizer {
    var transcript: String = ""
    var isRecording: Bool = false
    var errorMessage: String? = nil
    /// Niveau audio moyen normalisé (0…1) recalculé à chaque tap buffer.
    var audioLevel: Float = 0
    /// Locale actif (ex. "fr-FR", "en-US"). Change via `setLanguage`.
    private(set) var locale: Locale

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        let preferred = Self.detectPreferredLocale()
        self.locale = preferred
        self.recognizer = SFSpeechRecognizer(locale: preferred)
    }

    /// Détecte la langue préférée de l'utilisateur (fr / en) via Locale.preferredLanguages.
    /// Fallback: fr-FR.
    private static func detectPreferredLocale() -> Locale {
        let raw = Locale.preferredLanguages.first ?? "fr-FR"
        let code = String(raw.prefix(2)).lowercased()
        switch code {
        case "en": return Locale(identifier: "en-US")
        case "es": return Locale(identifier: "es-ES")
        case "de": return Locale(identifier: "de-DE")
        case "it": return Locale(identifier: "it-IT")
        case "pt": return Locale(identifier: "pt-BR")
        default:   return Locale(identifier: "fr-FR")
        }
    }

    func setLanguage(_ code: String) {
        let loc = Locale(identifier: code)
        locale = loc
        recognizer = SFSpeechRecognizer(locale: loc)
    }

    /// Demande les deux permissions (reconnaissance vocale + micro).
    func requestAuthorization() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else {
            errorMessage = "Autorise la reconnaissance vocale dans Réglages."
            return false
        }
        let mic: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        if !mic {
            errorMessage = "Autorise le micro dans Réglages."
        }
        return mic
    }

    func start() {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        do {
            try startRecording()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            stopEngineIfNeeded()
        }
    }

    func stop() {
        guard isRecording else { return }
        stopEngineIfNeeded()
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        stopEngineIfNeeded()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        transcript = ""
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Calcule le RMS d'un buffer PCM float32, normalisé perceptuellement (0…1).
    private static func rms(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let s = channel[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(count))
        // Perceptuel : compresser via log, mapper -50dB..0dB → 0..1
        let db = 20 * log10(max(rms, 0.0000001))
        let norm = max(0, min(1, (db + 50) / 50))
        return norm
    }

    private func stopEngineIfNeeded() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func startRecording() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Reconnaissance vocale indisponible."])
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let level = Self.rms(from: buffer)
            Task { @MainActor in self?.audioLevel = level }
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopEngineIfNeeded()
                    self.request = nil
                    self.task = nil
                    self.isRecording = false
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
        }
    }
}
