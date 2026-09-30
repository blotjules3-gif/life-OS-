import XCTest
@testable import LifeOS

/// Moteur Trilingo: seances, repetition espacee, placement, rappels, et la simulation
/// de 180 jours demandee par le brief (le parcours ne doit jamais devenir une boucle vide).
final class TrilingoEngineTests: XCTestCase {

    /// Cours synthetique: 200 jours de 12 phrases, identifiants uniques.
    private func course(days: Int = 200) -> TrilingoCourse {
        let ds = (0..<days).map { d in
            TrilingoDay(day: d + 1, unit: d / 10 + 1, level: d < 50 ? "A1" : d < 120 ? "A2" : "B1",
                        items: (0..<12).map { i in
                            let id = d * 12 + i + 1
                            return TrilingoItem(sid: id, tid: 100_000 + id, s: "phrase \(id)", t: "frase numero \(id)", audio: false)
                        }, words: [], known: (d + 1) * 10)
        }
        return TrilingoCourse(source: "fra", target: "spa", version: "t", status: "complet", days: ds, license: "test", noSpaces: false)
    }

    private let caps = TrilingoCapabilities(audio: true, speech: false)

    func testFirstSessionIntroducesNewSentencesInSeveralSkills() {
        let c = course()
        let s = TrilingoEngine.session(course: c, progress: TrilingoProgress(target: "spa"), today: "2026-10-01", minutes: 10, caps: caps)
        XCTAssertEqual(Set(s.filter { $0.kind == .intro }.map(\.item.tid)).count, 12, "un jour de cours par séance de 10 min")
        XCTAssertTrue(s.contains { $0.kind == .build })
        XCTAssertTrue(s.contains { $0.kind == .dictation || $0.kind == .listenChoose }, "écoute quand une voix existe")
        XCTAssertFalse(s.contains { $0.kind == .speak }, "pas d'oral sans reconnaissance vocale")
    }

    func testWrongAnswerGoesToNotebookAndComesBackTomorrow() {
        var p = TrilingoProgress(target: "spa")
        let item = course().days[0].items[0]
        let ex = TrilingoExercise(kind: .chooseMeaning, item: item, skill: .reading, isReview: false)
        TrilingoEngine.record(&p, exercise: ex, correct: false, today: "2026-10-01")
        XCTAssertEqual(p.mistakes, [item.tid])
        XCTAssertEqual(p.srs["\(item.tid)|lecture"]?.due, "2026-10-02")
        let review = TrilingoExercise(kind: .chooseMeaning, item: item, skill: .reading, isReview: true)
        TrilingoEngine.record(&p, exercise: review, correct: true, today: "2026-10-02")
        XCTAssertTrue(p.mistakes.isEmpty, "réussie en révision : sortie du carnet")
    }

    func testIntervalsGrow() {
        var p = TrilingoProgress(target: "spa")
        let item = course().days[0].items[0]
        let ex = TrilingoExercise(kind: .chooseMeaning, item: item, skill: .reading, isReview: true)
        var day = "2026-10-01"
        var gaps: [String] = []
        for _ in 0..<4 {
            TrilingoEngine.record(&p, exercise: ex, correct: true, today: day)
            day = p.srs["\(item.tid)|lecture"]!.due
            gaps.append(day)
        }
        XCTAssertEqual(gaps, ["2026-10-03", "2026-10-07", "2026-10-14", "2026-10-29"])
    }

    /// 180 journees simulees, 10 min par jour, 85 % de bonnes reponses: chaque jour a
    /// du contenu nouveau, les revisions existent, et on avance d'un jour de cours par
    /// seance (pas de boucle sur les memes phrases).
    func testSimulated180Days() {
        let c = course()
        var p = TrilingoProgress(target: "spa"); p.placementDone = true
        var day = "2026-10-01"
        var rng = SeededRNG(seed: 42)
        var introduced = Set<Int>()
        for n in 1...180 {
            let s = TrilingoEngine.session(course: c, progress: p, today: day, minutes: 10, caps: caps, seed: UInt64(n))
            let fresh = s.filter { $0.kind == .intro }.map(\.item.tid)
            XCTAssertFalse(fresh.isEmpty, "jour \(n) sans phrase nouvelle")
            XCTAssertTrue(introduced.isDisjoint(with: fresh), "jour \(n) : une phrase déjà introduite revient comme nouvelle")
            introduced.formUnion(fresh)
            if n > 3 { XCTAssertTrue(s.contains { $0.isReview }, "jour \(n) sans révision") }
            for e in s where e.kind != .intro { TrilingoEngine.record(&p, exercise: e, correct: rng.next() % 100 < 85, today: day) }
            TrilingoEngine.finish(&p, session: s, today: day)
            day = TrilingoEngine.addDays(day, 1)
        }
        XCTAssertEqual(introduced.count, 180 * 12)
        XCTAssertEqual(p.completedDates.count, 180)
    }

