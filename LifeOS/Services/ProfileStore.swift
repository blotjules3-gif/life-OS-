import Foundation
import SwiftData

/// CRUD centralisé sur les `ProfileField` avec gestion de confidence, historique
/// et contradictions.
///
/// Toutes les écritures passent par `upsert(...)`. Deux règles absolues :
///
/// 1. Avant chaque modification de valeur, on snapshot l'ancienne dans une
///    `ProfileFieldRevision`. Aucune perte d'historique.
/// 2. Une source « manuelle » (`quiz`, `manual`) ne peut être écrasée par une
///    source LLM (`chat`, `voice`) sans confirmation → retourne
///    `Result.blocked(.contradiction)`.
///
/// Le store est stateless côté données — chaque appel prend le `ModelContext`.
/// Adoption : `ProfileStore.shared.setContext(...)` au boot pour permettre les
/// helpers en pull (`value(_:)`).
@MainActor
final class ProfileStore {
    static let shared = ProfileStore()

    private var ctx: ModelContext?

    private init() {}

    // MARK: - Bootstrap

    func setContext(_ context: ModelContext) {
        self.ctx = context
    }

    // MARK: - Sources & résultats

    enum Source: String {
        case chat, voice, quiz, shortcut, manual, migration
    }

    enum WriteResult {
        case created(ProfileField)
        case updated(ProfileField)
        case ignored(reason: IgnoreReason)
        case blocked(Contradiction)
    }

    enum IgnoreReason {
        case confidenceTooLow          // < 0.60
        case sameValue                  // écrase par le même contenu
        case unknownFieldID             // pas dans le catalog
    }

    struct Contradiction {
        let field: ProfileField
        let newValueString: String
        let newSource: Source
        let newConfidence: Double
    }

    // MARK: - Lecture

    /// Retourne le field brut, ou `nil` s'il n'existe pas.
    func field(_ fieldID: String) -> ProfileField? {
        guard let ctx else { return nil }
        var descriptor = FetchDescriptor<ProfileField>(
            predicate: #Predicate { $0.fieldID == fieldID }
        )
        descriptor.fetchLimit = 1
        return (try? ctx.fetch(descriptor))?.first
    }

    /// Lit la valeur en la castant. Retourne `nil` si absent ou cast impossible.
    func value<T>(_ fieldID: String, as type: T.Type = T.self) -> T? {
        guard let f = field(fieldID) else { return nil }
        return decode(f.valueString, valueType: f.valueType, as: type)
    }

