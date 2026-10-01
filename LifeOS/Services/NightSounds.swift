import Foundation
import UIKit
import AVFoundation
import SoundAnalysis

// MARK: - Ecoute nocturne
//
// Une session de nuit explicite (distincte du journal de reves): le micro ecoute
// sur l'appareil, le classifieur sonore d'Apple (SoundAnalysis) repere ronflements,
// toux, paroles, pleurs, aboiements, et un seuil de volume repere les bruits forts.
// Chaque evenement garde un court extrait (quelques secondes avant et apres), range
// dans Documents/Nuits. Rien ne quitte l'appareil. Ce sont des evenements ESTIMES:
// ni un diagnostic, ni une mesure des phases du sommeil.

struct NightEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Categorie affichee: ronflement, toux, parole, pleurs, animal, bruit fort...
    let kind: String
    let start: Date
    var end: Date
    /// Confiance maximale du classifieur pendant l'evenement (0 a 1).
    var confidence: Double
    /// Nom du fichier de l'extrait dans le dossier de la nuit, nil si non garde.
    var clip: String?
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct NightSession: Codable, Identifiable, Equatable {
    var id = UUID()
    let start: Date
    var end: Date?
    var events: [NightEvent] = []
    /// Coupures (appel, autre app audio): l'ecoute n'a pas couvert ces moments.
    var gaps: [DateInterval] = []
    var stoppedReason: String?
    var folder: String { "night-" + NightSounds.stamp(start) }
}

