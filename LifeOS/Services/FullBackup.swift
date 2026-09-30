import Foundation
import SQLite3
import CryptoKit

/// Sauvegarde COMPLETE et restaurable de LifeOS, dans un seul fichier.
///
/// Pourquoi pas le JSON: `DataExporter` recopie a la main ~25 types sur plus de
/// 50, sans les photos ni les documents. Il ne peut rien reconstruire. Ici on
/// copie ce qui fait l'app, par construction:
///   - la base SwiftData entiere, par `VACUUM INTO` (copie coherente meme app
///     ouverte: SQLite la prend dans une transaction de lecture);
///   - tout le dossier Documents (photos, pages scannees, enregistrements...);
///   - les reglages de l'app et du groupe des widgets, SANS les secrets.
///
/// Format (version 1), lisible sans dependance:
///   "LIFEOSBK" | fichiers bout a bout | manifeste JSON | longueur (UInt64 LE) | "LIFEOSBK"
/// Le manifeste liste chaque fichier avec sa taille et son SHA-256: un octet
/// change et la restauration refuse, au lieu de restaurer une base abimee.
///
/// Restauration: on ne remplace jamais une base ouverte. Le fichier est verifie
/// et prepare, puis applique au lancement suivant AVANT l'ouverture de la base.
/// Les donnees en place sont deplacees dans un dossier date, jamais effacees.
enum FullBackup {

    static let formatVersion = 1
    static let fileExtension = "lifeosbackup"
    private static let magic = Data("LIFEOSBK".utf8)
    static let databaseEntry = "db/default.store"

    struct Entry: Codable, Equatable {
        let path: String
        let size: Int64
        let sha256: String
    }

    struct Manifest: Codable, Equatable {
        var format: Int
        var createdAt: Date
        var appVersion: String
        var entries: [Entry]
        /// Lignes par table de la base au moment de la sauvegarde.
        var rowCounts: [String: Int]

        var totalRows: Int { rowCounts.values.reduce(0, +) }
        var fileCount: Int { entries.filter { $0.path.hasPrefix("documents/") }.count }
    }

    enum Failure: LocalizedError, Equatable {
        case notABackup
        case newerFormat(Int)
        case corrupted(String)
        case missingDatabase
        case databaseUnreadable(String)
        case io(String)
        /// Dossier trop large (le ~/Documents de l'utilisateur, son dossier perso...).
        case unsafeRoot(String)
        /// La restauration a echoue ET le retour arriere aussi: rien n'est efface,
        /// la copie de securite reste la ou elle est.
        case rollbackIncomplete(String)

        var errorDescription: String? {
            switch self {
            case .notABackup: return "Ce fichier n'est pas une sauvegarde LifeOS."
            case .newerFormat(let v): return "Sauvegarde faite par une version plus récente de LifeOS (format \(v)). Mets l'app à jour."
            case .corrupted(let p): return "Sauvegarde abîmée (\(p)). Rien n'a été modifié."
            case .missingDatabase: return "La sauvegarde ne contient pas de base de données."
            case .databaseUnreadable(let m): return "La base de la sauvegarde est illisible : \(m)"
            case .io(let m): return "Erreur de fichier : \(m)"
            case .unsafeRoot(let p): return "Dossier refusé, il n'appartient pas à LifeOS : \(p)"
            case .rollbackIncomplete(let m): return m
            }
        }
    }

    // MARK: - Emplacements de l'app

    struct Locations {
        var store: URL
        var documents: URL
        /// Racine ou vivent la restauration en attente et les copies de securite.
        var support: URL

        var pending: URL { support.appendingPathComponent("LifeOSPendingRestore", isDirectory: true) }
        var pendingMarker: URL { pending.appendingPathComponent("READY") }

        static var app: Locations {
            // Racine propre a LifeOS (voir AppPaths): jamais le ~/Documents de
            // l'utilisateur sur un Mac sans sandbox.
            let fm = FileManager.default
            return Locations(store: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("default.store"),
                             documents: AppPaths.documents,
                             support: AppPaths.support)
        }
    }

    static let groupSuite = "group.com.chifandco.lifeos"