    /// Tous les fields, filtrable par catégorie.
    func allFields(category: String? = nil) -> [ProfileField] {
        guard let ctx else { return [] }
        let descriptor: FetchDescriptor<ProfileField>
        if let category {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.category == category },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    /// Retourne les specs pour lesquels aucune valeur n'existe ou dont la
    /// confidence est très basse. Filtré par sous-objectif si fourni.
    /// `minImportance` évite de proposer des champs de faible priorité au démarrage.
    func missingFields(
        for subGoal: ProfileFieldSpec.SubGoal? = nil,
        minImportance: ProfileFieldSpec.Importance = .medium,
        minConfidenceGap: Double = 0.5
    ) -> [ProfileFieldSpec] {
        let candidates = subGoal.map { ProfileFieldCatalog.specs(for: $0) } ?? Array(ProfileFieldCatalog.all.values)
        return candidates.filter { spec in
            guard spec.importance >= minImportance else { return false }
            guard dependenciesSatisfied(spec) else { return false }
            if let existing = field(spec.id), existing.confidence >= (1.0 - minConfidenceGap) {
                return false
            }
            return true
        }
    }

    /// Vrai si tous les `dependsOn` du spec ont une valeur enregistrée.
    private func dependenciesSatisfied(_ spec: ProfileFieldSpec) -> Bool {
        spec.dependsOn.allSatisfy { field($0) != nil }
    }

    // MARK: - Écriture

    /// Upsert idempotent avec gestion complète du cycle de vie.
    ///
    /// - Parameters:
    ///   - fieldID: identifiant catalog (`ProfileFieldSpec.id`)
    ///   - value: valeur brute (Int, Double, String, Bool, [String]…)
    ///   - source: qui a écrit
    ///   - confidence: 0.0 - 1.0
    ///   - reason: raison libre pour l'historique
    ///   - allowOverwriteManual: force l'écrasement d'une source manuelle
    ///     (à utiliser quand l'utilisateur a confirmé la contradiction)
    @discardableResult
    func upsert(
        _ fieldID: String,
        value: Any,
        source: Source,
        confidence: Double,
        reason: String? = nil,
        allowOverwriteManual: Bool = false
    ) -> WriteResult {
        guard let ctx else { return .ignored(reason: .unknownFieldID) }
        guard let spec = ProfileFieldCatalog.all[fieldID] else {
            AppLog.data.warning("ProfileStore.upsert unknown fieldID: \(fieldID, privacy: .public)")
            return .ignored(reason: .unknownFieldID)
        }
        guard confidence >= 0.60 else {
            return .ignored(reason: .confidenceTooLow)
        }

        let encoded = encode(value, valueType: spec.valueType)

        // Nouveau field
        guard let existing = field(fieldID) else {
            let newField = ProfileField(
                fieldID: fieldID,
                category: spec.category,
                valueString: encoded,
                valueType: spec.valueType.rawValue,
                confidence: confidence,
                source: source.rawValue
            )
            ctx.insert(newField)
            LifeOSTry(try ctx.save(), context: "ProfileStore create \(fieldID)", category: AppLog.data)
            // Force le flush pour que le prochain fetch trouve immédiatement le field
            // (bug SwiftData en context in-memory : insert seul ne suffit pas au fetch).
            ctx.processPendingChanges()
            return .created(newField)
        }

        // Même valeur → skip
        if existing.valueString == encoded && existing.confidence >= confidence {
            return .ignored(reason: .sameValue)
        }

        // Source manuelle protégée
        let currentSource = Source(rawValue: existing.source)
        let isCurrentManual = currentSource == .manual || currentSource == .quiz
        let isNewLLM = source == .chat || source == .voice
        if isCurrentManual && isNewLLM && !allowOverwriteManual {
            return .blocked(Contradiction(
                field: existing,
                newValueString: encoded,
                newSource: source,
                newConfidence: confidence
            ))
        }

        // Snapshot avant modif
        let revision = ProfileFieldRevision(
            previousValueString: existing.valueString,
            previousConfidence: existing.confidence,
            previousSource: existing.source,
            reason: reason
        )
        ctx.insert(revision)
        revision.field = existing
        existing.history.append(revision)

        // Update
        existing.valueString = encoded
        existing.confidence = confidence
        existing.source = source.rawValue
        existing.updatedAt = .now
        LifeOSTry(try ctx.save(), context: "ProfileStore update \(fieldID)", category: AppLog.data)
        return .updated(existing)
    }

    // MARK: - Contradiction check (dry-run)

    /// Vérifie si `upsert` refuserait cet écrasement. `nil` = pas de contradiction.
    func detectContradiction(fieldID: String, newValue: Any, newSource: Source, newConfidence: Double) -> Contradiction? {
        guard let spec = ProfileFieldCatalog.all[fieldID],
              let existing = field(fieldID) else { return nil }
        let encoded = encode(newValue, valueType: spec.valueType)
        guard encoded != existing.valueString else { return nil }
        let currentSource = Source(rawValue: existing.source)
        let isCurrentManual = currentSource == .manual || currentSource == .quiz
        let isNewLLM = newSource == .chat || newSource == .voice
        guard isCurrentManual && isNewLLM else { return nil }
        return Contradiction(
            field: existing,
            newValueString: encoded,
            newSource: newSource,
            newConfidence: newConfidence
        )
    }

    // MARK: - Encodage / décodage

    private func encode(_ value: Any, valueType: ProfileFieldSpec.ValueType) -> String {
        switch valueType {
        case .int:
            if let v = value as? Int { return String(v) }
            if let v = value as? Double { return String(Int(v)) }
            return "\(value)"
        case .double:
            if let v = value as? Double { return String(v) }
            if let v = value as? Int { return String(Double(v)) }
            return "\(value)"
        case .string, .enum:
            return "\(value)"
        case .bool:
            if let v = value as? Bool { return v ? "true" : "false" }
            let s = "\(value)".lowercased()
            return (s == "true" || s == "1" || s == "yes" || s == "oui") ? "true" : "false"
        case .array:
            if let arr = value as? [String] {
                return (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
            }
            return "\(value)"
        }
    }

    private func decode<T>(_ raw: String, valueType: String, as type: T.Type) -> T? {
        guard let vt = ProfileFieldSpec.ValueType(rawValue: valueType) else { return nil }
        switch vt {
        case .int:
            return Int(raw) as? T
        case .double:
            return Double(raw) as? T
        case .string, .enum:
            return raw as? T
        case .bool:
            return (raw == "true") as? T
        case .array:
            if let data = raw.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return arr as? T
            }
            return nil
        }
    }
}
