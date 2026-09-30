import Foundation

// Partage entre l'app et l'extension widgets (dossier LifeOSShared, compile dans
// les deux cibles). Ici: le format des ordres d'habitude venus d'en dehors de
// l'app, leur file durable, et l'instantane affiche par les widgets.
//
// Pourquoi une file de FICHIERS et pas une liste dans les UserDefaults partages:
// l'app et le widget sont deux processus. Une liste qu'on lit, modifie puis
// reecrit perd une action quand les deux ecrivent en meme temps. Un fichier par
// ordre, cree d'un coup, ne peut ni ecraser ni etre ecrase.

enum LifeOSGroup {
    static let id = "group.com.chifandco.lifeos"
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
}

/// Ordre EXPLICITE: jamais "inverser", pour qu'un double appui ou un ordre rejoue
/// deux fois donne le meme resultat.
enum HabitAction: String, Codable { case complete, uncomplete }

struct HabitOp: Codable, Equatable {
    var version = 2
    let opID: String
    /// Ordre explicite, en microsecondes, strictement croissant dans un processus.
    /// `createdAt` passe par ISO 8601, qui ne garde que la seconde: deux gestes
    /// opposes dans la meme seconde (cocher puis decocher) pouvaient etre rejoues
    /// dans le desordre. Cette valeur survit a la serialisation telle quelle.
    let order: Int64
    /// Identifiant stable de l'habitude (`Habit.uid`). Jamais le nom: deux
    /// habitudes peuvent porter le meme.
    let habitID: String
    let action: HabitAction
    /// Jour metier "yyyy-MM-dd", calcule dans le fuseau de l'utilisateur AU MOMENT
    /// du geste: un appui a 23 h 59 compte pour ce jour-la, meme rejoue le lendemain.
    let day: String
    let timeZone: String
    let createdAt: Date
    /// "widget", "notification".
    let source: String

    init(habitID: String, action: HabitAction, at date: Date = Date(), timeZone: TimeZone = .current, source: String) {
        opID = UUID().uuidString
        order = HabitOps.nextOrder(for: date)
        self.habitID = habitID; self.action = action
        day = HabitOps.businessDay(date, timeZone: timeZone)
        self.timeZone = timeZone.identifier
        createdAt = date; self.source = source
    }

    private enum CodingKeys: String, CodingKey { case version, opID, order, habitID, action, day, timeZone, createdAt, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        opID = try c.decode(String.self, forKey: .opID)
        habitID = try c.decode(String.self, forKey: .habitID)
        action = try c.decode(HabitAction.self, forKey: .action)
        day = try c.decode(String.self, forKey: .day)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = try c.decode(String.self, forKey: .source)
        // Ordre en file ecrit par la version 1 (sans ce champ): la seconde suffit.
        order = try c.decodeIfPresent(Int64.self, forKey: .order) ?? Int64(createdAt.timeIntervalSince1970 * 1_000_000)
    }
}

enum HabitOps {
    /// Remplacable dans les tests.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return LifeOSGroup.container?.appendingPathComponent("HabitOps", isDirectory: true)
    }

    private static let orderLock = NSLock()
    nonisolated(unsafe) private static var lastOrder: Int64 = 0

    /// Microsecondes depuis 1970, jamais deux fois la meme valeur ni en arriere
    /// dans ce processus (horloge identique ou reculee: +1).
    static func nextOrder(for date: Date) -> Int64 {
        orderLock.lock(); defer { orderLock.unlock() }
        let now = Int64(date.timeIntervalSince1970 * 1_000_000)
        lastOrder = max(now, lastOrder + 1)
        return lastOrder
    }

    static func businessDay(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Ecrit l'ordre dans son propre fichier, d'un coup (fichier temporaire puis
    /// renommage atomique). Echec = erreur remontee, jamais silencieuse.
    static func enqueue(_ op: HabitOp) throws {
        guard let dir = directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(op)
        let name = String(format: "%.6f", op.createdAt.timeIntervalSince1970) + "-" + op.opID + ".json"
        let tmp = dir.appendingPathComponent("." + name + ".tmp")
        try data.write(to: tmp, options: .atomic)
        try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(name))
    }

    /// Ordres en attente, dans l'ordre ou ils ont ete donnes. Un fichier illisible
    /// est mis de cote (renomme .bad), pas supprime ni rejoue a l'infini.
    static func pending() -> [(url: URL, op: HabitOp)] {
        guard let dir = directory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        var out: [(URL, HabitOp)] = []
        for url in files where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix(".") {
            if let data = try? Data(contentsOf: url), let op = try? dec.decode(HabitOp.self, from: data) {
                out.append((url, op))
            } else {
                try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bad"))
            }
        }
        return out.sorted { $0.1.order != $1.1.order ? $0.1.order < $1.1.order : $0.1.opID < $1.1.opID }
    }

    /// Accuse de traitement: appele SEULEMENT apres une sauvegarde reussie.
    static func acknowledge(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

/// Instantane des habitudes du jour, lu par les widgets. Versionne; il affiche,
/// il ne sauvegarde rien: la verite reste dans la base de l'app.
struct HabitSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var icon: String
        var colorHex: Int
        var done: Bool
    }
    var version = 2
    /// Jour metier de l'instantane. Un autre jour = instantane perime: tout est a
    /// faire (les coches sont par jour).
    var day: String
    var timeZone: String
    var generatedAt: Date
    var habits: [Entry]

    static let key = "widget_habits_v2"

    static func read(from d: UserDefaults? = LifeOSGroup.defaults) -> HabitSnapshot? {
        guard let data = d?.data(forKey: key) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(HabitSnapshot.self, from: data)
    }

    func write(to d: UserDefaults? = LifeOSGroup.defaults) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(self) { d?.set(data, forKey: Self.key) }
    }

    /// Ce que l'utilisateur doit voir AUJOURD'HUI: apres minuit, plus rien de coche.
    func current(now: Date = Date(), timeZone tz: TimeZone = .current) -> HabitSnapshot {
        let today = HabitOps.businessDay(now, timeZone: tz)
        guard day != today else { return self }
        var s = self
        s.day = today
        s.habits = habits.map { var e = $0; e.done = false; return e }
        return s
    }

    /// Affichage immediat apres un geste dans le widget (la sauvegarde, elle, est
    /// l'ordre en file).
    func applying(_ op: HabitOp) -> HabitSnapshot {
        var s = self
        if s.day != op.day { s = current() }
        s.habits = s.habits.map { e in
            guard e.id == op.habitID else { return e }
            var e = e; e.done = op.action == .complete; return e
        }
        return s
    }
}
