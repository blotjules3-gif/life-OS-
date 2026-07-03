import SwiftUI
import SwiftData

// MARK: - Routage « ajout rapide » vers le VRAI outil du pôle
// Chaque mention d'objectif (calories, protéines, eau…) ouvre l'outil dédié
// où l'on ajoute/ajuste vraiment cette donnée — pas un formulaire générique.

enum QuickTool: String, Identifiable {
    case calories, water, workout, habits, tasks, mood, sleep
    var id: String { rawValue }

    /// Depuis un libellé de métrique du score.
    static func from(metric label: String) -> QuickTool? {
        switch label {
        case "Calories", "Protéines": return .calories
        case "Eau":       return .water
        case "Activité":  return .workout
        case "Habitudes": return .habits
        case "Tâches":    return .tasks
        case "Humeur":    return .mood
        case "Sommeil":   return .sleep
        default:          return nil
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .calories: CalAIView()
        case .water:    HydrationView()
        case .workout:  StrengthView()
        case .habits:   HabitTrackerView()
        case .tasks:    TodoView()
        case .mood:     MoodJournalView()
        case .sleep:    SleepDashboardView()
        }
    }
}

// MARK: - Métrique d'un objectif du jour

struct DayMetric: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let value: String
    let fraction: Double   // 0…1
    let color: Color
}

// MARK: - Moteur : calcule les objectifs d'un jour donné (aujourd'hui OU passé)

enum DailyScoreEngine {
    static func metrics(for day: Date,
                        foods: [FoodEntry], waters: [WaterEntry], habits: [Habit],
                        steps: [StepEntry], todos: [TodoItem], workouts: [WorkoutSet],
                        moods: [MoodEntry], dreams: [DreamEntry], nights: [SleepNight] = [],
                        kcalGoal: Int, proteinGoal: Int, waterGoal: Int, stepGoal: Int,
                        sleepGoalHours: Double = 8) -> [DayMetric] {
        let cal = Calendar.current
        func here(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: day) }
        if cal.startOfDay(for: day) > cal.startOfDay(for: .now) { return [] }  // futur

        var out: [DayMetric] = []
        let dayFoods = foods.filter { here($0.date) }

        if kcalGoal > 0 {
            let k = dayFoods.reduce(0) { $0 + $1.calories }
            out.append(.init(label: "Calories", icon: "flame.fill", value: "\(k)/\(kcalGoal)",
                             fraction: min(1, Double(k) / Double(kcalGoal)), color: Color(hex: 0xF1746C)))
        }
        if proteinGoal > 0 {
            let p = dayFoods.reduce(0.0) { $0 + $1.protein }
            out.append(.init(label: "Protéines", icon: "fork.knife", value: "\(Int(p))/\(proteinGoal) g",
                             fraction: min(1, p / Double(proteinGoal)), color: Color(hex: 0xE0A23C)))
        }
        if waterGoal > 0 {
            let w = waters.filter { here($0.date) }.reduce(0) { $0 + $1.amountML }
            out.append(.init(label: "Eau", icon: "drop.fill", value: "\(w)/\(waterGoal) ml",
                             fraction: min(1, Double(w) / Double(waterGoal)), color: Color(hex: 0x3CB2E0)))
        }
        let sc = steps.filter { here($0.day) }.reduce(0) { $0 + $1.steps }
        let didW = workouts.contains { here($0.date) }
        let af = max(min(1, Double(sc) / Double(max(1, stepGoal))), didW ? 1 : 0)
        out.append(.init(label: "Activité", icon: "figure.walk",
                         value: didW ? "Séance ✓" : "\(sc)/\(stepGoal) pas", fraction: af, color: Color(hex: 0x4CD07A)))

