import XCTest
@testable import LifeOS

/// Tests unitaires du filet de sécurité coach.
///
/// Priorité : ces tests garantissent que le court-circuit détresse et le
/// scan de réponse coach fonctionnent pour les cas les plus critiques
/// (App Store safety + tenue de la promesse "coach ≠ médecin/psy").
///
/// Toute nouvelle heuristique dans CoachSafetyScanner doit venir avec son test.
@MainActor
final class CoachSafetyScannerTests: XCTestCase {

    // MARK: - Détresse (court-circuit avant LLM)

    func testDistress_detectedOnDirectSuicidalIntent() {
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "je veux me suicider"))
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "je vais me tuer"))
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "envie de mourir"))
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "plus envie de vivre"))
    }

    func testDistress_detectedOnSelfHarm() {
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "je veux me faire du mal"))
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "envie de me faire mal ce soir"))
    }

    func testDistress_caseInsensitiveAndDiacritics() {
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "JE VEUX EN FINIR"))
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "envie de mourír maintenant"))
    }

    func testDistress_notTriggeredOnBenignMentions() {
        // Ces phrases parlent de sujets voisins mais ne sont pas de la détresse.
        XCTAssertFalse(CoachSafetyScanner.detectsDistress(in: "j'ai regardé un documentaire sur le suicide"))
        XCTAssertFalse(CoachSafetyScanner.detectsDistress(in: "ma journée était mortelle de fatigue"))
        XCTAssertFalse(CoachSafetyScanner.detectsDistress(in: "je suis fatigué"))
    }

    func testDistress_reply_containsHelplineNumber() {
        XCTAssertTrue(CoachSafetyScanner.distressReply.contains("3114"))
        XCTAssertTrue(CoachSafetyScanner.distressReply.contains("15"))
    }

    // MARK: - Scan de la réponse générée

    func testScan_dosage_flagged() {
        // Le nom de médicament a priorité sur le dosage nu (badge plus informatif)
        XCTAssertEqual(CoachSafetyScanner.scan("prends 500 mg de paracétamol"), .medication)
        XCTAssertEqual(CoachSafetyScanner.scan("30 UI d'insuline"), .medication)
        // Dosage seul (sans nom de médicament) → .dosage
        XCTAssertEqual(CoachSafetyScanner.scan("dose recommandée : 800mg"), .dosage)
        XCTAssertEqual(CoachSafetyScanner.scan("dosage : 250 mcg par jour"), .dosage)
    }

    func testScan_ml_notFlaggedAsDosage() {
        // "ml" seul est ambigu (2500 ml d'eau = hydratation, pas dosage).
        // Bug fix : on n'affiche plus de badge dosage sur les ml.
        XCTAssertNil(CoachSafetyScanner.scan("bois 2500 ml par jour"))
        XCTAssertNil(CoachSafetyScanner.scan("objectif hydratation : 2000/2500 ml"))
    }

    func testScan_medication_flagged() {
        XCTAssertEqual(CoachSafetyScanner.scan("commence par du doliprane"), .medication)
        XCTAssertEqual(CoachSafetyScanner.scan("le xanax peut aider"), .medication)
        XCTAssertEqual(CoachSafetyScanner.scan("essaie l'ibuprofène"), .medication)
    }

    func testScan_finance_flagged() {
        XCTAssertEqual(CoachSafetyScanner.scan("achète du btc maintenant"), .finance)
        XCTAssertEqual(CoachSafetyScanner.scan("mets tout en etf world"), .finance)
        XCTAssertEqual(CoachSafetyScanner.scan("all-in sur nvidia"), .finance)
    }

    func testScan_restrictionExtreme_flagged() {
        // "500 kcal par jour" est un régime dangereux — .restriction (pas .dosage)
        XCTAssertEqual(CoachSafetyScanner.scan("essaie 500 kcal par jour"), .restriction)
        XCTAssertEqual(CoachSafetyScanner.scan("moins de 1000 kcal"), .restriction)
        XCTAssertEqual(CoachSafetyScanner.scan("jeûne de 3 jours peut marcher"), .restriction)
        XCTAssertEqual(CoachSafetyScanner.scan("arrête de manger le soir"), .restriction)
    }

    func testScan_benignResponse_returnsNil() {
        XCTAssertNil(CoachSafetyScanner.scan("Bonne idée, tu peux commencer par une marche de 10 minutes."))
        XCTAssertNil(CoachSafetyScanner.scan("Ta séance était top, continue comme ça."))
        XCTAssertNil(CoachSafetyScanner.scan("Pense à boire un verre d'eau."))
    }

    func testScan_returnsFirstBadgeOnly() {
        // Si plusieurs risques sont présents, on ne remonte qu'un badge —
        // documenté comme limitation actuelle. Test valide le comportement.
        let mixed = "prends 500 mg d'ibuprofène et achète du btc"
        XCTAssertNotNil(CoachSafetyScanner.scan(mixed))
    }

    // MARK: - RiskBadge propriétés

    func testRiskBadge_iconsAreNonEmpty() {
        for badge in [
            CoachSafetyScanner.RiskBadge.dosage,
            .medication, .finance, .restriction
        ] {
            XCTAssertFalse(badge.icon.isEmpty, "\(badge) icon vide")
            XCTAssertFalse(badge.label.isEmpty, "\(badge) label vide")
        }
    }

    func testRiskBadge_labelsAreUserFriendly() {
        // Rappel App Store : le texte affiché doit rediriger vers un pro,
        // pas se contenter d'un warning technique.
        XCTAssertTrue(CoachSafetyScanner.RiskBadge.dosage.label.contains("médecin"))
        XCTAssertTrue(CoachSafetyScanner.RiskBadge.medication.label.contains("médecin"))
        XCTAssertTrue(CoachSafetyScanner.RiskBadge.finance.label.lowercased().contains("simulation"))
        XCTAssertTrue(CoachSafetyScanner.RiskBadge.restriction.label.contains("pro"))
    }
}
