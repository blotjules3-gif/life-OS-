import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import LifeOS

/// Correctifs de l'audit "Apparence et Mental" (1er oct. 2026).
/// Chaque test vise la logique pure extraite des ecrans, pas les vues.
@MainActor
final class AuditFixesMindTests: XCTestCase {

    // MARK: Headplace: fin de seance planifiee a l'avance

    func testMeditationEndAlertIsScheduledForTheRealDeadline() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let delay = MeditationView.endAlertDelay(deadline: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(delay ?? 0, 600, accuracy: 0.001)
    }

    func testNoEndAlertWithoutRunningSessionOrPastDeadline() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(MeditationView.endAlertDelay(deadline: nil, now: now))
        XCTAssertNil(MeditationView.endAlertDelay(deadline: now.addingTimeInterval(-5), now: now))
    }

    // MARK: Endlo: interruption audio

    private let began = AVAudioSession.InterruptionType.began.rawValue
    private let ended = AVAudioSession.InterruptionType.ended.rawValue
    private let resume = AVAudioSession.InterruptionOptions.shouldResume.rawValue

    func testCallWhilePlayingPausesHonestly() {
        XCTAssertEqual(NoiseEngine.interruptionAction(typeRaw: began, optionsRaw: nil, isPlaying: true, resumePending: false), .pause)
        XCTAssertEqual(NoiseEngine.interruptionAction(typeRaw: began, optionsRaw: nil, isPlaying: false, resumePending: false), .ignore)
    }

    func testEndOfInterruptionResumesOnlyWhenAllowedAndPending() {
        XCTAssertEqual(NoiseEngine.interruptionAction(typeRaw: ended, optionsRaw: resume, isPlaying: false, resumePending: true), .resume)
        XCTAssertEqual(NoiseEngine.interruptionAction(typeRaw: ended, optionsRaw: 0, isPlaying: false, resumePending: true), .forget)
        // L'utilisateur a arrete pendant l'appel: rien ne doit repartir.
        XCTAssertEqual(NoiseEngine.interruptionAction(typeRaw: ended, optionsRaw: resume, isPlaying: false, resumePending: false), .ignore)
        XCTAssertEqual(NoiseEngine.interruptionAction(typeRaw: nil, optionsRaw: nil, isPlaying: true, resumePending: false), .ignore)
    }

    // MARK: Fabuleux: priorites du jour

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    func testRecurringAndOverdueTasksAppearInTodaysPriorities() {
        // Jeudi 1er octobre 2026, 9h a Paris.
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        let thursday = cal.component(.weekday, from: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(MorningBriefingView.isPriorityToday(done: false, due: nil, recurringDays: [thursday], now: now, calendar: cal))
        XCTAssertTrue(MorningBriefingView.isPriorityToday(done: false, due: yesterday, recurringDays: [], now: now, calendar: cal))
        XCTAssertTrue(MorningBriefingView.isPriorityToday(done: false, due: now.addingTimeInterval(3_600), recurringDays: [], now: now, calendar: cal))
    }

    func testUnplannedDoneOrFutureTasksStayOut() {
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        let other = cal.component(.weekday, from: now) % 7 + 1
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertFalse(MorningBriefingView.isPriorityToday(done: false, due: nil, recurringDays: [], now: now, calendar: cal))
        XCTAssertFalse(MorningBriefingView.isPriorityToday(done: true, due: now, recurringDays: [], now: now, calendar: cal))
        XCTAssertFalse(MorningBriefingView.isPriorityToday(done: false, due: tomorrow, recurringDays: [], now: now, calendar: cal))
        XCTAssertFalse(MorningBriefingView.isPriorityToday(done: false, due: nil, recurringDays: [other], now: now, calendar: cal))
    }

    // MARK: TrueSkin: profil et routine

    func testSavedProfileRoundTripsThroughTheEditor() {
        let raw = SkinRoutineEngine.encode(concerns: ["rides", "acné"], hasTreatment: true)
        let back = SkinRoutineEngine.decode(concernsRaw: raw)
        XCTAssertEqual(back.concerns, ["rides", "acné"])
        XCTAssertTrue(back.hasTreatment)
        XCTAssertFalse(SkinRoutineEngine.decode(concernsRaw: "").hasTreatment)
        XCTAssertTrue(SkinRoutineEngine.decode(concernsRaw: "").concerns.isEmpty)
    }

    func testEveryConcernChangesTheRoutine() {
        let base = SkinRoutineEngine.morningSteps(skinType: "normale", concerns: "")
        for c in ["rides", "pores", "teint terne", "rougeurs"] {
            let am = SkinRoutineEngine.morningSteps(skinType: "normale", concerns: c)
            let pm = SkinRoutineEngine.eveningSteps(skinType: "normale", concerns: c)
            let basePM = SkinRoutineEngine.eveningSteps(skinType: "normale", concerns: "")
            XCTAssertTrue(am != base || pm != basePM, "« \(c) » ne change rien")
        }
        XCTAssertTrue(SkinRoutineEngine.morningSteps(skinType: "normale", concerns: "rougeurs").contains("SPF 50 minéral"))
    }

    func testTreatmentNameAppearsInEveningRoutine() {
        let pm = SkinRoutineEngine.eveningSteps(skinType: "mixte", concerns: "acné,traitement", treatment: "tretinoin 0,025%")
        XCTAssertTrue(pm.contains { $0.contains("tretinoin 0,025%") })
        XCTAssertFalse(pm.contains { $0.contains("Acide salicylique") })
    }

    func testReminderTextMatchesTheGeneratedRoutine() {
        let steps = SkinRoutineEngine.morningSteps(skinType: "sensible", concerns: "")
        let body = SkinRoutineEngine.reminderBody(steps: steps)
        XCTAssertTrue(body.contains("Eau micellaire"))
        XCTAssertNotEqual(body, "Nettoyant + sérum + SPF")
    }

    // MARK: Progrez: date de prise de vue

    func testExifDateParsingRejectsFutureAndGarbage() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertNotNil(ProgressPhotoGalleryView.parseExifDate("2026:06:15 14:30:00", now: now, timeZone: paris))
        XCTAssertNil(ProgressPhotoGalleryView.parseExifDate("2099:01:01 00:00:00", now: now, timeZone: paris))
        XCTAssertNil(ProgressPhotoGalleryView.parseExifDate("pas une date", now: now, timeZone: paris))
    }

    func testCaptureDateIsReadFromPhotoMetadata() throws {
        let data = try makeJPEG(exifDate: "2026:03:02 08:15:00")
        let taken = try XCTUnwrap(ProgressPhotoGalleryView.captureDate(of: data))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: taken)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 3, 2, 8, 15])
        XCTAssertNil(ProgressPhotoGalleryView.captureDate(of: try makeJPEG(exifDate: nil)))
    }

    private func makeJPEG(exifDate: String?) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let img = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [:]
        if let exifDate { props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: exifDate] }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    // MARK: Umaxx: une erreur de fichier n'accuse pas le visage

    func testFileErrorsDoNotBlameTheFace() {
        XCTAssertFalse(FaceAnalysisIssue.unreadableFile.message.localizedCaseInsensitiveContains("visage"))
        XCTAssertFalse(FaceAnalysisIssue.photoLoadFailed.message.localizedCaseInsensitiveContains("visage"))
        XCTAssertTrue(FaceAnalysisIssue.noFace.message.localizedCaseInsensitiveContains("visage"))
    }
}
