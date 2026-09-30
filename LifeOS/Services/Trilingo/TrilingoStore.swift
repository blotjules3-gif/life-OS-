import Foundation
import AVFoundation
import Speech
import UserNotifications

/// Profil et progression Trilingo, dans Documents/Trilingo (la sauvegarde complete
/// les emporte). Une progression par langue: changer de langue puis revenir retrouve
/// l'ancienne progression.
@MainActor
final class TrilingoStore: ObservableObject {
    static let shared = TrilingoStore()

    @Published private(set) var profile: TrilingoProfile?
    @Published private(set) var progress: TrilingoProgress?
    @Published var lastError: String?

    let directory: URL
    private static let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init(directory: URL? = nil) {
        self.directory = directory ?? AppPaths.documents.appendingPathComponent("Trilingo", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        profile = read("profile.json")
        if let t = profile?.target { progress = read("progress-\(t).json") ?? TrilingoProgress(target: t) }
    }

    var course: TrilingoCourse? {
        guard let p = profile else { return nil }
        return TrilingoLibrary.course(source: p.source, target: p.target)
    }

    /// Le questionnaire est obligatoire: sans profil, pas de cours.
    var needsSetup: Bool { profile == nil || course == nil }

    func saveProfile(_ p: TrilingoProfile) throws {
        try write(p, "profile.json")
        profile = p
        progress = read("progress-\(p.target).json") ?? TrilingoProgress(target: p.target)
        try write(progress!, "progress-\(p.target).json")
    }

    func update(_ change: (inout TrilingoProgress) -> Void) throws {
        guard var p = progress else { return }
        change(&p)
        try write(p, "progress-\(p.target).json")
        progress = p
    }

    func eraseAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        profile = nil; progress = nil
    }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let d = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? Self.dec.decode(T.self, from: d)
    }

    private func write<T: Encodable>(_ v: T, _ name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.enc.encode(v).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

// MARK: - Rappel quotidien

enum TrilingoReminders {
    static let prefix = "trilingo.day."

    /// Remplace les rappels Trilingo par ceux des 7 prochains jours. Aucun doublon
    /// (identifiant par jour), rien aujourd'hui si la seance est faite.
    static func reschedule(_ profile: TrilingoProfile?, doneToday: Bool, languageName: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let p = profile, p.reminderOn else { return }
        for date in TrilingoEngine.reminderDates(now: Date(), hour: p.reminderHour, minute: p.reminderMinute, doneToday: doneToday) {
            let content = UNMutableNotificationContent()
            content.title = "Trilingo"
            content.body = "Ta séance de \(languageName) du jour t'attend (\(p.dailyMinutes) min)."
            content.sound = .default
            content.userInfo = ["route": "trilingo"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let req = UNNotificationRequest(identifier: prefix + TrilingoEngine.dayKey(date),
                                            content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }
}

// MARK: - Voix et micro

@MainActor
final class TrilingoSpeech: NSObject, ObservableObject {
    static let shared = TrilingoSpeech()
    private let synth = AVSpeechSynthesizer()
    private var player: AVPlayer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    @Published var heard = ""
    @Published var listening = false

    static func hasVoice(_ bcp47: String) -> Bool {
        let lang = bcp47.split(separator: "-").first.map(String.init) ?? bcp47
        return AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix(lang) }
    }

    static func speechAvailable(_ bcp47: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: bcp47))?.isAvailable == true
    }

    /// Enregistrement humain Tatoeba quand il existe (en ligne), sinon voix de l'appareil.
    func play(_ item: TrilingoItem, language: TrilingoLanguage, slow: Bool = false) {
        if item.audio == true, !slow, let url = URL(string: "https://audio.tatoeba.org/sentences/\(language.code)/\(item.tid).mp3") {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            player = AVPlayer(url: url)
            player?.play()
            return
        }
        speak(item.t, bcp47: language.bcp47, slow: slow)
    }

    func speak(_ text: String, bcp47: String, slow: Bool = false) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: bcp47)
        u.rate = slow ? AVSpeechUtteranceDefaultSpeechRate * 0.6 : AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }

    func requestSpeechPermission() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    func startListening(bcp47: String) throws {
        stopListening()
        heard = ""
        let mic = NightListener.microphoneUsable
        guard mic.ok else {
            throw NSError(domain: "Trilingo", code: 2, userInfo: [NSLocalizedDescriptionKey: (mic.reason ?? "Micro indisponible.").replacingOccurrences(of: "L'écoute nocturne ne fonctionne", with: "L'oral ne fonctionne")])
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: bcp47)), rec.isAvailable else {
            throw NSError(domain: "Trilingo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reconnaissance vocale indisponible pour cette langue sur cet appareil."])
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        try engine.start()
        listening = true
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                if let r = result { self?.heard = r.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self?.stopListening() }
            }
        }
    }

    func stopListening() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        listening = false
    }
}
