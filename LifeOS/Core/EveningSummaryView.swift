import SwiftUI
import SwiftData

struct EveningSummaryView: View {
    @AppStorage("stepGoal")  private var stepGoal  = 10000
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal")  private var kcalGoal  = 2200
    @AppStorage("userName")  private var userName   = ""

    @Query private var foods:  [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]
    @State private var challenges: [ChallengeOut] = []
    @State private var steps = 0
    @Environment(\.dismiss) private var dismiss

    init() {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 1, to: start) ?? start
        _foods  = Query(filter: #Predicate<FoodEntry>  { $0.date >= start && $0.date < end })
        _waters = Query(filter: #Predicate<WaterEntry> { $0.date >= start && $0.date < end })
        _moods  = Query(filter: #Predicate<MoodEntry>  { $0.date >= start && $0.date < end },
                        sort: \MoodEntry.date, order: .reverse)
    }

    private var kcalToday:  Int { foods.caloriesToday }
    private var waterToday: Int { waters.mlToday }
    private var habitsDone: Int {
        habits.filter { h in
            !h.isPending && h.completions.contains { Calendar.current.isDateInToday($0.date) }
        }.count
    }
    private var habitsTotal: Int { habits.filter { !h.isPending }.count }
    private var todayMood: MoodEntry? { moods.first }

    private var overallScore: Double {
        var total = 0.0
        var count = 0
        if stepGoal  > 0 { total += min(1, Double(steps)      / Double(stepGoal));  count += 1 }
        if waterGoal > 0 { total += min(1, Double(waterToday) / Double(waterGoal)); count += 1 }
        if kcalGoal  > 0 { total += min(1, Double(kcalToday)  / Double(kcalGoal));  count += 1 }
        if habitsTotal > 0 { total += Double(habitsDone) / Double(habitsTotal);      count += 1 }
        guard count > 0 else { return 0 }
        return total / Double(count)
    }

    private var scoreLabel: String {
        switch Int(overallScore * 100) {
        case 90...100: return "Journée exceptionnelle"
        case 75..<90:  return "Très bonne journée"
        case 50..<75:  return "Bonne journée"
        case 25..<50:  return "Journée moyenne"
        default:       return "Commence demain fort"
        }
    }
    private var scoreColor: Color {
        switch Int(overallScore * 100) {
        case 75...100: return Color(hex: 0x4CC38A)
        case 50..<75:  return Color(hex: 0xFF9F0A)
        default:       return Color(hex: 0x9B6CF1)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    scoreHeader
                    metricsGrid
                    if habitsTotal > 0 { habitsCard }
                    if todayMood != nil { moodCard }
                    activeChallengesCard
                    tomorrowPrompt
                }
                .padding(Theme.pad)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Bilan du soir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                if await HealthService.shared.requestAuthorization() {
                    steps = await HealthService.shared.cachedStepsToday()
                }
            }
        }
    }

    // MARK: Score header

    private var scoreHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 12)
                    .frame(width: 110, height: 110)
                Circle()
                    .trim(from: 0, to: overallScore)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.8, bounce: 0.3), value: overallScore)
                VStack(spacing: 2) {
                    Text("\(Int(overallScore * 100))")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(scoreColor)
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(scoreLabel)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: Date()).capitalized
    }

    // MARK: Metrics grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(
                icon: "figure.walk", color: Color(hex: 0xF1746C),
                value: steps, goal: stepGoal,
                label: "Pas", unit: ""
            )
            metricCard(
                icon: "drop.fill", color: Color(hex: 0x3CB2E0),
                value: waterToday, goal: waterGoal,
                label: "Eau", unit: "ml"
            )
            metricCard(
                icon: "flame.fill", color: Color(hex: 0x4CC38A),
                value: kcalToday, goal: kcalGoal,
                label: "Calories", unit: "kcal"
            )
            habitsMiniCard
        }
    }

    private func metricCard(icon: String, color: Color, value: Int, goal: Int, label: String, unit: String) -> some View {
        let ratio = goal > 0 ? min(1.0, Double(value) / Double(goal)) : 0
        let reached = ratio >= 1.0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                if reached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x4CC38A))
                }
            }
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .font(.system(size: 11))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12)).frame(height: 5)
                    Capsule().fill(reached ? Color(hex: 0x4CC38A) : color)
                        .frame(width: geo.size.width * ratio, height: 5)
                        .animation(.spring(duration: 0.7, bounce: 0.2), value: ratio)
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(reached ? Color(hex: 0x4CC38A).opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private var habitsMiniCard: some View {
        let ratio = habitsTotal > 0 ? Double(habitsDone) / Double(habitsTotal) : 0
        let reached = habitsDone >= habitsTotal && habitsTotal > 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppCategory.fitness.tint)
                    .frame(width: 30, height: 30)
                    .background(AppCategory.fitness.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                if reached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x4CC38A))
                }
            }
            Text("\(habitsDone)/\(habitsTotal)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Habitudes")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppCategory.fitness.tint.opacity(0.12)).frame(height: 5)
                    Capsule().fill(reached ? Color(hex: 0x4CC38A) : AppCategory.fitness.tint)
                        .frame(width: habitsTotal > 0 ? geo.size.width * ratio : 0, height: 5)
                        .animation(.spring(duration: 0.7, bounce: 0.2), value: ratio)
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(reached ? Color(hex: 0x4CC38A).opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: Habits detail card

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Habitudes du jour", systemImage: "checkmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            VStack(spacing: 0) {
                let active = habits.filter { !$0.isPending }
                ForEach(Array(active.enumerated()), id: \.element.id) { idx, habit in
                    let done = habit.completions.contains { Calendar.current.isDateInToday($0.date) }
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(done ? Color(hex: 0x4CC38A) : Color.secondary.opacity(0.35))
                        Text(habit.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(done ? .secondary : .primary)
                            .strikethrough(done, color: .secondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    if idx < active.count - 1 { Divider() }
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Mood card

    private var moodCard: some View {
        HStack(spacing: 14) {
            Text(todayMood?.emoji ?? "")
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 4) {
                Text("Humeur du jour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(todayMood?.label ?? "")
                    .font(.system(size: 15, weight: .semibold))
                if let note = todayMood?.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Active challenges card

    private var activeChallengesCard: some View {
        let active = challenges.filter { $0.isActive }
        guard !active.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Label("Défis en cours", systemImage: "flag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                ForEach(active.prefix(3)) { ch in
                    HStack(spacing: 12) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppCategory.productivity.tint)
                            .frame(width: 30, height: 30)
                            .background(AppCategory.productivity.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            Text("\(ch.daysElapsed) jour\(ch.daysElapsed > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        )
    }

    // MARK: Tomorrow prompt

    private var tomorrowPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppCategory.sleep.tint)
            Text("Bonne nuit")
                .font(.system(size: 16, weight: .semibold))
            Text("Repose-toi bien. Demain, une nouvelle journée commence.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppCategory.sleep.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(AppCategory.sleep.tint.opacity(0.2), lineWidth: 1)
        )
    }
}
