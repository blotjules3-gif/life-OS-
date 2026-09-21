import XCTest
@testable import LifeOS

/// Score d'energie du jour.
///
/// Le defaut corrige: le total etait divise par 100 quoi qu'il arrive, alors
/// que les six criteres pesent 100 points ENSEMBLE. Quelqu'un qui notait
/// seulement une humeur a 5 sur 5 recevait 15 sur 100, affiche "Tres faible".
/// L'app annoncait un effondrement d'energie a quelqu'un qui venait de dire
/// qu'il allait tres bien, et le widget de l'ecran d'accueil affichait le
/// meme chiffre en rouge.
final class EnergyScoreTests: XCTestCase {

    private func input(sleepHours: Double? = nil, sleepQuality: Int? = nil,
                       mood: Int? = nil, fatigue: Int? = nil, waterML: Int? = nil,
                       habitsDone: Int? = nil, habitsTotal: Int? = nil) -> EnergyScore.Input {
        EnergyScore.Input(sleepHours: sleepHours, sleepQuality: sleepQuality,
                          mood: mood, fatigue: fatigue, waterML: waterML,
                          habitsDone: habitsDone, habitsTotal: habitsTotal)
    }

    // MARK: - Le defaut

    /// Une humeur au maximum et rien d'autre doit donner 100, pas 15.
    /// Le score porte sur ce qui est renseigne.
    func testOnlyMoodLoggedIsNotAnEnergyCollapse() {
        let r = EnergyScore.compute(input(mood: 5))
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.label, "Excellent")
    }

    /// Et une humeur au plus bas reste au plus bas.
    func testOnlyMoodAtWorst() {
        XCTAssertEqual(EnergyScore.compute(input(mood: 1)).score, 20)
    }

    /// La couverture dit sur combien le score a ete calcule.
    func testCoverageReflectsWhatWasLogged() {
        XCTAssertEqual(EnergyScore.compute(input(mood: 5)).coverage, 0.15, accuracy: 0.001)
        XCTAssertEqual(EnergyScore.compute(input(sleepQuality: 4, mood: 3)).coverage,
                       0.45, accuracy: 0.001)
    }

    /// Une journee sans rien ne vaut aucun score.
    func testNothingLoggedGivesZeroCoverage() {
        let r = EnergyScore.compute(input())
        XCTAssertEqual(r.coverage, 0, accuracy: 0.001)
        XCTAssertEqual(r.score, 0)
    }

    // MARK: - Journee complete

    /// Tout au maximum donne 100, meme sans le critere fatigue qui n'est
    /// jamais renseigne cote iOS. Avant, une journee parfaite plafonnait a 95
    /// pour cette seule raison.
    func testPerfectDayWithoutFatigueStillReachesOneHundred() {
        let r = EnergyScore.compute(input(sleepHours: 8, sleepQuality: 5, mood: 5,
                                          waterML: 2500, habitsDone: 4, habitsTotal: 4))
        XCTAssertEqual(r.score, 100)
    }

    func testWorstCompleteDay() {
        let r = EnergyScore.compute(input(sleepHours: 0.01, sleepQuality: 1, mood: 1,
                                          fatigue: 5, waterML: 1, habitsDone: 0, habitsTotal: 4))
        XCTAssertLessThan(r.score, 20)
        XCTAssertEqual(r.label, "Très faible")
    }

    // MARK: - Bornes

    /// Dormir douze heures ne doit pas donner plus que dormir huit heures.
    func testOversleepingDoesNotOverflow() {
        let eight = EnergyScore.compute(input(sleepHours: 8)).score
        let twelve = EnergyScore.compute(input(sleepHours: 12)).score
        XCTAssertEqual(eight, 100)
        XCTAssertEqual(twelve, 100)
    }

    /// Boire cinq litres non plus.
    func testOverdrinkingDoesNotOverflow() {
        XCTAssertEqual(EnergyScore.compute(input(waterML: 5000)).score, 100)
    }

    /// Plus d'habitudes faites que d'habitudes existantes ne casse rien.
    func testMoreHabitsDoneThanTotal() {
        XCTAssertEqual(EnergyScore.compute(input(habitsDone: 9, habitsTotal: 4)).score, 100)
    }

    /// Zero habitude au total: le critere n'existe pas, il ne doit ni compter
    /// ni faire tomber le score.
    func testZeroHabitsTotalIsNotCounted() {
        let r = EnergyScore.compute(input(mood: 5, habitsDone: 0, habitsTotal: 0))
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.coverage, 0.15, accuracy: 0.001)
    }

    /// Le score reste dans 0…100 sur toutes les combinaisons raisonnables.
    func testScoreAlwaysInRange() {
        for q in 1...5 {
            for m in 1...5 {
                for h in [0.0, 4.0, 8.0, 11.0] {
                    let r = EnergyScore.compute(input(sleepHours: h, sleepQuality: q, mood: m))
                    XCTAssertGreaterThan(r.score + 1, 0)
                    XCTAssertLessThanOrEqual(r.score, 100)
                }
            }
        }
    }

    /// Mieux dormir ne doit jamais faire baisser le score.
    func testBetterSleepNeverLowersTheScore() {
        var previous = -1
        for q in 1...5 {
            let s = EnergyScore.compute(input(sleepQuality: q, mood: 3)).score
            XCTAssertGreaterThan(s + 1, previous)
            previous = s
        }
    }

    // MARK: - Seuil d'affichage

    /// Le seuil doit laisser passer une journee a moitie remplie, et refuser
    /// une journee ou seule l'humeur est notee: 15 % de couverture ne permet
    /// pas d'annoncer un niveau d'energie.
    func testMinimumCoverageThresholdIsSane() {
        XCTAssertLessThan(EnergyScore.compute(input(mood: 5)).coverage,
                          EnergyScore.minimumCoverage)
        XCTAssertGreaterThan(EnergyScore.compute(input(sleepQuality: 4, mood: 3)).coverage,
                             EnergyScore.minimumCoverage)
    }
}
