import Foundation
import SwiftData

/// Point d'accès unique au ModelContainer, partagé entre l'app et les App Intents.
/// L'app enregistre son container au lancement ; si un intent Siri s'exécute
/// avant (app fermée), un container est créé sur le même store.
enum LocalStore {

    static let schema = Schema([
        // Santé
        DreamEntry.self, FoodEntry.self, FastingSession.self, WaterEntry.self,
        Supplement.self, PantryItem.self, ShoppingItem.self, WorkoutSet.self, StepEntry.self,
        // Vie
        ProgressPhoto.self, WardrobeItem.self, MoodEntry.self, TodoItem.self,
        Habit.self, HabitCompletion.self, Note.self, MemoryEntry.self,
        Account.self, Txn.self, Envelope.self, Subscription.self, SavingsGoal.self, SplitExpense.self,
        // Patrimoine & reste
        Holding.self, NetWorthItem.self, Property.self, JobApplication.self, SkillGap.self,
        Flashcard.self, BookSummary.self, Chore.self, Pet.self, PetCare.self, Maintenance.self,
        Vehicle.self, FuelLog.self, Contact.self, SocialEvent.self, DocVault.self, Deadline.self,
        Trip.self, PackingItem.self,
        // Cycle
        CycleEntry.self,
        // Assistant IA
        AIMessage.self,
        // Santé médicale
        Medication.self, MedicalAppointment.self, VitalRecord.self, Vaccination.self,
        // Rappels perso (centre de notifications) + programme de sport
        CustomReminder.self, GymDay.self
    ])

    @MainActor private static var current: ModelContainer?

    @MainActor
    static func adopt(_ container: ModelContainer) {
        current = container
    }

    @MainActor
    static func container() throws -> ModelContainer {
        if let current { return current }
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let c = try ModelContainer(for: schema, configurations: [config])
        current = c
        return c
    }
}