enum NightSounds {
    /// Etiquettes du classifieur Apple -> categorie affichee.
    static let kinds: [String: String] = [
        "snoring": "ronflement", "cough": "toux", "sneeze": "éternuement", "speech": "parole",
        "whispering": "parole", "shout": "parole", "laughter": "rire", "baby_crying": "pleurs",
        "crying_sobbing": "pleurs", "dog_bark": "animal", "dog": "animal", "cat_meow": "animal", "cat": "animal",
        "door_slam": "porte", "knock": "porte", "alarm_clock": "alarme", "siren": "sirène", "car_horn": "klaxon",
        "breathing": "respiration", "gasp": "respiration",
    ]
    static let loudKind = "bruit fort"

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'_'HH-mm"
        return f.string(from: d)
    }

    /// Detection brute: un instant, une etiquette, une confiance.
    struct Detection: Equatable { let time: Date; let kind: String; let confidence: Double }

    /// Regroupe les detections en evenements: meme categorie, ecart de moins de
    /// `merge` secondes = un seul evenement. Un evenement de moins de `minDuration`
    /// n'est garde que s'il est tres sur (bruit ponctuel: toux, porte).
    static func events(from detections: [Detection], merge: TimeInterval = 4, minDuration: TimeInterval = 1,
                       minConfidence: Double = 0.6) -> [NightEvent] {
        var out: [NightEvent] = []
        var open: [String: NightEvent] = [:]
        for d in detections.sorted(by: { $0.time < $1.time }) where d.confidence >= minConfidence {
            if var e = open[d.kind], d.time.timeIntervalSince(e.end) <= merge {
                e.end = d.time; e.confidence = max(e.confidence, d.confidence); open[d.kind] = e
            } else {
                if let e = open[d.kind] { out.append(e) }
                open[d.kind] = NightEvent(kind: d.kind, start: d.time, end: d.time, confidence: d.confidence)
            }
        }
        out += open.values
        return out.filter { $0.duration >= minDuration || $0.confidence >= 0.85 }.sorted { $0.start < $1.start }
    }

    /// Resume du matin: nombre et duree par categorie.
    static func summary(_ s: NightSession) -> [(kind: String, count: Int, minutes: Double)] {
        Dictionary(grouping: s.events, by: \.kind)
            .map { ($0.key, $0.value.count, $0.value.reduce(0) { $0 + $1.duration } / 60) }
            // Ordre stable: le plus frequent, puis le plus long, puis le nom (un
            // tri sur le seul nombre changeait l'ordre a chaque affichage en cas d'egalite).
            .sorted { ($0.1, $0.2, $1.0) > ($1.1, $1.2, $0.0) }
    }

    /// Nuits plus vieilles que la duree de conservation: a effacer.
    static func expired(_ sessions: [NightSession], keepDays: Int, now: Date = Date()) -> [NightSession] {
        guard keepDays > 0 else { return [] }
        let limit = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return sessions.filter { ($0.end ?? $0.start) < limit }
    }

    /// Rattache les extraits aux evenements: meme categorie a moins de 12 s,
    /// sinon un extrait dont la fenetre couvre l'evenement (une 2e categorie
    /// detectee pendant un extrait ouvert est enregistree dans CE fichier).
    static func attach(clips: [ClipRecorder.Clip], to events: [NightEvent]) -> [NightEvent] {
        var out = events
        for i in out.indices where out[i].clip == nil {
            let e = out[i]
            out[i].clip = clips.first { $0.kind == e.kind && abs($0.start.timeIntervalSince(e.start)) < 12 }?.file
                ?? clips.first { $0.start.addingTimeInterval(-5) <= e.start && e.start <= $0.end.addingTimeInterval(8) }?.file
        }
        return out
    }

    /// Extraits ecrits mais rattaches a aucun evenement (detection ecartee
    /// ensuite par `events`): ils restaient sur le disque jusqu'a l'effacement
    /// de la nuit entiere.
    static func unreferenced(clipFiles: [String], events: [NightEvent]) -> [String] {
        let used = Set(events.compactMap(\.clip))
        return clipFiles.filter { !used.contains($0) }
    }

    /// Relit un extrait d'apres son nom ("<categorie>-<horodatage>.m4a"), pour
    /// rattacher ceux d'une nuit coupee net. La fin exacte est perdue: on
    /// prend la duree maximale d'un extrait (30 s).
    static func clip(fromFileName name: String) -> ClipRecorder.Clip? {
        guard name.hasSuffix(".m4a") else { return nil }
        let base = String(name.dropLast(4))
        guard let dash = base.lastIndex(of: "-"),
              let ts = TimeInterval(base[base.index(after: dash)...]) else { return nil }
        let kind = base[..<dash].replacingOccurrences(of: "-", with: " ")
        let start = Date(timeIntervalSince1970: ts)
        return ClipRecorder.Clip(kind: kind, start: start, end: start.addingTimeInterval(30), file: name)
    }

    static let orphanReason = "Écoute coupée : l'app a été fermée pendant la nuit."

    /// Nuits restees ouvertes (app tuee avant "Arrêter"): elles gardaient
    /// end = nil, donc la liste les cachait. On les ferme a la derniere trace
    /// connue pour que la nuit et ses evenements sauvegardes reapparaissent.
    static func closeOrphans(_ sessions: [NightSession]) -> [NightSession] {
        sessions.map { s in
            guard s.end == nil else { return s }
            var c = s
            let last = ([s.start] + s.events.map(\.end) + s.gaps.map(\.end)).max() ?? s.start
            c.end = last
            c.stoppedReason = orphanReason
            return c
        }
    }

    // MARK: Tendance sur plusieurs nuits

    struct TrendPoint: Identifiable, Equatable {
        let start: Date
        let minutes: Double
        /// Duree d'ecoute: une nuit courte ne doit pas passer pour une bonne nuit.
        let hours: Double
        var id: Date { start }
        var minutesPerHour: Double { hours > 0 ? minutes / hours : 0 }
    }

    /// Minutes d'une categorie par nuit terminee, de la plus ancienne a la plus recente.
    static func trend(_ sessions: [NightSession], kind: String = "ronflement", limit: Int = 30) -> [TrendPoint] {
        sessions.filter { $0.end != nil }
            .sorted { $0.start < $1.start }
            .suffix(limit)
            .map { s in
                TrendPoint(start: s.start,
                           minutes: s.events.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration } / 60,
                           hours: max(0, (s.end ?? s.start).timeIntervalSince(s.start)) / 3600)
            }
    }

    // MARK: Batterie

    /// Sous 10 % et pas sur secteur, l'ecoute s'arrete et le note.
    static let lowBatteryThreshold: Float = 0.10

    /// Niveau -1 = inconnu (simulateur, suivi coupe): on n'arrete rien.
    static func shouldStopForBattery(level: Float, charging: Bool) -> Bool {
        level >= 0 && level <= lowBatteryThreshold && !charging
    }

    static func lowBatteryReason(level: Float) -> String {
        "Batterie faible (\(Int((max(0, level) * 100).rounded())) %) : écoute arrêtée pour garder du courant."
    }

    // MARK: Export

    static let csvSummaryHeader = "nuit;debut;fin;ecoute_min;evenements;ronflement_min;toux;parole;bruit_fort;autres;coupures;arret"
    static let csvClipsHeader = "nuit;heure;categorie;duree_s;confiance_pct;extrait"

    /// Une ligne par nuit terminee.
    static func csvSummary(_ sessions: [NightSession]) -> String {
        let df = SleepCSV.formatter("yyyy-MM-dd"), tf = SleepCSV.formatter("HH:mm")
        let lines = sessions.filter { $0.end != nil }.sorted { $0.start < $1.start }.map { s -> String in
            let end = s.end ?? s.start
            let main: Set<String> = ["ronflement", "toux", "parole", loudKind]
            let snore = s.events.filter { $0.kind == "ronflement" }.reduce(0) { $0 + $1.duration } / 60
            return [df.string(from: s.start), tf.string(from: s.start), tf.string(from: end),
                    "\(Int((end.timeIntervalSince(s.start) / 60).rounded()))", "\(s.events.count)",
                    SleepCSV.decimal(snore),
                    "\(s.events.filter { $0.kind == "toux" }.count)",
                    "\(s.events.filter { $0.kind == "parole" }.count)",
                    "\(s.events.filter { $0.kind == loudKind }.count)",
                    "\(s.events.filter { !main.contains($0.kind) }.count)",
                    "\(s.gaps.count)", SleepCSV.field(s.stoppedReason ?? "")].joined(separator: ";")
        }
        return ([csvSummaryHeader] + lines).joined(separator: "\n") + "\n"
    }

    /// Liste des evenements et de leurs extraits (chemin dans Documents/Nuits).
    static func csvClips(_ sessions: [NightSession]) -> String {
        let df = SleepCSV.formatter("yyyy-MM-dd"), tf = SleepCSV.formatter("HH:mm:ss")
        var lines: [String] = []
        for s in sessions.filter({ $0.end != nil }).sorted(by: { $0.start < $1.start }) {
            for e in s.events.sorted(by: { $0.start < $1.start }) {
                lines.append([df.string(from: s.start), tf.string(from: e.start), SleepCSV.field(e.kind),
                              "\(max(1, Int(e.duration.rounded())))", "\(Int((e.confidence * 100).rounded()))",
                              e.clip.map { SleepCSV.field("\(s.folder)/\($0)") } ?? ""].joined(separator: ";"))
            }
        }
        return ([csvClipsHeader] + lines).joined(separator: "\n") + "\n"
    }

    /// Espace libre minimal pour lancer une nuit (extraits compresses, ~1 Mo / minute
    /// d'evenement au pire).
    static let minimumFreeBytes: Int64 = 300 * 1_024 * 1_024
}

