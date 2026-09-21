import XCTest
@testable import LifeOS

/// Identifiants des rappels ponctuels.
///
/// Le defaut corrige: chaque ecran fabriquait son identifiant a la main au
/// moment de POSER la notification, et nulle part au moment de supprimer la
/// ligne. Supprimer un rendez vous medical, un document, une echeance, un
/// evenement, un vehicule ou un animal laissait donc son rappel en place, et
/// plus rien ne pouvait le faire taire.
///
/// Ce qui compte ici n'est pas la forme de la chaine, c'est que les deux
/// cotes tombent sur la MEME.
final class ReminderIDsTests: XCTestCase {

    private let d1 = Date(timeIntervalSince1970: 1_800_000_000)
    private let d2 = Date(timeIntervalSince1970: 1_800_086_400)

    // MARK: - Meme entree, meme identifiant

    func testAppointmentIsStable() {
        XCTAssertEqual(ReminderIDs.appointment(d1), ReminderIDs.appointment(d1))
    }

    func testVaccinationIsStable() {
        XCTAssertEqual(ReminderIDs.vaccination(name: "Grippe", nextDate: d1),
                       ReminderIDs.vaccination(name: "Grippe", nextDate: d1))
    }

    func testPetCareIsStable() {
        XCTAssertEqual(ReminderIDs.petCare(pet: "Rex", type: "Vaccin", date: d1),
                       ReminderIDs.petCare(pet: "Rex", type: "Vaccin", date: d1))
    }

    /// Les secondes sont tronquees a l'entier: deux instants de la meme
    /// seconde doivent donner le meme identifiant, sinon un rappel pose
    /// devient introuvable a la suppression.
    func testSubSecondDifferenceDoesNotChangeTheIdentifier() {
        let a = Date(timeIntervalSince1970: 1_800_000_000.2)
        let b = Date(timeIntervalSince1970: 1_800_000_000.7)
        XCTAssertEqual(ReminderIDs.appointment(a), ReminderIDs.appointment(b))
    }

    // MARK: - Entrees differentes, identifiants differents

    func testDifferentDatesDiffer() {
        XCTAssertNotEqual(ReminderIDs.appointment(d1), ReminderIDs.appointment(d2))
    }

    func testDifferentTitlesDiffer() {
        XCTAssertNotEqual(ReminderIDs.deadline(title: "Impôts"),
                          ReminderIDs.deadline(title: "Assurance"))
    }

    /// Un vehicule a deux rappels: assurance et revision. Ils ne doivent pas
    /// se confondre, sinon poser le second effacerait le premier.
    func testVehicleInsuranceAndServiceDiffer() {
        XCTAssertNotEqual(ReminderIDs.vehicleInsurance(name: "Clio"),
                          ReminderIDs.vehicleService(name: "Clio"))
    }

    /// Deux soins du meme animal le meme jour, de types differents.
    func testSamePetSameDayDifferentCareDiffer() {
        XCTAssertNotEqual(ReminderIDs.petCare(pet: "Rex", type: "Vaccin", date: d1),
                          ReminderIDs.petCare(pet: "Rex", type: "Vétérinaire", date: d1))
    }

    /// Un document et une echeance portant le meme titre sont deux choses.
    func testDocumentAndDeadlineDoNotCollide() {
        XCTAssertNotEqual(ReminderIDs.document(title: "Assurance"),
                          ReminderIDs.deadline(title: "Assurance"))
    }

    func testDifferentEventsDiffer() {
        XCTAssertNotEqual(ReminderIDs.socialEvent(title: "Anniv", date: d1),
                          ReminderIDs.socialEvent(title: "Anniv", date: d2))
    }

    // MARK: - Forme

    /// Un identifiant vide ferait annuler toutes les notifications ou aucune.
    func testNeverEmptyEvenWithEmptyInput() {
        XCTAssertFalse(ReminderIDs.document(title: "").isEmpty)
        XCTAssertFalse(ReminderIDs.petCare(pet: "", type: "", date: d1).isEmpty)
    }

    /// Chaque famille a son prefixe: c'est ce qui evite qu'un document et un
    /// evenement au meme nom se marchent dessus.
    func testFamiliesHaveDistinctPrefixes() {
        let ids = [ReminderIDs.appointment(d1),
                   ReminderIDs.vaccination(name: "X", nextDate: d1),
                   ReminderIDs.document(title: "X"),
                   ReminderIDs.deadline(title: "X"),
                   ReminderIDs.socialEvent(title: "X", date: d1),
                   ReminderIDs.vehicleInsurance(name: "X"),
                   ReminderIDs.vehicleService(name: "X"),
                   ReminderIDs.petCare(pet: "X", type: "Y", date: d1)]
        XCTAssertEqual(Set(ids).count, ids.count, "deux familles produisent le même identifiant")
    }

    // MARK: - Personne ne refabrique la formule dans son coin

    /// Aucun rappel PONCTUEL ne doit construire son identifiant sur place.
    ///
    /// C'est la vraie cause du defaut, et elle reviendrait toute seule: tant
    /// que la formule est ecrite dans la vue qui POSE la notification, la vue
    /// qui SUPPRIME la ligne ne l'a pas sous les yeux et l'oublie.
    ///
    /// La regle ne vise QUE `schedule(id:...at:)`, le rappel a un coup, parce
    /// que c'est celui qui est attache a une ligne supprimable: un rendez
    /// vous, un document, une echeance. Les rappels recurrents
    /// (`scheduleDaily`, `scheduleWeekly`) interpolent legitimement un indice
    /// de boucle, "water\(h)" pour les huit rappels d'hydratation, et posent
    /// et annulent les memes identifiants au meme endroit: les inclure
    /// donnerait huit faux positifs et le test finirait desactive.
    func testOneShotRemindersDoNotBuildIdentifiersInline() throws {
        let root = repoRoot().appendingPathComponent("LifeOS")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("LifeOS/ introuvable à \(root.path)")
        }
        // `.schedule( id: "...\(` — l'appel peut tenir sur plusieurs lignes,
        // donc on lit le fichier entier et pas ligne par ligne.
        let re = try NSRegularExpression(pattern: #"\.schedule\(\s*id:\s*"[^"]*\\\("#,
                                         options: [.dotMatchesLineSeparators])

        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let r = NSRange(content.startIndex..<content.endIndex, in: content)
            for m in re.matches(in: content, options: [], range: r) {
                guard let rr = Range(m.range, in: content) else { continue }
                let line = content[content.startIndex..<rr.lowerBound].filter { $0 == "\n" }.count + 1
                offenders.append("\(url.lastPathComponent):\(line)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Rappels ponctuels dont l'identifiant est fabriqué sur place :\n"
                      + offenders.joined(separator: "\n")
                      + "\n\nAjoute la formule à ReminderIDs, sinon la suppression ne pourra pas annuler.")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LifeOSTests/
            .deletingLastPathComponent()   // racine
    }
}
