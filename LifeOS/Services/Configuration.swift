import Foundation

/// Shim minimal — depuis Option C (100 % local), l'app n'a plus de backend
/// à contacter. Les champs `apiBaseURL` et `apiKey` restent lisibles pour
/// ne pas casser l'écran de config dev (`ServerConfigView`, `#if DEBUG`)
/// mais leur valeur ne sert plus à rien côté production.
enum Configuration {

    static var apiBaseURL: String {
        UserDefaults.standard.string(forKey: "dev.apiBaseURL") ?? ""
    }

    static var apiKey: String {
        UserDefaults.standard.string(forKey: "dev.apiKey") ?? ""
    }
}
