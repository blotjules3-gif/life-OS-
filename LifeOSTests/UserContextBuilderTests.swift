import XCTest
@testable import LifeOS

/// Vérifie que le profil de vie renseigné à l'onboarding parvient bien au coach
/// via `UserContextBuilder.build(...)`.
///
/// Contexte : `OnboardingView` écrit dans la clé `"lifeProfile"` via `@AppStorage`.
/// Un ancien bug lisait `"userLifeProfile"` (jamais écrite) → le bloc « Profil : »
/// n'apparaissait jamais dans le contexte envoyé au coach. Ce test garde l'alignement.
final class UserContextBuilderTests: XCTestCase {

    private let profileKey = "lifeProfile"
    private let hasCycleKey = "userHasCycle"
    /// Toutes les clés UserDefaults qui pourraient rendre le context non-vide
    /// et faire échouer `testEmptyLifeProfileDoesNotEmitBlock`. Un test parallèle
    /// (extraction profil, onboarding view SwiftUI, etc.) peut avoir laissé
    /// une trace — on nettoie tout à setUp/tearDown.
    private let pollutingKeys = [
        "lifeProfile", "userName", "userGender",
        "activeModules", "userHasCycle"
    ]

    @MainActor
    override func setUp() {
        super.setUp()
        for k in pollutingKeys { UserDefaults.standard.removeObject(forKey: k) }
        // Le builder est un singleton avec cache TTL 60s — sinon un test hérite
        // du résultat du test précédent.
        UserContextBuilder.shared.invalidateCache()
    }

    @MainActor
    override func tearDown() {
        for k in pollutingKeys { UserDefaults.standard.removeObject(forKey: k) }
        UserContextBuilder.shared.invalidateCache()
        super.tearDown()
    }

    @MainActor
    func testLifeProfileAppearsInBuiltContext() {
        UserDefaults.standard.set("etudiant", forKey: profileKey)
        UserDefaults.standard.set(false, forKey: hasCycleKey)

        let context = UserContextBuilder.shared.build(message: nil)
        XCTAssertTrue(
            context.contains("Profil: etudiant"),
            "Le contexte devrait contenir 'Profil: etudiant'. Extrait obtenu :\n"
                + String(context.prefix(400))
        )
    }

    @MainActor
    func testEmptyLifeProfileDoesNotEmitBlock() {
        UserDefaults.standard.removeObject(forKey: profileKey)
        UserDefaults.standard.set(false, forKey: hasCycleKey)

        let context = UserContextBuilder.shared.build(message: nil)
        XCTAssertFalse(
            context.contains("Profil:"),
            "Sans profil renseigné le bloc 'Profil:' ne doit pas apparaître."
        )
    }
}