        if !habits.isEmpty {
            let d = habits.filter { h in h.completions.contains { here($0.date) } }.count
            out.append(.init(label: "Habitudes", icon: "checkmark.seal.fill", value: "\(d)/\(habits.count)",
                             fraction: Double(d) / Double(habits.count), color: Color(hex: 0x9B6CF1)))
        }
        let due = todos.filter { if let dd = $0.due { return here(dd) } else { return false } }
        if !due.isEmpty {
            let d = due.filter { $0.done }.count
            out.append(.init(label: "Tâches", icon: "checklist", value: "\(d)/\(due.count)",
                             fraction: Double(d) / Double(due.count), color: Color(hex: 0x5B8DEF)))
        }
        if let m = moods.first(where: { here($0.date) }) {
            out.append(.init(label: "Humeur", icon: "face.smiling", value: "\(m.score)/5",
                             fraction: Double(m.score) / 5, color: Color(hex: 0xEC6FB0)))
        }
        if let n = nights.first(where: { here($0.date) }) {
            let m = Int((n.hours * 60).rounded())
            out.append(.init(label: "Sommeil", icon: "moon.zzz.fill", value: "\(m / 60)h\(m % 60 == 0 ? "" : String(format: "%02d", m % 60))",
                             fraction: min(1, n.hours / max(1, sleepGoalHours)), color: Color(hex: 0x7C93C8)))
        } else if let s = dreams.first(where: { here($0.date) }) {
            out.append(.init(label: "Sommeil", icon: "moon.zzz.fill", value: "\(s.mood)/5",
                             fraction: Double(s.mood) / 5, color: Color(hex: 0x7C93C8)))
        }
        return out
    }

    static func score(_ m: [DayMetric]) -> Int {
        guard !m.isEmpty else { return 0 }
        return Int((m.reduce(0) { $0 + $1.fraction } / Double(m.count) * 100).rounded())
    }
}

// MARK: - Hero : orbe central + bande de la semaine

