import Foundation
import Security

/// Store sécurisé des clés API des providers cloud.
///
/// Contrat : les clés vivent dans le Keychain iOS (`kSecClassGenericPassword`).
/// Jamais dans UserDefaults, jamais loguées, jamais envoyées à un tiers autre
/// que le provider ciblé.
///
/// Utilisation :
///   AIProviderCredentials.shared.setKey("sk-...", for: .openai)
///   let key = AIProviderCredentials.shared.key(for: .openai)  // nil si absent
///   AIProviderCredentials.shared.deleteKey(for: .openai)
///
/// Slot par provider — un slot = un `service` Keychain distinct pour éviter
/// tout mélange (ex: coller une clé Mistral dans le slot OpenAI ne casse rien).
@MainActor
final class AIProviderCredentials {
    static let shared = AIProviderCredentials()

    /// Un slot par provider cloud pris en charge. Aligné avec les IDs des
    /// `AIProvider` concrets pour cohérence logs.
    enum Slot: String, CaseIterable, Sendable {
        case openai       = "ai.credentials.openai"
        case anthropic    = "ai.credentials.anthropic"
        case mistral      = "ai.credentials.mistral"
        case gemini       = "ai.credentials.gemini"

        /// Nom humain pour l'UI.
        var displayName: String {
            switch self {
            case .openai:    return "OpenAI"
            case .anthropic: return "Anthropic"
            case .mistral:   return "Mistral AI"
            case .gemini:    return "Google Gemini"
            }
        }

        /// URL doc où récupérer une clé.
        var docsURL: URL? {
            switch self {
            case .openai:    return URL(string: "https://platform.openai.com/api-keys")
            case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
            case .mistral:   return URL(string: "https://console.mistral.ai/api-keys/")
            case .gemini:    return URL(string: "https://aistudio.google.com/app/apikey")
            }
        }
    }

    private init() {}

    // MARK: - Public API

    /// Retourne la clé stockée ou `nil` si aucune / erreur d'accès.
    func key(for slot: Slot) -> String? {
        var query: [String: Any] = baseQuery(for: slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Stocke une clé (crée ou remplace). Retourne `true` si succès.
    @discardableResult
    func setKey(_ key: String, for slot: Slot) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return false
        }

        // Update si déjà présent, sinon insert.
        let query = baseQuery(for: slot)
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        // Insert
        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        return insertStatus == errSecSuccess
    }

    /// Supprime la clé. No-op si déjà absente.
    @discardableResult
    func deleteKey(for slot: Slot) -> Bool {
        let status = SecItemDelete(baseQuery(for: slot) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Vrai si une clé est présente pour ce slot.
    func hasKey(for slot: Slot) -> Bool {
        key(for: slot) != nil
    }

    // MARK: - Internals

    private func baseQuery(for slot: Slot) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.rawValue,
            kSecAttrAccount as String: "lifeos",
        ]
    }
}
