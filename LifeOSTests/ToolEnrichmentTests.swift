import XCTest
@testable import LifeOS

/// Vérifie que le pattern matching de `ToolEnrichment` détecte bien les
/// intents utilisateur classiques et route vers le bon tool.
///
/// Ne teste PAS l'exécution du tool (ProfileStore etc.) — juste le mapping
/// message → tool + fieldID.
@MainActor
final class ToolEnrichmentTests: XCTestCase {

    // MARK: - Profile field lookup

    func testProfileFieldQuery_weight_variants() {
        let expectations: [(String, String)] = [
            ("combien je pèse ?", "body.currentWeightKg"),
            ("quel est mon poids", "body.currentWeightKg"),
            ("mon poids actuel svp", "body.currentWeightKg"),
        ]
        for (msg, expected) in expectations {
            let norm = normalize(msg)
            XCTAssertEqual(
                ToolEnrichment.matchProfileFieldQuery(norm), expected,
                "Message \"\(msg)\" devrait matcher \(expected)"
            )
        }
    }

    func testProfileFieldQuery_targetWeight() {
        let msg = "quel est mon objectif poids"
        XCTAssertEqual(
            ToolEnrichment.matchProfileFieldQuery(normalize(msg)),
            "body.targetWeightKg"
        )
    }

    func testProfileFieldQuery_age() {
        XCTAssertEqual(
            ToolEnrichment.matchProfileFieldQuery(normalize("quel est mon âge")),
            "body.ageYears"
        )
    }

    func testProfileFieldQuery_height() {
        XCTAssertEqual(
            ToolEnrichment.matchProfileFieldQuery(normalize("ma taille c'est combien")),
            "body.heightCm"
        )
    }

    func testProfileFieldQuery_gymFrequency() {
        XCTAssertEqual(
            ToolEnrichment.matchProfileFieldQuery(normalize("ma fréquence de séances de sport")),
            "fitness.gymFrequency"
        )
    }

    func testProfileFieldQuery_noise_returnsNil() {
        // Message qui contient "poids" mais sans marqueur d'interrogation.
        XCTAssertNil(
            ToolEnrichment.matchProfileFieldQuery(normalize("le poids c'est important pour la santé"))
        )
    }

    // MARK: - Profile summary

    func testProfileSummary_positive() {
        XCTAssertTrue(ToolEnrichment.matchesProfileSummary(normalize("qui suis-je vraiment ?")))
        XCTAssertTrue(ToolEnrichment.matchesProfileSummary(normalize("résume mon profil stp")))
        XCTAssertTrue(ToolEnrichment.matchesProfileSummary(normalize("que sais-tu de moi")))
    }

    func testProfileSummary_negative() {
        XCTAssertFalse(ToolEnrichment.matchesProfileSummary(normalize("comment aller mieux ?")))
        XCTAssertFalse(ToolEnrichment.matchesProfileSummary(normalize("mon profil est ok")))
    }

    // MARK: - Memory search

    func testMemorySearch_extractsSubject() {
        let q = ToolEnrichment.matchMemorySearch(normalize("tu te souviens de mon voyage à rome"))
        XCTAssertNotNil(q)
        XCTAssertTrue(q!.contains("rome"), "Query extraite : \(q ?? "nil")")
    }

    func testMemorySearch_noKeyword_returnsNil() {
        XCTAssertNil(ToolEnrichment.matchMemorySearch(normalize("ça va toi ?")))
    }

    // MARK: - Helper

    /// Reproduit la normalisation appliquée par `ToolEnrichment.enrich`
    /// (folding diacritics + lowercase).
    private func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}
