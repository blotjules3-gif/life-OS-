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

struct ShortcutsHomeView: View {
    @AppStorage("homeShortcuts") private var enabledRaw = "tabata,calories,scan,todo"
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

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let maxShortcuts = 4

    private var enabled: [ShortcutTool] {
        Array(enabledRaw.split(separator: ",").compactMap { ShortcutTool(rawValue: String($0)) }.prefix(maxShortcuts))
    }

    // MARK: données du jour
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }
    private var fastHours: Double { fasts.first(where: { $0.isActive }).map { $0.elapsed / 3600 } ?? 0 }
    private var todayMood: MoodEntry? { moods.first { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .bottom) {
                        Text(userName.isEmpty ? greeting : "\(greeting), \(userName)")
                            .font(.largeTitle.bold())
                        Spacer()
                        if todayEnergyScore > 0 {
                            energyBadge
                        }
                    }
                    .padding(.horizontal, 4)

                    if showReengage, let msg = reengageMessage {
                        reengageBanner(message: msg, suggestion: reengageSuggestion)
                    }

                    if let module = weeklyModuleSuggestion {
                        weeklyModuleCard(module)
                    }

                    shortcutsSection
                    goalsSection
                    moodSection
                }
                .padding(Theme.pad)
            }
            .background(Theme.bg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "OK" : "Modifier") { withAnimation { editing.toggle() } }
                }
            }
            .navigationDestination(for: ShortcutTool.self) { $0.destination }
            .fullScreenCover(item: $fullScreenTool) { $0.destination }
            .sheet(isPresented: $showCatalog) { catalog }
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

    // MARK: Section 1 — Raccourcis (4 max)
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Raccourcis", trailing: enabled.count < maxShortcuts && editing ? "Ajouter" : nil) {
                showCatalog = true
            }
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(enabled) { tool in tile(tool) }
                if editing && enabled.count < maxShortcuts {
                    Button { showCatalog = true } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus").font(.title2.bold())
                            Text("Ajouter").font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(.secondary.opacity(0.5)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Section 2 — Objectifs du jour (anneaux + 3 objectifs) — tout est cliquable
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Objectifs du jour")
            LazyVGrid(columns: cols, spacing: 12) {
                NavigationLink { StepsView() } label: {
                    MetricRing(value: Double(steps), goal: Double(stepGoal), label: "Pas", unit: "", color: Color(hex: 0xF1746C), icon: "figure.walk")
                }.buttonStyle(.plain)
                NavigationLink { HydrationView() } label: {
                    MetricRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", unit: "ml", color: Color(hex: 0x3CB2E0), icon: "drop.fill")
                }.buttonStyle(.plain)
                NavigationLink { FoodSearchView() } label: {
                    MetricRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Calories", unit: "kcal", color: Color(hex: 0x4CC38A), icon: "flame.fill")
                }.buttonStyle(.plain)
                NavigationLink { FastingView() } label: {
                    MetricRing(value: fastHours, goal: Double(fastTarget), label: "Jeûne", unit: "h", color: Color(hex: 0x9B6CF1), icon: "timer")
                }.buttonStyle(.plain)
            }
            VStack(spacing: 4) {
                ForEach(Array(objectives.enumerated()), id: \.element.title) { i, o in
                    NavigationLink { objectiveDestination(o.title) } label: { objectiveRow(o) }
                        .buttonStyle(.plain)
                    if i < objectives.count - 1 { Divider().padding(.leading, 47) }
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    @ViewBuilder private func objectiveDestination(_ title: String) -> some View {
        switch title {
        case "S'hydrater": HydrationView()
        case "Habitudes":  HabitTrackerView()
        default:           StepsView()
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
            Image(systemName: o.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(o.color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(o.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    Text(o.sub).font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: o.progress).tint(o.color).scaleEffect(x: 1, y: 1.1, anchor: .center)
            }
            Image(systemName: o.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18)).foregroundStyle(o.done ? AnyShapeStyle(o.color) : AnyShapeStyle(Color.secondary.opacity(0.4)))
        }
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
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
                Image(systemName: module.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(module.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouveau module cette semaine ?")
                        .font(.caption.weight(.semibold))
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(module.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let trailing {
                Button(trailing, action: action).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func tile(_ tool: ShortcutTool) -> some View {
        Button {
            if editing { return }
            if tool.isFullScreen { fullScreenTool = tool } else { path.append(tool) }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(tool.tint.opacity(0.16)).frame(width: 52, height: 52)
                    Image(systemName: tool.icon).font(.title3.weight(.semibold)).foregroundStyle(tool.tint)
                }
                Text(tool.label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button { remove(tool) } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .offset(x: 8, y: -8)
                }
            }
            .scaleEffect(editing ? 0.97 : 1)
        }
        .buttonStyle(.plain)
    }

    private var catalog: some View {
        NavigationStack {
            List {
                ForEach(ShortcutTool.allCases) { tool in
                    Button {
                        if enabled.contains(tool) { remove(tool) } else { add(tool) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tool.icon).foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(tool.tint, in: RoundedRectangle(cornerRadius: 7))
                            Text(tool.label).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: enabled.contains(tool) ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(enabled.contains(tool) ? .green : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Raccourcis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showCatalog = false } } }
        }
    }

    private func add(_ tool: ShortcutTool) {
        guard !enabled.contains(tool), enabled.count < maxShortcuts else { return }
        enabledRaw = (enabled + [tool]).map { $0.rawValue }.joined(separator: ",")
    }
    private func remove(_ tool: ShortcutTool) {
        enabledRaw = enabled.filter { $0 != tool }.map { $0.rawValue }.joined(separator: ",")
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
