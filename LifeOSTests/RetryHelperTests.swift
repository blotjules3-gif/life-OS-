import XCTest
@testable import LifeOS

final class RetryHelperTests: XCTestCase {

    // MARK: Succès immédiat (pas de retry)

    func testWithBackoff_succeedsFirstTry() async throws {
        var attempts = 0
        let result: Int = try await RetryHelper.withBackoff(attempts: 3, delays: [0]) {
            attempts += 1
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(attempts, 1, "aucun retry si succès immédiat")
    }

    // MARK: Retry après échec

    func testWithBackoff_succeedsOnRetry() async throws {
        var attempts = 0
        let result: Int = try await RetryHelper.withBackoff(attempts: 3, delays: [0, 0, 0]) {
            attempts += 1
            if attempts < 2 {
                throw NSError(domain: "test", code: 1)
            }
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(attempts, 2)
    }

    // MARK: Toutes les tentatives échouent

    func testWithBackoff_allAttemptsFail_throws() async {
        var attempts = 0
        do {
            let _: Int = try await RetryHelper.withBackoff(attempts: 3, delays: [0, 0, 0]) {
                attempts += 1
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
            }
            XCTFail("aurait dû throw")
        } catch {
            XCTAssertEqual(attempts, 3, "3 tentatives faites avant l'échec final")
        }
    }

    // MARK: Variante nil-safe

    func testWithBackoffOrNil_returnsNilOnFail() async {
        let result: Int? = await RetryHelper.withBackoffOrNil(attempts: 2, delays: [0]) {
            throw NSError(domain: "test", code: 1)
        }
        XCTAssertNil(result)
    }

    func testWithBackoffOrNil_returnsValueOnSuccess() async {
        let result: Int? = await RetryHelper.withBackoffOrNil(attempts: 2, delays: [0]) {
            return 100
        }
        XCTAssertEqual(result, 100)
    }
}
