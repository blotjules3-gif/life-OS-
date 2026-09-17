import Foundation
import Security

/// Store des providers "custom" configurés par l'utilisateur : n'importe quel
/// endpoint compatible OpenAI ou Anthropic (Ollama local, LM Studio, Perplexity,
/// Together AI, proxy interne d'entreprise, futurs providers…).
///
/// Chaque config est identifiée par un `id` UUID stable, avec :
///   - nom affichable (choisi par l'user, ex: "Mon Ollama")
///   - dialecte (openai-compatible ou anthropic-compatible)
///   - URL base (ex: "http://192.168.1.10:11434/v1")
///   - modèle (ex: "llama3.2:latest")
///   - clé API (stockée à part dans le Keychain, jamais dans les configs)
///
/// Sécurité : les URLs et noms sont dans UserDefaults, les clés dans le Keychain.
@MainActor
final class CustomProviderStore: ObservableObject {
    static let shared = CustomProviderStore()

    /// Dialecte de l'API exposée par l'endpoint custom.
    enum Dialect: String, Codable, CaseIterable, Sendable {
        case openaiCompatible = "openai"
        case anthropicCompatible = "anthropic"

        var displayName: String {
            switch self {
            case .openaiCompatible: return "Compatible OpenAI"
            case .anthropicCompatible: return "Compatible Anthropic"
            }
        }

        /// Exemples d'endpoints connus, affichés en aide UI.
        var examples: [String] {
            switch self {
            case .openaiCompatible:
                return [
                    "http://localhost:11434/v1 (Ollama)",
                    "http://localhost:1234/v1 (LM Studio)",
                    "https://api.perplexity.ai (Perplexity)",
                    "https://api.together.xyz/v1 (Together AI)",
                ]
            case .anthropicCompatible:
                return [
                    "https://votre-proxy.entreprise.com/v1 (proxy interne)",
                ]
            }
        }
    }

    /// Config utilisateur d'un provider custom.
    struct Config: Codable, Identifiable, Equatable, Hashable {
        let id: UUID
        var name: String
        var dialect: Dialect
        var baseURL: String
        var model: String

        /// providerID exposé au router — préfixé pour éviter tout conflit avec les
        /// providers built-in.
        var providerID: String { "custom.\(dialect.rawValue).\(id.uuidString)" }

        /// Slot Keychain calculé à partir de l'id.
        var keychainService: String { "ai.credentials.custom.\(id.uuidString)" }
    }

    // MARK: - Persistence

    private let storageKey = "ai.custom.providers.v1"

    @Published private(set) var configs: [Config] = []

    private init() {
        reload()
    }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([Config].self, from: data) else {
            configs = []
            return
        }
        configs = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - CRUD configs

    /// Ajoute une nouvelle config. Retourne l'id créé.
    @discardableResult
    func add(name: String, dialect: Dialect, baseURL: String, model: String, apiKey: String?) -> UUID {
        let config = Config(id: UUID(), name: name, dialect: dialect, baseURL: baseURL, model: model)
        configs.append(config)
        save()
        if let apiKey, !apiKey.isEmpty {
            setKey(apiKey, for: config)
        }
        objectWillChange.send()
        return config.id
    }

    func update(_ config: Config) {
        guard let idx = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[idx] = config
        save()
        objectWillChange.send()
    }

    func delete(_ id: UUID) {
        guard let config = configs.first(where: { $0.id == id }) else { return }
        deleteKey(for: config)
        configs.removeAll { $0.id == id }
        save()
        objectWillChange.send()
    }

    func config(for providerID: String) -> Config? {
        configs.first { $0.providerID == providerID }
    }

    // MARK: - Keychain per-config

    /// Lit la clé API d'une config. `nil` si absente ou pas de clé (endpoints
    /// locaux type Ollama qui n'exigent pas d'auth).
    func key(for config: Config) -> String? {
        var query: [String: Any] = baseQuery(for: config)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    @discardableResult
    func setKey(_ key: String, for config: Config) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        let query = baseQuery(for: config)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func deleteKey(for config: Config) -> Bool {
        let status = SecItemDelete(baseQuery(for: config) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(for config: Config) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: config.keychainService,
            kSecAttrAccount as String: "lifeos",
        ]
    }
}
