import Foundation
import SwiftData

/// Tools cross-domaines (Loop 9) — donnent au coach l'accès aux données
/// jusqu'ici invisibles (nutrition FoodEntry, habitudes complétées, todos,
/// événements calendrier). Sans ça, le coach répondait "j'ai bien mangé ?"
/// avec du générique — maintenant il lit les vraies données.

// MARK: - GetTodayNutritionTool

/// Retourne le récap nutrition du jour : calories + macros + repas.
struct GetTodayNutritionTool: AITool {
    struct Arguments: Codable, Sendable {}
    struct Result: Codable, Sendable {
        let totalKcal: Int
        let totalProtein: Double
        let totalCarbs: Double
        let totalFat: Double
        let mealCount: Int
        let lastMealName: String?
        let lastMealTime: Date?
    }

    static let definition = AIToolDefinition(
        name: "get_today_nutrition",
        description: "Retourne les calories/protéines/glucides/lipides consommés aujourd'hui + dernier repas.",
        parametersSchema: #"{"type":"object","properties":{},"required":[]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.profileRead]

    func execute(_ args: Arguments) async throws -> Result {
        let entries = await MainActor.run { fetchTodayFoodEntries() }
        let totalKcal = entries.reduce(0) { $0 + $1.calories }
        let totalProtein = entries.reduce(0.0) { $0 + $1.protein }
        let totalCarbs = entries.reduce(0.0) { $0 + $1.carbs }
        let totalFat = entries.reduce(0.0) { $0 + $1.fat }
        let last = entries.max(by: { $0.date < $1.date })
        return Result(
            totalKcal: totalKcal,
            totalProtein: totalProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            mealCount: entries.count,
            lastMealName: last?.name,
            lastMealTime: last?.date
        )
    }

    @MainActor
    private func fetchTodayFoodEntries() -> [FoodEntry] {
        guard let ctx = SharedModelContextProvider.shared.context else {
            AppLog.coach.warning("GetTodayNutritionTool: no ModelContext, skipping fetch")
            return []
        }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? .now
        // Loop 12 fix M9 — borne supérieure pour ignorer les entrées futures (saisie manuelle erronée)
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < startOfTomorrow },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }
}

// MARK: - GetHabitCompletionsTool

/// Compte les habitudes complétées aujourd'hui + streak par habitude.
struct GetHabitCompletionsTool: AITool {
    struct Arguments: Codable, Sendable {}
    struct Result: Codable, Sendable {
        let habits: [HabitStatus]
        let totalCompletedToday: Int
        let totalActiveHabits: Int

        struct HabitStatus: Codable, Sendable {
            let name: String
            let completedToday: Bool
            let currentStreak: Int
        }
    }

    static let definition = AIToolDefinition(
        name: "get_habit_completions",
        description: "Retourne les habitudes actives + celles complétées aujourd'hui + streak courant.",
        parametersSchema: #"{"type":"object","properties":{},"required":[]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.habitsRead]

    func execute(_ args: Arguments) async throws -> Result {
        let (habits, todayCount) = await MainActor.run { fetchHabits() }
        return Result(
            habits: habits,
            totalCompletedToday: todayCount,
            totalActiveHabits: habits.count
        )
    }

    @MainActor
    private func fetchHabits() -> ([Result.HabitStatus], Int) {
        guard let ctx = SharedModelContextProvider.shared.context else {
            AppLog.coach.warning("GetHabitCompletionsTool: no ModelContext, skipping fetch")
            return ([], 0)
        }
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isArchived == false && $0.isPending == false }
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        let startOfDay = Calendar.current.startOfDay(for: .now)
        var todayCount = 0
        let statuses = all.map { habit -> Result.HabitStatus in
            let completedToday = habit.completions.contains { $0.date >= startOfDay }
            if completedToday { todayCount += 1 }
            return Result.HabitStatus(
                name: habit.name,
                completedToday: completedToday,
                currentStreak: computeStreak(completions: habit.completions)
            )
        }
        return (statuses, todayCount)
    }

    /// Streak courant : compte le nombre de jours consécutifs se terminant
    /// aujourd'hui ou hier avec au moins 1 complétion.
    private func computeStreak(completions: [HabitCompletion]) -> Int {
        let cal = Calendar.current
        let days = Set(completions.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: .now)
        // Autorise le start hier si pas encore fait aujourd'hui
        if !days.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }
}

// MARK: - GetTodayTodosTool

/// Retourne les todos : pending du jour + total pending + total done.
///
/// Note Loop 12 fix B2 : le model `TodoItem` n'a pas de champ `completedAt`
/// (juste `done: Bool`), donc impossible de savoir quand une tâche a été
/// complétée. On expose `totalDone` (compte cumulé de tâches faites) au lieu
/// d'un `doneToday` mensonger. Meilleure approche : ajouter `completedAt`
/// dans Models_Life.swift + migration — hors scope Loop 12.
struct GetTodayTodosTool: AITool {
    struct Arguments: Codable, Sendable {}
    struct Result: Codable, Sendable {
        let pending: [TodoBrief]
        let dueTodayCount: Int    // pending avec due date = aujourd'hui
        let totalPending: Int
        let totalDone: Int

        struct TodoBrief: Codable, Sendable {
            let title: String
            let due: Date?
            let priority: Int
            let dueToday: Bool
        }
    }

    static let definition = AIToolDefinition(
        name: "get_today_todos",
        description: "Retourne les tâches en cours + celles à faire aujourd'hui + totaux.",
        parametersSchema: #"{"type":"object","properties":{},"required":[]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.todosWrite]

    func execute(_ args: Arguments) async throws -> Result {
        let data = await MainActor.run { fetchTodos() }
        return data
    }

    @MainActor
    private func fetchTodos() -> Result {
        guard let ctx = SharedModelContextProvider.shared.context else {
            AppLog.coach.warning("GetTodayTodosTool: no ModelContext, skipping fetch")
            return Result(pending: [], dueTodayCount: 0, totalPending: 0, totalDone: 0)
        }
        let descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.due), SortDescriptor(\.priority, order: .reverse)]
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? .now
        let pending = all.filter { !$0.done }
        let dueTodayCount = pending.filter {
            guard let d = $0.due else { return false }
            return d >= startOfDay && d < startOfTomorrow
        }.count
        let briefs = pending.prefix(10).map { t in
            Result.TodoBrief(
                title: t.title,
                due: t.due,
                priority: t.priority,
                dueToday: (t.due.map { $0 >= startOfDay && $0 < startOfTomorrow }) ?? false
            )
        }
        return Result(
            pending: Array(briefs),
            dueTodayCount: dueTodayCount,
            totalPending: pending.count,
            totalDone: all.count - pending.count
        )
    }
}
