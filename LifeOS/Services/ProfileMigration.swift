import Foundation
import SwiftData

/// Migration one-shot des données existantes vers `ProfileField`.
///
/// Lit toutes les clés UserDefaults connues (@AppStorage historiques) et les
/// blobs JSON `moduleConfig_*` créés par l'onboarding, puis crée les
/// `ProfileField` correspondants avec `source = .migration` et
/// `confidence = 1.0`.
///
/// Idempotent : incrémenter `Self.version` re-déclenche la migration.
/// Chaque `upsert` respecte la règle "manuel ne s'écrase pas" — donc si le
/// user a déjà rempli quelque chose via chat depuis, on ne l'écrase pas.
@MainActor
enum ProfileMigration {

    /// Incrémenter à chaque changement de mapping.
    static let version = 2

    private static let versionKey = "profile_migration_version"

    static var didRun: Bool {
        UserDefaults.standard.integer(forKey: versionKey) >= version
    }

    /// Point d'entrée. À appeler dans `LifeOSApp` juste après le buildContainer.
    /// No-op si `didRun == true`.
    static func runIfNeeded(context: ModelContext) {
        guard !didRun else { return }
        ProfileStore.shared.setContext(context)
        migrateAppStorageKeys()
        migrateModuleConfigs()
        UserDefaults.standard.set(version, forKey: versionKey)
        AppLog.data.info("ProfileMigration v\(version) done")
    }

    // MARK: - AppStorage → ProfileField

    /// Mapping des clés `@AppStorage` scalaires vers `ProfileField.fieldID`.
    /// Toute clé non listée reste en UserDefaults (aucune migration n'est
    /// destructive — on ne supprime rien).
    private static let scalarMappings: [(udKey: String, fieldID: String, valueType: ProfileFieldSpec.ValueType)] = [
        // Identité
        ("userWeightKg", "body.currentWeightKg", .double),
        ("userHeightCm", "body.heightCm", .double),
        ("userAge", "body.ageYears", .int),
        ("userGender", "body.gender", .enum),
        ("userHasCycle", "body.hasCycle", .bool),
        ("userActivity", "body.activityLevel", .enum),

        // Fitness force
        ("userBench1RM", "fitness.bench1RM", .double),
        ("userSquat1RM", "fitness.squat1RM", .double),
        ("userDeadlift1RM", "fitness.deadlift1RM", .double),
        ("userTrainingYears", "fitness.trainingYears", .int),
        ("userWeeklyFrequency", "fitness.gymFrequency", .int),

        // Nutrition
        ("kcalGoal", "nutrition.kcalGoal", .int),
        ("proteinGoal", "nutrition.proteinGoal", .int),
        ("waterGoal", "nutrition.waterGoal", .int),

        // Sleep
        ("sleepGoalHours", "sleep.targetHours", .double),
        ("bedHour", "sleep.bedtimeHour", .int),
        ("wakeupHour", "sleep.wakeupHour", .int),

        // Productivity / mind
        ("focusMinGoal", "productivity.focusMinutes", .int),
        ("meditationGoalMin", "mind.meditationMinutes", .int),

        // Finance
        ("budgetGoal", "finance.monthlyBudget", .double),

        // Cycle
        ("cycleLengthDays", "cycle.averageLengthDays", .int),
    ]

    private static func migrateAppStorageKeys() {
        let ud = UserDefaults.standard
        for (udKey, fieldID, valueType) in scalarMappings {
            guard let value = readScalar(from: ud, key: udKey, valueType: valueType) else { continue }
            _ = ProfileStore.shared.upsert(
                fieldID,
                value: value,
                source: .migration,
                confidence: 1.0,
                reason: "app_storage_migration"
            )
        }
    }

    private static func readScalar(from ud: UserDefaults, key: String, valueType: ProfileFieldSpec.ValueType) -> Any? {
        // Distinguer "absent" de "présent avec valeur par défaut" via object(forKey:).
        guard ud.object(forKey: key) != nil else { return nil }
        switch valueType {
        case .int:
            let v = ud.integer(forKey: key)
            return v == 0 ? nil : v  // les défauts scalaires 0 sont ambigus, on skip
        case .double:
            let v = ud.double(forKey: key)
            return v == 0 ? nil : v
        case .bool:
            return ud.bool(forKey: key)
        case .string, .enum:
            let v = ud.string(forKey: key) ?? ""
            return v.isEmpty ? nil : v
        case .array:
            return ud.stringArray(forKey: key)
        }
    }

    // MARK: - moduleConfig_* JSON blobs → ProfileField

    /// Mapping (module, JSON key interne) → fieldID pour l'onboarding actuel.
    /// Format actuel du blob : `{"location": "gym", "frequency": "3-4"}`.
    private static let moduleConfigMappings: [String: [String: String]] = [
        "fitness": [
            "location": "fitness.location",
            "frequency": "fitness.gymFrequency",
            "goal": "goals.primary",
        ],
        "nutrition": [
            "diet": "nutrition.diet",
            "goal": "goals.primary",
        ],
        "sleep": [
            "bedtime": "sleep.bedtimeHour",
            "issue": "sleep.issues",
        ],
        "mind": [
            "stress": "mind.stressLevel",
        ],
        "finance": [
            "goal": "goals.primary",
        ],
        "invest": [
            "level": "invest.experienceLevel",
            "risk": "invest.riskProfile",
        ],
        "career": [
            "goal": "career.goal",
        ],
        "learning": [
            "time": "learning.dailyMinutes",
        ],
        "looks": [
            "skincare": "looks.skincareRoutine",
        ],
        "social": [
            "type": "social.personality",
        ],
        "home": [
            "type": "home.type",
        ],
        "mobility": [
            "vehicle": "mobility.mainVehicle",
        ],
        "travel": [
            "style": "travel.style",
        ],
    ]

    private static func migrateModuleConfigs() {
        for (module, mapping) in moduleConfigMappings {
            let udKey = "moduleConfig_\(module)"
            guard let raw = UserDefaults.standard.string(forKey: udKey),
                  let data = raw.data(using: .utf8),
                  let config = try? JSONDecoder().decode([String: String].self, from: data) else { continue }

            for (internalKey, rawValue) in config where !rawValue.isEmpty {
                guard let fieldID = mapping[internalKey] else { continue }
                guard let spec = ProfileFieldCatalog.all[fieldID] else { continue }
                let typedValue = interpretValue(rawValue, type: spec.valueType)
                _ = ProfileStore.shared.upsert(
                    fieldID,
                    value: typedValue,
                    source: .migration,
                    confidence: 1.0,
                    reason: "module_config_migration"
                )
            }
        }
    }

    /// Certains blobs stockent des strings représentant des ranges ("3-4 fois")
    /// ou des enums libres. On essaie de convertir vers le type déclaré du spec.
    private static func interpretValue(_ raw: String, type: ProfileFieldSpec.ValueType) -> Any {
        switch type {
        case .int:
            // "3-4" → 3, "5+" → 5, "6 fois" → 6, sinon 0
            let digits = raw.filter { $0.isNumber }
            return Int(digits.prefix(2)) ?? 0
        case .double:
            let cleaned = raw.replacingOccurrences(of: ",", with: ".")
            return Double(cleaned.filter { $0.isNumber || $0 == "." }) ?? 0.0
        case .bool:
            let low = raw.lowercased()
            return ["oui", "yes", "true", "1"].contains(low)
        default:
            return raw
        }
    }
}