struct DailyScoreRing: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 0
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("stepGoal") private var stepGoal = 10000
    @AppStorage("sleepGoalHours") private var sleepGoalHours = 8.0

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Query private var steps: [StepEntry]
    @Query private var todos: [TodoItem]
    @Query private var workouts: [WorkoutSet]
    @Query private var moods: [MoodEntry]
    @Query private var dreams: [DreamEntry]
    @Query private var nights: [SleepNight]

    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var showDetail = false

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let wd = cal.component(.weekday, from: today)      // 1=dim … 7=sam
        let fromMonday = (wd + 5) % 7
        let monday = cal.date(byAdding: .day, value: -fromMonday, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private func metrics(_ day: Date) -> [DayMetric] {
        DailyScoreEngine.metrics(for: day, foods: foods, waters: waters, habits: habits,
                                 steps: steps, todos: todos, workouts: workouts, moods: moods, dreams: dreams, nights: nights,
                                 kcalGoal: kcalGoal, proteinGoal: proteinGoal, waterGoal: waterGoal, stepGoal: stepGoal,
                                 sleepGoalHours: sleepGoalHours)
    }
    private func score(_ day: Date) -> Int { DailyScoreEngine.score(metrics(day)) }

    private func hasData(_ day: Date) -> Bool {
        let cal = Calendar.current
        func here(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: day) }
        return foods.contains { here($0.date) } || waters.contains { here($0.date) }
            || workouts.contains { here($0.date) } || moods.contains { here($0.date) }
            || dreams.contains { here($0.date) } || nights.contains { here($0.date) }
            || habits.contains { h in h.completions.contains { here($0.date) } }
            || todos.contains { if let d = $0.due { return here(d) && $0.done } else { return false } }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selected) }

    var body: some View {
        VStack(spacing: 18) {
            orb
            weekStrip
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .sheet(isPresented: $showDetail) {
            DailyScoreDetailSheet(date: selected, metrics: metrics(selected), score: score(selected))
                .presentationDetents([.medium, .large])
        }
    }

    // Orbe central tappable — anneau iridescent « bulle de savon » (bleu→magenta→or)
    private var iridescent: AngularGradient {
        AngularGradient(
            colors: [Color(hex: 0x3B6FF5), Color(hex: 0x9B6BF0), Color(hex: 0xEC5B9E),
                     Color(hex: 0xF0A65A), Color(hex: 0x6FD0F5), Color(hex: 0x3B6FF5)],
            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    private var orb: some View {
        let s = score(selected)
        let frac = Double(s) / 100
        let f = max(0.0001, frac)
        let done = metrics(selected).filter { $0.fraction >= 1 }.count
        let total = metrics(selected).count
        return Button { Haptics.tap(); showDetail = true } label: {
            ZStack {
                // halo ambiant diffus irisé (la lueur qui déborde)
                Circle().fill(iridescent)
                    .frame(width: 300, height: 300).blur(radius: 42)
                    .opacity(0.28 + 0.4 * frac)
                    .animation(.easeOut(duration: 0.9), value: frac)
                // piste faible (repère du cercle complet)
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 2)
                    .frame(width: 212, height: 212)
                // AURA irisée : couches floutées empilées → verre soufflé lumineux
                Group {
                    Circle().trim(from: 0, to: f)
                        .stroke(iridescent, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                        .blur(radius: 20).opacity(0.6)
                    Circle().trim(from: 0, to: f)
                        .stroke(iridescent, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .blur(radius: 7).opacity(0.95)
                    Circle().trim(from: 0, to: f)
                        .stroke(iridescent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .blur(radius: 2)
                    // reflet glossy (bord brillant façon bulle)
                    Circle().trim(from: 0, to: f)
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .blur(radius: 0.5)
                }
                .rotationEffect(.degrees(-90))
                .frame(width: 212, height: 212)
                .animation(.spring(response: 0.9, dampingFraction: 0.85), value: frac)
                // disque central en verre
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
                // centre
                VStack(spacing: 1) {
                    Text(isToday ? "SCORE" : shortDate(selected).uppercased())
                        .font(.system(size: 11, weight: .semibold)).kerning(1.8)
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(s)")
                        .font(.system(size: 60, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(total == 0 ? "%" : "\(done)/\(total) objectifs")
                        .font(.system(size: 11, weight: .medium)).kerning(0.3)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 244, height: 244)
        }
        .buttonStyle(PressableButtonStyle())
    }

    // Bande des 7 jours de la semaine
    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                dayBubble(day, letter: dayLetters[idx])
            }
        }
        .padding(.horizontal, 4)
    }

    private func dayBubble(_ day: Date, letter: String) -> some View {
        let cal = Calendar.current
        let future = cal.startOfDay(for: day) > cal.startOfDay(for: .now)
        let isSel = cal.isDate(day, inSameDayAs: selected)
        let today = cal.isDateInToday(day)
        let m = metrics(day)
        let sc = DailyScoreEngine.score(m)
        let showScore = !future && (today || hasData(day))   // pas de « 0 » pour les jours non suivis
        return VStack(spacing: 6) {
            Button {
                Haptics.tap(); withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = day }
            } label: {
                ZStack {
                    Circle().fill(isSel ? AnyShapeStyle(Theme.volt)
                                        : AnyShapeStyle(future ? AnyShapeStyle(Color.primary.opacity(0.05)) : Theme.cardFill))
                        .overlay(Circle().strokeBorder(today && !isSel ? Theme.volt : Theme.hairline,
                                                       lineWidth: today && !isSel ? 1.5 : 0.5))
                    if showScore {
                        Text("\(sc)").font(.system(size: 13, weight: .black)).monospacedDigit()
                            .foregroundStyle(isSel ? Theme.onVolt : Theme.textPrimary)
                    } else {
                        Image(systemName: "circle.dashed").font(.system(size: 12)).foregroundStyle(Theme.textSecondary.opacity(0.5))
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            Text(letter).font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSel ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    private func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

// MARK: - Détail (au tap sur l'orbe) : tous les objectifs du jour

struct DailyScoreDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let metrics: [DayMetric]
    let score: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("\(score)%")
                        .font(.system(size: 54, weight: .black)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8)
                    if metrics.isEmpty {
                        Text("Aucun objectif pour ce jour.").font(.subheadline).foregroundStyle(.secondary).padding(.top, 40)
                    } else {
                        Text("Touche un objectif pour l'ouvrir")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                    ForEach(metrics) { m in
                        if let t = QuickTool.from(metric: m.label) {
                            NavigationLink { t.destination } label: { metricRow(m, tappable: true) }
                                .buttonStyle(.plain)
                        } else {
                            metricRow(m, tappable: false)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.screenBG)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func metricRow(_ m: DayMetric, tappable: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: m.icon).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(m.color).frame(width: 22)
                Text(m.label).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(m.value).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(m.fraction >= 1 ? Theme.volt : Theme.textSecondary)
                if m.fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.volt).font(.system(size: 14))
                }
                if tappable {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                    Capsule().fill(m.fraction >= 1 ? Theme.volt : m.color)
                        .frame(width: max(8, geo.size.width * m.fraction), height: 8)
                }
            }
            .frame(height: 8)
        }
        .card(padding: 14)
    }
}