// MARK: - Magasin des nuits

@MainActor
final class NightStore: ObservableObject {
    static let shared = NightStore()
    @Published private(set) var sessions: [NightSession] = []
    let directory: URL
    static let keepDaysKey = "night.keepDays"

    init(directory: URL? = nil) {
        self.directory = directory ?? AppPaths.documents.appendingPathComponent("Nuits", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: self.directory.appendingPathComponent("nights.json")),
           let s = try? JSONDecoder().decode([NightSession].self, from: d) { sessions = s }
        recoverOrphans()
    }

    /// Au lancement aucune ecoute ne tourne encore: toute nuit sans fin vient
    /// d'une app tuee. On la ferme, on rattache les extraits restes sur le
    /// disque et on efface ceux qui ne servent a rien.
    private func recoverOrphans() {
        let open = sessions.filter { $0.end == nil }
        guard !open.isEmpty else { return }
        var closed = NightSounds.closeOrphans(sessions)
        let fm = FileManager.default
        for i in closed.indices where open.contains(where: { $0.id == closed[i].id }) {
            let dir = folder(closed[i])
            let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".m4a") }
            closed[i].events = NightSounds.attach(clips: files.compactMap(NightSounds.clip(fromFileName:)),
                                                  to: closed[i].events)
            for f in NightSounds.unreferenced(clipFiles: files, events: closed[i].events) {
                try? fm.removeItem(at: dir.appendingPathComponent(f))
            }
        }
        do { try write(closed); sessions = closed }
        catch { AppLog.general.error("nuits orphelines non fermées: \(error.localizedDescription, privacy: .public)") }
    }

    var keepDays: Int {
        get { let v = UserDefaults.standard.integer(forKey: Self.keepDaysKey); return v == 0 ? 14 : v }
        set { UserDefaults.standard.set(newValue, forKey: Self.keepDaysKey); purge() }
    }

    func folder(_ s: NightSession) -> URL { directory.appendingPathComponent(s.folder, isDirectory: true) }

    func save(_ s: NightSession) throws {
        var all = sessions.filter { $0.id != s.id }
        all.insert(s, at: 0)
        try write(all)
        sessions = all
    }

    func delete(_ s: NightSession) throws {
        try? FileManager.default.removeItem(at: folder(s))
        let all = sessions.filter { $0.id != s.id }
        try write(all); sessions = all
    }

    func deleteEvent(_ e: NightEvent, in s: NightSession) throws {
        // Un extrait peut servir a deux evenements (voir `attach`): on ne
        // l'efface que si plus personne ne le pointe.
        if let c = e.clip, !s.events.contains(where: { $0.id != e.id && $0.clip == c }) {
            try? FileManager.default.removeItem(at: folder(s).appendingPathComponent(c))
        }
        var copy = s; copy.events.removeAll { $0.id == e.id }
        try save(copy)
    }

    /// Efface les nuits trop anciennes (fichiers compris).
    func purge(now: Date = Date()) {
        for s in NightSounds.expired(sessions, keepDays: keepDays, now: now) { try? delete(s) }
    }

    func eraseAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        sessions = []
    }

    private func write(_ all: [NightSession]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(all).write(to: directory.appendingPathComponent("nights.json"), options: .atomic)
    }
}

