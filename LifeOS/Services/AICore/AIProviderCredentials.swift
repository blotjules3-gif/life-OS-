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

        /// Préfixe attendu pour valider un format minimal avant enregistrement.
        /// `nil` = pas de préfixe standardisé (Mistral / Gemini).
        var expectedPrefix: String? {
            switch self {
            case .openai:    return "sk-"
            case .anthropic: return "sk-ant-"
            case .mistral:   return nil
            case .gemini:    return nil
            }
        }

        /// Longueur minimale plausible (garde-fou contre les copies tronquées).
        var minLength: Int {
            switch self {
            case .openai:    return 40
            case .anthropic: return 40
            case .mistral:   return 20
            case .gemini:    return 20
            }
        }

        /// providerID exact utilisé par l'AIProvider concret — utilisé pour la
        /// préférence utilisateur (match exact côté router).
        var providerID: String {
            switch self {
            case .openai:    return "openai.gpt"
            case .anthropic: return "anthropic.claude"
            case .mistral:   return "mistral.direct"
            case .gemini:    return "google.gemini"
            }
        }
    }

    /// Résultat de validation d'une clé — utilisé par le sheet éditeur pour
    /// afficher un message clair avant enregistrement.
    enum ValidationError: Error, LocalizedError {
        case tooShort(min: Int)
        case wrongPrefix(expected: String)

        var errorDescription: String? {
            switch self {
            case .tooShort(let min):
                return "La clé semble tronquée (moins de \(min) caractères)."
            case .wrongPrefix(let expected):
                return "La clé devrait commencer par \"\(expected)\" — vérifie que tu l'as copiée depuis le bon provider."
            }
        }
    }

    /// Valide le format d'une clé avant enregistrement. Retourne `nil` si OK,
    /// sinon un `ValidationError` explicite.
    func validate(_ key: String, for slot: Slot) -> ValidationError? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < slot.minLength {
            return .tooShort(min: slot.minLength)
        }
        if let prefix = slot.expectedPrefix, !trimmed.hasPrefix(prefix) {
            return .wrongPrefix(expected: prefix)
        }
        return nil
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
