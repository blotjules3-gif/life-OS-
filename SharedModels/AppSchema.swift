import Foundation
import SwiftData

/// La liste de TOUS les modeles, en un seul endroit, lue par l'iPhone et par
/// l'Apple Watch.
///
/// Les deux appareils partagent la meme base iCloud. Si leurs listes
/// divergeaient, un appareil ignorerait en silence les donnees de l'autre.
/// D'ou une seule liste, dans le dossier que les deux cibles compilent.
enum AppSchema {
    static let schema = Schema([
        // Santé
        DreamEntry.self, SleepNight.self, FoodEntry.self, FastingSession.self, WaterEntry.self,
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
        // Messages du coach on-device
        AIMessage.self,
        // Santé médicale
        Medication.self, MedicalAppointment.self, VitalRecord.self, Vaccination.self,
        // Rappels perso (centre de notifications) + programme de sport
        CustomReminder.self, GymDay.self,
        // Intelligent Profile Engine — Bloc A
        ProfileField.self, ProfileFieldRevision.self,
        // Objectifs unifiés (Loop 24 Goal-Plan-Partner)
        UserGoal.self
    ])
}
