import Foundation
import UIKit

// MARK: - Configuration

enum AgentAPIConfig {
    // TODO: Set to deployed backend URL before shipping
    // Use .xcconfig / Info.plist injection to avoid hardcoding in source
    static let baseURL = URL(string: "http://192.168.1.7:8000")!
    // INTERNAL_API_KEY from backend/.env — move to Keychain or .xcconfig in production
    static let apiKey = "82d35e070ca086f995b84718054cfac5"
    static let timeoutInterval: TimeInterval = 30
}

// MARK: - Models

struct ChatRequest: Encodable {
    let device_id: String
    let message: String
    let module: String?
    let conversation_id: String?
    let apns_token: String?
}

struct ChatResponse: Decodable {
    let conversation_id: String
    let reply: String
    let tool_calls_executed: [String]
    let module_config_updated: Bool
    let goals_updated: Bool
    let actions: [AIAction]?
}

struct ModuleConfig: Decodable {
    let module_type: String
    let config: [String: AnyCodable]
    let updated_at: String
}

struct GoalOut: Decodable, Identifiable {
    let id: String
    let title: String
    let module: String
    let target_value: Double?
    let current_value: Double
    let unit: String?
    let frequency: String?
    let priority: Int
    let progress_pct: Double
}

struct GoalCreate: Encodable {
    let module_type: String
    let title: String
    let description: String?
    let target_value: Double?
    let unit: String?
    let frequency: String?
    let priority: Int
}

struct ChallengeOut: Decodable, Identifiable {
    let id: String
    let title: String
    let challenge_type: String
    let daily_target: Double?
    let unit: String?
    let duration_days: Int?
    let streak_days: Int
    let days_elapsed: Int
    let days_since_checkin: Int?
    let last_checkin_at: String?
    let notes: String?
    let is_active: Bool
    let started_at: String

    var isAbandoned: Bool {
        guard let days = days_since_checkin else {
            return days_elapsed >= 3
        }
        return days >= 3
    }

    var progressFraction: Double {
        guard let total = duration_days, total > 0 else { return 0 }
        return min(1.0, Double(days_elapsed) / Double(total))
    }

    var checkedInToday: Bool {
        guard let days = days_since_checkin else { return false }
        return days == 0
    }
}

// MARK: - Energy Score

struct EnergyCheckinRequest: Encodable {
    let device_id: String
    let checkin_date: String?
    let sleep_quality: Int?
    let sleep_hours: Double?
    let mood: Int?
    let fatigue: Int?
    let water_ml: Int?
    let habits_done: Int?
    let habits_total: Int?
    let sport_minutes: Int?
}

struct EnergyScoreOut: Decodable {
    let checkin_date: String
    let sleep_quality: Int?
    let sleep_hours: Double?
    let mood: Int?
    let fatigue: Int?
    let water_ml: Int?
    let habits_done: Int?
    let habits_total: Int?
    let sport_minutes: Int?
    let energy_score: Int?
    let label: String?
    let color: String?
}

struct EnergyHistoryOut: Decodable {
    let history: [EnergyScoreOut]
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v; return }
        if let v = try? container.decode(Int.self)    { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self) { value = v; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [String: AnyCodable]: try container.encode(v)
        case let v as [AnyCodable]: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}

// MARK: - API Errors

enum AgentAPIError: LocalizedError {
    case invalidResponse(Int)
    case decodingFailed(Error)
    case networkError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return "Erreur serveur (\(code))"
        case .decodingFailed: return "Réponse inattendue du serveur"
        case .networkError(let err): return "Erreur réseau: \(err.localizedDescription)"
        case .unauthorized: return "Clé API invalide"
        }
    }
}

// MARK: - AgentAPI

