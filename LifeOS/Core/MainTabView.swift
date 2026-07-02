import SwiftUI
import SwiftData
import Charts
import WidgetKit

// MARK: - Onglets

enum AppTab: String, CaseIterable, Identifiable {
    case wakeup, home, categories, profile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wakeup:     return "Réveil"
        case .home:       return "Accueil"
        case .categories: return "Catégories"
        case .profile:    return "Profil"
        }
    }
    var icon: String {
        switch self {
        case .wakeup:     return "alarm"
        case .home:       return "house"
        case .categories: return "square.grid.2x2"
        case .profile:    return "person.crop.circle"
        }
    }
    var iconFill: String {
        switch self {
        case .wakeup:     return "alarm.fill"
        case .home:       return "house.fill"
        case .categories: return "square.grid.2x2.fill"
        case .profile:    return "person.crop.circle.fill"
        }
    }
}

// MARK: - Conteneur principal

struct MainTabView: View {
    @State private var tab: AppTab = .home
    @State private var catPath: [AppCategory] = []
    @State private var showAIAssistant = false

    @AppStorage("appTheme") private var appThemeRaw = "classic"
    private var theme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 104) }
            FloatingTabBar(
                selected: $tab,
                onOpenAssistant: openAIAssistant
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(isPresented: $showAIAssistant) {
            AIAssistantView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenAIChat)) { _ in
            openAIAssistant()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenModule)) { notif in
            if let module = notif.userInfo?["module"] as? String,
               let cat = AppCategory(rawValue: module) {
                let isAIOpen = showAIAssistant
                showAIAssistant = false
                // Attendre la fin de l'animation de dismiss du fullScreenCover
                // avant de modifier la navigation, sinon conflit d'état UIKit/SwiftUI.
                let delay: TimeInterval = isAIOpen ? 0.35 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    tab = .categories
                    catPath = [cat]
                }
            }
        }
    }

    private func openAIAssistant() {
        // L'historique du chat est local : on ouvre toujours, l'état offline
        // est géré à l'intérieur de la vue (bandeau), pas en barrage à l'entrée.
        showAIAssistant = true
    }

    @ViewBuilder private var content: some View {
        ZStack {
            HabitWidgetSyncer()
            ThemedBubbleBackground(theme: theme)
                .ignoresSafeArea()
            ShortcutsHomeView()
                .opacity(tab == .home ? 1 : 0)
                .allowsHitTesting(tab == .home)
            WakeUpView()
                .opacity(tab == .wakeup ? 1 : 0)
                .allowsHitTesting(tab == .wakeup)
            NavigationStack(path: $catPath) {
                BubbleCategoriesView(onSelect: { title in
                    if let cat = AppCategory(bubbleTitle: title) { catPath.append(cat) }
                })
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppCategory.self) { $0.destination }
            }
            .opacity(tab == .categories ? 1 : 0)
            .allowsHitTesting(tab == .categories)
            ProfileView()
                .opacity(tab == .profile ? 1 : 0)
                .allowsHitTesting(tab == .profile)
        }
    }
}

// MARK: - Syncer invisible habitudes → widget

