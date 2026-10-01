import XCTest
import SwiftData
import UserNotifications
@testable import LifeOS

/// Lot 7 sante: MediSûr (calendrier, journal des prises, stock, export),
/// Doctolink (statut, historique par praticien), Maple Health (unites,
/// reperes, periodes, sources), Mon Espace Vaccin (proches, pieces jointes).
@MainActor
final class Lot7HealthTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.locale = Locale(identifier: "fr_FR")
        return c
    }()

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? cal).date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
    }

    private func rule(_ kind: MedSchedule.Kind, _ minutes: [Int], weekdays: Set<Int> = [], every: Int = 1,
                      start: Date, since: Date? = nil, end: Date? = nil, stop: Date? = nil) -> MedSchedule.Rule {
        MedSchedule.Rule(kind: kind, minutes: minutes, weekdays: weekdays, intervalDays: every, anchor: start,
                         effectiveStart: max(start, since ?? start), end: end, stop: stop)
    }

    // MARK: Calendrier de prise

    /// Avant: heures entieres seulement (Stepper 0...23, minute toujours 0).
    func testCustomTimesKeepTheirMinutes() {
        let r = rule(.daily, [7 * 60 + 30, 21 * 60 + 45], start: d(2026, 3, 1))
        let occ = MedSchedule.occurrences(r, from: d(2026, 3, 2), to: d(2026, 3, 2, 23, 59), calendar: cal)
        XCTAssertEqual(occ, [d(2026, 3, 2, 7, 30), d(2026, 3, 2, 21, 45)])
    }

    func testChosenWeekdaysOnly() {
        // 2026-03-02 est un lundi. Lundi (2), mercredi (4), vendredi (6).
        let r = rule(.weekdays, [480], weekdays: [2, 4, 6], start: d(2026, 3, 1))
        let occ = MedSchedule.occurrences(r, from: d(2026, 3, 2), to: d(2026, 3, 8, 23, 59), calendar: cal)
        XCTAssertEqual(occ, [d(2026, 3, 2, 8), d(2026, 3, 4, 8), d(2026, 3, 6, 8)])
    }

    func testEveryThreeDaysCountsFromTheTreatmentStart() {
        let r = rule(.interval, [600], every: 3, start: d(2026, 3, 1, 9))
        let occ = MedSchedule.occurrences(r, from: d(2026, 3, 1), to: d(2026, 3, 10, 23, 59), calendar: cal)
        XCTAssertEqual(occ, [d(2026, 3, 1, 10), d(2026, 3, 4, 10), d(2026, 3, 7, 10), d(2026, 3, 10, 10)])
    }

    func testAsNeededSchedulesNothing() {
        let r = rule(.prn, [], start: d(2026, 3, 1))
        XCTAssertTrue(MedSchedule.occurrences(r, from: d(2026, 3, 1), to: d(2026, 4, 1), calendar: cal).isEmpty)
        XCTAssertEqual(MedSchedule.reminderPlan(r, active: true, now: d(2026, 3, 2), calendar: cal), .none)
    }

    func testEndDateIsInclusiveAndStopEndsTheCourse() {
        let r = rule(.daily, [480, 1200], start: d(2026, 3, 1), end: d(2026, 3, 2))
        let occ = MedSchedule.occurrences(r, from: d(2026, 3, 1), to: d(2026, 3, 10), calendar: cal)
        XCTAssertEqual(occ.count, 4, "le 2 mars se prend encore")
        let stopped = rule(.daily, [480, 1200], start: d(2026, 3, 1), stop: d(2026, 3, 1, 12))
        XCTAssertEqual(MedSchedule.occurrences(stopped, from: d(2026, 3, 1), to: d(2026, 3, 10), calendar: cal), [d(2026, 3, 1, 8)])
    }

    /// Changer l'heure ne fabrique pas de prises "manquees" sous le nouvel horaire.
    func testScheduleChangeIsNotRetroactive() {
        let r = rule(.daily, [480], start: d(2026, 3, 1), since: d(2026, 3, 5, 12))
        let occ = MedSchedule.occurrences(r, from: d(2026, 3, 1), to: d(2026, 3, 6, 23, 59), calendar: cal)
        XCTAssertEqual(occ, [d(2026, 3, 6, 8)])
    }

    func testLegacyFrequenciesConvertToTheSameTimes() {
        let twice = MedSchedule.rule(kind: "", doseMinutes: "", weekdays: "", intervalDays: 1, frequency: "2x/jour",
                                     hourMorning: 8, hourEvening: 20, startDate: d(2026, 3, 2), scheduleSince: nil,
                                     endDate: nil, inactiveSince: nil, calendar: cal)
        XCTAssertEqual(twice.kind, .daily)
        XCTAssertEqual(twice.minutes, [480, 1200])
        let weekly = MedSchedule.rule(kind: "", doseMinutes: "", weekdays: "", intervalDays: 1, frequency: "1x/semaine",
                                      hourMorning: 9, hourEvening: nil, startDate: d(2026, 3, 4), scheduleSince: nil,
                                      endDate: nil, inactiveSince: nil, calendar: cal)
        XCTAssertEqual(weekly.kind, .weekdays)
        XCTAssertEqual(weekly.weekdays, [4])
        let prn = MedSchedule.rule(kind: "", doseMinutes: "", weekdays: "", intervalDays: 1, frequency: "Au besoin",
                                   hourMorning: 8, hourEvening: nil, startDate: d(2026, 3, 4), scheduleSince: nil,
                                   endDate: nil, inactiveSince: nil, calendar: cal)
        XCTAssertEqual(prn.kind, .prn)
    }

    func testEncodingRoundTripAndSummary() {
        XCTAssertEqual(MedSchedule.parseMinutes("1230, 480,480,9999"), [480, 1230])
        XCTAssertEqual(MedSchedule.encodeMinutes([1230, 480]), "480,1230")
        XCTAssertEqual(MedSchedule.parseWeekdays("6,2,9"), [2, 6])
        let r = rule(.weekdays, [480, 1230], weekdays: [6, 2], start: d(2026, 3, 1))
        XCTAssertEqual(MedSchedule.summary(r), "Lun, Ven à 08:00, 20:30")
        XCTAssertEqual(MedSchedule.summary(rule(.interval, [600], every: 3, start: d(2026, 3, 1))), "Tous les 3 jours à 10:00")
    }

    func testReminderPlans() {
        let now = d(2026, 3, 2, 9)
        let daily = rule(.daily, [480, 1230], start: d(2026, 3, 1))
        XCTAssertEqual(MedSchedule.reminderPlan(daily, active: true, now: now, calendar: cal),
                       .repeating([.init(weekday: nil, hour: 8, minute: 0), .init(weekday: nil, hour: 20, minute: 30)]))
        let days = rule(.weekdays, [480], weekdays: [2, 6], start: d(2026, 3, 1))
        XCTAssertEqual(MedSchedule.reminderPlan(days, active: true, now: now, calendar: cal),
                       .repeating([.init(weekday: 2, hour: 8, minute: 0), .init(weekday: 6, hour: 8, minute: 0)]))
        let every3 = rule(.interval, [600], every: 3, start: d(2026, 3, 1))
        guard case .dates(let dates) = MedSchedule.reminderPlan(every3, active: true, now: now, horizonDays: 7, calendar: cal) else {
            return XCTFail("tous les 3 jours: dates precises")
        }
        XCTAssertEqual(dates, [d(2026, 3, 4, 10), d(2026, 3, 7, 10)])
        XCTAssertEqual(MedSchedule.reminderPlan(daily, active: false, now: now, calendar: cal), .none)
    }

    /// Une prise a venir deja notee ne doit plus sonner.
    func testAlreadyLoggedDoseIsNotReminded() {
        let now = d(2026, 3, 2, 19)
        let daily = rule(.daily, [480, 1230], start: d(2026, 3, 1))
        let plan = MedSchedule.reminderPlan(daily, active: true, now: now, horizonDays: 2,
                                            handled: [d(2026, 3, 2, 20, 30)], calendar: cal)
        guard case .dates(let dates) = plan else { return XCTFail("dates precises attendues") }
        XCTAssertFalse(dates.contains(d(2026, 3, 2, 20, 30)))
        XCTAssertEqual(dates.first, d(2026, 3, 3, 8))
    }

    // MARK: Journal des prises

    private func ev(_ at: Date?, _ status: String, logged: Date, until: Date? = nil, q: Double = 1) -> DoseLog.Event {
        DoseLog.Event(scheduledAt: at, loggedAt: logged, status: status, snoozedUntil: until, quantity: q)
    }

    func testDoseStatuses() {
        let at = d(2026, 3, 2, 8)
        XCTAssertEqual(DoseLog.status(at: at, events: [], now: d(2026, 3, 2, 7)), .upcoming)
        XCTAssertEqual(DoseLog.status(at: at, events: [], now: d(2026, 3, 2, 9)), .due)
        XCTAssertEqual(DoseLog.status(at: at, events: [], now: d(2026, 3, 2, 10, 1)), .missed)
        XCTAssertEqual(DoseLog.status(at: at, events: [ev(at, "taken", logged: d(2026, 3, 2, 8, 5))], now: d(2026, 3, 3)), .taken)
        XCTAssertEqual(DoseLog.status(at: at, events: [ev(at, "skipped", logged: d(2026, 3, 2, 8, 5))], now: d(2026, 3, 3)), .skipped)
        let snooze = ev(at, "snoozed", logged: d(2026, 3, 2, 8, 1), until: d(2026, 3, 2, 8, 31))
        XCTAssertEqual(DoseLog.status(at: at, events: [snooze], now: d(2026, 3, 2, 8, 10)), .snoozed(until: d(2026, 3, 2, 8, 31)))
        XCTAssertEqual(DoseLog.status(at: at, events: [snooze], now: d(2026, 3, 2, 11)), .missed)
    }

    /// Annuler = retirer la derniere ligne: la precedente reprend la main.
    func testLatestEventWinsAndUndoRestoresThePreviousState() {
        let at = d(2026, 3, 2, 8)
        let snooze = ev(at, "snoozed", logged: d(2026, 3, 2, 8, 1), until: d(2026, 3, 2, 8, 16))
        let taken = ev(at, "taken", logged: d(2026, 3, 2, 8, 20))
        let now = d(2026, 3, 2, 8, 25)
        XCTAssertEqual(DoseLog.status(at: at, events: [snooze, taken], now: now), .taken)
        XCTAssertEqual(DoseLog.status(at: at, events: [snooze], now: now), .snoozed(until: d(2026, 3, 2, 8, 16)))
        XCTAssertEqual(DoseLog.status(at: at, events: [], now: now), .due)
    }

    func testAdherenceCountsAndIgnoresAsNeeded() {
        let a1 = d(2026, 3, 1, 8), a2 = d(2026, 3, 1, 20), a3 = d(2026, 3, 2, 8)
        let events = [ev(a1, "taken", logged: a1), ev(a2, "skipped", logged: a2),
                      ev(nil, "taken", logged: d(2026, 3, 1, 15)),          // au besoin
                      ev(d(2026, 2, 28, 9), "taken", logged: d(2026, 2, 28, 9))] // ancien horaire
        let occ = [a1, a2, a3]
        let slots = DoseLog.slots(occurrences: occ, events: events, now: d(2026, 3, 3))
        let orphans = DoseLog.orphans(occurrences: occ, events: events)
        XCTAssertEqual(orphans.count, 2)
        let a = DoseLog.adherence(slots: slots, orphans: orphans)
        XCTAssertEqual(a, DoseLog.Adherence(taken: 2, skipped: 1, missed: 1))
        XCTAssertEqual(a.rate ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertNil(DoseLog.Adherence().rate, "rien d'attendu n'est pas 0 %")
    }

    // MARK: Stock

    func testStockDerivesFromTakenDosesOnly() {
        let setAt = d(2026, 3, 1, 12)
        let events = [ev(d(2026, 3, 1, 8), "taken", logged: d(2026, 3, 1, 8)),     // avant le comptage
                      ev(d(2026, 3, 1, 20), "taken", logged: d(2026, 3, 1, 20)),
                      ev(d(2026, 3, 2, 8), "taken", logged: d(2026, 3, 2, 8), q: 2),
                      ev(d(2026, 3, 2, 20), "skipped", logged: d(2026, 3, 2, 20), q: 0)]
        XCTAssertEqual(DoseLog.stock(initial: 10, setAt: setAt, events: events), 7)
        // Annuler la prise du 2 au matin rend 2 unites.
        XCTAssertEqual(DoseLog.stock(initial: 10, setAt: setAt, events: Array(events.prefix(2))), 9)
    }

    func testRefillDateAndDaysLeft() {
        let up = [d(2026, 3, 2, 8), d(2026, 3, 2, 20), d(2026, 3, 3, 8), d(2026, 3, 3, 20)]
        XCTAssertEqual(DoseLog.refillDate(stock: 5, threshold: 2, perDose: 1, upcoming: up), d(2026, 3, 3, 8))
        XCTAssertNil(DoseLog.refillDate(stock: 2, threshold: 2, perDose: 1, upcoming: up), "deja sous le seuil: l'ecran le dit")
        XCTAssertEqual(DoseLog.daysLeft(stock: 10, perDose: 1, dosesPerDay: 2), 5)
        XCTAssertNil(DoseLog.daysLeft(stock: 10, perDose: 1, dosesPerDay: 0))
        XCTAssertEqual(DoseLog.dosesPerDay(rule(.weekdays, [480, 1200], weekdays: [2, 4, 6, 7, 1, 3, 5], start: d(2026, 3, 1))), 2, accuracy: 0.001)
        XCTAssertEqual(DoseLog.dosesPerDay(rule(.interval, [480], every: 2, start: d(2026, 3, 1))), 0.5, accuracy: 0.001)
    }

    // MARK: Export

    func testCSVEscapesAndUsesSemicolons() {
        let csv = MedicalCSV.adherence([
            .init(person: "Moi", medication: "Doliprane; 1000", dosage: "1 \"cp\"", scheduled: d(2026, 3, 2, 8, 5, calendar: .current),
                  status: "Pris", logged: nil)
        ])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "Personne;Médicament;Dosage;Prévu;Statut;Enregistré")
        XCTAssertEqual(lines[1], "Moi;\"Doliprane; 1000\";\"1 \"\"cp\"\"\";2026-03-02 08:05;Pris;")
    }

    // MARK: Mesures

    func testUnitConversionIsReversibleAndStoredCanonical() {
        let mmol = VitalUnits.toDisplay(1.0, type: "glycémie", glucose: "mmol/L", weight: "kg")
        XCTAssertEqual(mmol, 5.55, accuracy: 0.01)
        XCTAssertEqual(VitalUnits.toCanonical(mmol, type: "glycémie", glucose: "mmol/L", weight: "kg"), 1.0, accuracy: 1e-9)
        let lb = VitalUnits.toDisplay(70, type: "poids", glucose: "g/L", weight: "lb")
        XCTAssertEqual(lb, 154.32, accuracy: 0.01)
        XCTAssertEqual(VitalUnits.toCanonical(lb, type: "poids", glucose: "g/L", weight: "lb"), 70, accuracy: 1e-9)
        XCTAssertEqual(VitalUnits.toDisplay(120, type: "tension", glucose: "mmol/L", weight: "lb"), 120)
        XCTAssertEqual(VitalUnits.canonicalUnit("SpO2"), "%")
    }

    func testReferencePositions() {
        XCTAssertEqual(VitalReference.position(value: 140, value2: 80, type: "tension"), .above)
        XCTAssertEqual(VitalReference.position(value: 120, value2: 88, type: "tension"), .above, "la diastolique compte")
        XCTAssertEqual(VitalReference.position(value: 120, value2: 80, type: "tension"), .within)
        XCTAssertEqual(VitalReference.position(value: 0.6, value2: nil, type: "glycémie"), .below)
        XCTAssertEqual(VitalReference.position(value: 93, value2: nil, type: "SpO2"), .below)
        XCTAssertNil(VitalReference.position(value: 70, value2: nil, type: "poids"))
        for t in ["tension", "glycémie", "fréquence cardiaque", "température", "SpO2", "sommeil"] {
            XCTAssertFalse(VitalReference.range(t)?.source.isEmpty ?? true, "\(t): source nommee")
        }
    }

    func testPeriodFilter() {
        let now = d(2026, 3, 31, 12)
        XCTAssertTrue(VitalPeriod.week.contains(d(2026, 3, 25, 0, 1), now: now, calendar: cal))
        XCTAssertFalse(VitalPeriod.week.contains(d(2026, 3, 24, 23), now: now, calendar: cal))
        XCTAssertTrue(VitalPeriod.year.contains(d(2025, 4, 1), now: now, calendar: cal))
        XCTAssertTrue(VitalPeriod.all.contains(d(2001, 1, 1), now: now, calendar: cal))
    }

    func testSourcesAndDuplicates() {
        XCTAssertEqual(VitalSource.label(source: "", notes: "Apple Santé"), "Apple Santé")
        XCTAssertEqual(VitalSource.label(source: "", notes: "après repas"), "Saisie manuelle")
        let existing = [(type: "poids", date: d(2026, 3, 2, 7, 0)), (type: "sommeil", date: d(2026, 3, 2))]
        XCTAssertTrue(VitalSource.isDuplicate(type: "poids", date: d(2026, 3, 2, 7, 0).addingTimeInterval(20), existing: existing, sameDay: false, calendar: cal))
        XCTAssertFalse(VitalSource.isDuplicate(type: "poids", date: d(2026, 3, 2, 9), existing: existing, sameDay: false, calendar: cal))
        XCTAssertTrue(VitalSource.isDuplicate(type: "sommeil", date: d(2026, 3, 2, 6), existing: existing, sameDay: true, calendar: cal))
    }

    /// Avant: toute baisse hors poids etait neutre, donc une SpO2 qui chute ne se voyait pas.
    func testFallingOxygenAndSleepAreFlagged() {
        XCTAssertEqual(VitalTrend.tone(type: "SpO2", deltas: [-3]), .worse)
        XCTAssertEqual(VitalTrend.tone(type: "sommeil", deltas: [-1.5]), .worse)
        XCTAssertEqual(VitalTrend.tone(type: "sommeil", deltas: [1]), .neutral)
        XCTAssertEqual(VitalTrend.tone(type: "température", deltas: [1.2]), .worse)
    }

    // MARK: Rendez-vous

    func testAppointmentStatusNeverClaimsAProviderBooking() {
        let now = d(2026, 3, 10, 12)
        XCTAssertEqual(AppointmentStatus.effective(stored: "", date: d(2026, 3, 11), now: now), .planned)
        XCTAssertEqual(AppointmentStatus.effective(stored: "confirmed", date: d(2026, 3, 11), now: now), .confirmed)
        XCTAssertEqual(AppointmentStatus.effective(stored: "confirmed", date: d(2026, 3, 9), now: now), .done)
        XCTAssertEqual(AppointmentStatus.effective(stored: "cancelled", date: d(2026, 3, 9), now: now), .cancelled)
        XCTAssertEqual(AppointmentStatus.confirmed.label, "Confirmé par le cabinet")
    }

    func testConsultationHistoryByPractitioner() {
        let now = d(2026, 3, 10)
        let e: [AppointmentHistory.Entry] = [
            .init(date: d(2026, 1, 5), doctor: "Dr Lévy", specialty: "Cardiologue", notes: "ECG", cancelled: false, files: 1),
            .init(date: d(2026, 2, 5), doctor: "dr levy ", specialty: "Cardiologue", notes: "", cancelled: false, files: 0),
            .init(date: d(2026, 2, 6), doctor: "Dr Lévy", specialty: "Cardiologue", notes: "", cancelled: true, files: 0),
            .init(date: d(2026, 4, 1), doctor: "Dr Lévy", specialty: "Cardiologue", notes: "", cancelled: false, files: 0),
            .init(date: d(2026, 2, 20), doctor: "", specialty: "Dentiste", notes: "", cancelled: false, files: 0),
        ]
        let groups = AppointmentHistory.byPractitioner(e, now: now)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Dentiste", "le plus recent d'abord")
        XCTAssertEqual(groups[1].visits.count, 2, "annule et futur exclus, accents et casse ignores")
        XCTAssertEqual(groups[1].visits.first?.date, d(2026, 2, 5))
    }

    // MARK: Pieces jointes et personnes

    func testAttachmentDraftDeletesTheRightFiles() {
        var draft = MedicalFiles.Draft(raw: "a.jpg\nb.jpg")
        draft.add("c.jpg")
        draft.remove("a.jpg")
        XCTAssertEqual(draft.deletedOnSave, ["a.jpg"])
        XCTAssertEqual(draft.deletedOnCancel, ["c.jpg"])
        XCTAssertEqual(draft.raw, "b.jpg\nc.jpg")
        XCTAssertEqual(MedicalFiles.list("\n x.jpg \n\n"), ["x.jpg"])
    }

    func testPeopleFilterAndNames() {
        XCTAssertTrue(MedicalPeople.matches(filter: MedicalPeople.everyone, personID: "abc"))
        XCTAssertTrue(MedicalPeople.matches(filter: "", personID: ""))
        XCTAssertFalse(MedicalPeople.matches(filter: "", personID: "abc"))
        XCTAssertEqual(MedicalPeople.name(for: "", in: []), "Moi")
        XCTAssertEqual(MedicalPeople.name(for: "abc", in: [("abc", "Léa")]), "Léa")
    }

    func testVaccineReminderIDSeparatesPeopleButKeepsMine() {
        let next = d(2026, 6, 1)
        XCTAssertEqual(VaccineReminder.id(name: "ROR", personID: "", next: next), ReminderIDs.vaccination(name: "ROR", nextDate: next))
        XCTAssertNotEqual(VaccineReminder.id(name: "ROR", personID: "p1", next: next),
                          VaccineReminder.id(name: "ROR", personID: "p2", next: next))
    }

    // MARK: Scenario d'acceptation (base en memoire)

    /// Traitement 2x/jour finissant demain: une prise, un saut, l'heure change,
    /// puis stock, historique et rappels; suppression sans rien laisser.
    func testTwiceDailyCourseEndToEnd() async throws {
        let container = try ModelContainer(for: Medication.self, DoseEvent.self, MedicalPerson.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let c = Calendar.current
        let start = c.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 7))!
        let med = Medication(name: "Amoxicilline", dosage: "500mg", startDate: start)
        med.stableID = UUID().uuidString
        med.scheduleKind = "daily"; med.doseMinutes = "480,1200"; med.scheduleSince = start
        med.endDate = c.date(byAdding: .day, value: 1, to: start)
        med.trackStock = true; med.stockCount = 10; med.stockSetAt = start
        let photo = try XCTUnwrap(ImageStore.save(Data([0xFF, 0xD8, 0xFF]), prefix: "rxtest"))
        med.attachmentFiles = MedicalFiles.encode([photo])
        ctx.insert(med)

        let morning = c.date(bySettingHour: 8, minute: 0, second: 0, of: start)!
        let evening = c.date(bySettingHour: 20, minute: 0, second: 0, of: start)!
        ctx.insert(DoseEvent(medID: med.stableID, scheduledAt: morning, status: "taken", loggedAt: morning.addingTimeInterval(300)))
        ctx.insert(DoseEvent(medID: med.stableID, scheduledAt: evening, status: "skipped", loggedAt: evening.addingTimeInterval(60), quantity: 0))
        try ctx.save()

        // L'heure du soir passe a 21:30 le lendemain matin.
        let editAt = c.date(byAdding: .hour, value: 2, to: c.date(byAdding: .day, value: 1, to: start)!)!
        med.doseMinutes = "480,1290"; med.scheduleSince = editAt
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<DoseEvent>())
        let events = MedicalData.events(of: med, in: all)
        XCTAssertEqual(MedicalData.stock(of: med, events: events), 9)

        let now = c.date(byAdding: .hour, value: 1, to: editAt)!
        let history = MedicalData.history(med, events: events, from: nil, now: now, calendar: c)
        XCTAssertEqual(history.filter { $0.status == .taken }.count, 1)
        XCTAssertEqual(history.filter { $0.status == .skipped }.count, 1)
        XCTAssertTrue(history.filter { $0.status == .missed }.isEmpty, "rien d'invente avant le nouvel horaire")

        let reqs = MedicationReminders.requests(for: med, base: "med.\(med.stableID)", now: now, events: events, calendar: c)
        // Dates rebaties depuis les composantes: nextTriggerDate() rend nil pour une date passee.
        let fireDates = reqs.compactMap { ($0.trigger as? UNCalendarNotificationTrigger).flatMap { c.date(from: $0.dateComponents) } }
        XCTAssertFalse(fireDates.isEmpty)
        XCTAssertTrue(fireDates.allSatisfy { c.startOfDay(for: $0) <= c.startOfDay(for: med.endDate!) }, "rien apres la fin")
        XCTAssertTrue(reqs.contains { r in
            guard let t = r.trigger as? UNCalendarNotificationTrigger else { return false }
            return t.dateComponents.hour == 21 && t.dateComponents.minute == 30
        }, "le nouvel horaire est programme")

        let deleted = MedicalData.deleteMedication(med, ctx: ctx)
        XCTAssertEqual(deleted, [photo])
        XCTAssertNil(ImageStore.url(for: photo), "la photo d'ordonnance part avec le traitement")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<DoseEvent>()), 0, "aucune prise orpheline")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Medication>()), 0)
        await MedicationReminders.waitForIdle()
    }
}
