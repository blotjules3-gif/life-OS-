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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
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
