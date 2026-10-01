import XCTest
import UIKit
import ImageIO
@testable import LifeOS

/// Correctifs de l'audit (groupe 6): Fuelo, Papernid, Digicoffre, Hipp,
/// Adobo Scan. Chaque test echoue sur l'ancien comportement.
final class AuditFixesAdminTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Fuelo: kilometrage vide

    /// Vide devenait 0 et etait enregistre.
    func testEmptyOrZeroOdometerIsRejected() {
        XCTAssertNil(FuelMath.parseOdometer(""))
        XCTAssertNil(FuelMath.parseOdometer("  "))
        XCTAssertNil(FuelMath.parseOdometer("0"))
        XCTAssertNil(FuelMath.parseOdometer("12a"))
        XCTAssertEqual(FuelMath.parseOdometer("12 345"), 12345)
    }

    /// Un ancien plein a 0 km passait premier au tri et la conso tombait a
    /// 0,67 L/100 au lieu de 8.
    func testZeroOdometerFillDoesNotBreakAverage() throws {
        let entries = [FuelMath.Entry(date: date(2026, 9, 1), liters: 30, odometer: 10_000),
                       FuelMath.Entry(date: date(2026, 9, 10), liters: 40, odometer: 10_500),
                       FuelMath.Entry(date: date(2026, 9, 20), liters: 35, odometer: 0)]
        let avg = try XCTUnwrap(FuelMath.averageConsumption(entries))
        XCTAssertEqual(avg, 8.0, accuracy: 0.001)
    }

    /// Un plein sans compteur ENTRE deux pleins valides: ses litres manquent,
    /// on n'affiche rien plutot qu'une conso fausse.
    func testUnknownFillInsideRangeGivesNoAverage() {
        let entries = [FuelMath.Entry(date: date(2026, 9, 1), liters: 30, odometer: 10_000),
                       FuelMath.Entry(date: date(2026, 9, 5), liters: 40, odometer: 0),
                       FuelMath.Entry(date: date(2026, 9, 10), liters: 40, odometer: 10_500)]
        XCTAssertNil(FuelMath.averageConsumption(entries))
    }

    // MARK: - Papernid: J-x

    /// Echeance creee a 9 h pour demain, regardee a 15 h: l'ancien calcul
    /// donnait 0 ("Aujourd'hui").
    func testTomorrowDeadlineIsJMinusOne() {
        let now = date(2026, 10, 1, 15)
        let due = date(2026, 10, 2, 9)
        XCTAssertEqual(DeadlineMath.daysUntil(due, from: now, calendar: cal), 1)
        XCTAssertEqual(DeadlineMath.daysUntil(date(2026, 10, 1, 8), from: now, calendar: cal), 0)
        XCTAssertEqual(DeadlineMath.daysUntil(date(2026, 10, 8, 1), from: now, calendar: cal), 7)
    }

    // MARK: - Digicoffre: identifiants de rappel

    /// Deux documents de meme titre, expirations differentes: un rappel chacun.
    func testSameTitleDifferentDatesDoNotShareReminder() {
        XCTAssertNotEqual(ReminderIDs.document(title: "Assurance", expiry: date(2027, 1, 1)),
                          ReminderIDs.document(title: "Assurance", expiry: date(2028, 1, 1)))
        XCTAssertNotEqual(ReminderIDs.deadline(title: "Impôts", date: date(2027, 5, 1)),
                          ReminderIDs.deadline(title: "Impôts", date: date(2028, 5, 1)))
    }

    /// Supprimer un document ne doit pas annuler le rappel encore utilise par
    /// un autre (ancienne forme sans date comprise).
    func testDeletingOneDocumentKeepsTheOthersReminder() {
        let a = ReminderIDs.documentIDs(title: "Assurance", expiry: date(2027, 1, 1))
        let b = ReminderIDs.documentIDs(title: "Assurance", expiry: date(2028, 1, 1))
        let toCancel = ReminderIDs.cancellable(a, stillUsedBy: [b])
        XCTAssertEqual(toCancel, [ReminderIDs.document(title: "Assurance", expiry: date(2027, 1, 1))])
        XCTAssertFalse(toCancel.contains(ReminderIDs.document(title: "Assurance")))
        // Seul document: l'ancienne forme est annulee aussi.
        XCTAssertTrue(ReminderIDs.cancellable(a, stillUsedBy: []).contains(ReminderIDs.document(title: "Assurance")))
    }

    func testDocumentWithoutExpiryHasNoReminder() {
        XCTAssertTrue(ReminderIDs.documentIDs(title: "Passeport", expiry: nil).isEmpty)
    }

    /// Renommer un vehicule: les rappels a annuler portent l'ANCIEN nom, y
    /// compris l'ancienne forme posee avant le correctif.
    func testVehicleRenameCancelsOldNameReminders() {
        let ins = date(2027, 3, 1)
        let old = ReminderIDs.vehicleIDs(name: "Clio", insurance: ins, service: nil)
        let new = ReminderIDs.vehicleIDs(name: "Peugeot 208", insurance: ins, service: nil)
        XCTAssertTrue(old.contains(ReminderIDs.vehicleInsurance(name: "Clio")))
        XCTAssertTrue(old.contains(ReminderIDs.vehicleInsurance(name: "Clio", date: ins)))
        XCTAssertTrue(Set(old).isDisjoint(with: new))
    }

    // MARK: - Hipp: anniversaires

    /// La suppression d'un contact doit retrouver l'identifiant DEJA pose par
    /// la vue Anniversaires (meme forme qu'avant).
    func testBirthdayIdentifierKeepsLegacyShape() {
        let b = Date(timeIntervalSince1970: 631_152_000)
        XCTAssertEqual(ReminderIDs.birthday(name: "Jean Dupont", birthday: b), "bday.Jean_Dupont.631152000")
    }

    /// Ne le 2 mars 2000 (bissextile): l'ancien calcul donnait le 28 fevrier,
    /// 2 jours avant les annees normales.
    func testBirthdayReminderUsesNonLeapYear() {
        let r = BirthdayMath.reminderMonthDay(birthday: date(2000, 3, 2), daysBefore: 3, calendar: cal)
        XCTAssertEqual(r.month, 2)
        XCTAssertEqual(r.day, 27)
        let normal = BirthdayMath.reminderMonthDay(birthday: date(1990, 6, 15), daysBefore: 3, calendar: cal)
        XCTAssertEqual(normal.month, 6)
        XCTAssertEqual(normal.day, 12)
    }

    // MARK: - Adobo Scan

    /// Texte inconnu ou OCR vide: plus de faux "Identité".
    func testUnknownTextIsNotClassified() {
        XCTAssertNil(DocClassifier.categorize(""))
        XCTAssertNil(DocClassifier.categorize("Liste de courses: pommes, lait"))
        XCTAssertEqual(DocClassifier.categorize("Facture n° 42, total TTC"), "Facture")
        XCTAssertEqual(DocClassifier.categorize("PASSEPORT"), "Identité")
    }

    /// L'orientation de la photo est transmise a Vision.
    func testOCROrientationFollowsTheImage() {
        XCTAssertEqual(DocOCR.cgOrientation(.right), .right)
        XCTAssertEqual(DocOCR.cgOrientation(.up), .up)
        XCTAssertEqual(DocOCR.cgOrientation(.leftMirrored), .leftMirrored)
        XCTAssertEqual(DocOCR.cgOrientation(.down), .down)
    }
}