    /// Une cle de reglage qui ressemble a un secret ne part jamais dans un fichier
    /// que l'utilisateur va ranger ou envoyer.
    static func isSecretKey(_ key: String) -> Bool {
        let k = key.lowercased()
        return ["apikey", "api_key", "token", "secret", "password", "motdepasse"].contains { k.contains($0) }
    }

    // MARK: - Creer

    /// Deplacement de fichier. Remplacable dans les tests pour forcer un echec
    /// precis (aller ou retour) sans toucher au vrai disque.
    nonisolated(unsafe) static var mover: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    /// Refuse tout dossier qui n'est pas exclusivement a LifeOS. Le parcours de la
    /// sauvegarde et les deplacements de la restauration ne touchent QUE `documents`:
    /// si ce dossier etait le ~/Documents de l'utilisateur, ils toucheraient ses
    /// fichiers personnels.
    static func checkRoot(_ url: URL, unsandboxedMac: Bool = AppPaths.isUnsandboxedMac,
                          home: String = NSHomeDirectory()) throws {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard p != "/", p.split(separator: "/").count >= 3 else { throw Failure.unsafeRoot(p) }
        // Sur iPhone, iPad et Mac sandboxe, le dossier de l'app est prive. Sur un Mac
        // sans sandbox, "home" est le vrai dossier de l'utilisateur.
        guard unsandboxedMac else { return }
        let h = URL(fileURLWithPath: home).standardizedFileURL.resolvingSymlinksInPath().path
        let personal = [h] + ["Documents", "Desktop", "Downloads", "Library", "Pictures", "Movies", "Music"]
            .map { (h as NSString).appendingPathComponent($0) }
        guard !personal.contains(p), p.contains(AppPaths.bundleFolder) else { throw Failure.unsafeRoot(p) }
    }


