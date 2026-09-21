import XCTest
@testable import LifeOS

/// Stabilite des identifiants de notification.
///
/// Le bug corrige: les identifiants etaient derives de `hashValue`. Le hachage
/// de Swift est amorce AU HASARD a chaque demarrage du processus, donc l'ID
/// changeait d'un lancement a l'autre. Deux consequences vues en vrai:
/// supprimer un element annulait une notification qui n'existait pas, et
/// reprogrammer la meme chose creait un doublon au lieu de remplacer.
///
/// Ces tests figent la propriete qui compte: le meme texte doit TOUJOURS
/// donner le meme identifiant.
final class ReminderIdentifierTests: XCTestCase {

    func testSameTextGivesSameIdentifier() {
        XCTAssertEqual(AddAnythingSheet.slug("Prendre Vitamine D"),
                       AddAnythingSheet.slug("Prendre Vitamine D"))
    }

    /// La casse ne doit pas creer un deuxieme rappel.
    func testCaseInsensitive() {
        XCTAssertEqual(AddAnythingSheet.slug("Prendre Vitamine D"),
                       AddAnythingSheet.slug("prendre vitamine d"))
    }

    /// Les accents non plus: "Cafe" et "Café" sont le meme rappel.
    func testAccentInsensitive() {
        XCTAssertEqual(AddAnythingSheet.slug("Café du matin"),
                       AddAnythingSheet.slug("Cafe du matin"))
    }

    func testPunctuationAndSpacingCollapse() {
        XCTAssertEqual(AddAnythingSheet.slug("Appeler  maman !!"),
                       AddAnythingSheet.slug("appeler maman"))
    }

    /// Deux rappels differents ne doivent PAS se confondre, sinon programmer
    /// le second effacerait le premier.
    func testDifferentTextsGiveDifferentIdentifiers() {
        XCTAssertNotEqual(AddAnythingSheet.slug("Vitamine D"),
                          AddAnythingSheet.slug("Vitamine C"))
    }

    /// Un identifiant doit rester sain: pas d'espace, pas d'emoji.
    func testIdentifierIsSafe() {
        let s = AddAnythingSheet.slug("Café ☕ du matin, 8h !")
        XCTAssertFalse(s.contains(" "))
        XCTAssertFalse(s.contains("☕"))
        XCTAssertTrue(s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
    }

    /// Un texte tres long ne doit pas produire un identifiant sans fin.
    func testVeryLongTextIsBounded() {
        let s = AddAnythingSheet.slug(String(repeating: "rappel ", count: 60))
        XCTAssertLessThanOrEqual(s.count, 48)
        XCTAssertFalse(s.isEmpty)
    }

    /// Un texte sans aucun caractere exploitable ne doit pas planter.
    func testSymbolsOnlyDoesNotCrash() {
        XCTAssertNoThrow(_ = AddAnythingSheet.slug("!!! ??? ..."))
    }
}
