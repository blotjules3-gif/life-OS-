import XCTest
@testable import LifeOS

/// Garde anti-regression du plantage de "Ajouter une habitude" sur la version bureau.
///
/// Cause reelle, lue dans les rapports LifeOS-2026-09-25-0131*.ips :
///
///   -[UIView(UICatalystMacIdiomUnsupported_Internal) _throwForUnsupportedNonMacIdiomBehaviorWithReason:]
///   -[UIPickerView _didMoveFromWindow:toWindow:]
///
/// `UIPickerView` est INTERDIT sur Mac Catalyst en idiome Mac, et notre cible EST en
/// idiome Mac (`UIDeviceFamily = [6]`). UIKit ne degrade pas, il leve une exception des
/// que la roue entre dans une fenetre. Donc chaque ecran qui contient une roue tombe
/// immediatement sur Mac.
///
/// `.pickerStyle(.wheel)` et `.datePickerStyle(.wheel)` sont donc interdits en direct.
/// Passer par `.adaptiveWheelPicker()` / `.adaptiveWheelDatePicker()` (PlatformPickers.swift),
/// qui gardent la roue sur iPhone et iPad et prennent une commande native sur Mac.
///
/// Ce test lit les SOURCES, parce que le defaut n'est pas une valeur fausse a l'execution :
/// c'est une ligne de code qui ne doit exister nulle part.
final class MacCatalystSafetyTests: XCTestCase {

    /// Seul fichier autorise a nommer `.wheel` : celui qui fait la bascule.
    private let allowed = "PlatformPickers.swift"

    private func swiftSources() throws -> [URL] {
        // Remonte depuis le bundle de test jusqu'a la racine du depot.
        var dir = URL(fileURLWithPath: #filePath)            // .../LifeOSTests/MacCatalystSafetyTests.swift
            .deletingLastPathComponent()                      // .../LifeOSTests
            .deletingLastPathComponent()                      // racine
        dir.appendPathComponent("LifeOS")
        let fm = FileManager.default
        guard let it = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return it.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testNoRawWheelPickerAnywhere() throws {
        let sources = try swiftSources()
        XCTAssertFalse(sources.isEmpty, "Aucun fichier source trouve : le test se croirait vert a tort.")

        var offenders: [String] = []
        for url in sources where url.lastPathComponent != allowed {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.contains(".pickerStyle(.wheel)") || line.contains(".datePickerStyle(.wheel)") {
                    offenders.append("\(url.lastPathComponent):\(i + 1)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Roue de selection interdite sur Mac Catalyst, elle fait planter l'ecran a l'ouverture.
            Remplacer par .adaptiveWheelPicker() ou .adaptiveWheelDatePicker().
            Sites : \(offenders.joined(separator: ", "))
            """
        )
    }

    /// Le fichier de bascule doit exister et couvrir les deux cas, sinon le test ci dessus
    /// passerait simplement parce que plus personne n'utilise de roue du tout.
    func testAdaptiveHelpersExist() throws {
        let helper = try swiftSources().first { $0.lastPathComponent == allowed }
        let text = try XCTUnwrap(helper.map { try? String(contentsOf: $0, encoding: .utf8) } ?? nil,
                                 "PlatformPickers.swift est introuvable.")
        XCTAssertTrue(text.contains("func adaptiveWheelPicker()"))
        XCTAssertTrue(text.contains("func adaptiveWheelDatePicker()"))
        XCTAssertTrue(text.contains("targetEnvironment(macCatalyst)"),
                      "La bascule doit etre conditionnee a Mac Catalyst.")
    }
}
