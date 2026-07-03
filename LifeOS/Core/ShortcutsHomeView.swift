import SwiftUI
import SwiftData

/// Outils directs qu'on peut épingler en raccourci sur l'accueil.
enum ShortcutTool: String, CaseIterable, Identifiable {
    case dashboard, tabata, calories, scan, todo, fasting, water, habits
    case focus, mood, breathing, bedtime, budget, portfolio, flashcards, nap, progressPhotos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Tableau de bord"
        case .tabata: return "HIIT / Tabata"
        case .calories: return "Calories"
        case .scan: return "Scan produit"
        case .todo: return "To-do"
        case .fasting: return "Jeûne"
        case .water: return "Hydratation"
        case .habits: return "Habitudes"
        case .focus: return "Focus"
        case .mood: return "Humeur"
        case .breathing: return "Respiration"
        case .bedtime: return "Coucher"
        case .budget: return "Budget"
        case .portfolio: return "Portefeuille"
        case .flashcards: return "Flashcards"
        case .nap: return "Sieste"
        case .progressPhotos: return "Photos"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .tabata: return "timer"
        case .calories: return "flame.fill"
        case .scan: return "barcode.viewfinder"
        case .todo: return "checklist"
        case .fasting: return "hourglass"
        case .water: return "drop.fill"
        case .habits: return "square.grid.3x3.fill"
        case .focus: return "brain.head.profile"
        case .mood: return "face.smiling"
        case .breathing: return "wind"
        case .bedtime: return "bed.double.fill"
        case .budget: return "tray.2.fill"
        case .portfolio: return "chart.pie.fill"
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .nap: return "powersleep"
        case .progressPhotos: return "camera.fill"
        }
    }
    var tint: Color {
        switch self {
        case .dashboard: return Color(hex: 0x618EF1)
        case .tabata, .habits, .nap: return AppCategory.fitness.tint
        case .calories, .scan, .fasting, .water: return AppCategory.nutrition.tint
        case .todo, .focus: return AppCategory.productivity.tint
        case .mood, .breathing: return AppCategory.mind.tint
        case .bedtime: return AppCategory.sleep.tint
        case .budget: return AppCategory.finance.tint
        case .portfolio: return AppCategory.invest.tint
        case .flashcards: return AppCategory.learning.tint
        case .progressPhotos: return AppCategory.looks.tint
        }
    }
    var isFullScreen: Bool { self == .tabata }

    @ViewBuilder var destination: some View {
        switch self {
        case .dashboard: HomeDashboardContent()
        case .tabata: TabataView()
        case .calories: CalAIView()
        case .scan: ScanProductView()
        case .todo: TodoView()
        case .fasting: FastingView()
        case .water: HydrationView()
        case .habits: HabitTrackerView()
        case .focus: FocusTimerView()
        case .mood: MoodJournalView()
        case .breathing: BreathingView()
        case .bedtime: BedtimeCalculatorView()
        case .budget: BudgetView()
        case .portfolio: PortfolioView()
        case .flashcards: FlashcardsView()
        case .nap: PowerNapView()
        case .progressPhotos: ProgressPhotoGalleryView()
        }
    }
}

/// Anneaux de progression épinglables sur l'accueil (« Objectifs du jour »).
enum HomeMetric: String, CaseIterable, Identifiable {
    case steps, water, calories, fasting, habits

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steps:    return "Pas"
        case .water:    return "Eau"
        case .calories: return "Calories"
        case .fasting:  return "Jeûne"
        case .habits:   return "Habitudes"
        }
    }
    var unit: String {
        switch self {
        case .steps:    return ""
        case .water:    return "ml"
        case .calories: return "kcal"
        case .fasting:  return "h"
        case .habits:   return ""
        }
    }
    var icon: String {
        switch self {
        case .steps:    return "figure.walk"
        case .water:    return "drop.fill"
        case .calories: return "flame.fill"
        case .fasting:  return "timer"
        case .habits:   return "checklist"
        }
    }
    var color: Color {
        switch self {
        case .steps:    return Color(hex: 0xF1746C)
        case .water:    return Color(hex: 0x3CB2E0)
        case .calories: return Color(hex: 0x4CC38A)
        case .fasting:  return Color(hex: 0x9B6CF1)
        case .habits:   return Color(hex: 0xF1A33C)
        }
    }
}

