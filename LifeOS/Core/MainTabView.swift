import SwiftUI
import SwiftData
import Charts

// MARK: - Onglets

enum AppTab: String, CaseIterable, Identifiable {
    case home, categories, chat, camera, profile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Accueil"
        case .categories: return "Catégories"
        case .chat: return "Chat"
        case .camera: return "Photo"
        case .profile: return "Profil"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .categories: return "square.grid.2x2"
        case .chat: return "sparkles"
        case .camera: return "camera"
        case .profile: return "person"
        }
    }
    var iconFill: String {
        switch self {
        case .home: return "house.fill"
        case .categories: return "square.grid.2x2.fill"
        case .chat: return "sparkles"
        case .camera: return "camera.fill"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - Conteneur principal

struct MainTabView: View {
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 74) }
            FloatingTabBar(selected: $tab)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: ShortcutsHomeView()
        case .categories: HoneycombCategoriesView()
        case .chat: ChatView()
        case .camera: CameraView()
        case .profile: ProfileView()
        }
    }
}

// MARK: - Barre flottante

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selected = t }
                    Haptics.tap()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected == t ? t.iconFill : t.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .symbolEffect(.bounce, value: selected == t)
                        Text(t.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selected == t ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
        .padding(.horizontal, 22)
    }
}

// MARK: - Tableau de bord du jour

struct HomeDashboardContent: View {
    @Query private var waters: [WaterEntry]
    @Query private var foods: [FoodEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @Query private var moods: [MoodEntry]

    @AppStorage("stepGoal") private var stepGoal = 10000
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("fastTarget") private var fastTarget = 16

    @State private var steps = 0

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                    // Anneaux du jour
                    LazyVGrid(columns: cols, spacing: 12) {
                        MetricRing(value: Double(steps), goal: Double(stepGoal), label: "Pas", unit: "", color: Color(hex: 0xF1746C), icon: "figure.walk")
                        MetricRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", unit: "ml", color: Color(hex: 0x3CB2E0), icon: "drop.fill")
                        MetricRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Calories", unit: "kcal", color: Color(hex: 0x4CC38A), icon: "flame.fill")
                        MetricRing(value: fastHours, goal: Double(fastTarget), label: "Jeûne", unit: "h", color: Color(hex: 0x9B6CF1), icon: "timer")
                    }

                    // Objectifs du jour (barres)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Objectifs du jour").font(.headline)
                        goalBar("Pas", Double(steps), Double(stepGoal), Color(hex: 0xF1746C))
                        goalBar("Hydratation", Double(waterToday), Double(waterGoal), Color(hex: 0x3CB2E0))
                        goalBar("Calories", Double(kcalToday), Double(kcalGoal), Color(hex: 0x4CC38A))
                        if !habits.isEmpty {
                            goalBar("Habitudes", Double(habitsDoneToday), Double(habits.count), Color(hex: 0xE0A23C))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Habitudes de la semaine
                    if !habits.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Habitudes — 7 derniers jours").font(.headline)
                            Chart(weekData, id: \.0) { item in
                                BarMark(x: .value("Jour", item.0, unit: .day), y: .value("Faites", item.1))
                                    .foregroundStyle(Color.accentColor.gradient)
                                    .cornerRadius(5)
                            }
                            .frame(height: 150)
                            .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel() } }
                            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    // Humeur récente
                    if !recentMoods.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Humeur").font(.headline)
                            Chart(recentMoods) { m in
                                LineMark(x: .value("Date", m.date), y: .value("Humeur", m.score))
                                    .foregroundStyle(Color(hex: 0x9B6CF1))
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Date", m.date), y: .value("Humeur", m.score))
                                    .foregroundStyle(Color(hex: 0x9B6CF1))
                            }
                            .frame(height: 120)
                            .chartYScale(domain: 1...5)
                            .chartYAxis { AxisMarks(values: [1, 3, 5]) { _ in AxisGridLine(); AxisValueLabel() } }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
                .padding(Theme.pad)
            }
            .background(Theme.bg)
            .navigationTitle(greeting)
            .task {
                if await HealthService.shared.requestAuthorization() {
                    steps = await HealthService.shared.stepsToday()
                }
            }
    }

    // MARK: Calculs

    private var todayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var fastHours: Double {
        guard let active = fasts.first(where: { $0.isActive }) else { return 0 }
        return active.elapsed / 3600
    }
    private var habitsDoneToday: Int {
        habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
    }
    private var weekData: [(Date, Int)] {
        (0..<7).reversed().map { off in
            let day = Calendar.current.date(byAdding: .day, value: -off, to: todayStart)!
            let count = habits.reduce(0) { acc, h in acc + h.completions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.count }
            return (day, count)
        }
    }
    private var recentMoods: [MoodEntry] {
        moods.filter { $0.date > Calendar.current.date(byAdding: .day, value: -14, to: .now)! }
            .sorted { $0.date < $1.date }
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon aprèm"
        case 18..<23: return "Bonsoir"
        default: return "Bonne nuit"
        }
    }

    private func goalBar(_ label: String, _ value: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(value)) / \(Int(goal))").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, goal), total: max(1, goal)).tint(color)
        }
    }
}

struct MetricRing: View {
    let value: Double
    let goal: Double
    let label: String
    let unit: String
    let color: Color
    let icon: String
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(progress: goal > 0 ? value / goal : 0, lineWidth: 9, tint: color)
                    .frame(width: 84, height: 84)
                VStack(spacing: 1) {
                    Image(systemName: icon).font(.caption).foregroundStyle(color)
                    Text("\(Int(value))").font(.title3.bold().monospacedDigit())
                }
            }
            VStack(spacing: 0) {
                Text(label).font(.subheadline.weight(.medium))
                Text(goal > 0 ? "/ \(Int(goal)) \(unit)" : "").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}