private struct HabitWidgetSyncer: View {
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]
    @Query(sort: \HabitCompletion.date) private var completions: [HabitCompletion]

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { sync() }
            .task {
                // Deuxième sync après un court délai pour garantir que SwiftData est chargé
                try? await Task.sleep(for: .milliseconds(300))
                sync()
            }
            .onChange(of: allHabits.count) { _, _ in sync() }
            .onChange(of: completions.count) { _, _ in sync() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in sync() }
    }

    private func sync() {
        guard !allHabits.isEmpty || completions.isEmpty else { return }
        let today = Date()
        // Toutes les habitudes (pending ou non) — l'utilisateur les voit toutes dans le widget
        let entries: [[String: Any]] = allHabits.map { h in
            let done = h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
            return ["name": h.name, "icon": h.icon, "colorHex": h.colorHex, "done": done]
        }
        guard let defaults = UserDefaults(suiteName: "group.lifeos.app") else { return }
        defaults.set(try? JSONSerialization.data(withJSONObject: entries), forKey: "widget_habits")
        defaults.set(Date(), forKey: "widget_habits_sync_date")
        defaults.set(entries.filter { $0["done"] as? Bool == true }.count, forKey: "habits_done_today")
        defaults.set(entries.count, forKey: "habits_total_today")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Barre flottante : [2 onglets] [assistant] [2 onglets]

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var onOpenAssistant: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var serverStatus = ServerStatusMonitor.shared
    @State private var showServerConfig = false
    @Namespace private var ns

    private static let barBg   = Color(uiColor: .secondarySystemBackground)
    private static let selBg   = Color(uiColor: .systemGray5)
    private static let fieldBg = Color(uiColor: .tertiarySystemFill)
    private static let barInset: CGFloat = 10

    private let leftTabs:  [AppTab] = [.home, .wakeup]
    private let rightTabs: [AppTab] = [.categories, .profile]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(leftTabs) { t in tabBtn(t) }
            }

            ZStack(alignment: .topLeading) {
                Button {
                    Haptics.tap()
                    serverStatus.pingNow()
                    onOpenAssistant()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Pose une question…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(uiColor: .placeholderText))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Self.fieldBg, in: Capsule())
                }
                .buttonStyle(.plain)

                if serverStatus.isOnline != nil {
                    Button {
                        Haptics.tap()
                        #if DEBUG
                        showServerConfig = true
                        #else
                        serverStatus.pingNow()
                        #endif
                    } label: {
                        ZStack {
                            Color.clear.frame(width: 22, height: 22)
                            Circle()
                                .fill(serverStatus.dotColor)
                                .frame(width: 6, height: 6)
                                .overlay(Circle().stroke(Self.fieldBg, lineWidth: 1.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: 20, y: 0)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(serverStatus.isOnline == false)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: serverStatus.isOnline)
            #if DEBUG
            .sheet(isPresented: $showServerConfig) {
                ServerConfigView {
                    showServerConfig = false
                    serverStatus.pingNow()
                }
            }
            #endif

            HStack(spacing: 0) {
                ForEach(rightTabs) { t in tabBtn(t) }
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 10)
        // iOS 26 : coins concentriques avec le coin de l'écran (style Safari)
        .background(Self.barBg, in: ConcentricRectangle(corners: .concentric, isUniform: true))
        .overlay(ConcentricRectangle(corners: .concentric, isUniform: true)
            .stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 6)
        .padding(.horizontal, Self.barInset)
        .padding(.bottom, Self.barInset)
    }

    private func tabBtn(_ t: AppTab) -> some View {
        Button {
            let anim: Animation? = reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.35)
            withAnimation(anim) { selected = t }
            if t == .profile { Haptics.medium() } else { Haptics.tap() }
        } label: {
            ZStack {
                if selected == t {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Self.selBg)
                        .frame(width: 54, height: 42)
                        .matchedGeometryEffect(id: "sel", in: ns)
                }
                Image(systemName: selected == t ? t.iconFill : t.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected == t ? Color.primary : Color(uiColor: .systemGray))
                    .animation(reduceMotion ? nil : .spring(duration: 0.28), value: selected)
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
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
    @State private var weekWorkouts = 0

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                    // Anneaux du jour
                    LazyVGrid(columns: cols, spacing: 12) {
                        MetricRing(value: Double(steps), goal: Double(stepGoal), label: "Pas", unit: "", color: Color(hex: 0xF1746C), icon: "figure.walk")
                        MetricRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", unit: "ml", color: Color(hex: 0x3CB2E0), icon: "drop.fill")
                        MetricRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Calories", unit: "kcal", color: Color(hex: 0x4CC38A), icon: "flame.fill")
                        TimelineView(.everyMinute) { _ in
                            MetricRing(value: fastHours, goal: Double(fastTarget), label: "Jeûne", unit: "h", color: Color(hex: 0x9B6CF1), icon: "timer")
                        }
                        if weekWorkouts > 0 {
                            MetricRing(value: Double(weekWorkouts), goal: 5, label: "Séances", unit: "/sem", color: Color(hex: 0xE0A23C), icon: "dumbbell.fill")
                        }
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
                    async let s = HealthService.shared.cachedStepsToday()
                    async let w = HealthService.shared.workoutsThisWeek()
                    steps = await s
                    weekWorkouts = await w
                }
            }
    }

    // MARK: Calculs

    private var todayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var waterToday: Int { waters.mlToday }
    private var kcalToday: Int  { foods.caloriesToday }
    private var fastHours: Double {
        guard let active = fasts.first(where: { $0.isActive }) else { return 0 }
        return active.elapsed / 3600
    }
    private var habitsDoneToday: Int {
        habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
    }
    private var weekData: [(Date, Int)] {
        (0..<7).reversed().compactMap { off -> (Date, Int)? in
            guard let day = Calendar.current.date(byAdding: .day, value: -off, to: todayStart) else { return nil }
            let count = habits.reduce(0) { acc, h in acc + h.completions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.count }
            return (day, count)
        }
    }
    private var recentMoods: [MoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? Date()
        return moods.filter { $0.date > cutoff }.sorted { $0.date < $1.date }
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon aprèm"
        case 18..<23: return "Bonsoir"
        default:      return "Bonne nuit"
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
    var delta: Int? = nil

    private var deltaLabel: String? {
        guard let d = delta, d != 0 else { return nil }
        return d > 0 ? "+\(d)" : "\(d)"
    }
    private var deltaColor: Color { (delta ?? 0) >= 0 ? Theme.success : Theme.danger }

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
            VStack(spacing: 2) {
                Text(label).font(.subheadline.weight(.medium))
                Text(goal > 0 ? "/ \(Int(goal)) \(unit)" : "").font(.caption2).foregroundStyle(.secondary)
                if let dl = deltaLabel {
                    Text(dl)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(deltaColor)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// MARK: - ConcentricRectangle (coins parallèles à l'écran — style iOS 26)

enum ConcentricCorners { case concentric }

struct ConcentricRectangle: Shape {
    var corners: ConcentricCorners = .concentric
    var isUniform: Bool = true
    // Rayon écran iPhone ≈ 44pt ; inset barre = 10pt → rayon concentric = 44 − 10 = 34pt
    private static let radius: CGFloat = 34

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous).path(in: rect)
    }
}