struct ShortcutsHomeView: View {
    @AppStorage("homeShortcuts") private var enabledRaw = "tabata,calories,scan,todo"
    @AppStorage("homeMetrics") private var metricsRaw = "steps,water,calories,fasting"
    @AppStorage("userName") private var userName = ""
    @AppStorage("stepGoal") private var stepGoal = 10000
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("fastTarget") private var fastTarget = 16
    @AppStorage("todayEnergyScore") private var todayEnergyScore = 0
    @AppStorage("todayEnergyLabel") private var todayEnergyLabel = ""
    @State private var reengageMessage: String? = nil
    @State private var reengageSuggestion: String? = nil
    @State private var showReengage = true
    @State private var weeklyModuleSuggestion: AppCategory? = nil

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]
    @Environment(\.modelContext) private var ctx

    @State private var steps = 0
    @State private var editingMood = false
    @State private var editingShortcuts = false
    @State private var editingMetrics = false

    private var enabledShortcuts: [ShortcutTool] {
        enabledRaw.split(separator: ",").compactMap { ShortcutTool(rawValue: String($0)) }
    }
    private var enabledMetrics: [HomeMetric] {
        metricsRaw.split(separator: ",").compactMap { HomeMetric(rawValue: String($0)) }
    }

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    // MARK: données du jour
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }
    private var fastHours: Double { fasts.first(where: { $0.isActive }).map { $0.elapsed / 3600 } ?? 0 }
    private var todayMood: MoodEntry? { moods.first { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .bottom) {
                        Text(userName.isEmpty ? greeting : "\(greeting), \(userName)")
                            .font(.system(size: 40, weight: .black)).textCase(.uppercase).kerning(-1)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        Spacer()
                        if todayEnergyScore > 0 {
                            energyBadge
                        }
                    }
                    .padding(.horizontal, 4)

                    if showReengage, let msg = reengageMessage {
                        reengageBanner(message: msg, suggestion: reengageSuggestion)
                    }

                    DailyScoreRing()   // score unique du jour (mélange tous les objectifs)

                    LifeBrainCard()
                        .padding(.horizontal, -Theme.pad)   // guidance transversale, en tête

                    if let module = weeklyModuleSuggestion {
                        weeklyModuleCard(module)
                    }

                    TodayAgendaSection()
                        .padding(.horizontal, -Theme.pad)   // pleine largeur (compense le padding parent)

                    shortcutsSection
                    habitsSection
                    moodSection
                }
                .padding(Theme.pad)
            }
            .floatingBarClearance()       // le dernier bloc ne passe pas sous la barre flottante
            .scrollContentBackground(.hidden)
            .background(Theme.screenBG)   // verre global : wallpaper dépoli en thème Verre
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editingShortcuts) {
                ShortcutPickerSheet(enabledRaw: $enabledRaw)
            }
            .sheet(isPresented: $editingMetrics) {
                HomeMetricPickerSheet(metricsRaw: $metricsRaw)
            }
            .task {
                if await HealthService.shared.requestAuthorization() {
                    steps = await HealthService.shared.stepsToday()
                }
                reengageMessage    = EngagementTracker.shared.reengagementMessage
                reengageSuggestion = EngagementTracker.shared.simplificationSuggestion
                weeklyModuleSuggestion = WeeklyModuleSuggester.shared.currentSuggestion()
                WeeklyModuleSuggester.shared.scheduleWeeklyNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    if await HealthService.shared.requestAuthorization() {
                        steps = await HealthService.shared.stepsToday()
                    }
                }
            }
        }
    }

    // MARK: Section 1 — Habitudes

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Habitudes")
            if habits.isEmpty {
                Button {
                    Haptics.tap()
                    NotificationCenter.default.post(
                        name: .lifeOSOpenAIChat, object: nil,
                        userInfo: ["prefill": "Crée-moi une nouvelle habitude quotidienne"]
                    )
                } label: {
                    HStack(spacing: 13) {
                        IconBadge(icon: "sparkles", tint: Color(hex: 0x9B6CF1), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Créer une habitude")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("Demande à l'assistant IA")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(habits.enumerated()), id: \.element.id) { idx, habit in
                        habitRow(habit, isLast: idx == habits.count - 1)
                    }
                }
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
            }
        }
    }

    private func habitRow(_ habit: Habit, isLast: Bool) -> some View {
        let done = habit.completions.contains { Calendar.current.isDateInToday($0.date) }
        return Button { toggleHabit(habit) } label: {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Theme.volt : Color.secondary.opacity(0.4))
                Text(habit.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().padding(.leading, 52) }
        }
    }

    private func toggleHabit(_ habit: Habit) {
        if let completion = habit.completions.first(where: { Calendar.current.isDateInToday($0.date) }) {
            ctx.delete(completion)
        } else {
            let c = HabitCompletion(date: .now)
            habit.completions.append(c)
        }
        try? ctx.save()
        Haptics.soft()
    }

    // MARK: Section 2 — Objectifs du jour (anneaux + 3 objectifs) — tout est cliquable
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Objectifs du jour", trailing: "Éditer") { editingMetrics = true }
            if !enabledMetrics.isEmpty {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(enabledMetrics) { m in
                        let v = metricValue(m)
                        NavigationLink { metricDestination(m).floatingBarClearance() } label: {
                            MetricRing(value: v.value, goal: v.goal, label: m.label, unit: m.unit, color: m.color, icon: m.icon)
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(spacing: 4) {
                ForEach(Array(objectives.enumerated()), id: \.element.title) { i, o in
                    NavigationLink { objectiveDestination(o.title).floatingBarClearance() } label: { objectiveRow(o) }
                        .buttonStyle(.plain)
                    if i < objectives.count - 1 { Divider().padding(.leading, 47) }
                }
            }
            .padding(16)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
        }
    }

    @ViewBuilder private func objectiveDestination(_ title: String) -> some View {
        switch title {
        case "S'hydrater": HydrationView()
        case "Habitudes":  HabitTrackerView()
        default:           StepsView()
        }
    }

    private func metricValue(_ m: HomeMetric) -> (value: Double, goal: Double) {
        switch m {
        case .steps:    return (Double(steps), Double(stepGoal))
        case .water:    return (Double(waterToday), Double(waterGoal))
        case .calories: return (Double(kcalToday), Double(kcalGoal))
        case .fasting:  return (fastHours, Double(fastTarget))
        case .habits:   return (Double(habitsDone), Double(max(1, habits.count)))
        }
    }

    @ViewBuilder private func metricDestination(_ m: HomeMetric) -> some View {
        switch m {
        case .steps:    StepsView()
        case .water:    HydrationView()
        case .calories: FoodSearchView()
        case .fasting:  FastingView()
        case .habits:   HabitTrackerView()
        }
    }

    private struct Objective { let icon: String; let title: String; let sub: String; let color: Color; let progress: Double; let done: Bool }
    private var objectives: [Objective] {
        let sp = min(1.0, Double(steps) / Double(max(1, stepGoal)))
        let wp = min(1.0, Double(waterToday) / Double(max(1, waterGoal)))
        let hp = habits.isEmpty ? 0 : min(1.0, Double(habitsDone) / Double(habits.count))
        return [
            Objective(icon: "figure.walk", title: "Bouger", sub: "\(steps) / \(stepGoal) pas", color: Color(hex: 0xF1746C), progress: sp, done: sp >= 1),
            Objective(icon: "drop.fill", title: "S'hydrater", sub: "\(waterToday) / \(waterGoal) ml", color: Color(hex: 0x3CB2E0), progress: wp, done: wp >= 1),
            Objective(icon: "checklist", title: "Habitudes", sub: habits.isEmpty ? "Aucune habitude" : "\(habitsDone) / \(habits.count) faites", color: Color(hex: 0x9B6CF1), progress: hp, done: hp >= 1 && !habits.isEmpty)
        ]
    }

    private func objectiveRow(_ o: Objective) -> some View {
        HStack(spacing: 13) {
            IconBadge(icon: o.icon, tint: o.color, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(o.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    Text(o.sub).font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: o.progress).tint(Theme.volt).scaleEffect(x: 1, y: 1.1, anchor: .center)
            }
            Image(systemName: o.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18)).foregroundStyle(o.done ? AnyShapeStyle(Theme.volt) : AnyShapeStyle(Color.secondary.opacity(0.4)))
        }
    }

    // MARK: Section — Raccourcis épinglés
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Raccourcis", trailing: "Éditer") { editingShortcuts = true }
            if enabledShortcuts.isEmpty {
                Button { editingShortcuts = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(.secondary)
                        Text("Épingle tes outils favoris ici")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16).frame(maxWidth: .infinity)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(enabledShortcuts) { tool in
                        NavigationLink { tool.destination.floatingBarClearance() } label: { shortcutTile(tool) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func shortcutTile(_ tool: ShortcutTool) -> some View {
        VStack(spacing: 11) {
            IconBadge(icon: tool.icon, tint: tool.tint, size: 48)
            Text(tool.label)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 18, elevated: true)
    }

    // MARK: Section 3 — Humeur du jour (check-in)
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Comment tu te sens ?")
            if let m = todayMood, !editingMood {
                HStack(spacing: 14) {
                    Text(moodEmoji(m.score)).font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Humeur enregistrée").font(.subheadline.weight(.semibold))
                        Text("Bonne journée à toi ✨").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Modifier") { withAnimation { editingMood = true } }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
            } else {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { s in
                        Button { logMood(s) } label: {
                            Text(moodEmoji(s)).font(.system(size: 30))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
            }
        }
    }

    private func moodEmoji(_ s: Int) -> String { ["😞", "😕", "😐", "🙂", "😄"][max(0, min(4, s - 1))] }
    private func logMood(_ s: Int) {
        if let m = todayMood { m.score = s } else { ctx.insert(MoodEntry(score: s)) }
        try? ctx.save()
        Haptics.soft()
        withAnimation { editingMood = false }
    }

    private func weeklyModuleCard(_ module: AppCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(icon: module.icon, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouveau module cette semaine ?")
                        .monoLabel(10)
                        .foregroundStyle(.secondary)
                    Text(module.title)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
            Text(module.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    WeeklyModuleSuggester.shared.accept(module)
                    withAnimation { weeklyModuleSuggestion = nil }
                } label: {
                    Text("Ajouter")
                        .font(.system(size: 14, weight: .black)).textCase(.uppercase).kerning(0.5)
                        .foregroundStyle(Theme.onVolt)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    WeeklyModuleSuggester.shared.dismiss(module)
                    withAnimation { weeklyModuleSuggestion = nil }
                } label: {
                    Text("Pas maintenant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(module.tint.opacity(0.2), lineWidth: 1)
        )
    }

    private func reengageBanner(message: String, suggestion: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF9F0A))
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { withAnimation(.easeOut(duration: 0.2)) { showReengage = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if let s = suggestion {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }
        }
        .padding(14)
        .background(
            Color(hex: 0xFF9F0A).opacity(0.08),
            in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Color(hex: 0xFF9F0A).opacity(0.2), lineWidth: 1)
        )
    }

    private var energyBadge: some View {
        let scoreColor: Color = {
            switch todayEnergyScore {
            case 85...100: return Color(hex: 0x34C759)
            case 70..<85:  return Color(hex: 0x30D158)
            case 50..<70:  return Color(hex: 0xFF9F0A)
            case 30..<50:  return Color(hex: 0xFF6B35)
            default:       return Color(hex: 0xFF3B30)
            }
        }()
        return VStack(alignment: .trailing, spacing: 1) {
            Text("\(todayEnergyScore)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText())
            Text(todayEnergyLabel.isEmpty ? "Énergie" : todayEnergyLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(scoreColor.opacity(0.8))
        }
    }

    private func sectionHeader(_ title: String, trailing: String? = nil, action: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 20, weight: .black)).textCase(.uppercase).kerning(-0.3)
            Spacer()
            if let trailing {
                Button(action: action) { Text(trailing).monoLabel(11).foregroundStyle(.primary) }
            }
        }
        .padding(.horizontal, 4)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon aprèm"
        case 18..<23: return "Bonsoir"
        default:      return "Bonne nuit"
        }
    }
}

// MARK: - Éditeur de raccourcis de l'accueil

private struct ShortcutPickerSheet: View {
    @Binding var enabledRaw: String
    @Environment(\.dismiss) private var dismiss

    private var enabled: [String] { enabledRaw.split(separator: ",").map(String.init) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ShortcutTool.allCases) { tool in
                        let on = enabled.contains(tool.rawValue)
                        Button { toggle(tool, on: on) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(tool.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(tool.label).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(on ? AnyShapeStyle(tool.tint) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Choisis les raccourcis affichés sur l'accueil")
                } footer: {
                    Text("Touche pour épingler ou retirer. L'ordre suit tes sélections.")
                }
            }
            .navigationTitle("Raccourcis").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func toggle(_ tool: ShortcutTool, on: Bool) {
        var list = enabled
        if on { list.removeAll { $0 == tool.rawValue } }
        else { list.append(tool.rawValue) }
        enabledRaw = list.joined(separator: ",")
        Haptics.soft()
    }
}

// MARK: - Éditeur des anneaux « Objectifs du jour »

private struct HomeMetricPickerSheet: View {
    @Binding var metricsRaw: String
    @Environment(\.dismiss) private var dismiss

    private var enabled: [String] { metricsRaw.split(separator: ",").map(String.init) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeMetric.allCases) { m in
                        let on = enabled.contains(m.rawValue)
                        Button { toggle(m, on: on) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: m.icon)
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(m.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(m.label).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(on ? AnyShapeStyle(m.color) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Choisis les anneaux affichés sur l'accueil")
                } footer: {
                    Text("Touche pour ajouter ou retirer. L'ordre suit tes sélections.")
                }
            }
            .navigationTitle("Objectifs du jour").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func toggle(_ m: HomeMetric, on: Bool) {
        var list = enabled
        if on { list.removeAll { $0 == m.rawValue } }
        else { list.append(m.rawValue) }
        metricsRaw = list.joined(separator: ",")
        Haptics.soft()
    }
}