    /// `defaults`: nom de domaine -> reglages (deja filtres ou non, filtres ici).
    static func make(at loc: Locations, defaults: [String: [String: Any]], appVersion: String,
                     to output: URL) throws -> Manifest {
        let fm = FileManager.default
        try checkRoot(loc.documents)
        guard fm.fileExists(atPath: loc.store.path) else { throw Failure.missingDatabase }
        let work = fm.temporaryDirectory.appendingPathComponent("lifeos-backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let dbCopy = work.appendingPathComponent("default.store")
        try vacuumInto(source: loc.store, destination: dbCopy)
        let counts = try rowCounts(dbCopy)

        var files: [(path: String, url: URL)] = [(databaseEntry, dbCopy)]
        for (rel, url) in try listFiles(under: loc.documents) {
            files.append(("documents/" + rel, url))
        }
        for (name, dict) in defaults.sorted(by: { $0.key < $1.key }) {
            let clean = dict.filter { !isSecretKey($0.key) }
            let data: Data
            do { data = try PropertyListSerialization.data(fromPropertyList: clean, format: .binary, options: 0) }
            catch { throw Failure.io("réglages \(name) non sérialisables") }
            let url = work.appendingPathComponent("defaults-\(name).plist")
            try data.write(to: url)
            files.append(("defaults/\(name).plist", url))
        }

        let manifest = Manifest(format: formatVersion, createdAt: Date(), appVersion: appVersion,
                                entries: [], rowCounts: counts)
        return try writeArchive(files: files, manifest: manifest, to: output)
    }

    // MARK: - Archive

    static func writeArchive(files: [(path: String, url: URL)], manifest base: Manifest, to output: URL) throws -> Manifest {
        let fm = FileManager.default
        try? fm.removeItem(at: output)
        guard fm.createFile(atPath: output.path, contents: nil),
              let out = try? FileHandle(forWritingTo: output) else { throw Failure.io("écriture impossible") }
        defer { try? out.close() }
        var manifest = base
        do {
            try out.write(contentsOf: magic)
            for f in files {
                guard let input = try? FileHandle(forReadingFrom: f.url) else { throw Failure.io("lecture de \(f.path)") }
                defer { try? input.close() }
                var hasher = SHA256()
                var size: Int64 = 0
                while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                    hasher.update(data: chunk)
                    try out.write(contentsOf: chunk)
                    size += Int64(chunk.count)
                }
                manifest.entries.append(Entry(path: f.path, size: size, sha256: hex(hasher.finalize())))
            }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.sortedKeys]
            let json = try enc.encode(manifest)
            try out.write(contentsOf: json)
            var len = UInt64(json.count).littleEndian
            try out.write(contentsOf: Data(bytes: &len, count: 8))
            try out.write(contentsOf: magic)
        } catch let e as Failure {
            try? fm.removeItem(at: output); throw e
        } catch {
            try? fm.removeItem(at: output); throw Failure.io(error.localizedDescription)
        }
        return manifest
    }

    static func readManifest(_ archive: URL) throws -> Manifest {
        guard let h = try? FileHandle(forReadingFrom: archive) else { throw Failure.io("lecture impossible") }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        let tail = UInt64(magic.count + 8)
        guard end >= UInt64(magic.count) + tail,
              (try? h.seek(toOffset: 0)) != nil, (try? h.read(upToCount: magic.count)) == magic,
              (try? h.seek(toOffset: end - tail)) != nil,
              let lenData = try? h.read(upToCount: 8), lenData.count == 8,
              (try? h.read(upToCount: magic.count)) == magic
        else { throw Failure.notABackup }
        let len = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        guard len > 0, len <= end - tail - UInt64(magic.count),
              (try? h.seek(toOffset: end - tail - len)) != nil,
              let json = try? h.read(upToCount: Int(len))
        else { throw Failure.notABackup }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        // Lire la version AVANT tout le reste: un format plus recent doit donner
        // un message clair, pas une erreur de decodage.
        struct Head: Decodable { let format: Int }
        guard let head = try? dec.decode(Head.self, from: json) else { throw Failure.notABackup }
        guard head.format <= formatVersion else { throw Failure.newerFormat(head.format) }
        guard let m = try? dec.decode(Manifest.self, from: json) else { throw Failure.notABackup }
        let payload = m.entries.reduce(Int64(0)) { $0 + $1.size }
        guard UInt64(payload) == end - tail - len - UInt64(magic.count) else { throw Failure.corrupted("tailles") }
        return m
    }

    /// Extrait et VERIFIE chaque fichier. Rien n'est garde si un seul echoue.
    static func extract(_ archive: URL, to dir: URL) throws -> Manifest {
        let m = try readManifest(archive)
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let h = try? FileHandle(forReadingFrom: archive) else { throw Failure.io("lecture impossible") }
        defer { try? h.close() }
        do {
            try h.seek(toOffset: UInt64(magic.count))
            for e in m.entries {
                guard isSafe(e.path) else { throw Failure.corrupted("chemin \(e.path)") }
                let dest = dir.appendingPathComponent(e.path)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: dest.path, contents: nil)
                let out = try FileHandle(forWritingTo: dest)
                var hasher = SHA256()
                var left = e.size
                while left > 0 {
                    guard let chunk = try h.read(upToCount: Int(min(left, 1 << 20))), !chunk.isEmpty else {
                        try? out.close(); throw Failure.corrupted(e.path)
                    }
                    hasher.update(data: chunk)
                    try out.write(contentsOf: chunk)
                    left -= Int64(chunk.count)
                }
                try out.close()
                guard hex(hasher.finalize()) == e.sha256 else { throw Failure.corrupted(e.path) }
            }
        } catch {
            try? fm.removeItem(at: dir)
            if let f = error as? Failure { throw f }
            throw Failure.io(error.localizedDescription)
        }
        guard m.entries.contains(where: { $0.path == databaseEntry }) else {
            try? fm.removeItem(at: dir); throw Failure.missingDatabase
        }
        return m
    }

    // MARK: - Restaurer

    /// Verifie la sauvegarde et la prepare pour le prochain lancement.
    static func stageRestore(from archive: URL, at loc: Locations) throws -> Manifest {
        let fm = FileManager.default
        try? fm.removeItem(at: loc.pending)
        let m = try extract(archive, to: loc.pending)
        let db = loc.pending.appendingPathComponent(databaseEntry)
        do {
            try integrityCheck(db)
            // Les comptes relus doivent etre ceux ecrits: preuve que la base
            // extraite est bien celle qui a ete sauvegardee.
            guard try rowCounts(db) == m.rowCounts else { throw Failure.corrupted("contenu de la base") }
        } catch {
            try? fm.removeItem(at: loc.pending); throw error
        }
        guard fm.createFile(atPath: loc.pendingMarker.path, contents: Data()) else {
            try? fm.removeItem(at: loc.pending); throw Failure.io("préparation impossible")
        }
        return m
    }

    static func hasPendingRestore(at loc: Locations = .app) -> Bool {
        FileManager.default.fileExists(atPath: loc.pendingMarker.path)
    }

    static func cancelPendingRestore(at loc: Locations = .app) {
        try? FileManager.default.removeItem(at: loc.pending)
    }

    /// A appeler au lancement, AVANT d'ouvrir la base. Rend le dossier ou les
    /// donnees precedentes ont ete mises de cote, ou nil s'il n'y avait rien.
    /// Si un deplacement echoue en route, tout ce qui a ete deplace revient a sa
    /// place: on ne laisse jamais l'app ouvrir une base a moitie echangee.
    @discardableResult
    static func applyPendingRestore(at loc: Locations,
                                    applyDefaults: ([String: [String: Any]]) -> Void) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: loc.pendingMarker.path) else { return nil }
        try checkRoot(loc.documents)

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = loc.support.appendingPathComponent("LifeOSBackup-restore-\(stamp)", isDirectory: true)
        let asideDocs = aside.appendingPathComponent("documents")
        var moves: [(from: URL, to: URL)] = []
        func move(_ from: URL, _ to: URL) throws {
            try mover(from, to)
            moves.append((from, to))
        }

        do {
            try fm.createDirectory(at: asideDocs, withIntermediateDirectories: true)
            try fm.createDirectory(at: loc.documents, withIntermediateDirectories: true)
            try fm.createDirectory(at: loc.store.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 1. Mettre de cote la base actuelle et ses journaux.
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: loc.store.path + suffix)
                if fm.fileExists(atPath: src.path) { try move(src, aside.appendingPathComponent(src.lastPathComponent)) }
            }
            // 2. Mettre de cote les documents actuels.
            // Un dossier illisible est une ERREUR, pas un dossier vide.
            for item in try fm.contentsOfDirectory(at: loc.documents, includingPropertiesForKeys: nil) {
                try move(item, asideDocs.appendingPathComponent(item.lastPathComponent))
            }
            // 3. Poser la base et les documents restaures.
            try move(loc.pending.appendingPathComponent(databaseEntry), loc.store)
            let restoredDocs = loc.pending.appendingPathComponent("documents")
            if fm.fileExists(atPath: restoredDocs.path) {
                for item in try fm.contentsOfDirectory(at: restoredDocs, includingPropertiesForKeys: nil) {
                    try move(item, loc.documents.appendingPathComponent(item.lastPathComponent))
                }
            }
        } catch {
            // Retour arriere: chaque deplacement est defait. La copie de securite
            // n'est supprimee QUE si tout est revenu; sinon elle reste, et l'erreur
            // dit ou elle est et ce qui n'a pas pu revenir.
            var failed: [String] = []
            for m in moves.reversed() {
                do { try mover(m.to, m.from) }
                catch { failed.append(m.from.lastPathComponent) }
            }
            if failed.isEmpty {
                try? fm.removeItem(at: aside)
                throw Failure.io("restauration annulée, rien n'a changé (\(error.localizedDescription))")
            }
            throw Failure.rollbackIncomplete("La restauration a échoué (\(error.localizedDescription)) et \(failed.count) élément(s) n'ont pas pu revenir : \(failed.prefix(5).joined(separator: ", ")). Rien n'a été supprimé : la copie de sécurité est dans \(aside.path).")
        }

        // 4. Reglages, une fois les fichiers en place.
        var defaults: [String: [String: Any]] = [:]
        let dDir = loc.pending.appendingPathComponent("defaults")
        for f in (try? fm.contentsOfDirectory(at: dDir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "plist" {
            if let data = try? Data(contentsOf: f),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                defaults[f.deletingPathExtension().lastPathComponent] = dict
            }
        }
        applyDefaults(defaults)
        try? fm.removeItem(at: loc.pending)
        return aside
    }

    /// Dossier des donnees mises de cote par la restauration de ce lancement.
    @MainActor private(set) static var restoredThisLaunch: URL?
    @MainActor private(set) static var restoreError: String?

    /// Point d'entree unique au lancement, appele par les DEUX chemins qui
    /// ouvrent la base (l'app et `LocalStore`), avant toute ouverture.
    @MainActor
    static func applyAtLaunch(storeURL: URL) {
        var loc = Locations.app
        loc.store = storeURL
        guard hasPendingRestore(at: loc) else { return }
        do {
            restoredThisLaunch = try applyPendingRestore(at: loc, applyDefaults: applyToUserDefaults)
        } catch {
            restoreError = error.localizedDescription
            // Ne pas retenter a chaque lancement une restauration qui echoue.
            cancelPendingRestore(at: loc)
        }
    }

    /// Reglages de l'app en service: les secrets deja presents sont gardes, ils
    /// ne sont jamais dans la sauvegarde.
    static func applyToUserDefaults(_ restored: [String: [String: Any]]) {
        if let bundle = Bundle.main.bundleIdentifier, var dict = restored["standard"] {
            let current = UserDefaults.standard.persistentDomain(forName: bundle) ?? [:]
            for (k, v) in current where isSecretKey(k) { dict[k] = v }
            UserDefaults.standard.setPersistentDomain(dict, forName: bundle)
        }
        if let dict = restored["group"], let group = UserDefaults(suiteName: groupSuite) {
            group.setPersistentDomain(dict, forName: groupSuite)
        }
    }

    static func currentDefaults() -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        if let bundle = Bundle.main.bundleIdentifier {
            out["standard"] = UserDefaults.standard.persistentDomain(forName: bundle) ?? [:]
        }
        out["group"] = UserDefaults(suiteName: groupSuite)?.persistentDomain(forName: groupSuite) ?? [:]
        return out
    }

    // MARK: - SQLite

    static func vacuumInto(source: URL, destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        var db: OpaquePointer?
        guard sqlite3_open_v2(source.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); throw Failure.databaseUnreadable("ouverture")
        }
        defer { sqlite3_close(db) }
        let path = destination.path.replacingOccurrences(of: "'", with: "''")
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, "VACUUM INTO '\(path)'", nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "VACUUM"
            sqlite3_free(err)
            throw Failure.databaseUnreadable(msg)
        }
    }

    static func integrityCheck(_ url: URL) throws {
        let rows = try query(url, "PRAGMA integrity_check")
        guard rows.first?.first == "ok" else { throw Failure.databaseUnreadable(rows.first?.first ?? "vide") }
    }

    /// Lignes par table de donnees (tables SwiftData: Z + nom de l'entite).
    static func rowCounts(_ url: URL) throws -> [String: Int] {
        let tables = try query(url, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\'")
            .compactMap(\.first)
        var out: [String: Int] = [:]
        for t in tables {
            let n = try query(url, "SELECT COUNT(*) FROM \"\(t.replacingOccurrences(of: "\"", with: "\"\""))\"").first?.first
            out[t] = Int(n ?? "0") ?? 0
        }
        return out
    }

    private static func query(_ url: URL, _ sql: String) throws -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); throw Failure.databaseUnreadable("ouverture")
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Failure.databaseUnreadable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(stmt)).map {
                sqlite3_column_text(stmt, $0).map { String(cString: $0) } ?? ""
            })
        }
        return rows
    }

    // MARK: - Aides

    /// Fichiers sous `root`, chemins relatifs, dans un ordre stable.
    /// Un element illisible fait echouer la sauvegarde: une sauvegarde qui saute
    /// des fichiers en silence ferait croire a une copie complete.
    static func listFiles(under root: URL) throws -> [(String, URL)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        var enumerationError: Error?
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                     errorHandler: { _, err in enumerationError = err; return false })
        else { throw Failure.io("dossier illisible : \(root.lastPathComponent)") }
        var out: [(String, URL)] = []
        for case let url as URL in en {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let p = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard p.hasPrefix(base + "/") else { continue }
            out.append((String(p.dropFirst(base.count + 1)), url))
        }
        if let enumerationError { throw Failure.io("lecture impossible dans \(root.lastPathComponent) : \(enumerationError.localizedDescription)") }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Pas de chemin absolu ni de "..": une archive trafiquee ne doit pas ecrire
    /// hors du dossier de restauration.
    static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private static func hex(_ d: SHA256.Digest) -> String { d.map { String(format: "%02x", $0) }.joined() }
}