actor AgentAPI {
    static let shared = AgentAPI()

    private let session: URLSession
    private var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AgentAPIConfig.timeoutInterval
        config.timeoutIntervalForResource = AgentAPIConfig.timeoutInterval
        session = URLSession(configuration: config)
    }

    // MARK: - Chat

    func chat(
        message: String,
        module: String?,
        conversationID: String?
    ) async throws -> ChatResponse {
        let body = ChatRequest(
            device_id: deviceID,
            message: message,
            module: module,
            conversation_id: conversationID,
            apns_token: await currentAPNsToken()
        )
        return try await post(path: "/api/v1/chat", body: body)
    }

    // MARK: - Module Config

    func getModuleConfig(module: String) async throws -> ModuleConfig {
        return try await get(path: "/api/v1/modules/\(module)", queryItems: [
            URLQueryItem(name: "device_id", value: deviceID)
        ])
    }

    // MARK: - Goals

    func listGoals(module: String? = nil) async throws -> [GoalOut] {
        var items: [URLQueryItem] = [URLQueryItem(name: "device_id", value: deviceID)]
        if let m = module { items.append(URLQueryItem(name: "module", value: m)) }
        let result: [String: [GoalOut]] = try await get(path: "/api/v1/goals", queryItems: items)
        return result["goals"] ?? []
    }

    func createGoal(_ goal: GoalCreate) async throws {
        let _: [String: String] = try await post(
            path: "/api/v1/goals?device_id=\(deviceID)", body: goal
        )
    }

    // MARK: - Challenges

    func fetchChallenges(activeOnly: Bool = true) async throws -> [ChallengeOut] {
        let items: [URLQueryItem] = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "active_only", value: activeOnly ? "true" : "false"),
        ]
        let result: [String: [ChallengeOut]] = try await get(path: "/api/v1/challenges", queryItems: items)
        return result["challenges"] ?? []
    }

    func checkinChallenge(id: String) async throws -> [String: AnyCodable] {
        var req = makeRequest(path: "/api/v1/challenges/\(id)/checkin?device_id=\(deviceID)")
        req.httpMethod = "POST"
        let (data, response) = try await session.data(for: req)
        try validateResponse(data: data, response: response)
        return try decode([String: AnyCodable].self, from: data)
    }

    // MARK: - Energy Score

    func logCheckin(
        sleepQuality: Int? = nil,
        sleepHours: Double? = nil,
        mood: Int? = nil,
        fatigue: Int? = nil,
        waterML: Int? = nil,
        habitsDone: Int? = nil,
        habitsTotal: Int? = nil,
        sportMinutes: Int? = nil
    ) async throws -> EnergyScoreOut {
        let body = EnergyCheckinRequest(
            device_id: deviceID,
            checkin_date: nil,
            sleep_quality: sleepQuality,
            sleep_hours: sleepHours,
            mood: mood,
            fatigue: fatigue,
            water_ml: waterML,
            habits_done: habitsDone,
            habits_total: habitsTotal,
            sport_minutes: sportMinutes
        )
        return try await post(path: "/api/v1/energy/checkin", body: body)
    }

    func fetchEnergyScore() async throws -> EnergyScoreOut {
        return try await get(path: "/api/v1/energy/score", queryItems: [
            URLQueryItem(name: "device_id", value: deviceID)
        ])
    }

    func fetchEnergyHistory(days: Int = 7) async throws -> [EnergyScoreOut] {
        let result: EnergyHistoryOut = try await get(path: "/api/v1/energy/history", queryItems: [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "days", value: "\(days)"),
        ])
        return result.history
    }

    func fetchBehavioralInsights() async throws -> [String] {
        let result: [String: [String]] = try await get(path: "/api/v1/energy/insights", queryItems: [
            URLQueryItem(name: "device_id", value: deviceID)
        ])
        return result["insights"] ?? []
    }

    // MARK: - Goals (delete)

    func deleteGoal(id: String) async throws {
        var req = makeRequest(path: "/api/v1/goals/\(id)?device_id=\(deviceID)")
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try validateResponse(data: data, response: response)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: AgentAPIConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue(AgentAPIConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: req)
        try validateResponse(data: data, response: response)
        return try decode(T.self, from: data)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var req = makeRequest(path: path)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        try validateResponse(data: data, response: response)
        return try decode(Response.self, from: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        var req = URLRequest(url: AgentAPIConfig.baseURL.appendingPathComponent(path))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AgentAPIConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        return req
    }

    @discardableResult
    private func validateResponse(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw AgentAPIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw AgentAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw AgentAPIError.invalidResponse(http.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentAPIError.decodingFailed(error)
        }
    }

    private func currentAPNsToken() async -> String? {
        await MainActor.run {
            UserDefaults.standard.string(forKey: "apnsToken")
        }
    }
}
