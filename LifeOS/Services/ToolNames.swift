import Foundation

/// Noms affiches des outils, pilotes depuis la table Notion.
///
/// Theo renomme un outil dans Notion, le serveur `lifeos-names` relit la
/// table, et l'app recupere les noms a chaque ouverture: pas besoin d'une
/// nouvelle version sur TestFlight pour changer un nom.
///
/// La cle Notion n'est PAS dans l'app. Elle vit sur le serveur, parce qu'une
/// cle embarquee dans un binaire iOS se lit en deux minutes.
///
/// L'app ne depend jamais du reseau pour afficher un nom: hors ligne, elle
/// garde les derniers noms recus, et sans eux, les noms ecrits dans le code.
enum ToolNames {

    /// Cle de stockage. Les vues l'observent via @AppStorage pour se
    /// redessiner quand de nouveaux noms arrivent.
    static let storageKey = "toolNames.v1"
    static let endpoint = URL(string: "https://lifeos-names.chifandcopt.workers.dev/names")!
    static let maxLength = 40

    /// Lit la reponse du serveur. Pure, donc testable sans reseau.
    ///
    /// Un nom vide ou demesure est ecarte ligne par ligne: une faute de
    /// frappe dans Notion ne doit pas vider un bouton ni casser une grille.
    static func parse(_ data: Data) -> [String: String]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["names"] as? [String: Any]
        else { return nil }
        var out: [String: String] = [:]
        for (alias, value) in raw {
            guard let s = value as? String else { continue }
            let name = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !name.isEmpty, name.count <= maxLength else { continue }
            out[alias] = name
        }
        return out.isEmpty ? nil : out
    }

    /// Petit cache: `name(for:)` est appele pour chaque outil a chaque rendu,
    /// et relire le JSON 83 fois par ecran serait du gachis. Verrouille parce
    /// qu'il peut etre lu depuis plusieurs fils.
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var raw: String?
        var names: [String: String] = [:]
    }
    private static let cache = Cache()

    static func current(_ defaults: UserDefaults = .standard) -> [String: String] {
        let raw = defaults.string(forKey: storageKey) ?? ""
        cache.lock.lock(); defer { cache.lock.unlock() }
        if raw == cache.raw { return cache.names }
        let names = raw.data(using: .utf8).flatMap(parse) ?? [:]
        cache.raw = raw
        cache.names = names
        return names
    }

    /// Nom a afficher pour un outil, ou nil pour garder celui du code.
    static func name(for alias: String) -> String? {
        alias.isEmpty ? nil : current()[alias]
    }

    /// Recupere les noms. Silencieux en cas d'echec: les noms deja connus
    /// restent en place, rien ne s'affiche de travers.
    ///
    /// Sur le fil principal: l'ecriture reveille les vues qui observent la
    /// cle, et l'attente reseau ne bloque pas l'interface pour autant.
    @MainActor
    static func refresh(_ defaults: UserDefaults = .standard) async {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let names = parse(data),
              let stored = try? JSONSerialization.data(withJSONObject: ["names": names], options: [.sortedKeys]),
              let text = String(data: stored, encoding: .utf8)
        else {
            AppLog.general.info("noms des outils: pas de mise a jour, on garde les derniers connus")
            return
        }
        if defaults.string(forKey: storageKey) != text {
            defaults.set(text, forKey: storageKey)
        }
    }
}
