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
        return "82d35e070ca086f995b84718054cfac5"  // fallback développement local
    }

    // MARK: - Réseau

    static let timeoutInterval: TimeInterval = 30

    // MARK: - Helpers

    static var isLocalDev: Bool {
        apiBaseURL.contains("192.168") || apiBaseURL.contains("localhost")
    }

    static var baseURL: URL {
        URL(string: apiBaseURL)!
    }
}
