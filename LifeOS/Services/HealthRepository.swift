import SwiftUI
import SwiftData

// Couche d'accès aux données santé.
// Les vues injectent un ModelContext mais passent par ce service
// pour les opérations communes — évite les @Query dupliqués et
// centralise les mutations SwiftData.

@MainActor
final class HealthRepository: ObservableObject {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Food

    func addFood(_ entry: FoodEntry) {
        context.insert(entry)
        save("addFood")
    }

    func deleteFood(_ entry: FoodEntry) {
        context.delete(entry)
        save("deleteFood")
    }

    func foodEntries(for date: Date) throws -> [FoodEntry] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor)
    }

    func caloriesToday() throws -> Int {
        try foodEntries(for: .now).reduce(0) { $0 + $1.calories }
    }

    // MARK: - Water

    func addWater(_ entry: WaterEntry) {
        context.insert(entry)
        save("addWater")
    }

    func waterEntriesForToday() throws -> [WaterEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return try context.fetch(descriptor)
    }

    func mlToday() throws -> Int {
        try waterEntriesForToday().reduce(0) { $0 + $1.amountML }
    }

    // MARK: - Habits

    func toggleHabit(_ habit: Habit) {
        if let completion = habit.completions.first(where: { Calendar.current.isDateInToday($0.date) }) {
            context.delete(completion)
        } else {
            habit.completions.append(HabitCompletion(date: .now))
        }
        save("toggleHabit")
    }

    func habitsDoneToday(from habits: [Habit]) -> Int {
        habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
    }

    // MARK: - Mood

    func logMood(score: Int, existing: MoodEntry?) {
        if let existing { existing.score = score }
        else { context.insert(MoodEntry(score: score)) }
        save("logMood")
    }

    // MARK: - Privé

    private func save(_ operation: String) {
        do { try context.save() } catch { print("[HealthRepository] \(operation) save failed: \(error)") }
    }
}