    func testPlacementStopsAtFirstFailedLevel() {
        let probes = [5, 20, 45, 80, 120, 170]
        XCTAssertEqual(TrilingoEngine.placementStart(results: [5: 3, 20: 2, 45: 1], probes: probes), 20)
        XCTAssertEqual(TrilingoEngine.placementStart(results: [5: 1], probes: probes), 1)
        XCTAssertEqual(TrilingoEngine.placementStart(results: Dictionary(uniqueKeysWithValues: probes.map { ($0, 3) }), probes: probes), 170)
    }

    func testPlacementDayMovesTheStartOfNewSentences() {
        let c = course()
        var p = TrilingoProgress(target: "spa"); p.placementDone = true; p.placementDay = 20
        let s = TrilingoEngine.session(course: c, progress: p, today: "2026-10-01", minutes: 10, caps: caps)
        XCTAssertEqual(s.first { $0.kind == .intro }?.item.tid, c.days[19].items[0].tid)
    }

    func testRemindersSkipTodayWhenDoneAndNeverDuplicate() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        let dates = TrilingoEngine.reminderDates(now: morning, hour: 19, minute: 0, doneToday: false, timeZone: cal.timeZone)
        XCTAssertEqual(dates.count, 7)
        let done = TrilingoEngine.reminderDates(now: morning, hour: 19, minute: 0, doneToday: true, timeZone: cal.timeZone)
        XCTAssertEqual(done.count, 6, "séance faite : pas de rappel aujourd'hui")
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 21))!
        XCTAssertEqual(TrilingoEngine.reminderDates(now: late, hour: 19, minute: 0, doneToday: false, timeZone: cal.timeZone).count, 6)
        XCTAssertEqual(Set(dates.map { TrilingoEngine.dayKey($0, timeZone: cal.timeZone) }).count, 7, "un rappel par jour, pas de doublon")
        // Passage a l'heure d'hiver (25 oct 2026): le rappel reste a 19 h locale.
        let beforeDST = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!
        for d in TrilingoEngine.reminderDates(now: beforeDST, hour: 19, minute: 0, doneToday: false, timeZone: cal.timeZone) {
            XCTAssertEqual(cal.component(.hour, from: d), 19)
        }
    }

    func testAnswerCheckingIgnoresAccentsCaseAndPunctuation() {
        XCTAssertEqual(TrilingoEngine.similarity("¿Dónde está el baño?", "donde esta el bano"), 1)
        XCTAssertLessThan(TrilingoEngine.similarity("Yo tengo un perro", "tengo un gato"), 0.85)
        XCTAssertEqual(TrilingoEngine.similarity("私はここにいたい。", "私はここにいたい", noSpaces: true), 1)
    }

    /// Cours reels embarques: chaque cours annonce "complet" a au moins 180 jours,
    /// et le vocabulaire progresse (pas 240 jours de A1).
    func testBundledCoursesAreHonest() throws {
        let m = try XCTUnwrap(TrilingoLibrary.manifest(), "manifeste Trilingo embarqué")
        for (code, e) in m.courses where e.days > 0 {
            let c = try XCTUnwrap(TrilingoLibrary.course(source: m.source, target: code), code)
            if c.status == "complet" { XCTAssertGreaterThanOrEqual(c.days.count, 180, code) }
            let firstKnown = c.days.first?.known ?? 0, lastKnown = c.days.last?.known ?? 0
            XCTAssertGreaterThan(lastKnown, firstKnown * 10, "\(code) : le vocabulaire doit progresser")
            XCTAssertEqual(Set(c.allItems.map(\.tid)).count, c.allItems.count, "\(code) : aucune phrase en double")
        }
    }
}
