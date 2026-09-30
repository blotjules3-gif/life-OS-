import XCTest
@testable import LifeOS

/// Le profil ne doit plus rien affirmer qui ne soit vrai.
final class AccountStatusTests: XCTestCase {

    func testLeftoverEmailIsNotAVerifiedAccount() {
        // Ce qu'une ancienne version pouvait laisser: un email et un fournisseur.
        let a = AccountStatus.account(isAuthenticated: true, provider: "apple", email: "x@icloud.com")
        XCTAssertEqual(a, .local, "aucun compte en ligne n'existe dans cette version")
        XCTAssertEqual(AccountStatus.label(a), "Session locale")
    }

    func testStorageSaysLocalUnlessSyncReallyRuns() {
        XCTAssertFalse(AccountStatus.storage(syncActive: false).synced)
        XCTAssertEqual(AccountStatus.storage(syncActive: false).title, "Sur cet appareil")
        XCTAssertTrue(AccountStatus.storage(syncActive: true).synced)
    }

    func testNoFalseSyncWordingLeftInTheProfile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = ["LifeOS/Core/ProfileView.swift", "LifeOS/Shared/NotificationsSettingsView.swift", "LifeOS/Core/FAQView.swift"]
        let text = try files.map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }.joined()
        for phrase in ["Compte vérifié", "se synchronisent automatiquement", "Synchronisation active",
                       "Chiffrement bout en bout", "chiffrées de bout en bout", "Temps réel"] {
            XCTAssertFalse(text.contains(phrase), "promesse fausse revenue: \(phrase)")
        }
    }
}