// MARK: - Ecoute (micro, classifieur, extraits)

@MainActor
final class NightListener: NSObject, ObservableObject {
    static let shared = NightListener()
    @Published private(set) var session: NightSession?
    @Published private(set) var lastSound = ""
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let queue = DispatchQueue(label: "night.analysis")
    private var detections: [NightSounds.Detection] = []
    private var recorder: ClipRecorder?
    private var observer: ResultsObserver?
    private var interruptionStart: Date?
    private var checkpointPending = false

    var isRunning: Bool { session != nil }

    func requestPermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    /// Le micro peut-il etre ouvert ici? Dans le simulateur, ouvrir l'entree audio
    /// fait avorter l'app (serveur audio de l'hote sans reponse, mesure le 29 sept):
    /// on refuse proprement au lieu de planter.
    static var microphoneUsable: (ok: Bool, reason: String?) {
        #if targetEnvironment(simulator)
        return (false, "L'écoute nocturne ne fonctionne que sur un vrai iPhone (le simulateur n'a pas de micro fiable).")
        #else
        return AVAudioSession.sharedInstance().isInputAvailable ? (true, nil) : (false, "Aucun micro disponible.")
        #endif
    }

    func start() throws {
        guard session == nil else { return }
        let mic = Self.microphoneUsable
        guard mic.ok else { throw NSError(domain: "Nuit", code: 2, userInfo: [NSLocalizedDescriptionKey: mic.reason ?? "Micro indisponible."]) }
        // Batterie deja trop basse: ne pas lancer une nuit qui s'arreterait tout de suite.
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if NightSounds.shouldStopForBattery(level: device.batteryLevel, charging: Self.isCharging(device)) {
            device.isBatteryMonitoringEnabled = false
            throw NSError(domain: "Nuit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Batterie trop faible (\(Int((device.batteryLevel * 100).rounded())) %) : branche ton téléphone avant de lancer l'écoute."])
        }
        if let free = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < NightSounds.minimumFreeBytes {
            throw NSError(domain: "Nuit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stockage presque plein : libère au moins 300 Mo avant de lancer l'écoute."])
        }
        let s = NightSession(start: Date())
        let folder = NightStore.shared.folder(s)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: [.mixWithOthers])
        try audio.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        let obs = ResultsObserver { [weak self] label, conf in
            Task { @MainActor in self?.handle(label: label, confidence: conf) }
        }
        try analyzer.add(request, withObserver: obs)
        self.analyzer = analyzer; self.observer = obs
        let rec = ClipRecorder(format: format, folder: folder)
        self.recorder = rec
        input.installTap(onBus: 0, bufferSize: 8_192, format: format) { [weak self] buf, when in
            rec.append(buf)
            self?.queue.async { analyzer.analyze(buf, atAudioFramePosition: when.sampleTime) }
            // Volume: bruit fort au dessus de -20 dBFS.
            if let ch = buf.floatChannelData?[0] {
                let n = Int(buf.frameLength); var sum: Float = 0
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                let db = 20 * log10(max(rms, 1e-7))
                if db > -20 { Task { @MainActor in self?.handle(label: NightSounds.loudKind, confidence: 0.9) } }
            }
        }
        engine.prepare()
        try engine.start()
        session = s
        detections = []
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged(_:)), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged(_:)), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        try NightStore.shared.save(s)
    }

    static func isCharging(_ d: UIDevice) -> Bool { d.batteryState == .charging || d.batteryState == .full }

    /// Avant, rien ne surveillait la batterie: une nuit debranchee pouvait vider
    /// le telephone (et son reveil). Sous 10 %, on arrete et on note pourquoi.
    @objc private func batteryChanged(_ n: Notification) {
        Task { @MainActor in
            guard self.session != nil else { return }
            let d = UIDevice.current
            if NightSounds.shouldStopForBattery(level: d.batteryLevel, charging: Self.isCharging(d)) {
                self.stop(reason: NightSounds.lowBatteryReason(level: d.batteryLevel))
            }
        }
    }

    private func handle(label: String, confidence: Double) {
        let kind = label == NightSounds.loudKind ? label : (NightSounds.kinds[label] ?? "")
        guard !kind.isEmpty, confidence >= 0.6, session != nil else { return }
        lastSound = kind
        detections.append(.init(time: Date(), kind: kind, confidence: confidence))
        recorder?.mark(kind: kind)
        scheduleCheckpoint()
    }

    /// Les detections ne vivaient qu'en memoire jusqu'a stop(): app tuee la
    /// nuit = tous les evenements perdus. Sauvegarde provisoire au plus 30 s
    /// apres chaque detection.
    private func scheduleCheckpoint() {
        guard !checkpointPending else { return }
        checkpointPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.checkpoint()
        }
    }

    private func checkpoint() {
        checkpointPending = false
        guard var s = session else { return }
        s.events = NightSounds.attach(clips: recorder?.closedClips() ?? [], to: NightSounds.events(from: detections))
        try? NightStore.shared.save(s)
    }

    @objc private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            if type == .began { interruptionStart = Date() }
            else if let s = interruptionStart {
                session?.gaps.append(DateInterval(start: s, end: Date()))
                interruptionStart = nil
                try? AVAudioSession.sharedInstance().setActive(true)
                try? engine.start()
            }
        }
    }

    /// Fin de nuit: regroupe les detections en evenements et rattache les extraits.
    func stop(reason: String? = nil) {
        guard var s = session else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        analyzer?.removeAllRequests()
        let clips = recorder?.finish() ?? []
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
        UIDevice.current.isBatteryMonitoringEnabled = false
        s.end = Date()
        s.stoppedReason = reason
        let events = NightSounds.attach(clips: clips, to: NightSounds.events(from: detections))
        s.events = events
        let folder = NightStore.shared.folder(s)
        for f in NightSounds.unreferenced(clipFiles: clips.map(\.file), events: events) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(f))
        }
        checkpointPending = false
        try? NightStore.shared.save(s)
        NightStore.shared.purge()
        session = nil; recorder = nil; analyzer = nil; observer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Recoit les resultats du classifieur (hors fil principal).
