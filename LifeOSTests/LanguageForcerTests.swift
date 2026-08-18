import XCTest
@testable import LifeOS

final class LanguageForcerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.appLanguage)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.appLanguage)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        super.tearDown()
    }

    // MARK: Persistance

    func testSet_persistsChoiceToUserDefaults() {
        LanguageForcer.set(.fr)
        let stored = UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage)
        XCTAssertEqual(stored, "fr")
    }

    func testCurrent_defaultsToAuto() {
        XCTAssertEqual(LanguageForcer.current, .auto)
    }

    func testCurrent_reflectsPersistedChoice() {
        LanguageForcer.set(.en)
        XCTAssertEqual(LanguageForcer.current, .en)
    }

    // MARK: Application AppleLanguages

    func testApply_forFrench_overridesAppleLanguages() {
        LanguageForcer.set(.fr)
        LanguageForcer.applyPersistedChoice()
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertEqual(langs, ["fr"])
    }

    func testApply_forAuto_clearsAppleLanguages() {
        // Setup : d'abord forcer FR
        UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
        LanguageForcer.set(.auto)
        LanguageForcer.applyPersistedChoice()
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages")
        XCTAssertNil(langs, "auto doit supprimer l'override")
    }

    // MARK: Options

    func testOptions_haveExpectedRawValues() {
        XCTAssertEqual(LanguageForcer.Option.auto.rawValue, "auto")
        XCTAssertEqual(LanguageForcer.Option.fr.rawValue, "fr")
        XCTAssertEqual(LanguageForcer.Option.en.rawValue, "en")
    }

    func testOptions_labelsAreNonEmpty() {
        for option in LanguageForcer.Option.allCases {
            XCTAssertFalse(option.label.isEmpty, "\(option) doit avoir un label")
        }
    }
}
