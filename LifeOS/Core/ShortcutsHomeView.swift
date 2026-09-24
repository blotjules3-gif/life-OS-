import SwiftUI
import UniformTypeIdentifiers
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
    @AppStorage(AppStorageKeys.homeShortcuts) private var enabledRaw = "tabata,calories,scan,todo"
    @AppStorage(AppStorageKeys.homeMetrics) private var metricsRaw = "steps,water,calories,fasting"
    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.stepGoal) private var stepGoal = 10000
    @AppStorage(AppStorageKeys.waterGoal) private var waterGoal = 2500
    @AppStorage(AppStorageKeys.kcalGoal) private var kcalGoal = 2200
    @AppStorage(AppStorageKeys.fastTarget) private var fastTarget = 16
    @AppStorage(AppStorageKeys.todayEnergyScore) private var todayEnergyScore = 0
    @AppStorage(AppStorageKeys.todayEnergyLabel) private var todayEnergyLabel = ""
    @AppStorage(AppStorageKeys.recommendedModules) private var recommendedModulesRaw = ""
    @AppStorage(AppStorageKeys.onboardingDone) private var onboardingDone = false
    // Une seule demande Sante, jamais rejouee a chaque ouverture.
    @AppStorage("healthAskedOnHome") private var healthAsked = false
    @State private var reengageMessage: String?
    @State private var reengageSuggestion: String?
    @State private var showReengage = true
    @State private var weeklyModuleSuggestion: AppCategory?

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var foodsYesterday: [FoodEntry]
    @Query private var watersYesterday: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @Query(sort: \TodoItem.due) private var todos: [TodoItem]
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
    @State private var newTask = ""
    @State private var showAllTasks = false
    @State private var showHabits = false
    @FocusState private var taskFieldFocused: Bool
    private var enabledMetrics: [HomeMetric] {
        HomeOrder.parse(metricsRaw, valid: Set(HomeMetric.allCases.map(\.rawValue)))
            .compactMap(HomeMetric.init(rawValue:))
    }

    @State private var steps = 0
    @State private var stepsYesterday = 0

    private var kcalYesterday: Int  { foodsYesterday.caloriesToday }
    private var waterYesterday: Int { watersYesterday.mlToday }
    @State private var showBilan = false
    @State private var fullScreenTool: ShortcutTool?
    @AppStorage(AppStorageKeys.tutorialDone) private var tutorialDone = false
    @State private var showTutorial = false
    @State private var editingShortcuts = false
    /// Ordre des blocs de l'accueil, voir HomeLayout.
    @AppStorage(HomeLayout.storageKey) private var layoutRaw = ""
    @State private var editingHome = false
    @State private var draggedWidget: HomeWidget?
    @State private var showWidgetGallery = false
    private var layout: HomeLayout { HomeLayout.parse(layoutRaw) }
    @State private var homeAppeared = false

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var activeShortcuts: [ShortcutTool] {
        HomeOrder.parse(enabledRaw, valid: Set(ShortcutTool.allCases.map(\.rawValue)))
            .compactMap(ShortcutTool.init(rawValue:))
    }

    // MARK: données du jour (foods/waters already filtered to today by @Query predicate)
    private var kcalToday: Int  { foods.caloriesToday }
    private var waterToday: Int { waters.mlToday }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }
    private var fastHours: Double { fasts.first(where: { $0.isActive }).map { $0.elapsed / 3600 } ?? 0 }
    /// Relit les pas. `force` saute le cache de 5 minutes, pour que revenir
    /// sur l'app apres une marche montre tout de suite le bon chiffre.
    private func refreshSteps(force: Bool = false) async {
        steps = force ? await HealthService.shared.stepsToday()
                      : await HealthService.shared.cachedStepsToday()
        stepsYesterday = await HealthService.shared.stepsYesterday()
    }

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
                .background(Color(hex: 0xFF9F0A).opacity(0.20),
                             in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Ta journée commence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Voilà ce qui t'attend aujourd'hui.")
                    .font(.footnote)
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
                        .background(chip.color.opacity(0.26),
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
                    if editingHome {
                        HomeEditBar(hiddenCount: layout.hidden.count,
                                    onAdd: { showWidgetGallery = true },
                                    onDone: exitHomeEditing)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(userName.isEmpty ? greeting : "\(greeting), \(userName)")
                                    .font(AppFont.sans(size: 34, weight: .black))
                                    .textCase(.uppercase)
                                    .kerning(-0.8)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Text("Gérez votre journée, vos habitudes et vos objectifs.")
                                    .font(AppFont.body(size: 14, weight: .regular))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if todayEnergyScore > 0 {
                                energyBadge
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .staggered(0, appeared: homeAppeared)

                    // Boutons capsules style Apple Aperçu ("Nouveau document" / "Scanner")
                    VStack(spacing: 12) {
                        Button {
                            showAllTasks = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 17, weight: .bold))
                                Text("Nouvelle tâche")
                                    .font(AppFont.heading(size: 16, weight: .bold))
                            }
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .applePreviewPill(height: 52)

                        Button {
                            editingShortcuts = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Personnaliser les raccourcis")
                                    .font(AppFont.heading(size: 16, weight: .bold))
                            }
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .applePreviewPill(height: 52)
                    }
                    .padding(.horizontal, 2)
                    .staggered(1, appeared: homeAppeared)

                    // Bandeaux de contexte: ils apparaissent quand il y a
                    // quelque chose a dire et ne se deplacent pas. Un message
                    // du moment n'a pas de place fixe a choisir.
                    if showReengage, let msg = reengageMessage {
                        reengageBanner(message: msg, suggestion: reengageSuggestion)
                    }
                    if let module = weeklyModuleSuggestion {
                        weeklyModuleCard(module)
                    }
                    if isMorningEmpty {
                        morningContextCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Les blocs, dans l'ordre choisi par l'utilisateur.
                    ForEach(Array(shownWidgets.enumerated()), id: \.element) { index, widget in
                        homeWidget(widget)
                            .staggered(min(index + 1, 5), appeared: homeAppeared)
                            .modifier(HomeWidgetChrome(
                                widget: widget,
                                editing: editingHome,
                                isDragged: draggedWidget == widget,
                                onRemove: { updateLayout { $0.hide(widget) } },
                                onShift: { d in updateLayout { $0.shift(widget, by: d) } },
                                onDragStart: { draggedWidget = widget }))
                            .onDrop(of: [.text], delegate: HomeDropDelegate(
                                target: widget, raw: $layoutRaw, dragged: $draggedWidget))
                            // Appui long pour entrer en edition, comme sur iOS.
                            // Pas sur les taches: leurs lignes ont deja un menu
                            // a l'appui long, les deux se marcheraient dessus.
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in enterHomeEditing() },
                                including: widget == .tasks || editingHome ? .subviews : .all)
                    }

                    if layout.visible.isEmpty {
                        Text("Ton accueil est vide. Touche « Modifier l'accueil » pour remettre des blocs.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }

                    // Comme en bas de la vue Aujourd'hui d'iOS: un bouton
                    // visible, pour qui ne devine pas l'appui long.
                    if !editingHome {
                        Button { enterHomeEditing() } label: {
                            Text("Modifier l'accueil")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(Theme.pad)
                .onDrop(of: [.text], delegate: HomeDropCleanup(dragged: $draggedWidget))
            }
            .floatingBarClearance()       // le dernier bloc ne passe pas sous la barre flottante
            .sheet(isPresented: $showWidgetGallery) { HomeWidgetGallery(raw: $layoutRaw) }
            // Changer d'onglet quitte l'edition: revenir sur un accueil qui
            // tremble encore, sans savoir pourquoi, serait deroutant.
            .onDisappear { exitHomeEditing() }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBG)   // verre global : wallpaper dépoli en thème Verre
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHabits) {
                NavigationStack { HabitTrackerView() }
            }
            .sheet(isPresented: $showAllTasks) {
                NavigationStack { TodoView() }
            }
            .sheet(isPresented: $editingShortcuts) {
                HomeOrderEditor(
                    title: "Raccourcis",
                    options: ShortcutTool.allCases.map {
                        HomeOrderOption(id: $0.rawValue, label: $0.label, icon: $0.icon, tint: $0.tint)
                    },
                    raw: $enabledRaw)
            }
            .sheet(isPresented: $editingMetrics) {
                HomeOrderEditor(
                    title: "Objectifs du jour",
                    options: HomeMetric.allCases.map {
                        HomeOrderOption(id: $0.rawValue, label: $0.label, icon: $0.icon, tint: $0.color)
                    },
                    raw: $metricsRaw)
            }
            .task {
                // Santé : on demande UNE fois, et seulement une fois l'onboarding
                // fini. Avant, la lecture etait totalement silencieuse pour eviter
                // la double pop-up au lancement, mais du coup personne ne demandait
                // jamais l'acces : les pas restaient a zero tant qu'on n'allait pas
                // dans Profil. Ici on est apres l'onboarding, l'ecran est visible,
                // et la demande a un sens.
                if onboardingDone && !healthAsked {
                    healthAsked = true
                    _ = await HealthService.shared.requestAuthorization()
                }
                await refreshSteps()
                reengageMessage    = EngagementTracker.shared.reengagementMessage
                reengageSuggestion = EngagementTracker.shared.simplificationSuggestion
                weeklyModuleSuggestion = WeeklyModuleSuggester.shared.currentSuggestion()
                WeeklyModuleSuggester.shared.scheduleWeeklyNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Au retour au premier plan on relit, sans re-demander l'acces.
                Task { await refreshSteps() }
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
                // Le fondu en cascade doit commencer APRES l'ecran d'ouverture.
                // L'accueil est construit pendant que le logo est encore
                // affiche, donc l'animation se jouait derriere lui et on
                // decouvrait un ecran deja entierement en place.
                if !homeAppeared {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        homeAppeared = true
                    }
                }
                if !tutorialDone {
                    withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(1.2)) { showTutorial = true }
                }
            }
        }
    }

    private var tutorialOverlay: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "infinity")
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
                    .foregroundStyle(Theme.onAccent)
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
            sectionHeader("Raccourcis", trailing: "Éditer") { editingShortcuts = true }
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
            // Pastille de couleur PLEINE, pas un lavis a 20 %. C'est la tuile
            // des Reglages d'iOS: la couleur porte, le glyphe reste lisible.
            Image(systemName: tool.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tool.tint.readableInk)
                .frame(width: 44, height: 44)
                .background(tool.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: tool.tint.opacity(0.35), radius: 6, y: 3)
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

    private var todayHabits: [Habit] {
        habits.filter { !$0.isArchived && !$0.isPending && $0.isActive(on: .now) }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Gérer" ouvre le suivi complet: créer et configurer ses habitudes
            sectionHeader("Habitudes", trailing: "Gérer") { showHabits = true }
            if todayHabits.isEmpty {
                Button {
                    Haptics.tap()
                    showHabits = true
                } label: {
                    HStack(spacing: 13) {
                        IconBadge(icon: "infinity", tint: Color(hex: 0x9B6CF1), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Créer une habitude")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("Personnalise tes habitudes du jour")
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
                VStack(spacing: 8) {
                    ForEach(todayHabits) { habit in
                        habitRow(habit)
                    }
                }
            }
        }
    }

    private func habitStreak(_ habit: Habit) -> Int {
        let cal = Calendar.current
        var streak = 0
        var date = cal.startOfDay(for: .now)
        while habit.completions.contains(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    private func habitRow(_ habit: Habit) -> some View {
        let cal = Calendar.current
        let done = habit.completions.contains { cal.isDateInToday($0.date) }
        let color = Color(hex: UInt(habit.colorHex))
        let streak = habitStreak(habit)

        return Button {
            withAnimation(.spring(duration: 0.32, bounce: 0.25)) {
                toggleHabit(habit)
            }
            let gen = UIImpactFeedbackGenerator(style: done ? .light : .medium)
            gen.impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(done ? color : color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: done ? "checkmark" : habit.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(done ? .white : color)
                        .scaleEffect(done ? 1.0 : 0.92)
                }
                .animation(.spring(duration: 0.35, bounce: 0.3), value: done)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .strikethrough(done, color: .secondary)
                        .lineLimit(1)
                    if habit.scheduledHour > 0 || habit.scheduledMinute > 0 {
                        Text(String(format: "%02dh%02d", habit.scheduledHour, habit.scheduledMinute))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(streak)j")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(Color(hex: 0xE0A23C))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xE0A23C).opacity(0.20), in: Capsule())
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(LifeOSPressStyle())
        .accessibilityLabel(done ? "\(habit.name) — validée aujourd'hui" : "Valider \(habit.name)")
    }

    private func triggerStreakActivity(for habit: Habit) {
        guard #available(iOS 16.1, *) else { return }
        let cal = Calendar.current
        let days = Set(habit.completions.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: .now)
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        StreakActivityManager.startIfMilestone(
            habitName: habit.name, iconName: habit.icon,
            streakDays: streak, doneToday: true
        )
    }

    private func toggleHabit(_ habit: Habit) {
        let wasDone = habit.completions.contains { Calendar.current.isDateInToday($0.date) }
        if wasDone {
            if let completion = habit.completions.first(where: { Calendar.current.isDateInToday($0.date) }) {
                ctx.delete(completion)
            }
        } else {
            let c = HabitCompletion(date: .now)
            habit.completions.append(c)
        }
        do { try ctx.save() } catch { AppLog.data.error("toggleHabit failed: \(error.localizedDescription, privacy: .public)") }
        Haptics.soft()
        if !wasDone { triggerStreakActivity(for: habit) }
    }

    // MARK: Section 1b — Recap hebdo

    private var weeklyRecapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Cette semaine")
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(weeklyScore * 100))%")
                            .font(.system(size: 42, weight: .black, design: .monospaced))
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
                            .background(Color(hex: UInt(best.colorHex)).opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    // MARK: Section 1bis — Taches a faire (ponctuelles, pas des habitudes)
    //
    // Une habitude revient tous les jours, une tache se fait UNE fois et
    // disparait. Les deux vivaient au meme endroit, donc la liste d'habitudes
    // se remplissait de choses ponctuelles qui cassaient les series.

    /// Taches pas encore faites, les plus urgentes d'abord, 5 au maximum sur
    /// l'accueil: au dela ce n'est plus un rappel, c'est une deuxieme appli.
    private var openTasks: [TodoItem] {
        todos.filter { !$0.done && $0.applies(to: .now) }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (nil, _?):    return false   // sans date = moins urgent
                case (_?, nil):    return true
                default:           return false
                }
            }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Tâches", trailing: "Tout voir") { showAllTasks = true }

            VStack(spacing: 8) {
                ForEach(openTasks.prefix(5), id: \.persistentModelID) { task in
                    taskRow(task)
                }

                // Ajout sur place
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppCategory.productivity.tint)
                    TextField("Ajouter une tâche", text: $newTask)
                        .focused($taskFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(addTask)
                    if !newTask.isEmpty {
                        Button("Ajouter", action: addTask)
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
            }
        }
    }

    private func taskRow(_ task: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    task.done = true
                    saveTasks("cocher")
                }
                Haptics.soft()
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.done ? Color.green : (task.priority >= 2 ? Color(hex: 0xF1746C)
                                   : task.priority == 1 ? Color(hex: 0xF1A33C)
                                   : Theme.textSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terminer \(task.title)")

            VStack(alignment: .leading, spacing: 2) {
                TextField("Tâche", text: Binding(
                    get: { task.title },
                    set: { task.title = $0 }
                ), axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .strikethrough(task.done, color: .secondary)
                .foregroundStyle(task.done ? .secondary : .primary)
                .lineLimit(1...3)
                .onSubmit { saveTasks("renommer") }

                if !task.project.isEmpty && task.project != "Perso" {
                    Text(task.project)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let due = task.due {
                if due < Date.now && !task.done {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                        Text(due, format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                        Text("En retard")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(due, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.bg2, in: Capsule())
                }
            }
            if !task.recurringDaysRaw.isEmpty {
                Image(systemName: "repeat")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        // Appui long, pas balayage: swipeActions n'existe QUE dans une List,
        // et cette section est une VStack dans un ScrollView. Le geste aurait
        // ete inerte, sans la moindre erreur pour le signaler.
        .contextMenu {
            Button { task.priority = task.priority >= 2 ? 0 : task.priority + 1; saveTasks("priorité") } label: {
                Label("Changer la priorité", systemImage: "flag")
            }
            Button(role: .destructive) {
                ctx.delete(task); saveTasks("supprimer")
            } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func addTask() {
        let t = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        ctx.insert(TodoItem(title: t))
        newTask = ""
        saveTasks("ajouter")
        Haptics.tap()
    }

    /// Un echec d'ecriture doit se voir dans les logs, pas disparaitre: sinon
    /// la tache semble ajoutee et revient morte au prochain lancement.
    private func saveTasks(_ what: String) {
        do { try ctx.save() }
        catch { AppLog.data.error("tache \(what, privacy: .public) echouee: \(error.localizedDescription, privacy: .public)") }
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
                            MetricRing(value: v.value, goal: v.goal, label: m.label, unit: m.unit, color: m.color, icon: m.icon,
                                       delta: metricDelta(m))
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

    private func metricDelta(_ m: HomeMetric) -> Int? {
        switch m {
        case .steps:    return stepsYesterday > 0 ? steps - stepsYesterday : nil
        case .water:    return waterYesterday > 0 ? waterToday - waterYesterday : nil
        case .calories: return kcalYesterday > 0 ? kcalToday - kcalYesterday : nil
        default:        return nil
        }
    }

    @ViewBuilder private func metricDestination(_ m: HomeMetric) -> some View {
        switch m {
        case .steps:    StepsView()
        case .water:    HydrationView()
        // Appareil photo direct: on tape Calories parce qu'on a une assiette
        // devant soi, pas pour fouiller une liste d'aliments. La recherche
        // reste accessible depuis l'ecran photo.
        case .calories: PhotoCalorieView(autoOpenCamera: true)
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
                ProgressView(value: o.progress).tint(Color.accentColor).scaleEffect(x: 1, y: 1.1, anchor: .center)
                    .animation(.spring(duration: 0.6, bounce: 0.1), value: o.progress)
            }
            Image(systemName: o.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18)).foregroundStyle(o.done ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(duration: 0.35, bounce: 0.4), value: o.done)
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
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
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
            Color(hex: 0xFF9F0A).opacity(0.16),
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
                .font(AppFont.heading(size: 28, weight: .black))
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText())
            Text(todayEnergyLabel.isEmpty ? "ÉNERGIE" : todayEnergyLabel)
                .font(AppFont.body(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(scoreColor.opacity(0.8))
        }
    }

    private func sectionHeader(_ title: String, trailing: String? = nil, action: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(AppFont.heading(size: 20, weight: .black))
                .textCase(.uppercase)
                .kerning(-0.3)
                .foregroundStyle(Color.primary)
            Spacer()
            if let trailing {
                Button(action: action) {
                    HStack(spacing: 5) {
                        Text(trailing)
                            .font(AppFont.body(size: 11, weight: .bold))
                            .textCase(.uppercase)
                            .kerning(0.5)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .applePreviewIsland()
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Blocs reordonnables

    @ViewBuilder
    private func homeWidget(_ w: HomeWidget) -> some View {
        switch w {
        case .score:
            DailyScoreRing()   // score unique du jour (melange tous les objectifs)
        case .shortcuts:
            if hasContent(w) { shortcutsSection } else { HomeWidgetPlaceholder(widget: w) }
        case .coach:
            LifeBrainCard()
                .padding(.horizontal, -Theme.pad)   // pleine largeur
        case .agenda:
            TodayAgendaSection()
                .padding(.horizontal, -Theme.pad)   // pleine largeur (compense le padding parent)
        case .habits:
            habitsSection.scrollFade()
        case .tasks:
            tasksSection.scrollFade()
        case .weekRecap:
            if hasContent(w) { weeklyRecapSection.scrollFade() } else { HomeWidgetPlaceholder(widget: w) }
        case .goals:
            goalsSection.scrollFade()
        }
    }

    /// Les blocs qui n'ont rien a montrer sont ecartes AVANT la liste, pas
    /// rendus vides dedans: un bloc vide garde sa part d'espacement et
    /// laisserait un trou. En edition ils restent, avec un bloc temoin, pour
    /// pouvoir etre deplaces ou retires.
    private var shownWidgets: [HomeWidget] {
        layout.visible.filter { editingHome || hasContent($0) }
    }

    private func hasContent(_ w: HomeWidget) -> Bool {
        switch w {
        case .shortcuts: return !activeShortcuts.isEmpty
        case .weekRecap: return !activeHabits.isEmpty
        default:         return true
        }
    }

    private func updateLayout(_ change: (inout HomeLayout) -> Void) {
        var l = HomeLayout.parse(layoutRaw)
        change(&l)
        withAnimation(.spring(duration: 0.3)) { layoutRaw = l.raw }
        Haptics.tap()
    }

    private func enterHomeEditing() {
        guard !editingHome else { return }
        Haptics.success()
        withAnimation(.spring(duration: 0.3)) { editingHome = true }
    }

    private func exitHomeEditing() {
        draggedWidget = nil
        guard editingHome else { return }
        withAnimation(.spring(duration: 0.3)) { editingHome = false }
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


// MARK: - WeeklyBilanView + WeeklyShareCard → extraits dans LifeOS/Core/WeeklyBilanView.swift


// MARK: - Éditeur de l'accueil (raccourcis et anneaux)

/// Une ligne proposee dans l'editeur, quel que soit ce qu'elle represente.
struct HomeOrderOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let tint: Color
}

/// Choisir ET ordonner ce qui s'affiche sur l'accueil.
///
/// Avant, la seule facon de changer l'ordre etait de tout decocher puis de
/// recocher dans l'ordre voulu, comme l'indiquait la note en bas de liste.
/// Maintenant: ce qui est affiche est en haut, dans l'ordre de l'accueil, et
/// se deplace a la poignee. Le reste est en dessous et s'ajoute a la fin.
struct HomeOrderEditor: View {
    let title: String
    let options: [HomeOrderOption]
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss

    private var chosen: [HomeOrderOption] {
        let byId = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        return HomeOrder.parse(raw, valid: Set(byId.keys)).compactMap { byId[$0] }
    }
    private var available: [HomeOrderOption] {
        let on = Set(chosen.map(\.id))
        return options.filter { !on.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if chosen.isEmpty {
                        Text("Rien d'affiché. Ajoute un élément ci-dessous.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(chosen) { o in row(o) }
                        .onMove(perform: move)
                        .onDelete(perform: remove)
                } header: {
                    Text("Sur l'accueil")
                } footer: {
                    Text("Glisse la poignée pour changer l'ordre. L'accueil suit cet ordre.")
                }

                if !available.isEmpty {
                    Section("Ajouter") {
                        ForEach(available) { o in
                            HStack {
                                row(o)
                                Button { add(o) } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3).foregroundStyle(.green)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Ajouter \(o.label)")
                            }
                            .moveDisabled(true)
                            .deleteDisabled(true)
                        }
                    }
                }
            }
            // Mode edition permanent: les poignees et les boutons de retrait
            // sont visibles tout de suite, sans chercher un bouton Modifier.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func row(_ o: HomeOrderOption) -> some View {
        HStack(spacing: 14) {
            Image(systemName: o.icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(o.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(o.label).foregroundStyle(.primary)
            Spacer()
        }
    }

    private func save(_ ids: [String]) {
        raw = ids.joined(separator: ",")
        Haptics.soft()
    }
    private func move(from: IndexSet, to: Int) {
        var ids = chosen.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        save(ids)
    }
    private func remove(at offsets: IndexSet) {
        var ids = chosen.map(\.id)
        ids.remove(atOffsets: offsets)
        save(ids)
    }
    private func add(_ o: HomeOrderOption) {
        save(chosen.map(\.id) + [o.id])
    }
}
