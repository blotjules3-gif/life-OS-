import XCTest
import SwiftData
@testable import LifeOS

/// La base d'un vrai telephone survit-elle au passage a la synchro iCloud ?
///
/// Pour etre synchronisables, les relations "une habitude a des coches" ont
/// du devenir optionnelles et gagner un lien retour cote enfant. Ca change
/// la facon dont la base est rangee sur le disque. Si la migration rate,
/// l'app deplace la base dans une sauvegarde et repart a vide: l'utilisateur
/// perd ses series du jour au lendemain.
///
/// On ne peut pas verifier ca a la main. Ce test ecrit une base avec
/// l'ANCIENNE forme des modeles (recopiee telle quelle de la version en
/// TestFlight), la ferme, la rouvre avec la forme actuelle, et compte.
final class SyncMigrationTests: XCTestCase {

    /// Copie exacte des modeles tels qu'ils sont sur les telephones avant la
    /// synchro. Ne pas "corriger": c'est ce que la migration doit lire.
    enum V1 {
        @Model final class Habit {
            var name: String
            var icon: String
            var colorHex: Int
            var createdAt: Date
            var isPending: Bool
            var isArchived: Bool
            var moduleTag: String
            var scheduledHour: Int
            var scheduledMinute: Int
            var sourceGoalID: String = ""
            @Relationship(deleteRule: .cascade) var completions: [HabitCompletion]
            init(name: String) {
                self.name = name; self.icon = "checkmark"; self.colorHex = 0x4CC38A
                self.createdAt = .now; self.isPending = false; self.isArchived = false
                self.moduleTag = ""; self.scheduledHour = 9; self.scheduledMinute = 0
                self.completions = []
            }
        }
        @Model final class HabitCompletion {
            var date: Date
            init(date: Date) { self.date = date }
        }
        @Model final class Pet {
            var name: String
            var species: String
            @Relationship(deleteRule: .cascade) var events: [PetCare]
            init(name: String) { self.name = name; self.species = "Chat"; self.events = [] }
        }
        @Model final class PetCare {
            var type: String
            var date: Date
            var note: String
            var recurringDays: Int
            init(type: String, date: Date) {
                self.type = type; self.date = date; self.note = ""; self.recurringDays = 0
            }
        }
    }

    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-migration-\(UUID().uuidString).store")
    }

    override func tearDown() {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(n) * 86_400) }

    /// Ecrit une base "ancien telephone": une habitude cochee 30 jours, un
    /// animal avec 3 soins.
    private func writeOldStore() throws {
        let schema = Schema([V1.Habit.self, V1.HabitCompletion.self, V1.Pet.self, V1.PetCare.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, url: url)])
        let ctx = ModelContext(container)
        let h = V1.Habit(name: "Lire 20 pages")
        ctx.insert(h)
        for d in 0..<30 { h.completions.append(V1.HabitCompletion(date: day(d))) }
        let p = V1.Pet(name: "Rex")
        ctx.insert(p)
        for (i, t) in ["Vaccin", "Vétérinaire", "Anti-puces"].enumerated() {
            p.events.append(V1.PetCare(type: t, date: day(i)))
        }
        try ctx.save()
    }

    private func openWithCurrentSchema() throws -> ModelContext {
        let schema = LocalStore.schema
        let c = try ModelContainer(for: schema,
                                   configurations: [ModelConfiguration(schema: schema, url: url)])
        return ModelContext(c)
    }

    /// Le test qui compte: les 30 coches, donc la serie, sont toujours la.
    func testHabitCompletionsSurvive() throws {
        try writeOldStore()
        let ctx = try openWithCurrentSchema()
        let habits = try ctx.fetch(FetchDescriptor<Habit>())
        XCTAssertEqual(habits.count, 1, "l'habitude a disparu à la migration")
        XCTAssertEqual(habits.first?.completions.count, 30, "des coches ont été perdues: la série casse")
    }

    /// Le lien retour, necessaire a iCloud, doit etre rempli pour les
    /// anciennes lignes aussi, pas seulement les nouvelles.
    func testBackLinkIsFilledForOldRows() throws {
        try writeOldStore()
        let ctx = try openWithCurrentSchema()
        let habit = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertTrue(habit.completions.allSatisfy { $0.habit === habit })
    }

    func testPetCareSurvives() throws {
        try writeOldStore()
        let ctx = try openWithCurrentSchema()
        let pet = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Pet>()).first)
        XCTAssertEqual(pet.name, "Rex")
        XCTAssertEqual(Set(pet.events.map(\.type)), ["Vaccin", "Vétérinaire", "Anti-puces"])
    }

    /// Ecrire par la propriete calculee doit toujours persister.
    func testAppendingThroughComputedPropertyPersists() throws {
        try writeOldStore()
        let ctx = try openWithCurrentSchema()
        let habit = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Habit>()).first)
        habit.completions.append(HabitCompletion(date: day(31)))
        try ctx.save()
        let again = try openWithCurrentSchema()
        XCTAssertEqual(try again.fetch(FetchDescriptor<Habit>()).first?.completions.count, 31)
    }
}
