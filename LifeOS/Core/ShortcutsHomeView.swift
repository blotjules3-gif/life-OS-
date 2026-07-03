import SwiftUI
import SwiftData
import Charts
import UIKit

/// Outils directs qu'on peut épingler en raccourci sur l'accueil.
enum ShortcutTool: String, CaseIterable, Identifiable {
    case dashboard, tabata, calories, scan, todo, fasting, water, habits
    case focus, mood, breathing, bedtime, budget, portfolio, flashcards, nap, progressPhotos
    case bilanSoir

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
        case .bilanSoir: return "Bilan du soir"
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
        case .bilanSoir: return "sunset.fill"
        }
    }
    var tint: Color {
        switch self {
        case .dashboard: return Color(hex: 0x618EF1)
        case .tabata, .habits, .nap: return AppCategory.fitness.tint
        case .calories, .scan, .fasting, .water: return AppCategory.nutrition.tint
        case .todo, .focus: return AppCategory.productivity.tint
        case .mood, .breathing: return AppCategory.mind.tint
        case .bedtime, .bilanSoir: return AppCategory.sleep.tint
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
        case .bilanSoir: EveningSummaryView()
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
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @State private var reengageMessage: String? = nil
    @State private var reengageSuggestion: String? = nil
    @State private var showReengage = true
    @State private var weeklyModuleSuggestion: AppCategory? = nil

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var foodsYesterday: [FoodEntry]
    @Query private var watersYesterday: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]
    @Environment(\.modelContext) private var ctx

    init() {
        let cal = Calendar.current
        let todayStart    = cal.startOfDay(for: Date())
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        _foods  = Query(filter: #Predicate<FoodEntry>  { $0.date >= todayStart && $0.date < tomorrowStart })
        _waters = Query(filter: #Predicate<WaterEntry> { $0.date >= todayStart && $0.date < tomorrowStart })
        _foodsYesterday  = Query(filter: #Predicate<FoodEntry>  { $0.date >= yesterdayStart && $0.date < todayStart })
        _watersYesterday = Query(filter: #Predicate<WaterEntry> { $0.date >= yesterdayStart && $0.date < todayStart })
        _moods  = Query(filter: #Predicate<MoodEntry>  { $0.date >= fourteenDaysAgo },
                        sort: \MoodEntry.date, order: .reverse)
    }

    @State private var editingMetrics = false
    private var enabledMetrics: [HomeMetric] {
        metricsRaw.split(separator: ",").compactMap { HomeMetric(rawValue: String($0)) }
    }

    @State private var steps = 0
    @State private var stepsYesterday = 0

    private var kcalYesterday: Int  { foodsYesterday.caloriesToday }
    private var waterYesterday: Int { watersYesterday.mlToday }
    @State private var editingMood = false
    @State private var animatedHabitIDs: Set<PersistentIdentifier> = []
    @State private var moodDismissed = false
    @State private var showBilan = false
    @State private var fullScreenTool: ShortcutTool? = nil
    @AppStorage("tutorialDone") private var tutorialDone = false
    @State private var showTutorial = false
    @State private var editingShortcuts = false
    @State private var homeAppeared = false

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var activeShortcuts: [ShortcutTool] {
        enabledRaw.split(separator: ",").compactMap { ShortcutTool(rawValue: String($0)) }
    }

    // MARK: données du jour (foods/waters already filtered to today by @Query predicate)
    private var kcalToday: Int  { foods.caloriesToday }
    private var waterToday: Int { waters.mlToday }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }
    private var fastHours: Double { fasts.first(where: { $0.isActive }).map { $0.elapsed / 3600 } ?? 0 }
    private var todayMood: MoodEntry? { moods.first { Calendar.current.isDateInToday($0.date) } }

    private var isMorningEmpty: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 10 && kcalToday == 0 && waterToday == 0 && steps < 200 && habitsDone == 0
    }

    private var morningModuleChips: [(icon: String, label: String, color: Color)] {
        let active = Set(recommendedModulesRaw.split(separator: ",").map(String.init))
        var chips: [(String, String, Color)] = []
        if active.contains("nutrition") { chips.append(("flame.fill", "Calories", Color(hex: 0xF1746C))) }
        if active.contains("fitness")   { chips.append(("figure.run", "Activité", Color(hex: 0x4CC38A))) }
        if active.contains("sleep")     { chips.append(("moon.stars.fill", "Sommeil", Color(hex: 0x6C7BF1))) }
        if active.contains("mind")      { chips.append(("brain.head.profile", "Focus", Color(hex: 0x9B6CF1))) }
        if chips.isEmpty {
            chips = [("sun.horizon.fill", "Journée", Color(hex: 0xFF9F0A)),
                     ("figure.run", "Activité", Color(hex: 0x4CC38A)),
                     ("drop.fill", "Hydratation", Color(hex: 0x3CB2E0))]
        }
        return Array(chips.prefix(4))
    }

    private var morningContextCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFF9F0A))
                .frame(width: 44, height: 44)
                .background(Color(hex: 0xFF9F0A).opacity(0.12),
                             in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Ta journée commence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Voilà ce qui t'attend aujourd'hui.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(morningModuleChips, id: \.label) { chip in
                        HStack(spacing: 5) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(chip.color)
                            Text(chip.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(chip.color.opacity(0.10),
                                     in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xFF9F0A).opacity(0.07), Color(hex: 0xFF9F0A).opacity(0.02)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Color(hex: 0xFF9F0A).opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: données hebdo
    private var activeHabits: [Habit] { habits.filter { !$0.isPending } }
    private var weekDays: [Date] {
        let cal = Calendar.current
        return (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now))! }
    }
    private func completionRatio(for day: Date) -> Double {
        guard !activeHabits.isEmpty else { return 0 }
        let done = activeHabits.filter { h in h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: day) } }.count
        return Double(done) / Double(activeHabits.count)
    }
    private var weeklyScore: Double {
        guard !activeHabits.isEmpty else { return 0 }
        let total = weekDays.reduce(0.0) { $0 + completionRatio(for: $1) }
        return total / 7.0
    }
    private var perfectDaysCount: Int {
        weekDays.filter { completionRatio(for: $0) >= 1.0 && !activeHabits.isEmpty }.count
    }
    private var bestHabitWeek: Habit? {
        activeHabits.max { a, b in
            let ca = weekDays.filter { d in a.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: d) } }.count
            let cb = weekDays.filter { d in b.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: d) } }.count
            return ca < cb
        }
    }
    private var weeklyMotivation: String {
        let pct = Int(weeklyScore * 100)
        switch pct {
        case 90...100: return "Semaine exceptionnelle. Continue comme ca."
        case 70..<90:  return "Bonne semaine. Tu progresses."
        case 50..<70:  return "Mi-chemin. Un effort de plus demain."
        case 1..<50:   return "La regularite s'installe peu a peu."
        default:       return "La semaine commence maintenant."
        }
    }

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
                    .staggered(0, appeared: homeAppeared)

                    if !activeShortcuts.isEmpty {
                        shortcutsSection
                            .staggered(1, appeared: homeAppeared)
                    }

                    if !moodDismissed || editingMood {
                        moodSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .staggered(2, appeared: homeAppeared)
                    }

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

                    habitsSection
                        .staggered(3, appeared: homeAppeared)
                        .scrollFade()
                    if !activeHabits.isEmpty {
                        weeklyRecapSection
                            .staggered(4, appeared: homeAppeared)
                            .scrollFade()
                    }
                    if isMorningEmpty {
                        morningContextCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    goalsSection
                        .staggered(5, appeared: homeAppeared)
                        .scrollFade()
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
                    steps = await HealthService.shared.cachedStepsToday()
                    stepsYesterday = await HealthService.shared.stepsYesterday()
                }
                reengageMessage    = EngagementTracker.shared.reengagementMessage
                reengageSuggestion = EngagementTracker.shared.simplificationSuggestion
                weeklyModuleSuggestion = WeeklyModuleSuggester.shared.currentSuggestion()
                WeeklyModuleSuggester.shared.scheduleWeeklyNotification()
                if todayMood != nil { moodDismissed = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    if await HealthService.shared.requestAuthorization() {
                        steps = await HealthService.shared.cachedStepsToday()
                    }
                }
                if todayMood == nil { withAnimation { moodDismissed = false } }
            }
            .sheet(isPresented: $showBilan) { WeeklyBilanView() }
            .fullScreenCover(item: $fullScreenTool) { tool in
                tool.destination
            }
            .overlay(alignment: .bottom) {
                if showTutorial {
                    tutorialOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                homeAppeared = true
                if !tutorialDone {
                    withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(1.2)) { showTutorial = true }
                }
            }
        }
    }

    private var tutorialOverlay: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ton coach est en bas")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Appuie sur le champ \"Ton assistant…\" pour poser une question, créer une habitude ou naviguer vers un module.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
                tutorialDone = true
            } label: {
                Text("Compris")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 120)
    }

    // MARK: Section 0 — Raccourcis personnalisés

    private let shortcutCols = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Raccourcis")
            LazyVGrid(columns: shortcutCols, spacing: 10) {
                ForEach(activeShortcuts) { tool in
                    if tool.isFullScreen {
                        Button { fullScreenTool = tool } label: { shortcutTile(tool) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tool.label)
                    } else {
                        NavigationLink(destination: tool.destination) {
                            shortcutTile(tool)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tool.label)
                    }
                }
            }
        }
    }

    private func shortcutTile(_ tool: ShortcutTool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: tool.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tool.tint)
                .frame(width: 44, height: 44)
                .background(tool.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(tool.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
                            Text("Demande à ton coach")
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
                            .opacity(animatedHabitIDs.contains(habit.id) ? 1 : 0)
                            .offset(y: animatedHabitIDs.contains(habit.id) ? 0 : 16)
                    }
                }
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
            }
        }
        .onChange(of: habits.count) { _, _ in animateNewHabits() }
        .onAppear { animateNewHabits() }
    }

    private func animateNewHabits() {
        let newIDs = Set(habits.map { $0.id }).subtracting(animatedHabitIDs)
        guard !newIDs.isEmpty else { return }
        for (i, id) in newIDs.sorted(by: { $0.hashValue < $1.hashValue }).enumerated() {
            withAnimation(.spring(duration: 0.45, bounce: 0.2).delay(Double(i) * 0.07)) {
                animatedHabitIDs.insert(id)
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
                    .contentTransition(.symbolEffect(.replace))
                Text(habit.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                Spacer()
            }
            .animation(.spring(duration: 0.35, bounce: 0.4), value: done)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(habit.name), \(done ? "faite" : "non faite")")
        .accessibilityHint(done ? "Double-tapez pour décocher" : "Double-tapez pour valider")
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
        do { try ctx.save() } catch { print("[SwiftData] toggleHabit failed: \(error)") }
        Haptics.soft()
    }

    // MARK: Section 1b — Recap hebdo

    private var weeklyRecapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Cette semaine")
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(weeklyScore * 100))%")
                            .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(weeklyScoreColor)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.5), value: weeklyScore)
                        Text(weeklyMotivation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(perfectDaysCount) jour\(perfectDaysCount > 1 ? "s" : "") parfait\(perfectDaysCount > 1 ? "s" : "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: 0x4CC38A))
                        weekDotsRow
                    }
                }
                if let best = bestHabitWeek {
                    Divider().opacity(0.4)
                    HStack(spacing: 10) {
                        Image(systemName: best.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: UInt(best.colorHex)))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: UInt(best.colorHex)).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Top habitude").font(.caption).foregroundStyle(.secondary)
                            Text(best.name).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                Divider().opacity(0.4)
                Button { showBilan = true } label: {
                    HStack {
                        Text("Voir le bilan complet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(weeklyScoreColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(weeklyScoreColor.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(weeklyScoreColor.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var weekDotsRow: some View {
        let cal = Calendar.current
        let daySymbols = ["L", "M", "M", "J", "V", "S", "D"]
        return HStack(spacing: 6) {
            ForEach(0..<7) { i in
                let day = weekDays[i]
                let ratio = completionRatio(for: day)
                let isToday = cal.isDateInToday(day)
                VStack(spacing: 3) {
                    Text(daySymbols[i])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    Circle()
                        .fill(dotColor(ratio: ratio))
                        .frame(width: 8, height: 8)
                        .overlay(isToday ? Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1) : nil)
                }
            }
        }
    }

    private func dotColor(ratio: Double) -> Color {
        if ratio >= 1.0 { return Color(hex: 0x4CC38A) }
        if ratio > 0 { return Color(hex: 0xFF9F0A) }
        return Color.secondary.opacity(0.2)
    }

    private var weeklyScoreColor: Color {
        let pct = Int(weeklyScore * 100)
        switch pct {
        case 80...100: return Color(hex: 0x4CC38A)
        case 50..<80:  return Color(hex: 0xFF9F0A)
        default:       return Color(hex: 0x9B6CF1)
        }
    }

    // MARK: Section 2 — Objectifs du jour (anneaux + 3 objectifs) — tout est cliquable
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
<<<<<<< HEAD
            sectionHeader("Objectifs du jour")
            LazyVGrid(columns: cols, spacing: 12) {
                NavigationLink { StepsView() } label: {
                    MetricRing(value: Double(steps), goal: Double(stepGoal), label: "Pas", unit: "", color: Color(hex: 0xF1746C), icon: "figure.walk",
                               delta: stepsYesterday > 0 ? steps - stepsYesterday : nil)
                }.buttonStyle(.plain)
                NavigationLink { HydrationView() } label: {
                    MetricRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", unit: "ml", color: Color(hex: 0x3CB2E0), icon: "drop.fill",
                               delta: waterYesterday > 0 ? waterToday - waterYesterday : nil)
                }.buttonStyle(.plain)
                NavigationLink { FoodSearchView() } label: {
                    MetricRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Calories", unit: "kcal", color: Color(hex: 0x4CC38A), icon: "flame.fill",
                               delta: kcalYesterday > 0 ? kcalToday - kcalYesterday : nil)
                }.buttonStyle(.plain)
                NavigationLink { FastingView() } label: {
                    MetricRing(value: fastHours, goal: Double(fastTarget), label: "Jeûne", unit: "h", color: Color(hex: 0x9B6CF1), icon: "timer")
                }.buttonStyle(.plain)
