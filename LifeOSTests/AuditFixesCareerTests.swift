import XCTest
@testable import LifeOS

/// Defauts de l'audit sur Zetty (CV), Welcome to the Djob (offres) et Huntly.
final class AuditFixesCareerTests: XCTestCase {

    // MARK: - Zetty: la liste de mots-cles ne part pas dans le profil

    func testKeywordsAreSplitOffTheProfile() {
        let reply = "Développeur iOS, 5 ans sur des apps grand public.\n\n**Mots-clés à ajouter :** Kotlin, CI/CD"
        let parts = CVKeywords.split(reply)
        XCTAssertEqual(parts.profile, "Développeur iOS, 5 ans sur des apps grand public.")
        XCTAssertEqual(parts.keywords, "Kotlin, CI/CD")
        XCTAssertFalse(parts.profile.localizedCaseInsensitiveContains("mots"))
    }

    func testKeywordsHeaderWithoutAccentsOnSameLine() {
        let parts = CVKeywords.split("Profil ici. Mots cles a ajouter: SQL")
        XCTAssertEqual(parts.profile, "Profil ici.")
        XCTAssertEqual(parts.keywords, "SQL")
    }

    func testReplyWithoutKeywordsIsKeptWhole() {
        let parts = CVKeywords.split("  Profil seul.  ")
        XCTAssertEqual(parts.profile, "Profil seul.")
        XCTAssertEqual(parts.keywords, "")
    }

    // MARK: - Djob: seules les competences acquises comptent

    func testOnlyAcquiredSkillsCount() {
        let skills = JobMatching.acquiredSkills([
            (skill: "Swift", acquired: true),
            (skill: "swift ", acquired: true),   // doublon
            (skill: "Kotlin", acquired: false),  // pas acquise
            (skill: "x", acquired: true)         // trop court
        ])
        XCTAssertEqual(skills, ["Swift"])
        XCTAssertEqual(JobMatching.score(title: "Android Kotlin Developer", tags: [], skills: skills), 0)
    }

    // MARK: - Djob: mot entier, casse et accents ignores

    func testWholeWordMatching() {
        XCTAssertFalse(JobMatching.contains(skill: "go", in: "Google Engineer"))
        XCTAssertFalse(JobMatching.contains(skill: "java", in: "Senior JavaScript Developer"))
        XCTAssertTrue(JobMatching.contains(skill: "Go", in: "Backend go developer"))
        XCTAssertTrue(JobMatching.contains(skill: "securite", in: "Ingénieur Sécurité réseau"))
        XCTAssertTrue(JobMatching.contains(skill: "c++", in: "C++/Qt"))
        XCTAssertTrue(JobMatching.contains(skill: "gestion de projet", in: "Chef de Gestion de Projet"))
        XCTAssertEqual(JobMatching.score(title: "Google Ads Manager", tags: ["JavaScript"], skills: ["go", "java"]), 0)
        XCTAssertEqual(JobMatching.score(title: "Go Developer", tags: ["java", "AWS"], skills: ["go", "java"]), 2)
    }

    // MARK: - Djob: "Suivre" ne cree pas de doublon

    func testTrackKeyIgnoresUrlCosmetics() {
        let a = JobMatching.trackKey(url: "https://www.arbeitnow.com/jobs/acme-ios/", company: "Acme", role: "iOS")
        let b = JobMatching.trackKey(url: " http://arbeitnow.com/jobs/acme-ios ", company: "ACME SAS", role: "iOS dev")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, JobMatching.trackKey(url: "https://arbeitnow.com/jobs/other", company: "Acme", role: "iOS"))
        // Sans url, on retombe sur entreprise + poste.
        XCTAssertEqual(JobMatching.trackKey(url: "", company: "Acme ", role: "iOS"),
                       JobMatching.trackKey(url: "  ", company: "acme", role: "ios"))
    }

    // MARK: - Djob: l'erreur dit la vraie cause

    func testErrorMessagesNameTheRealCause() throws {
        let net = try XCTUnwrap(JobSearchService.describe(URLError(.notConnectedToInternet)))
        XCTAssertTrue(net.isNetwork)

        let http = try XCTUnwrap(JobSearchService.describe(JobSearchError.badStatus(503)))
        XCTAssertFalse(http.isNetwork)
        XCTAssertTrue(http.message.contains("503"))
        XCTAssertFalse(http.message.contains("connexion"))

        struct Shape: Decodable { let a: Int }
        do {
            _ = try JSONDecoder().decode(Shape.self, from: Data("{}".utf8))
            XCTFail("le decodage aurait du echouer")
        } catch {
            let format = try XCTUnwrap(JobSearchService.describe(error))
            XCTAssertFalse(format.isNetwork)
            XCTAssertTrue(format.message.contains("format"))
        }

        // Tirer pour rafraichir annule la requete: rien a afficher.
        XCTAssertNil(JobSearchService.describe(URLError(.cancelled)))
        XCTAssertNil(JobSearchService.describe(CancellationError()))
    }
}