final class ResultsObserver: NSObject, SNResultsObserving {
    let onResult: (String, Double) -> Void
    init(onResult: @escaping (String, Double) -> Void) { self.onResult = onResult }
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult, let top = r.classifications.first else { return }
        onResult(top.identifier, top.confidence)
    }
}

/// Garde les ~5 dernieres secondes en memoire; a chaque evenement, ecrit un extrait
/// (5 s avant, jusqu'a 8 s apres la derniere detection, 30 s au plus) en AAC.
final class ClipRecorder: @unchecked Sendable {
    struct Clip: Equatable { let kind: String; let start: Date; let end: Date; let file: String }
    private let format: AVAudioFormat
    private let folder: URL
    private var ring: [AVAudioPCMBuffer] = []
    private var ringFrames: AVAudioFrameCount = 0
    private var file: AVAudioFile?
    private var current: (kind: String, start: Date, last: Date, name: String)?
    private var clips: [Clip] = []
    private let lock = NSLock()

    init(format: AVAudioFormat, folder: URL) { self.format = format; self.folder = folder }

    func append(_ buf: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: buf.frameLength) else { return }
        copy.frameLength = buf.frameLength
        if let src = buf.floatChannelData, let dst = copy.floatChannelData {
            for c in 0..<Int(buf.format.channelCount) { dst[c].update(from: src[c], count: Int(buf.frameLength)) }
        }
        if let f = file, let cur = current {
            try? f.write(from: copy)
            if Date().timeIntervalSince(cur.last) > 8 || Date().timeIntervalSince(cur.start) > 30 { close() }
            return
        }
        ring.append(copy); ringFrames += copy.frameLength
        while ringFrames > AVAudioFrameCount(format.sampleRate * 5), let first = ring.first {
            ringFrames -= first.frameLength; ring.removeFirst()
        }
    }

    func mark(kind: String) {
        lock.lock(); defer { lock.unlock() }
        if var cur = current { cur.last = Date(); current = cur; return }
        let name = "\(kind.replacingOccurrences(of: " ", with: "-"))-\(Int(Date().timeIntervalSince1970)).m4a"
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 32_000]
        guard let f = try? AVAudioFile(forWriting: folder.appendingPathComponent(name), settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false) else { return }
        for b in ring { try? f.write(from: b) }
        ring = []; ringFrames = 0
        file = f
        current = (kind, Date(), Date(), name)
    }

    private func close() {
        if let cur = current { clips.append(Clip(kind: cur.kind, start: cur.start, end: Date(), file: cur.name)) }
        file = nil; current = nil
    }

    /// Extraits deja fermes, pour la sauvegarde provisoire (sans couper
    /// l'extrait en cours).
    func closedClips() -> [Clip] {
        lock.lock(); defer { lock.unlock() }
        return clips
    }

    func finish() -> [Clip] {
        lock.lock(); defer { lock.unlock() }
        close()
        return clips
    }
}