=======
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
>>>>>>> origin/pote
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
                    Text(o.sub)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: o.sub)
                }
<<<<<<< HEAD
                ProgressView(value: o.progress).tint(o.color).scaleEffect(x: 1, y: 1.1, anchor: .center)
                    .animation(.spring(duration: 0.6, bounce: 0.1), value: o.progress)
            }
            Image(systemName: o.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18)).foregroundStyle(o.done ? AnyShapeStyle(o.color) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(duration: 0.35, bounce: 0.4), value: o.done)
        }
    }

    // MARK: Humeur — compact, en haut, disparaît après vote
=======
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
>>>>>>> origin/pote
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Comment tu te sens ?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                moodHistoryDots
            }
            .padding(.horizontal, 4)
            if let m = todayMood, !editingMood {
                HStack(spacing: 12) {
                    Text(moodEmoji(m.score)).font(.system(size: 28))
                    Text("Noté — revote dans 24h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Modifier") { withAnimation(.spring(duration: 0.3)) { editingMood = true } }
                        .font(.caption).foregroundStyle(.secondary)
                }
<<<<<<< HEAD
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
=======
                .padding(16)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
>>>>>>> origin/pote
            } else {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { s in
                        Button { logMood(s) } label: {
                            Text(moodEmoji(s))
                                .font(.system(size: 26))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
<<<<<<< HEAD
=======
                .padding(16)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .softElevation()
>>>>>>> origin/pote
            }
        }
    }

    private var moodHistoryDots: some View {
        let cal = Calendar.current
        let past6 = (1...6).reversed().compactMap { off -> MoodEntry? in
            guard let day = cal.date(byAdding: .day, value: -off, to: .now) else { return nil }
            return moods.first { cal.isDate($0.date, inSameDayAs: day) }
        }
        return HStack(spacing: 4) {
            Spacer()
            ForEach(past6, id: \.date) { m in
                Circle()
                    .fill(moodColor(m.score))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
    }

    private func moodColor(_ score: Int) -> Color {
        switch score {
        case 5: return Color(hex: 0x4CC38A)
        case 4: return Color(hex: 0x30C77A)
        case 3: return Color(hex: 0xFF9F0A)
        case 2: return Color(hex: 0xFF6B35)
        default: return Color(hex: 0xF1746C)
        }
    }

    private func moodEmoji(_ s: Int) -> String { ["😞", "😕", "😐", "🙂", "😄"][max(0, min(4, s - 1))] }
    private func logMood(_ s: Int) {
        if let m = todayMood { m.score = s } else { ctx.insert(MoodEntry(score: s)) }
        do { try ctx.save() } catch { print("[SwiftData] logMood failed: \(error)") }
        Haptics.soft()
        withAnimation(.spring(duration: 0.3)) { editingMood = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.4)) { moodDismissed = true }
        }
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
                .accessibilityLabel("Fermer")
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

// MARK: - Bilan de semaine

struct WeeklyBilanView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var waters: [WaterEntry]
    @Query private var foods: [FoodEntry]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]

    @State private var aiBilan: String? = nil
    @State private var bilanLoading = false
    @State private var shareImage: UIImage? = nil
    @AppStorage("lastWeeklyBilanText") private var cachedBilan = ""
    @AppStorage("lastWeeklyBilanDate") private var cachedBilanDate = 0.0

    private var activeHabits: [Habit] { habits.filter { !$0.isPending } }
    private var cal: Calendar { Calendar.current }

    private var weekDays: [Date] {
        (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now))! }
    }
    private func done(_ habit: Habit, on day: Date) -> Bool {
        habit.completions.contains { cal.isDate($0.date, inSameDayAs: day) }
    }
    private func ratio(for day: Date) -> Double {
        guard !activeHabits.isEmpty else { return 0 }
        return Double(activeHabits.filter { done($0, on: day) }.count) / Double(activeHabits.count)
    }
    private var weeklyScore: Double {
        guard !activeHabits.isEmpty else { return 0 }
        return weekDays.reduce(0.0) { $0 + ratio(for: $1) } / 7.0
    }
    private var perfectDays: Int { weekDays.filter { ratio(for: $0) >= 1 && !activeHabits.isEmpty }.count }
    private var avgWater: Int {
        // Divisé par 7 (semaine entière) — jours sans données comptent comme 0
        let total = weekDays.reduce(0) { acc, d in
            acc + waters.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.amountML }
        }
        return total / 7
    }
    private var avgKcal: Int {
        // Divisé par 7 (semaine entière) — jours sans données comptent comme 0
        let total = weekDays.reduce(0) { acc, d in
            acc + foods.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.calories }
        }
        return total / 7
    }
    private var avgMood: Double {
        let week = moods.filter { m in weekDays.contains { cal.isDate(m.date, inSameDayAs: $0) } }
        return week.isEmpty ? 0 : Double(week.reduce(0) { $0 + $1.score }) / Double(week.count)
    }
    private var weekMoods: [(Date, Int)] {
        weekDays.compactMap { day -> (Date, Int)? in
            guard let entry = moods.first(where: { cal.isDate($0.date, inSameDayAs: day) }) else { return nil }
            return (day, entry.score)
        }
    }
    private var scoreColor: Color {
        let p = Int(weeklyScore * 100)
        if p >= 80 { return Color(hex: 0x4CC38A) }
        if p >= 50 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0x9B6CF1)
    }
    private var message: String {
        let p = Int(weeklyScore * 100)
        switch p {
        case 90...100: return "Semaine exceptionnelle. Tu es en feu."
        case 70..<90:  return "Très bonne semaine. Continue sur cette lancée."
        case 50..<70:  return "Semaine correcte. Un peu plus de régularité et tu explooses."
        case 1..<50:   return "Semaine difficile. L'important c'est de repartir."
        default:       return "Semaine vierge. Tout commence maintenant."
        }
    }

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Score global
                    VStack(spacing: 6) {
                        Text("\(Int(weeklyScore * 100))%")
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .foregroundStyle(scoreColor)
                            .contentTransition(.numericText())
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Dots semaine
                    HStack(spacing: 14) {
                        ForEach(0..<7, id: \.self) { i in
                            let day = weekDays[i]
                            let r = ratio(for: day)
                            let isToday = cal.isDateInToday(day)
                            VStack(spacing: 6) {
                                Text(dayLetters[i])
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isToday ? Color.primary : Color.secondary)
                                Circle()
                                    .fill(r >= 1 ? Color(hex: 0x4CC38A) : (r > 0 ? Color(hex: 0xFF9F0A) : Color.secondary.opacity(0.2)))
                                    .frame(width: 12, height: 12)
                                    .overlay(isToday ? Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1.5) : nil)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                    // Bilan IA
                    aiBilanCard

                    // Stats rapides
                    if avgWater > 0 || avgKcal > 0 || avgMood > 0 {
                        HStack(spacing: 12) {
                            if avgWater > 0 { statPill("drop.fill", "\(avgWater) ml", Color(hex: 0x3CB2E0)) }
                            if avgKcal > 0  { statPill("flame.fill", "\(avgKcal) kcal", Color(hex: 0x4CC38A)) }
                            if avgMood > 0  { statPill("face.smiling", String(format: "%.1f/5", avgMood), Color(hex: 0x9B6CF1)) }
                        }
                    }

                    // Graphe humeur 7 jours
                    if !weekMoods.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("HUMEUR — 7 JOURS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                            Chart(weekMoods, id: \.0) { item in
                                LineMark(
                                    x: .value("Jour", item.0, unit: .day),
                                    y: .value("Humeur", item.1)
                                )
                                .foregroundStyle(Color(hex: 0x9B6CF1))
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Jour", item.0, unit: .day),
                                    y: .value("Humeur", item.1)
                                )
                                .foregroundStyle(Color(hex: 0x9B6CF1))
                                .symbolSize(40)
                            }
                            .frame(height: 100)
                            .chartYScale(domain: 1...5)
                            .chartYAxis {
                                AxisMarks(values: [1, 3, 5]) { v in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        let labels = ["😞", "😐", "😄"]
                                        let idx = min(v.index, labels.count - 1)
                                        Text(labels[idx]).font(.caption)
                                    }
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }

                    // Habitudes détaillées
                    if !activeHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("HABITUDES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            ForEach(Array(activeHabits.enumerated()), id: \.element.id) { idx, habit in
                                habitBilanRow(habit, isLast: idx == activeHabits.count - 1)
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }

                    if perfectDays > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xFF9F0A))
                            Text("\(perfectDays) jour\(perfectDays > 1 ? "s" : "") avec 100% des habitudes cette semaine")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFF9F0A).opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Bilan de semaine")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let ui = shareImage {
                        ShareLink(
                            item: Image(uiImage: ui),
                            preview: SharePreview("Mon bilan de semaine", image: Image(uiImage: ui))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .task {
                renderShareCard()
                await loadAIBilan()
            }
        }
    }

    // MARK: Partage

    private var shareDateRange: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM"
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(df.string(from: first)) — \(df.string(from: last))"
    }

    @MainActor
    private func renderShareCard() {
        let card = WeeklyShareCard(
            score: Int(weeklyScore * 100),
            dayRatios: weekDays.map { ratio(for: $0) },
            perfectDays: perfectDays,
            avgWater: avgWater,
            avgKcal: avgKcal,
            avgMood: avgMood,
            message: message,
            dateRange: shareDateRange
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    // MARK: Bilan IA

    private var aiBilanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Analyse du coach")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                Spacer()
                if bilanLoading { ProgressView().scaleEffect(0.7) }
            }
            if let text = aiBilan {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !bilanLoading && !cachedBilan.isEmpty {
                Text(cachedBilan)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !bilanLoading {
                Text("Connexion requise pour générer l'analyse.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private func loadAIBilan() async {
        // Use cache if generated today
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        if cachedBilanDate >= today && !cachedBilan.isEmpty {
            aiBilan = cachedBilan
            return
        }
        bilanLoading = true
        let habitNames = activeHabits.map { $0.name }.joined(separator: ", ")
        let prompt = """
        [BILAN_SEMAINE]
        Score habitudes: \(Int(weeklyScore * 100))%
        Jours parfaits: \(perfectDays)/7
        Habitudes: \(habitNames.isEmpty ? "aucune" : habitNames)
        Eau moy: \(avgWater) ml/j
        Calories moy: \(avgKcal) kcal/j
        Humeur moy: \(avgMood > 0 ? String(format: "%.1f/5", avgMood) : "non renseignée")
        Instruction: Fais un bilan de semaine motivant en 2-3 phrases. Sois direct, précis, encourage sans être artificiel.
        """
        do {
            let response = try await AgentAPI.shared.chat(message: prompt, module: nil, conversationID: nil)
            aiBilan = response.reply
            cachedBilan = response.reply
            cachedBilanDate = today
        } catch {
            // Silently fall back to cached or empty
        }
        bilanLoading = false
    }

    private func statPill(_ icon: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func habitBilanRow(_ habit: Habit, isLast: Bool) -> some View {
        let count = weekDays.filter { done(habit, on: $0) }.count
        return HStack(spacing: 12) {
            Image(systemName: habit.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: UInt(habit.colorHex)))
                .frame(width: 30, height: 30)
                .background(Color(hex: UInt(habit.colorHex)).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(habit.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(done(habit, on: weekDays[i])
                              ? Color(hex: UInt(habit.colorHex))
                              : Color.secondary.opacity(0.15))
                        .frame(width: 8, height: 18)
                }
            }
            Text("\(count)/7")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(count >= 5 ? Color(hex: 0x4CC38A) : .secondary)
                .frame(width: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().padding(.leading, 58) }
        }
    }
}

// MARK: - Carte de partage du bilan (rendue en image, format story)

// Couleurs fixes (pas de tokens adaptatifs) : ImageRenderer rend hors écran,
// la carte doit être identique quel que soit le thème ou le mode clair/sombre.
private struct WeeklyShareCard: View {
    let score: Int
    let dayRatios: [Double]
    let perfectDays: Int
    let avgWater: Int
    let avgKcal: Int
    let avgMood: Double
    let message: String
    let dateRange: String

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private var scoreColor: Color {
        if score >= 80 { return Color(hex: 0x4CC38A) }
        if score >= 50 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0x9B6CF1)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("BILAN DE SEMAINE")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(2.5)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(dateRange)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.top, 52)

            Spacer()

            VStack(spacing: 14) {
                Text("\(score)%")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()

            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 8) {
                            Text(dayLetters[i])
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                            Circle()
                                .fill(dayRatios[i] >= 1 ? Color(hex: 0x4CC38A)
                                      : (dayRatios[i] > 0 ? Color(hex: 0xFF9F0A) : Color.white.opacity(0.12)))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 10) {
                    if perfectDays > 0 {
                        sharePill("star.fill", "\(perfectDays) jour\(perfectDays > 1 ? "s" : "") parfait\(perfectDays > 1 ? "s" : "")", Color(hex: 0xFF9F0A))
                    }
                    if avgWater > 0 { sharePill("drop.fill", "\(avgWater) ml/j", Color(hex: 0x3CB2E0)) }
                    if avgMood > 0 { sharePill("face.smiling", String(format: "%.1f/5", avgMood), Color(hex: 0x9B6CF1)) }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("LifeOS")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.bottom, 44)
        }
        .frame(width: 360, height: 640)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x0E1120), Color(hex: 0x1A1D33)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func sharePill(_ icon: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.07), in: Capsule())
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
