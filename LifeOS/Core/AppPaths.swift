import Foundation

/// Ou LifeOS range ses fichiers. UN seul endroit, pour toute l'app.
///
/// Le danger mesure le 28 septembre: sur Mac, une copie NON sandboxee (signature
/// locale sans droits) recoit pour "Documents" le vrai `~/Documents` de
/// l'utilisateur. LifeOS y ecrivait deja `analytics.jsonl`, a cote des dossiers
/// personnels. La sauvegarde complete aurait copie tout `~/Documents`, et une
/// restauration aurait DEPLACE tout son contenu. Ici, hors sandbox, LifeOS a son
/// propre dossier, et rien d'autre n'est jamais parcouru.
enum AppPaths {

    static let bundleFolder = "com.chifandco.lifeos"

    /// Vrai sur Mac quand l'app tourne sans sandbox: les dossiers systeme sont
    /// alors ceux de l'utilisateur, partages avec tout le reste.
    static var isUnsandboxedMac: Bool {
        #if targetEnvironment(macCatalyst)
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
        #else
        return false
        #endif
    }

    /// Racine privee de LifeOS hors sandbox: `~/Library/Application Support/com.chifandco.lifeos`.
    private static var privateRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleFolder, isDirectory: true)
    }

    /// Fichiers de l'utilisateur crees par LifeOS (photos, pages, audio, journaux).
    static var documents: URL {
        let url = isUnsandboxedMac
            ? privateRoot.appendingPathComponent("Documents", isDirectory: true)
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Restaurations en attente et copies de securite.
    static var support: URL {
        let url = isUnsandboxedMac
            ? privateRoot
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = isUnsandboxedMac ? base.appendingPathComponent(bundleFolder, isDirectory: true) : base
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Fichiers possedes par LifeOS

    /// Noms fixes ecrits par LifeOS.
    static let ownedNames: Set<String> = [
        "analytics.jsonl", "coach_reports.jsonl", "coach_feedback.jsonl",
        "glassprobe.txt", "routesmoke.txt", "translateprobe.txt", "Yuko", "Trilingo", "Nuits", "yuko-check.txt",
    ]

    /// Vrai seulement pour un nom que LifeOS a pu creer lui meme:
    /// `<prefixe>-<UUID>.jpg` (ImageStore), `dream-<horodatage>.m4a`, ou un nom fixe.
    /// Tout le reste appartient a l'utilisateur et n'est jamais touche.
    static func isOwned(_ name: String) -> Bool {
        if ownedNames.contains(name) { return true }
        let image = #"^[a-z]+-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.(jpg|jpeg|png)$"#
        let dream = #"^dream-[0-9]{9,11}\.m4a$"#
        return name.range(of: image, options: .regularExpression) != nil
            || name.range(of: dream, options: .regularExpression) != nil
    }

    /// Une seule fois, hors sandbox: deplace de `~/Documents` vers le dossier prive
    /// les SEULS fichiers que LifeOS a crees. Rend les noms deplaces.
    @discardableResult
    static func migrateOwnedFiles(from legacy: URL, to target: URL) -> [String] {
        let fm = FileManager.default
        guard legacy.standardizedFileURL != target.standardizedFileURL,
              let items = try? fm.contentsOfDirectory(atPath: legacy.path) else { return [] }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        var moved: [String] = []
        for name in items where isOwned(name) {
            let src = legacy.appendingPathComponent(name), dst = target.appendingPathComponent(name)
            guard !fm.fileExists(atPath: dst.path) else { continue }   // jamais d'ecrasement
            if (try? fm.moveItem(at: src, to: dst)) != nil { moved.append(name) }
        }
        return moved
    }

    /// Appele au lancement. Sans effet sur iPhone, iPad et Mac sandboxe.
    static func migrateIfNeeded() {
        guard isUnsandboxedMac else { return }
        let legacy = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let moved = migrateOwnedFiles(from: legacy, to: documents)
        if !moved.isEmpty { AppLog.data.info("AppPaths: \(moved.count) fichier(s) LifeOS sortis de ~/Documents") }
    }
}
