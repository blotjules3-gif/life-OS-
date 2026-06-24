import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {
    /// Conteneur SwiftData : toutes les entités de l'app y sont déclarées.
    let container: ModelContainer = {
        let schema = Schema([
            // Santé
            DreamEntry.self, FoodEntry.self, FastingSession.self, WaterEntry.self,
            Supplement.self, PantryItem.self, ShoppingItem.self, WorkoutSet.self, StepEntry.self,
            // Vie
            ProgressPhoto.self, WardrobeItem.self, MoodEntry.self, TodoItem.self,
            Habit.self, HabitCompletion.self, Note.self,
            Account.self, Txn.self, Envelope.self, Subscription.self, SavingsGoal.self, SplitExpense.self,
            // Patrimoine & reste
            Holding.self, NetWorthItem.self, Property.self, JobApplication.self, SkillGap.self,
            Flashcard.self, BookSummary.self, Chore.self, Pet.self, PetCare.self, Maintenance.self,
            Vehicle.self, FuelLog.self, Contact.self, SocialEvent.self, DocVault.self, Deadline.self,
            Trip.self, PackingItem.self
        ])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)])
        } catch {
            // Si la migration échoue (schéma modifié en dev), on repart sur une base en mémoire.
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .tint(Theme.accent)
                .task {
                    _ = await NotificationManager.shared.requestAuthorization()
                }
        }
        .modelContainer(container)
    }
}
