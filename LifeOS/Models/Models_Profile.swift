import Foundation
import SwiftData

/// Champ du profil utilisateur avec historique et confidence.
///
/// Un `ProfileField` par (spec.id, user). L'utilisateur unique en local — pas
/// besoin d'un userID. Le `fieldID` correspond à un `ProfileFieldSpec` défini
/// statiquement dans `ProfileFieldSpec.swift`.
///
/// Toute mise à jour de `valueString` doit d'abord snapshoter l'ancienne valeur
/// dans `history` (voir `ProfileStore.upsert`).
@Model
final class ProfileField {
    /// Identifiant unique du spec (ex: "body.currentWeightKg"). Utilisé aussi comme
    /// clé de recherche dans ProfileFieldSpec.
    @Attribute(.unique) var fieldID: String

    /// Catégorie du champ (`AppCategory.rawValue`). Dénormalisé pour requêtes rapides.
    var category: String

    /// Valeur sérialisée. Format dépend de `valueType` :
    /// - int/double → "74.5"
    /// - string → "etudiant"
    /// - bool → "true"
    /// - enum → raw value du case
    /// - array → JSON array
    var valueString: String

    /// Type de la valeur : "int" | "double" | "string" | "bool" | "enum" | "array".
    var valueType: String

    /// Confidence de la source, entre 0.0 et 1.0.
    var confidence: Double

    /// Source de l'écriture : "chat" | "voice" | "quiz" | "shortcut" | "manual" | "migration".
    var source: String

    var createdAt: Date
    var updatedAt: Date

    /// Historique des révisions, snapshotée avant chaque update par ProfileStore.
    @Relationship(deleteRule: .cascade, inverse: \ProfileFieldRevision.field)
    var history: [ProfileFieldRevision] = []

    init(
        fieldID: String,
        category: String,
        valueString: String,
        valueType: String,
        confidence: Double,
        source: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.fieldID = fieldID
        self.category = category
        self.valueString = valueString
        self.valueType = valueType
        self.confidence = confidence
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Snapshot immuable d'une ancienne valeur d'un ProfileField avant modification.
/// Créé automatiquement par `ProfileStore.upsert()` avant de modifier `valueString`.
@Model
final class ProfileFieldRevision {
    var previousValueString: String
    var previousConfidence: Double
    var previousSource: String
    var changedAt: Date
    /// Raison libre du changement, ex: "user_correction", "llm_extraction", "migration".
    var reason: String?

    var field: ProfileField?

    init(
        previousValueString: String,
        previousConfidence: Double,
        previousSource: String,
        changedAt: Date = .now,
        reason: String? = nil
    ) {
        self.previousValueString = previousValueString
        self.previousConfidence = previousConfidence
        self.previousSource = previousSource
        self.changedAt = changedAt
        self.reason = reason
    }
}
