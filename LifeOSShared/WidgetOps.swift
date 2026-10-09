import Foundation

// File d'ordres venus des widgets (taches, eau), partagee app + extension.
//
// Meme principe que `HabitOps` (qui reste en place pour les habitudes, sa file et
// ses tests ne changent pas) : un fichier par ordre, ecrit d'un coup, lu et applique
// par l'app, efface seulement apres une sauvegarde reussie.
//
// Deux protections contre la double ecriture :
// 1. Le nom du fichier EST l'identifiant de l'ordre. Deux appuis qui portent le meme
//    identifiant (meme rendu du widget) ne creent qu'un fichier.
// 2. L'app garde la liste des derniers identifiants appliques (`AppliedLedger`) :
//    un ordre rejoue apres un arret (sauvegarde faite, fichier pas encore efface)
//    est reconnu et ignore.

/// Ecriture/lecture atomique d'une file de fichiers JSON. Utilise par `WidgetOps`
/// et par `HabitOps`.
enum OpFileQueue {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// Ecrit `data` sous `name` dans `dir` (temporaire puis renommage). Si un fichier
    /// du meme nom existe deja, rien n'est ecrit et la fonction rend `false`.
    @discardableResult
    static func write(_ data: Data, name: String, in dir: URL) throws -> Bool {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let final = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: final.path) { return false }
        let tmp = dir.appendingPathComponent("." + name + ".tmp")
        try data.write(to: tmp, options: .atomic)
        do {
            try FileManager.default.moveItem(at: tmp, to: final)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            // Course avec un autre processus qui a ecrit le meme ordre : pas une erreur.
            if FileManager.default.fileExists(atPath: final.path) { return false }
            throw error
        }
        return true
    }

    /// Fichiers en attente decodes. Un fichier illisible est renomme `.bad`, jamais
    /// rejoue a l'infini ni supprime en silence.
    static func pending<T: Decodable>(_ type: T.Type, in dir: URL?) -> [(url: URL, op: T)] {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let dec = decoder()
        var out: [(URL, T)] = []
        for url in files where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix(".") {
            if let data = try? Data(contentsOf: url), let op = try? dec.decode(T.self, from: data) {
                out.append((url, op))
            } else {
                try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bad"))
            }
        }
        return out
    }

    static func acknowledge(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

enum WidgetOpKind: String, Codable { case task, water }
enum WidgetOpAction: String, Codable { case complete, uncomplete, add }

struct WidgetOp: Codable, Equatable {
    var version = 1
    let opID: String
    let order: Int64
    let kind: WidgetOpKind
    /// `TodoItem.uid` pour une tache, vide pour l'eau.
    let targetID: String
    let action: WidgetOpAction
    /// Millilitres pour l'eau.
    let amount: Int
    /// Jour metier "yyyy-MM-dd" au moment du geste.
    let day: String
    let timeZone: String
    let createdAt: Date
    let source: String

    init(opID: String? = nil, kind: WidgetOpKind, targetID: String = "", action: WidgetOpAction,
         amount: Int = 0, at date: Date = Date(), timeZone: TimeZone = .current, source: String) {
        self.opID = opID ?? UUID().uuidString
        order = HabitOps.nextOrder(for: date)
        self.kind = kind; self.targetID = targetID; self.action = action; self.amount = amount
        day = HabitOps.businessDay(date, timeZone: timeZone)
        self.timeZone = timeZone.identifier
        // A la seconde : la date sert aussi de cle naturelle a la prise d'eau creee
        // (ISO 8601 ne garde pas les fractions de seconde).
        createdAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        self.source = source
    }

    /// Identifiant d'un ajout d'eau depuis un rendu donne du widget : deux appuis
    /// sur le meme rendu (avant que le widget ne se redessine) donnent le meme
    /// identifiant, donc une seule prise.
    static func waterOpID(day: String, baseML: Int, amount: Int, renderedAt: Date) -> String {
        "water-\(day)-\(baseML)-\(amount)-\(Int(renderedAt.timeIntervalSince1970))"
    }
}

enum WidgetOps {
    nonisolated(unsafe) static var directoryOverride: URL?
    nonisolated(unsafe) static var ledgerDefaultsOverride: UserDefaults?

    static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return LifeOSGroup.container?.appendingPathComponent("WidgetOps", isDirectory: true)
    }

    static func fileName(_ op: WidgetOp) -> String {
        let safe = op.opID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return String(safe) + ".json"
    }

    /// Rend `false` si un ordre de meme identifiant est deja en file (double appui).
    @discardableResult
    static func enqueue(_ op: WidgetOp) throws -> Bool {
        guard let dir = directory else { throw CocoaError(.fileNoSuchFile) }
        if AppliedLedger.contains(op.opID, defaults: ledgerDefaults) { return false }
        return try OpFileQueue.write(OpFileQueue.encoder().encode(op), name: fileName(op), in: dir)
    }

    static func pending() -> [(url: URL, op: WidgetOp)] {
        OpFileQueue.pending(WidgetOp.self, in: directory)
            .sorted { $0.op.order != $1.op.order ? $0.op.order < $1.op.order : $0.op.opID < $1.op.opID }
    }

    static func acknowledge(_ url: URL) { OpFileQueue.acknowledge(url) }

    static var ledgerDefaults: UserDefaults? { ledgerDefaultsOverride ?? LifeOSGroup.defaults }
}

/// Derniers identifiants d'ordres appliques (borne). Un ordre deja applique n'est
/// jamais applique une seconde fois, meme rejoue.
enum AppliedLedger {
    static let key = "widget_ops_applied_v1"
    static let capacity = 400

    static func contains(_ id: String, defaults: UserDefaults?) -> Bool {
        (defaults?.stringArray(forKey: key) ?? []).contains(id)
    }

    static func record(_ ids: [String], defaults: UserDefaults?) {
        guard let defaults, !ids.isEmpty else { return }
        var list = defaults.stringArray(forKey: key) ?? []
        for id in ids where !list.contains(id) { list.append(id) }
        if list.count > capacity { list.removeFirst(list.count - capacity) }
        defaults.set(list, forKey: key)
    }
}

/// Signal entre processus (notification Darwin, sans contenu) : le widget previent
/// l'app qu'un ordre attend. Si l'app tourne, elle l'applique tout de suite ; sinon
/// elle le fera au prochain retour au premier plan.
enum WidgetOpsSignal {
    static let name = "com.chifandco.lifeos.widgetops"

    static func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name as CFString), nil, nil, true)
    }
}
