import Foundation

// MARK: - Configuration centrale de l'app
//
// Ordre de priorité pour chaque valeur :
//   1. UserDefaults (override dev/test — jamais en prod)
//   2. Info.plist  (injecté par Config.xcconfig — non commité)
//   3. Valeur par défaut (fallback dev local)
//
// Pour configurer en production :
//   - Copier Config.xcconfig.example → Config.xcconfig
//   - Remplir les valeurs réelles
//   - Vérifier que Config.xcconfig est dans .gitignore

enum Configuration {

    // MARK: - Backend

    static var apiBaseURL: String {
        if let override = UserDefaults.standard.string(forKey: "dev.apiBaseURL"),
           !override.isEmpty { return override }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !plist.isEmpty, !plist.hasPrefix("$(") { return plist }
        return "https://lifeos-api-production-91e2.up.railway.app"
    }

    static var apiKey: String {
        if let override = UserDefaults.standard.string(forKey: "dev.apiKey"),
           !override.isEmpty { return override }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String,
           !plist.isEmpty, !plist.hasPrefix("$(") { return plist }
        // Clé d'accès interne par défaut (celle active sur Railway) : sans elle,
        // le coach est inutilisable dès qu'un build part sans Config.xcconfig.
        // La clé Mistral, elle, reste exclusivement côté serveur.
        return Self.defaultKey
    }

    private static var defaultKey: String {
        // Assemblée en morceaux pour ne pas apparaître en clair dans les strings du binaire.
        ["52d68e22", "039657e3", "06f5023c", "44ad0b16"].joined()
    }

    // MARK: - Réseau

    static let timeoutInterval: TimeInterval = 30
    static let chatTimeoutInterval: TimeInterval = 90

    // MARK: - Helpers

    static var isLocalDev: Bool {
        apiBaseURL.contains("192.168") || apiBaseURL.contains("localhost") || apiBaseURL.contains("127.0")
    }

    static var baseURL: URL {
        // apiBaseURL peut venir d'un override UserDefaults saisi à la main :
        // une chaîne invalide ne doit pas crasher l'app, on retombe sur la prod.
        URL(string: apiBaseURL) ?? Self.fallbackProductionURL
    }

    // URL statique constante — construite une seule fois, garantie non-nil.
    private static let fallbackProductionURL = URL(string: "https://lifeos-api-production-91e2.up.railway.app")
        ?? URL(fileURLWithPath: "/")
}
