import XCTest
import SwiftData
@testable import LifeOS

/// Lot 6: Anko (flashcards), Coursia (programmes), Blinklist (livres), Headwave (notions).
/// Chaque test porte sur une fonction qui n'existait pas ou se comportait autrement avant.
@MainActor
final class Lot6LearningTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.timeZone = cal.timeZone
        return f.date(from: s)!
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Flashcard.self, CardDeck.self, CardReview.self, Course.self, CourseModule.self,
                           CourseLesson.self, BookSummary.self, BookPassage.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func fetch<T: PersistentModel>(_ ctx: ModelContext, _ t: T.Type) throws -> [T] {
        try ctx.fetch(FetchDescriptor<T>())
    }

    // MARK: SM-2 (aucun test avant)

    func testSM2_intervalsAreDeterministic() {
        let now = date("2026-10-01T22:30:00+02:00")
        let c = Flashcard(front: "q")
        SM2.apply(to: c, quality: 4, now: now, calendar: cal)
        XCTAssertEqual(c.intervalDays, 1)
        XCTAssertEqual(c.due, date("2026-10-02T00:00:00+02:00"))
        SM2.apply(to: c, quality: 4, now: now, calendar: cal)
        XCTAssertEqual(c.intervalDays, 6)
        SM2.apply(to: c, quality: 5, now: now, calendar: cal)
        XCTAssertEqual(c.intervalDays, 15) // 6 x 2.5 arrondi
        SM2.apply(to: c, quality: 2, now: now, calendar: cal)
        XCTAssertEqual(c.reps, 0); XCTAssertEqual(c.intervalDays, 1)
        XCTAssertGreaterThanOrEqual(c.ease, 1.3)
    }

    // MARK: Textes a trous et cartes inversees

    func testCloze_indicesQuestionAnswer() {
        let t = "{{c1::Lisbonne}} est la capitale du {{c2::Portugal::pays}}."
        XCTAssertEqual(Cloze.indices(in: t), [1, 2])
        XCTAssertEqual(Cloze.question(t, index: 1), "[…] est la capitale du Portugal.")
        XCTAssertEqual(Cloze.question(t, index: 2), "Lisbonne est la capitale du [pays].")
        XCTAssertEqual(Cloze.answer(t, index: 2), "Lisbonne est la capitale du [Portugal].")
        XCTAssertEqual(Cloze.plain(t), "Lisbonne est la capitale du Portugal.")
        XCTAssertEqual(Cloze.indices(in: "pas de trou {{c0::x}}"), [])
    }

    func testNoteFactory_specsPerType() {
        XCTAssertEqual(NoteFactory.specs(type: .basic, front: "Q", back: "R").count, 1)
        XCTAssertEqual(NoteFactory.specs(type: .basicReversed, front: "Q", back: "R").map(\.kind), [CardKind.basic, CardKind.reverse])
        XCTAssertEqual(NoteFactory.specs(type: .basicReversed, front: "Q", back: " ").count, 1, "Pas de carte inversee a question vide")
        XCTAssertEqual(NoteFactory.specs(type: .cloze, front: "{{c1::a}} {{c3::b}} {{c1::c}}", back: "").map(\.clozeIndex), [1, 3])
        XCTAssertTrue(NoteFactory.specs(type: .cloze, front: "sans trou", back: "").isEmpty)
        XCTAssertTrue(NoteFactory.specs(type: .basic, front: "  ", back: "R").isEmpty)
    }

    func testCardFace_reverseSwapsAndClozeHides() {
        let r = Flashcard(front: "chien", back: "dog"); r.kind = CardKind.reverse
        XCTAssertEqual(CardFace.question(r), "dog"); XCTAssertEqual(CardFace.answer(r), "chien")
        let c = Flashcard(front: "{{c1::Paris}} en France", back: "note"); c.kind = CardKind.cloze; c.clozeIndex = 1
        XCTAssertEqual(CardFace.question(c), "[…] en France")
        XCTAssertEqual(CardFace.answer(c), "[Paris] en France\n\nnote")
    }

    func testNoteStore_editKeepsSchedulingOfKeptCards() throws {
        let ctx = ModelContext(try container())
        let deck = CardDeck(name: "Langues"); ctx.insert(deck)
        let cards = NoteStore.save(existing: [], type: .cloze, front: "{{c1::a}} {{c2::b}}", back: "", deck: deck, tags: "#voc  voc grammaire", source: "", in: ctx)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(Set(cards.compactMap(\.noteID)).count, 1, "Les trous partagent la note")
        XCTAssertEqual(cards[0].tags, "voc grammaire")
        let c1 = cards.first { $0.clozeIndex == 1 }!
        c1.intervalDays = 12; c1.reps = 3
        let edited = NoteStore.save(existing: cards, type: .cloze, front: "{{c1::a}} {{c3::z}}", back: "", deck: deck, tags: "", source: "", in: ctx)
        try ctx.save()
        XCTAssertEqual(edited.map(\.clozeIndex).sorted(), [1, 3])
        XCTAssertTrue(edited.contains { $0 === c1 })
        XCTAssertEqual(c1.intervalDays, 12, "Modifier le texte ne remet pas la carte a zero")
        XCTAssertEqual(try fetch(ctx, Flashcard.self).count, 2, "Le trou c2 retire est supprime")
    }

    // MARK: Paquets et migration

    func testDeckMigration_assignsDecksAndLosesNothing() throws {
        let ctx = ModelContext(try container())
        let a = Flashcard(front: "Q1", back: "R1", deck: "Anglais")
        let b = Flashcard(front: "Q2", back: "R2", deck: "")
        let c = Flashcard(front: "Q3", back: "R3", deck: "Anglais")
        for x in [a, b, c] { x.uid = nil; x.noteID = nil; x.deckID = nil; x.intervalDays = 4; ctx.insert(x) }
        try ctx.save()
        let changes = DeckMigration.run(cards: [a, b, c], decks: [], in: ctx)
        try ctx.save()
        XCTAssertGreaterThan(changes, 0)
        let decks = try fetch(ctx, CardDeck.self)
        XCTAssertEqual(Set(decks.map(\.name)), ["Anglais", DeckTree.defaultName])
        XCTAssertEqual(a.deckID, c.deckID)
        XCTAssertEqual(b.deck, DeckTree.defaultName)
        XCTAssertNotNil(a.uid); XCTAssertNotEqual(a.uid, c.uid)
        XCTAssertEqual(a.noteID, a.uid)
        XCTAssertEqual([a, b, c].map(\.front), ["Q1", "Q2", "Q3"])
        XCTAssertEqual([a, b, c].map(\.intervalDays), [4, 4, 4])
        XCTAssertEqual(DeckMigration.run(cards: [a, b, c], decks: decks, in: ctx), 0, "Migration idempotente")
    }

    func testDeckTree_hierarchy() {
        XCTAssertEqual(DeckTree.normalize(" Langues :: Anglais ::"), "Langues::Anglais")
        XCTAssertEqual(DeckTree.ancestors("A::B::C"), ["A", "A::B"])
        XCTAssertTrue(DeckTree.contains("A", "A::B"))
        XCTAssertFalse(DeckTree.contains("A", "AB"))
        XCTAssertEqual(DeckTree.renamed("A::B", from: "A", to: "X"), "X::B")
        XCTAssertNil(DeckTree.renamed("AB", from: "A", to: "X"))
        XCTAssertEqual(DeckTree.sorted(["B", "A::Z", "A", "A::B"]), ["A", "A::B", "A::Z", "B"])
    }

    func testDeckOps_createRenameDelete() throws {
        let ctx = ModelContext(try container())
        var decks: [CardDeck] = []
        guard case .success(let child) = DeckOps.create("Langues::Anglais", decks: &decks, in: ctx) else { return XCTFail() }
        XCTAssertEqual(decks.map(\.name).sorted(), ["Langues", "Langues::Anglais"], "Le parent est cree")
        let parent = decks.first { $0.name == "Langues" }!
        let general = DeckOps.ensure(DeckTree.defaultName, decks: &decks, in: ctx)
        XCTAssertEqual(DeckOps.create("Langues", decks: &decks, in: ctx).failureValue, .exists)
        let card = Flashcard(front: "q", deck: child.name); card.deckID = child.uid; ctx.insert(card)
        XCTAssertNil(DeckOps.rename(parent, to: "Idiomas", decks: decks, cards: [card]))
        XCTAssertEqual(child.name, "Idiomas::Anglais")
        XCTAssertEqual(card.deck, "Idiomas::Anglais")
        XCTAssertEqual(DeckOps.rename(general, to: "X", decks: decks, cards: []), .protected)
        XCTAssertNil(DeckOps.delete(parent, decks: decks, cards: [card], moveTo: general, in: ctx))
        try ctx.save()
        XCTAssertEqual(card.deckID, general.uid, "Les cartes sont deplacees, pas perdues")
        XCTAssertEqual(try fetch(ctx, CardDeck.self).map(\.name), [DeckTree.defaultName])
        XCTAssertEqual(try fetch(ctx, Flashcard.self).count, 1)
    }

    // MARK: Etiquettes et recherche

    func testTagsAndSearch() {
        XCTAssertEqual(CardTags.normalize("#voc, Voc  grammaire"), "voc grammaire")
        let c = Flashcard(front: "Le café", back: "coffee"); c.tags = "boisson voc"
        XCTAssertTrue(CardSearch.matches(c, query: "cafe"), "Sans accent")
        XCTAssertTrue(CardSearch.matches(c, query: "tag:voc coffee"))
        XCTAssertFalse(CardSearch.matches(c, query: "tag:grammaire"))
        XCTAssertFalse(CardSearch.matches(c, query: "is:suspendue"))
        c.suspended = true
        XCTAssertTrue(CardSearch.matches(c, query: "is:suspendue"))
    }

    // MARK: Suspendre, enterrer, file de seance, annulation

    func testSuspendBuryAndSessionPicksOnePerNote() {
        let now = date("2026-10-01T10:00:00+02:00")
        let a = Flashcard(front: "a", due: now.addingTimeInterval(-60))
        let aRev = Flashcard(front: "a", due: now.addingTimeInterval(-30)); aRev.noteID = a.noteID; aRev.kind = CardKind.reverse
        let s = Flashcard(front: "s", due: now.addingTimeInterval(-60)); s.suspended = true
        let b = Flashcard(front: "b", due: now.addingTimeInterval(-10))
        CardScheduling.bury(b, now: now, calendar: cal)
        XCTAssertEqual(b.buriedUntil, date("2026-10-02T00:00:00+02:00"))
        XCTAssertEqual(CardScheduling.sessionCards([a, aRev, s, b], now: now).map(\.front), ["a"])
        XCTAssertTrue(CardScheduling.isDue(b, now: date("2026-10-02T00:00:01+02:00")), "Revient le lendemain")
    }

    func testReviewQueue_relearnAndUndo() {
        var q = ReviewQueue(count: 2)
        XCTAssertEqual(q.current, 0)
        q.answer(quality: 2)                     // ratee: revient en fin de seance
        XCTAssertEqual(q.current, 1); XCTAssertEqual(q.remaining, 2)
        q.answer(quality: 4)
        XCTAssertEqual(q.current, 0, "La carte ratee revient")
        XCTAssertEqual(q.undo(), 1)
        XCTAssertEqual(q.undo(), 0)
        XCTAssertEqual(q.remaining, 2, "La remise en file est annulee aussi")
        XCTAssertFalse(q.canUndo)
        q.skip(); q.answer(quality: 5)
        XCTAssertNil(q.current)
    }

    func testAnswerAndUndoRestoresCardExactly() throws {
        let ctx = ModelContext(try container())
        let now = date("2026-10-01T10:00:00+02:00")
        let c = Flashcard(front: "q", ease: 2.36, intervalDays: 10, due: now, reps: 4); ctx.insert(c)
        let before = CardScheduling.answer(c, quality: 2, now: now, calendar: cal)
        XCTAssertEqual(c.lapses, 1); XCTAssertEqual(c.reps, 0)
        let r = CardReview(cardUID: c.uid, date: now, quality: 2, before: before); ctx.insert(r)
        try ctx.save()
        let found = ReviewUndo.last(reviews: try fetch(ctx, CardReview.self), cards: [c])
        XCTAssertTrue(found?.1 === c)
        ReviewUndo.undo(r, on: c)
        XCTAssertEqual(CardScheduling.snapshot(c), before)
        XCTAssertEqual(c.intervalDays, 10); XCTAssertEqual(c.reps, 4); XCTAssertEqual(c.lapses, 0)
        XCTAssertNil(ReviewUndo.last(reviews: [r], cards: []), "Carte supprimee: rien a annuler")
    }

    // MARK: Statistiques

    func testStats_dueReviewsRetention() {
        let now = date("2026-10-01T10:00:00+02:00")
        let due = Flashcard(front: "d", due: date("2026-10-01T20:00:00+02:00"))
        let later = Flashcard(front: "l", due: date("2026-10-05T08:00:00+02:00"))
        let susp = Flashcard(front: "s", due: now); susp.suspended = true
        let snap = CardScheduling.snapshot(due)
        let reviews = [CardReview(cardUID: nil, date: now, quality: 4, before: snap),
                       CardReview(cardUID: nil, date: now, quality: 2, before: snap),
                       CardReview(cardUID: nil, date: date("2026-09-30T09:00:00+02:00"), quality: 5, before: snap),
                       CardReview(cardUID: nil, date: date("2026-08-01T09:00:00+02:00"), quality: 2, before: snap)]
        let s = CardStats.summary(cards: [due, later, susp], reviews: reviews, now: now, calendar: cal)
        XCTAssertEqual(s.total, 3); XCTAssertEqual(s.dueToday, 1); XCTAssertEqual(s.suspended, 1)
        XCTAssertEqual(s.reviewsPerDay.count, 14)
        XCTAssertEqual(s.reviewsPerDay.last?.count, 2)
        XCTAssertEqual(s.reviewsPerDay[12].count, 1)
        XCTAssertEqual(s.reviews30, 3)
        XCTAssertEqual(s.retention!, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertNil(CardStats.summary(cards: [], reviews: [], now: now, calendar: cal).retention)
    }

    // MARK: CSV

    func testCSV_parseQuotesDelimitersAndAnkiHeader() {
        let csv = "recto,verso,paquet,etiquettes,type\n\"Bonjour, toi\",\"Hello\nyou\",Langues::Anglais,voc,inversee\n{{c1::Lisbonne}} capitale,,,,\n,vide,,,\n"
        let p = FlashcardCSV.parse(csv)
        XCTAssertEqual(p.notes.count, 2); XCTAssertEqual(p.skipped, 1)
        XCTAssertEqual(p.notes[0], CSVNote(front: "Bonjour, toi", back: "Hello\nyou", deck: "Langues::Anglais", tags: "voc", type: .basicReversed))
        XCTAssertEqual(p.notes[1].type, .cloze, "Trous reconnus sans colonne type")
        XCTAssertEqual(p.notes[1].deck, DeckTree.defaultName)

        let anki = "#separator:tab\r\n#html:true\r\n#tags column:3\r\nchien<br>animal\tdog &amp; co\ttag1\r\n"
        let a = FlashcardCSV.parse(anki)
        XCTAssertEqual(a.notes.first?.front, "chien\nanimal")
        XCTAssertEqual(a.notes.first?.back, "dog & co")
        XCTAssertEqual(a.notes.first?.tags, "tag1", "Colonne des etiquettes declaree par Anki")
        XCTAssertEqual(a.notes.first?.deck, DeckTree.defaultName)

        let semi = FlashcardCSV.parse("q1;r1\nq2;r2")
        XCTAssertEqual(semi.notes.map(\.back), ["r1", "r2"])
    }

    func testCSV_exportReimportRoundTripKeepsTypesWithoutDuplicates() throws {
        let ctx = ModelContext(try container())
        var decks: [CardDeck] = []
        let d = DeckOps.ensure("Langues::Anglais", decks: &decks, in: ctx)
        NoteStore.save(existing: [], type: .basicReversed, front: "chat", back: "cat, \"le\"", deck: d, tags: "voc", source: "", in: ctx)
        NoteStore.save(existing: [], type: .cloze, front: "{{c1::a}} et {{c2::b}}", back: "", deck: d, tags: "", source: "", in: ctx)
        try ctx.save()
        let cards = try fetch(ctx, Flashcard.self)
        XCTAssertEqual(cards.count, 4)
        let notes = FlashcardCSV.notes(from: cards)
        XCTAssertEqual(notes.count, 2, "Une ligne par note")
        let text = FlashcardCSV.export(notes)
        let back = FlashcardCSV.parse(text)
        XCTAssertEqual(Set(back.notes.map(\.type)), [.basicReversed, .cloze])
        XCTAssertEqual(back.notes.first { $0.type == .basicReversed }?.back, "cat, \"le\"")

        let again = FlashcardCSV.apply(back.notes, cards: cards, decks: try fetch(ctx, CardDeck.self), in: ctx)
        XCTAssertEqual(again.added, 0); XCTAssertEqual(again.duplicates, 2)

        let ctx2 = ModelContext(try container())
        let fresh = FlashcardCSV.apply(back.notes, cards: [], decks: [], in: ctx2)
        try ctx2.save()
        XCTAssertEqual(fresh.added, 2)
        XCTAssertEqual(try fetch(ctx2, Flashcard.self).count, 4, "Inversee et trous recrees")
        XCTAssertEqual(Set(try fetch(ctx2, CardDeck.self).map(\.name)), ["Langues", "Langues::Anglais"])
    }

    // MARK: Headwave

    func testNotions_areFlashcardsWithTag() {
        let n = Flashcard(front: "Loi de Parkinson", back: "x"); n.tags = "notion"
        let other = Flashcard(front: "q")
        XCTAssertEqual(NotionStore.notions([other, n]).map(\.front), ["Loi de Parkinson"])
        XCTAssertTrue(NotionStore.exists(title: " loi de parkinson ", in: [n]))
        XCTAssertFalse(NotionStore.exists(title: "q", in: [other]))
    }

    // MARK: Coursia

    func testSkillPlanMigration_keepsStepsAndDoneState() throws {
        let ctx = ModelContext(try container())
        let c = SkillPlanMigration.migrate(skill: "Anglais", stepsRaw: "Lire\nÉcouter\nParler", doneRaw: "Écouter", in: ctx)
        try ctx.save()
        XCTAssertEqual(c?.title, "Anglais"); XCTAssertEqual(c?.origin, "skillPlan")
        let ls = CourseOps.lessons(of: c!, modules: try fetch(ctx, CourseModule.self), lessons: try fetch(ctx, CourseLesson.self))
        XCTAssertEqual(ls.map(\.title), ["Lire", "Écouter", "Parler"])
        XCTAssertEqual(ls.map(\.done), [false, true, false])
        XCTAssertNil(SkillPlanMigration.migrate(skill: " ", stepsRaw: "", doneRaw: "", in: ctx), "Rien a reprendre")
    }

    func testCourses_progressNextReorderAndCascadeDelete() throws {
        let ctx = ModelContext(try container())
        let c1 = Course(title: "A"), c2 = Course(title: "B", sortIndex: 1)
        [c1, c2].forEach { ctx.insert($0) }
        let m1 = CourseModule(courseUID: c1.uid, title: "M1", sortIndex: 0)
        let m2 = CourseModule(courseUID: c1.uid, title: "M2", sortIndex: 1)
        let other = CourseModule(courseUID: c2.uid, title: "X")
        [m1, m2, other].forEach { ctx.insert($0) }
        let l1 = CourseLesson(moduleUID: m2.uid, title: "L3", sortIndex: 0)
        let l2 = CourseLesson(moduleUID: m1.uid, title: "L1", sortIndex: 0)
        let l3 = CourseLesson(moduleUID: m1.uid, title: "L2", sortIndex: 1)
        let lx = CourseLesson(moduleUID: other.uid, title: "LX")
        [l1, l2, l3, lx].forEach { ctx.insert($0) }
        try ctx.save()
        let all = try fetch(ctx, CourseLesson.self), mods = try fetch(ctx, CourseModule.self)
        var ls = CourseOps.lessons(of: c1, modules: mods, lessons: all)
        XCTAssertEqual(ls.map(\.title), ["L1", "L2", "L3"])
        CourseOps.toggle(l2, now: date("2026-10-01T10:00:00+02:00"))
        XCTAssertNotNil(l2.doneAt)
        XCTAssertEqual(CourseOps.progress(ls).done, 1)
        XCTAssertEqual(CourseOps.next(ls)?.title, "L2")
        CourseOps.renumber(CourseOps.moved(CourseOps.lessons(of: m1, in: all), from: [1], to: 0))
        ls = CourseOps.lessons(of: c1, modules: mods, lessons: all)
        XCTAssertEqual(ls.map(\.title), ["L2", "L1", "L3"])
        XCTAssertEqual(CourseOps.moved(["a", "b", "c", "d"], from: [0], to: 3), ["b", "c", "a", "d"])
        let gone = CourseOps.delete(c1, modules: mods, lessons: all, in: ctx)
        try ctx.save()
        XCTAssertEqual(Set(gone), Set([l1, l2, l3].compactMap(\.uid)))
        XCTAssertEqual(try fetch(ctx, CourseLesson.self).map(\.title), ["LX"], "L'autre programme est intact")
        XCTAssertEqual(try fetch(ctx, Course.self).map(\.title), ["B"])
    }

    func testCourses_linksDeadlinesReminders() {
        XCTAssertEqual(CourseOps.url(from: "coursera.org/learn/x")?.absoluteString, "https://coursera.org/learn/x")
        XCTAssertNotNil(CourseOps.url(from: "http://a.fr"))
        XCTAssertNil(CourseOps.url(from: "pas un lien"))
        XCTAssertNil(CourseOps.url(from: "javascript:alert(1)"))
        let now = date("2026-10-01T10:00:00+02:00")
        XCTAssertNil(CourseOps.reminderDate(for: date("2026-10-01T00:00:00+02:00"), now: now, calendar: cal), "9 h deja passe")
        XCTAssertEqual(CourseOps.reminderDate(for: date("2026-10-03T00:00:00+02:00"), now: now, calendar: cal), date("2026-10-03T09:00:00+02:00"))
        XCTAssertEqual(CourseOps.deadlineLabel(date("2026-10-04T12:00:00+02:00"), now: now, calendar: cal).text, "Échéance dans 3 j")
        XCTAssertTrue(CourseOps.deadlineLabel(date("2026-09-29T12:00:00+02:00"), now: now, calendar: cal).overdue)
    }

    // MARK: Blinklist

    func testBooks_outlineSearchCollectionsMigration() throws {
        let ctx = ModelContext(try container())
        let b = BookSummary(title: "Atomic Habits", author: "James Clear", keyIdeas: "Systèmes", rating: 5)
        b.uid = nil; ctx.insert(b)
        XCTAssertEqual(BookOps.migrate([b]), 1); XCTAssertNotNil(b.uid)
        XCTAssertEqual(BookOps.migrate([b]), 0)
        let p0 = BookPassage(bookUID: b.uid, kind: "idea", text: "Avant tout chapitre", sortIndex: 0)
        let ch = BookPassage(bookUID: b.uid, kind: "chapter", text: "Chapitre 1", sortIndex: 1)
        let h = BookPassage(bookUID: b.uid, kind: "highlight", text: "Un passage sur l'identité", page: "12", sortIndex: 2)
        let alien = BookPassage(bookUID: UUID(), kind: "idea", text: "autre livre")
        [p0, ch, h, alien].forEach { ctx.insert($0) }
        let all = [p0, ch, h, alien]
        let ordered = BookOps.passages(of: b, in: all)
        XCTAssertEqual(ordered.count, 3)
        let outline = BookOps.outline(ordered)
        XCTAssertEqual(outline.count, 2)
        XCTAssertNil(outline[0].chapter); XCTAssertTrue(outline[1].chapter === ch)
        XCTAssertEqual(outline[1].items.map(\.text), ["Un passage sur l'identité"])
        XCTAssertTrue(BookOps.matches(b, passages: all, query: "identite"))
        XCTAssertFalse(BookOps.matches(b, passages: all, query: "autre livre"))
        BookOps.move(h, by: -1, in: ordered)
        XCTAssertEqual(BookOps.passages(of: b, in: all).map(\.text).last, "Chapitre 1")
        XCTAssertEqual(BookCollections.list("Business, business\nÀ relire"), ["Business", "À relire"])
        XCTAssertEqual(BookCollections.toggled("A\nB", "a"), "B")
        BookOps.delete(b, passages: all, in: ctx)
        try ctx.save()
        XCTAssertEqual(try fetch(ctx, BookPassage.self).map(\.text), ["autre livre"])
    }

    func testCoachSummaryStaysMarkedAfterEdit() {
        let ai = BookSummaryOrigin.markAI("- Idée")
        let edited = BookSummaryOrigin.markAI(BookSummaryOrigin.body(ai) + "\n- Ajout")
        XCTAssertTrue(BookSummaryOrigin.isAI(edited))
        XCTAssertEqual(BookSummaryOrigin.body(edited), "- Idée\n- Ajout")
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let e) = self { return e }; return nil }
}
