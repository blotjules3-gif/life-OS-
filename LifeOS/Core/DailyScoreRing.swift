import SwiftUI
import SwiftData

// Anneau unique « Score du jour » sur l'accueil : mélange TOUS les objectifs du jour
// (calories, protéines, eau, activité/sport, habitudes, tâches). Le score central = moyenne
// des objectifs pertinents ; la roue se remplit à mesure qu'on accomplit les choses.
struct DailyScoreRing: View {
    @Environment(\.modelContext) private var ctx

    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 0
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("stepGoal") private var stepGoal = 10000

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Query private var steps: [StepEntry]
    @Query private var todos: [TodoItem]
    @Query private var workouts: [WorkoutSet]

    private struct Metric: Identifiable {
        let id = UUID(); let label: String; let icon: String
        let value: String; let fraction: Double; let color: Color
    }

    private var isToday: (Date) -> Bool { Calendar.current.isDateInToday }

    private var metrics: [Metric] {
        var out: [Metric] = []

        // Calories
        let kcal = foods.filter { isToday($0.date) }.reduce(0) { $0 + $1.calories }
        if kcalGoal > 0 {
            out.append(.init(label: "Calories", icon: "flame.fill", value: "\(kcal)/\(kcalGoal)",
                             fraction: min(1, Double(kcal) / Double(kcalGoal)), color: Color(hex: 0xF1746C)))
        }
        // Protéines (si objectif défini)
        if proteinGoal > 0 {
            let prot = foods.filter { isToday($0.date) }.reduce(0.0) { $0 + $1.protein }
            out.append(.init(label: "Protéines", icon: "fork.knife", value: "\(Int(prot))/\(proteinGoal) g",
                             fraction: min(1, prot / Double(proteinGoal)), color: Color(hex: 0xE0A23C)))
        }
        // Eau
        let water = waters.filter { isToday($0.date) }.reduce(0) { $0 + $1.amountML }
        out.append(.init(label: "Eau", icon: "drop.fill", value: "\(water)/\(waterGoal) ml",
                         fraction: min(1, Double(water) / Double(max(1, waterGoal))), color: Color(hex: 0x3CB2E0)))
        // Activité (pas + séance du jour compte comme bonus)
        let stepCount = steps.filter { isToday($0.day) }.reduce(0) { $0 + $1.steps }
        let didWorkout = workouts.contains { isToday($0.date) }
        let actFrac = max(min(1, Double(stepCount) / Double(max(1, stepGoal))), didWorkout ? 1 : 0)
        out.append(.init(label: "Activité", icon: "figure.walk",
                         value: didWorkout ? "Séance ✓" : "\(stepCount)/\(stepGoal) pas",
                         fraction: actFrac, color: Color(hex: 0x4CD07A)))
        // Habitudes
        if !habits.isEmpty {
            let done = habits.filter { h in h.completions.contains { isToday($0.date) } }.count
            out.append(.init(label: "Habitudes", icon: "checkmark.seal.fill", value: "\(done)/\(habits.count)",
                             fraction: Double(done) / Double(habits.count), color: Color(hex: 0x9B6CF1)))
        }
        // Tâches du jour (échéance aujourd'hui)
        let dueToday = todos.filter { if let d = $0.due { return isToday(d) } else { return false } }
        if !dueToday.isEmpty {
            let done = dueToday.filter { $0.done }.count
            out.append(.init(label: "Tâches", icon: "checklist", value: "\(done)/\(dueToday.count)",
                             fraction: Double(done) / Double(dueToday.count), color: Color(hex: 0x5B8DEF)))
        }
        return out
    }

    private var score: Int {
        let m = metrics
        guard !m.isEmpty else { return 0 }
        return Int((m.reduce(0) { $0 + $1.fraction } / Double(m.count) * 100).rounded())
    }

    var body: some View {
        let m = metrics
        let frac = Double(score) / 100
        VStack(alignment: .leading, spacing: 14) {
            Text("Objectifs du jour")
                .font(.system(size: 20, weight: .black)).textCase(.uppercase).kerning(-0.3)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.10), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: max(0.001, frac))
                        .stroke(Theme.volt, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: frac)
                    VStack(spacing: 0) {
                        Text("\(score)").font(.system(size: 34, weight: .black)).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("%").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(m) { metric in legendRow(metric) }
                    if m.isEmpty {
                        Text("Renseigne tes objectifs pour voir ton score.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: 16, elevated: true)
    }

    private func legendRow(_ m: Metric) -> some View {
        HStack(spacing: 8) {
            Image(systemName: m.icon).font(.system(size: 11, weight: .bold))
                .foregroundStyle(m.color).frame(width: 16)
            Text(m.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            Text(m.value).font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(m.fraction >= 1 ? Theme.volt : Theme.textSecondary)
            if m.fraction >= 1 {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.volt)
            }
        }
    }
}
