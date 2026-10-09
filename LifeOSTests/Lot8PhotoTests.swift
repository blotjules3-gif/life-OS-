import XCTest
import UIKit
@testable import LifeOS

/// Lot 8, studio photo et widget photo: modele, fichiers, frise, comptes a rebours,
/// requete de l'entite. Tout est teste en logique pure, sans simulateur de widget.
final class Lot8PhotoTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("pw-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        PhotoWidgetStorage.rootOverride = tempRoot
    }

    override func tearDown() {
        PhotoWidgetStorage.rootOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func jpeg(width: Int, height: Int) -> Data {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return img.jpegData(compressionQuality: 0.9)!
    }

    // MARK: Modele

    func testConfigEncodeDecodeRoundTrip() throws {
        var c = PhotoWidgetConfig.makeDefault(.collage)
        c.name = "Vacances"
        c.photos = [PhotoRef(fileName: "a.jpg", crop: PhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5), inRotation: false),
                    PhotoRef(fileName: "b.jpg")]
        c.rotation = .every3h
        c.style.borderWidth = 3
        c.typography.family = .serif
        c.content.text = "Été"
        c.action = .tool(category: "fitness", name: "TabaTime")
        let data = try PhotoWidgetStorage.encodeIndex([c])
        let back = try XCTUnwrap(PhotoWidgetStorage.decodeIndex(data))
        XCTAssertEqual(back.count, 1)
        // Les dates passent par ISO 8601 (a la seconde): on compare le reste.
        var expected = c
        expected.createdAt = back[0].createdAt; expected.updatedAt = back[0].updatedAt
        XCTAssertEqual(back[0], expected)
    }

    func testOldOrPartialJSONDecodesWithDefaults() throws {
        let id = UUID()
        let json = """
        {"version":1,"configs":[{"id":"\(id.uuidString)","name":"Ancien","template":"hologram","photos":[{"fileName":"x.jpg"}]}]}
        """
        let configs = try XCTUnwrap(PhotoWidgetStorage.decodeIndex(Data(json.utf8)))
        XCTAssertEqual(configs.first?.id, id)
        XCTAssertEqual(configs.first?.template, .note, "un modele inconnu devient une note au lieu de casser l'index")
        XCTAssertEqual(configs.first?.rotation, .off)
        XCTAssertEqual(configs.first?.photos.first?.crop, .full)
        XCTAssertEqual(configs.first?.photos.first?.inRotation, true)
        XCTAssertEqual(configs.first?.action.kind, .studio)
    }

    func testTemplateDefaults() {
        let photo = PhotoWidgetConfig.makeDefault(.photo)
        XCTAssertEqual(photo.rotation, .daily)
        XCTAssertTrue(PhotoWidgetLayoutRules.photoIsBackdrop(photo), "photo par defaut = plein cadre")
        XCTAssertEqual(photo.missingContent, "Ajoute au moins une photo.")

        XCTAssertEqual(PhotoWidgetConfig.makeDefault(.collage).style.layout, .grid2)

        let note = PhotoWidgetConfig.makeDefault(.note)
        XCTAssertNotNil(note.missingContent, "aucun texte invente")
        XCTAssertTrue(note.content.text.isEmpty)

        let cd = PhotoWidgetConfig.makeDefault(.countdown)
        XCTAssertNil(cd.content.countdownDate, "aucune date inventee")
        XCTAssertNotNil(cd.missingContent)

        var goal = PhotoWidgetConfig.makeDefault(.goal)
        XCTAssertNotNil(goal.missingContent)
        goal.content.goalTitle = "Lire"; goal.content.goalTarget = 12
        XCTAssertNil(goal.missingContent)

        for t in PhotoWidgetTemplate.allCases {
            XCTAssertEqual(PhotoWidgetConfig.makeDefault(t).name, t.title)
            XCTAssertEqual(PhotoWidgetConfig.makeDefault(t).action.kind, .studio)
        }
        XCTAssertEqual(PhotoWidgetTemplate.allCases.filter(\.supportsLockScreen), [.note, .countdown, .goal])
    }

    func testTapURLs() {
        let id = UUID()
        XCTAssertEqual(PhotoWidgetTapAction.studio.url(configID: id).absoluteString, "lifeos://photo-widget?id=\(id.uuidString)")
        XCTAssertEqual(PhotoWidgetTapAction.home.url(configID: id).absoluteString, "lifeos://home")
        let tool = PhotoWidgetTapAction.tool(category: "nutrition", name: "Journal & macros").url(configID: id)
        let comps = URLComponents(url: tool, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.host, "tool")
        XCTAssertEqual(comps?.queryItems?.first { $0.name == "cat" }?.value, "nutrition")
        XCTAssertEqual(comps?.queryItems?.first { $0.name == "name" }?.value, "Journal & macros")
        XCTAssertEqual(PhotoWidgetTapAction.tool(category: "nutrition", name: "").url(configID: id).absoluteString, "lifeos://home",
                       "un outil sans nom ne doit pas donner un lien vers rien")
    }

    func testCropClampAndPixelRect() {
        let c = PhotoCrop(x: 0.9, y: -1, width: 0.5, height: 3).clamped
        XCTAssertEqual(c.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.y, 0, accuracy: 1e-9)
        XCTAssertEqual(c.height, 1, accuracy: 1e-9)
        let r = PhotoCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.5).pixelRect(width: 1000, height: 800)
        XCTAssertEqual(r, CGRect(x: 250, y: 400, width: 500, height: 400))
        XCTAssertTrue(PhotoCrop.full.isFull)
    }

    func testCropMathKeepsWidgetRatio() {
        let size = CGSize(width: 1000, height: 750)
        let m = PhotoCropMath.maxFrame(ratio: 1, imageSize: size)
        XCTAssertEqual(m.w, 0.75, accuracy: 1e-9); XCTAssertEqual(m.h, 1, accuracy: 1e-9)
        let crop = PhotoCropMath.crop(ratio: 364.0 / 170.0, imageSize: size, center: CGPoint(x: 0.5, y: 0.5), zoom: 1)
        let pixelRatio = (crop.width * 1000) / (crop.height * 750)
        XCTAssertEqual(pixelRatio, 364.0 / 170.0, accuracy: 0.001)
        XCTAssertEqual(PhotoCropMath.closestAspect(to: crop, imageSize: size), .medium)
        XCTAssertEqual(PhotoCropMath.crop(ratio: nil, imageSize: size, center: .zero, zoom: 0.5), .full)
        // Le cadre ne sort jamais de l'image, meme centre dans un coin.
        let corner = PhotoCropMath.crop(ratio: 1, imageSize: size, center: CGPoint(x: 0, y: 1), zoom: 0.5)
        XCTAssertGreaterThanOrEqual(corner.x, 0); XCTAssertLessThanOrEqual(corner.y + corner.height, 1.0000001)
    }

    // MARK: Images

    func testDownsizeCapsLongSideAndKeepsRatio() throws {
        let out = try XCTUnwrap(PhotoWidgetImage.downsizedJPEG(from: jpeg(width: 3000, height: 2000)))
        let size = try XCTUnwrap(PhotoWidgetImage.pixelSize(of: out))
        XCTAssertEqual(max(size.width, size.height), 1000)
        XCTAssertEqual(size.width / size.height, 1.5, accuracy: 0.01)

        let small = try XCTUnwrap(PhotoWidgetImage.downsizedJPEG(from: jpeg(width: 400, height: 300)))
        let smallSize = try XCTUnwrap(PhotoWidgetImage.pixelSize(of: small))
        XCTAssertLessThanOrEqual(max(smallSize.width, smallSize.height), 400, "jamais agrandie")

        XCTAssertNil(PhotoWidgetImage.downsizedJPEG(from: Data("pas une image".utf8)))
    }

    func testWidgetLoadReadsReducedAndCropped() throws {
        let dir = try XCTUnwrap(PhotoWidgetStorage.imagesDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stored = try XCTUnwrap(PhotoWidgetImage.downsizedJPEG(from: jpeg(width: 2000, height: 1000)))
        try stored.write(to: dir.appendingPathComponent("p.jpg"))
        let ref = PhotoRef(fileName: "p.jpg", crop: PhotoCrop(x: 0, y: 0, width: 0.5, height: 1))
        let img = try XCTUnwrap(PhotoWidgetImage.load(ref, maxPixel: 520))
        XCTAssertLessThanOrEqual(img.size.width * img.scale, 261)
        XCTAssertEqual(img.size.width / img.size.height, 1, accuracy: 0.02)
        XCTAssertNil(PhotoWidgetStorage.imageURL("../escape.jpg"), "un nom ne sort jamais du dossier")
    }

    // MARK: Fichiers

    func testCleanupRemovesOnlyUnreferencedFiles() throws {
        let dir = tempRoot.appendingPathComponent("img", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in ["used.jpg", "draft.jpg", "orphan.jpg"] { try Data([1, 2, 3]).write(to: dir.appendingPathComponent(n)) }
        let removed = PhotoWidgetFiles.cleanup(directory: dir, referenced: ["used.jpg"], protecting: ["draft.jpg"])
        XCTAssertEqual(removed, ["orphan.jpg"])
        let left = Set(PhotoWidgetFiles.listImages(in: dir).map(\.name))
        XCTAssertEqual(left, ["used.jpg", "draft.jpg"])
        XCTAssertEqual(PhotoWidgetFiles.totalSize(in: dir), 6)
    }

    func testDuplicateCopiesFilesAndIsIndependent() throws {
        var c = PhotoWidgetConfig.makeDefault(.photo)
        c.name = "Mer"
        c.photos = [PhotoRef(fileName: "a.jpg", crop: PhotoCrop(x: 0.1, y: 0, width: 0.5, height: 0.5)), PhotoRef(fileName: "b.jpg", inRotation: false)]
        var copies: [(String, String)] = []
        let dup = PhotoWidgetFiles.duplicate(c) { old, new in copies.append((old, new)) }
        XCTAssertNotEqual(dup.id, c.id)
        XCTAssertEqual(dup.name, "Mer (copie)")
        XCTAssertEqual(copies.map(\.0), ["a.jpg", "b.jpg"])
        XCTAssertEqual(dup.photos.map(\.fileName), copies.map(\.1))
        XCTAssertTrue(Set(dup.photos.map(\.fileName)).isDisjoint(with: ["a.jpg", "b.jpg"]), "nouveaux fichiers: supprimer l'un ne casse pas l'autre")
        XCTAssertEqual(dup.photos.map(\.crop), c.photos.map(\.crop))
        XCTAssertEqual(dup.photos.map(\.inRotation), [true, false])
        XCTAssertNotEqual(dup.photos[0].id, c.photos[0].id)
    }

    func testDeleteRemovesOnlyFilesNoOtherConfigUses() {
        var a = PhotoWidgetConfig.makeDefault(.photo); a.photos = [PhotoRef(fileName: "shared.jpg"), PhotoRef(fileName: "a-only.jpg")]
        var b = PhotoWidgetConfig.makeDefault(.collage); b.photos = [PhotoRef(fileName: "shared.jpg")]
        let r = PhotoWidgetFiles.remove(a.id, from: [a, b])
        XCTAssertEqual(r.configs.map(\.id), [b.id])
        XCTAssertEqual(r.filesToDelete, ["a-only.jpg"])
        let none = PhotoWidgetFiles.remove(UUID(), from: [a, b])
        XCTAssertEqual(none.configs.count, 2); XCTAssertTrue(none.filesToDelete.isEmpty)
    }

    func testUpsertKeepsOrder() {
        let a = PhotoWidgetConfig.makeDefault(.note), b = PhotoWidgetConfig.makeDefault(.goal)
        var a2 = a; a2.name = "Modifié"
        let out = PhotoWidgetFiles.upsert(a2, into: [a, b])
        XCTAssertEqual(out.map(\.id), [a.id, b.id]); XCTAssertEqual(out[0].name, "Modifié")
        XCTAssertEqual(PhotoWidgetFiles.upsert(PhotoWidgetConfig.makeDefault(.photo), into: [a, b]).count, 3)
    }

    func testIndexFileRoundTripAndCorruptFile() throws {
        XCTAssertEqual(PhotoWidgetStorage.readIndex(), [], "pas de fichier = aucun widget")
        var c = PhotoWidgetConfig.makeDefault(.note); c.content.text = "Respire"
        try PhotoWidgetStorage.writeIndex([c])
        XCTAssertEqual(PhotoWidgetStorage.readIndex().map(\.id), [c.id])
        XCTAssertEqual(PhotoWidgetStorage.config(id: c.id)?.content.text, "Respire")
        try Data("{oups".utf8).write(to: XCTUnwrap(PhotoWidgetStorage.indexURL))
        XCTAssertEqual(PhotoWidgetStorage.readIndex(), [])
    }

    @MainActor
    func testStoreSaveDuplicateDeleteOnDisk() async throws {
        let store = PhotoWidgetStore()
        var reloads = 0
        store.reloadWidgets = { reloads += 1 }
        let refs = try await store.importPhotos([jpeg(width: 1600, height: 1200)])
        XCTAssertEqual(refs.count, 1)
        var c = PhotoWidgetConfig.makeDefault(.photo)
        c.name = "  "
        c.photos = refs
        try store.save(c)
        XCTAssertEqual(store.configs.first?.name, "Photo", "nom vide = nom du modele")
        XCTAssertEqual(reloads, 1)

        let dup = try store.duplicate(c.id)
        XCTAssertEqual(store.configs.count, 2)
        let dir = try XCTUnwrap(PhotoWidgetStorage.imagesDirectory)
        XCTAssertEqual(PhotoWidgetFiles.listImages(in: dir).count, 2)

        try store.delete(c.id)
        XCTAssertEqual(PhotoWidgetStorage.readIndex().map(\.id), [dup.id])
        let left = PhotoWidgetFiles.listImages(in: dir).map(\.name)
        XCTAssertEqual(left, dup.photos.map(\.fileName), "la copie garde ses photos")

        // Brouillon abandonne: ses photos partent.
        let draft = try await store.importPhotos([jpeg(width: 300, height: 300)])
        store.discardDraftFiles(draft.map(\.fileName))
        XCTAssertEqual(PhotoWidgetFiles.listImages(in: dir).count, 1)
        XCTAssertEqual(reloads, 3)
    }

    // MARK: Frise et rotation

    func testRotationScheduleHourly() {
        let cal = utcCalendar()
        let now = date(2026, 10, 4, 14, 20, cal: cal)
        let slots = PhotoWidgetSchedule.slots(photoCount: 3, rotation: .hourly, now: now, calendar: cal)
        XCTAssertEqual(slots.count, 12, "3 photos x 4 tours, sous le plafond de 24")
        XCTAssertEqual(slots[0].date, now, "la premiere entree est maintenant")
        XCTAssertEqual(slots[1].date, date(2026, 10, 4, 15, 0, cal: cal))
        XCTAssertEqual(slots[2].date, date(2026, 10, 4, 16, 0, cal: cal))
        // Cale sur l'horloge: chaque heure suivante avance d'une photo.
        XCTAssertEqual(slots[1].photoOffset, (slots[0].photoOffset + 1) % 3)
        XCTAssertEqual(slots[2].photoOffset, (slots[0].photoOffset + 2) % 3)
        // Recharger 10 minutes plus tard garde la meme photo.
        let later = PhotoWidgetSchedule.slots(photoCount: 3, rotation: .hourly, now: now.addingTimeInterval(600), calendar: cal)
        XCTAssertEqual(later[0].photoOffset, slots[0].photoOffset)
    }

    func testRotationScheduleDailyAlignsOnLocalMidnightAndCaps() {
        let cal = utcCalendar()
        let now = date(2026, 10, 4, 22, 0, cal: cal)
        let slots = PhotoWidgetSchedule.slots(photoCount: 10, rotation: .daily, now: now, calendar: cal)
        XCTAssertEqual(slots.count, PhotoWidgetSchedule.maxEntries)
        XCTAssertEqual(slots[1].date, date(2026, 10, 5, 0, 0, cal: cal))
        XCTAssertEqual(slots[2].date, date(2026, 10, 6, 0, 0, cal: cal))
        XCTAssertEqual(slots[1].photoOffset, (slots[0].photoOffset + 1) % 10)
    }

    func testNoRotationOrSinglePhotoGivesOneEntry() {
        let now = Date()
        XCTAssertEqual(PhotoWidgetSchedule.slots(photoCount: 5, rotation: .off, now: now).count, 1)
        XCTAssertEqual(PhotoWidgetSchedule.slots(photoCount: 1, rotation: .hourly, now: now).count, 1)
        XCTAssertEqual(PhotoWidgetSchedule.slots(photoCount: 0, rotation: .daily, now: now), [.init(date: now, photoOffset: 0)])
    }

    func testPhotosForOffsetWrapAround() {
        let refs = (0..<3).map { PhotoRef(fileName: "\($0).jpg") }
        XCTAssertEqual(PhotoWidgetSchedule.photos(refs, offset: 2, count: 2).map(\.fileName), ["2.jpg", "0.jpg"])
        XCTAssertEqual(PhotoWidgetSchedule.photos(refs, offset: 0, count: 5).count, 3)
        XCTAssertTrue(PhotoWidgetSchedule.photos([], offset: 1, count: 2).isEmpty)
    }

    func testRotatingPhotosNeverEmptyByMistake() {
        var c = PhotoWidgetConfig.makeDefault(.photo)
        c.photos = [PhotoRef(fileName: "a.jpg", inRotation: false), PhotoRef(fileName: "b.jpg", inRotation: true)]
        XCTAssertEqual(c.rotatingPhotos.map(\.fileName), ["b.jpg"])
        c.photos[1].inRotation = false
        XCTAssertEqual(c.rotatingPhotos.count, 2, "toutes sorties de la rotation = toutes gardees")
    }

    func testTimelineStateAndPlans() {
        let cal = utcCalendar()
        var old = PhotoWidgetConfig.makeDefault(.note, now: Date(timeIntervalSince1970: 100))
        old.content.text = "a"
        var recent = PhotoWidgetConfig.makeDefault(.goal, now: Date(timeIntervalSince1970: 200))
        recent.updatedAt = Date(timeIntervalSince1970: 300)
        XCTAssertEqual(PhotoWidgetTimeline.state(selectedID: nil, configs: []), .notChosen(hasConfigs: false))
        XCTAssertEqual(PhotoWidgetTimeline.state(selectedID: nil, configs: [old, recent]), .config(recent, photoOffset: 0))
        XCTAssertEqual(PhotoWidgetTimeline.state(selectedID: old.id, configs: [old, recent]), .config(old, photoOffset: 0))
        XCTAssertEqual(PhotoWidgetTimeline.state(selectedID: UUID(), configs: [old, recent]), .deleted)

        let now = date(2026, 10, 4, 18, 0, cal: cal)
        var cd = PhotoWidgetConfig.makeDefault(.countdown); cd.content.countdownDate = date(2026, 12, 24, cal: cal)
        let cdPlan = PhotoWidgetTimeline.plan(for: cd, now: now, calendar: cal)
        XCTAssertEqual(cdPlan.dates.count, 8)
        XCTAssertEqual(cdPlan.dates[1].date, date(2026, 10, 5, cal: cal))
        XCTAssertTrue(cdPlan.reloadAtEnd)
        XCTAssertEqual(PhotoWidgetTimeline.plan(for: old, now: now, calendar: cal).dates.count, 1)
        XCTAssertFalse(PhotoWidgetTimeline.plan(for: old, now: now, calendar: cal).reloadAtEnd)
    }

    // MARK: Compte a rebours et objectif

    func testCountdownDaysUseLocalCalendarDays() {
        let cal = utcCalendar()
        let lateEvening = date(2026, 10, 5, 23, 0, cal: cal)
        XCTAssertEqual(PhotoWidgetCountdown.daysLeft(to: date(2026, 10, 6, 1, 0, cal: cal), from: lateEvening, calendar: cal), 1)
        XCTAssertEqual(PhotoWidgetCountdown.daysLeft(to: date(2026, 10, 5, 8, 0, cal: cal), from: lateEvening, calendar: cal), 0)
        XCTAssertEqual(PhotoWidgetCountdown.daysLeft(to: date(2026, 12, 25, cal: cal), from: date(2026, 10, 4, 12, cal: cal), calendar: cal), 82)
        XCTAssertEqual(PhotoWidgetCountdown.daysLeft(to: date(2026, 10, 1, cal: cal), from: date(2026, 10, 4, 9, cal: cal), calendar: cal), -3)
        // Passage a l'heure d'hiver (25 octobre a Paris): toujours un jour par jour.
        XCTAssertEqual(PhotoWidgetCountdown.daysLeft(to: date(2026, 10, 26, cal: cal), from: date(2026, 10, 24, 12, cal: cal), calendar: cal), 2)
    }

    func testCountdownTexts() {
        XCTAssertEqual(PhotoWidgetCountdown.headline(days: 0), "Aujourd'hui")
        XCTAssertEqual(PhotoWidgetCountdown.headline(days: 12), "12")
        XCTAssertEqual(PhotoWidgetCountdown.headline(days: -4), "4")
        XCTAssertEqual(PhotoWidgetCountdown.caption(days: 1), "jour restant")
        XCTAssertEqual(PhotoWidgetCountdown.caption(days: 5), "jours restants")
        XCTAssertEqual(PhotoWidgetCountdown.caption(days: -1), "jour depuis")
        XCTAssertEqual(PhotoWidgetCountdown.caption(days: -9), "jours depuis")
        XCTAssertEqual(PhotoWidgetCountdown.sentence(days: 12, label: "Vacances"), "Vacances : dans 12 jours")
        XCTAssertEqual(PhotoWidgetCountdown.sentence(days: -2, label: ""), "la date : il y a 2 jours")
        XCTAssertEqual(PhotoWidgetCountdown.sentence(days: 1, label: "Anniv"), "Anniv : demain")
        for s in ["Aujourd'hui", "jour restant", "jours depuis"] { XCTAssertFalse(s.contains("—") || s.contains("–")) }
    }

    func testGoalMath() {
        XCTAssertEqual(PhotoWidgetGoal.fraction(current: 3, target: 12), 0.25, accuracy: 1e-9)
        XCTAssertEqual(PhotoWidgetGoal.fraction(current: 20, target: 12), 1)
        XCTAssertEqual(PhotoWidgetGoal.fraction(current: -2, target: 12), 0)
        XCTAssertEqual(PhotoWidgetGoal.fraction(current: 5, target: 0), 0)
        XCTAssertEqual(PhotoWidgetGoal.progressText(current: 2.5, target: 10, unit: "km"), "2,5 / 10 km")
        XCTAssertEqual(PhotoWidgetGoal.progressText(current: 3, target: 12, unit: ""), "3 / 12")
        XCTAssertEqual(PhotoWidgetEditorMath.parseNumber("12,5"), 12.5)
        XCTAssertNil(PhotoWidgetEditorMath.parseNumber("douze"))
    }

    // MARK: Requete de l'entite (choix du widget)

    func testEntityQueryFromIndex() throws {
        var a = PhotoWidgetConfig.makeDefault(.photo); a.name = "Été à Lisbonne"
        var b = PhotoWidgetConfig.makeDefault(.countdown); b.name = "Mariage"
        var n = PhotoWidgetConfig.makeDefault(.note); n.name = "Mantra"
        try PhotoWidgetStorage.writeIndex([a, b, n])
        let index = PhotoWidgetStorage.readIndex()

        let gone = UUID()
        let found = PhotoWidgetIndexQuery.entities(for: [n.id, gone, a.id], in: index)
        XCTAssertEqual(found.map(\.id), [n.id, a.id], "ordre demande garde, identifiant supprime absent")
        XCTAssertEqual(found.first?.template, .note)

        XCTAssertEqual(PhotoWidgetIndexQuery.matching("ete", in: index).map(\.id), [a.id], "sans accents ni casse")
        XCTAssertEqual(PhotoWidgetIndexQuery.matching("  ", in: index).count, 3)
        XCTAssertEqual(PhotoWidgetIndexQuery.lockScreenSummaries(index).map(\.id), [b.id, n.id])
        XCTAssertEqual(PhotoWidgetIndexQuery.summaries(index).map(\.name), ["Été à Lisbonne", "Mariage", "Mantra"])
    }

    func testFontFallbackNeverEmpty() {
        XCTAssertEqual(PhotoWidgetFonts.postScriptName(.satoshi, .black), "Satoshi-Black")
        XCTAssertEqual(PhotoWidgetFonts.postScriptName(.inter, .semibold), "Inter-Bold")
        XCTAssertNil(PhotoWidgetFonts.postScriptName(.serif, .bold))
    }

    func testContrastWarningMath() {
        XCTAssertEqual(PhotoWidgetEditorMath.contrast(.white, .black), 21, accuracy: 0.01)
        XCTAssertLessThan(PhotoWidgetEditorMath.contrast(.white, .paper), 3)
        XCTAssertEqual(PhotoWidgetLayoutRules.ink(on: .paper), .ink)
        XCTAssertEqual(PhotoWidgetLayoutRules.ink(on: .night), .white)
    }
}
