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
        case .wakeup:     return SecondTab.current.label
        case .home:       return "Accueil"
        case .categories: return "Catégories"
        case .profile:    return "Profil"
        }
    }
    var icon: String {
        switch self {
        case .wakeup:     return SecondTab.current.icon
        case .home:       return "house"
        case .categories: return "square.grid.2x2"
        case .profile:    return "person.crop.circle"
        }
    }
    var iconFill: String {
        switch self {
        case .wakeup:     return SecondTab.current.iconFill
        case .home:       return "house.fill"
        case .categories: return "square.grid.2x2.fill"
        case .profile:    return "person.crop.circle.fill"
        }
    }
}

// MARK: - Dégagement pour la barre d'onglets flottante
// La barre flotte AU-DESSUS du contenu. Le safeAreaInset posé sur le conteneur ne
// traverse pas les NavigationStack internes des pages → il faut réserver l'espace
// DIRECTEMENT sur chaque vue défilante racine (accueil, réveil, profil, chaque outil).
extension View {
    /// Hauteur réservée sous le contenu = barre + sa marge + un peu d'air.
    /// Dérivée des mêmes métriques que la barre, pour qu'elles ne divergent jamais.
    static var floatingBarSpace: CGFloat {
        let m = TabBarMetrics.forWidth(UIScreen.main.bounds.width)
        return m.height + m.margin * 2
    }

    /// Réserve la place sous le contenu ET fait fondre le contenu avant la barre,
    /// pour qu'il ne se coupe jamais net derrière le verre (effet de bord iOS 26).
    @ViewBuilder
    func floatingBarClearance(_ height: CGFloat? = nil) -> some View {
        let base = safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: height ?? Self.floatingBarSpace)
        }
        if #available(iOS 26.0, *) {
            base.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            base
        }
    }
}

// MARK: - Deuxieme onglet personnalisable

/// Ce que montre le 2e onglet de la barre du bas. Le Reveil par defaut; sinon le hub
/// d'une categorie. Une valeur inconnue (ancienne version, reglage abime) retombe sur
/// le Reveil, jamais sur un onglet vide.
enum SecondTab: String, CaseIterable, Identifiable {
    case wakeup, nutrition, fitness, productivity, sleep, finance

    var id: String { rawValue }
    var category: AppCategory? { self == .wakeup ? nil : AppCategory(rawValue: rawValue) }
    var label: String {
        switch self {
        case .wakeup: return "Réveil"
        case .nutrition: return "Nutrition"
        case .fitness: return "Sport"
        case .productivity: return "Tâches"
        case .sleep: return "Sommeil"
        case .finance: return "Argent"
        }
    }
    var icon: String {
        switch self {
        case .wakeup: return "alarm"
        case .nutrition: return "fork.knife"
        case .fitness: return "figure.run"
        case .productivity: return "checklist"
        case .sleep: return "moon.stars"
        case .finance: return "creditcard"
        }
    }
    var iconFill: String {
        switch self {
        case .wakeup: return "alarm.fill"
        case .nutrition: return "fork.knife"
        case .fitness: return "figure.run"
        case .productivity: return "checklist.checked"
        case .sleep: return "moon.stars.fill"
        case .finance: return "creditcard.fill"
        }
    }
    static var current: SecondTab {
        SecondTab(rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.secondTab) ?? "") ?? .wakeup
    }
}

// MARK: - Conteneur principal

struct MainTabView: View {
    // L'onglet survit a la reconstruction de la fenetre (changement de palette,
    // voir LifeOSApp) : sinon choisir "Neutre" dans le Profil renvoyait a l'Accueil.
    @SceneStorage("mainTab") private var tab: AppTab = .home
    #if DEBUG
    @State private var catPath: [AppCategory] = MainTabView.shotModule.map { [$0] } ?? []
    #else
    @State private var catPath: [AppCategory] = []
    #endif
    @AppStorage(AppStorageKeys.secondTab) private var secondTabRaw = SecondTab.wakeup.rawValue
    @State private var showAIAssistant = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var aiPrefill: String?

    @AppStorage(AppStorageKeys.appTheme) private var appThemeRaw = "classic"
    /// Ouvrir l'assistant, c'est avoir compris le bandeau qui le presente.
    @AppStorage(AppStorageKeys.tutorialDone) private var tutorialDone = false
    private var theme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }

    #if DEBUG
    /// Le tableau de bord bureau ne s'affiche que sur Mac, et la capture d'ecran macOS
    /// est bloquee ici. Ce drapeau le fait rendre dans le simulateur iPad pour pouvoir
    /// le REGARDER au lieu de le deviner. Absent des builds Release.
    private static let forceDesktop = ProcessInfo.processInfo.arguments.contains("-desktop")

    /// `-shotTab <onglet>` et `-shotModule <categorie>` ouvrent l'app directement sur
    /// un ecran, pour les captures de la fiche App Store. Le simulateur ne sait pas
    /// cliquer, d'ou ce crochet. Absent des builds Release.
    private static var shotTab: AppTab? {
        DebugLaunchFlags.value("-shotTab").flatMap(AppTab.init(rawValue:))
    }
    private static var shotModule: AppCategory? {
        DebugLaunchFlags.value("-shotModule").flatMap(AppCategory.init(rawValue:))
    }
    #endif

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-glassGallery") { return AnyView(GlassGallery()) }
        if ProcessInfo.processInfo.arguments.contains("-powerNap") { return AnyView(NavigationStack { PowerNapView() }) }
        if DebugLaunchFlags.has("-routeSmoke") { return AnyView(RouteSmokeView()) }
        // `-shotTool <titre>` ouvre un outil precis, dans sa categorie, pour le
        // regarder sans taper le chemin a chaque passe.
        if let name = DebugLaunchFlags.value("-shotTool"),
           let tool = AppCategory.allCases.lazy.flatMap(\.tools).first(where: { $0.title == name }) {
            return AnyView(NavigationStack { tool.dest() })
        }
        #endif
        return AnyView(realBody)
    }

    @ViewBuilder private var realBody: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            #if DEBUG
            // `-desktop` force la mise en page bureau dans le simulateur iPad, meme en
            // portrait. Sans lui le drapeau existait mais n'etait plus lu nulle part.
            let isMobile = !Self.forceDesktop && (w < 720 || (w / max(h, 1) < 0.85))
            #else
            let isMobile = w < 720 || (w / max(h, 1) < 0.85)
            #endif

            Group {
                if isMobile {
                    phoneLayout
                } else {
                    ZStack {
                        HabitWidgetSyncer()
                        FitnessWidgetSyncer()
                        MoodWidgetSyncer()
                        SleepWidgetSyncer()
                        NutritionTodaySyncer()
                        MemoryWidgetSyncer()

                        MacDesktopMainView(availableWidth: w, availableHeight: h)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isMobile)
        }
    }

    @ViewBuilder private var phoneLayout: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: AnyView.floatingBarSpace)
                }
            FloatingTabBar(
                selected: $tab,
                onOpenAssistant: openAIAssistant
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(isPresented: $showAIAssistant) {
            AIAssistantView(prefill: aiPrefill)
        }
        #if DEBUG
        .onAppear {
            if let t = Self.shotTab { tab = t }
            // `-shotCoach` ouvre le coach pour la capture de la fiche App Store.
            if DebugLaunchFlags.has("-shotCoach") { showAIAssistant = true }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenAIChat)) { note in
            aiPrefill = note.userInfo?["prefill"] as? String
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
        tutorialDone = true
        // L'historique du chat est local : on ouvre toujours, l'état offline
        // est géré à l'intérieur de la vue (bandeau), pas en barrage à l'entrée.
        showAIAssistant = true
    }

    private var currentTabIndex: Int {
        switch tab {
        case .home: return 0
        case .wakeup: return 1
        case .categories: return 2
        case .profile: return 3
        }
    }

    @ViewBuilder private var content: some View {
        GeometryReader { geo in
            let w = geo.size.width

            ZStack {
                HabitWidgetSyncer()
                FitnessWidgetSyncer()
                MoodWidgetSyncer()
                SleepWidgetSyncer()
                NutritionTodaySyncer()
                MemoryWidgetSyncer()
                ThemedBubbleBackground(theme: theme)
                    .ignoresSafeArea()

                tabPane(ShortcutsHomeView(), index: 0, screenWidth: w)
                tabPane(secondPane, index: 1, screenWidth: w)
                tabPane(
                    NavigationStack(path: $catPath) {
                        BubbleCategoriesView(onSelect: { title in
                            if let cat = AppCategory(bubbleTitle: title) { catPath.append(cat) }
                        })
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: AppCategory.self) { $0.destination }
                    },
                    index: 2,
                    screenWidth: w
                )
                tabPane(ProfileView(), index: 3, screenWidth: w)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: tab)
        }
    }

    /// Deuxieme onglet choisi dans le Profil : le Reveil ou le hub d'une categorie.
    /// Le Reveil reste ouvrable depuis Sommeil quand il n'est plus un onglet.
    @ViewBuilder private var secondPane: some View {
        if let cat = (SecondTab(rawValue: secondTabRaw) ?? .wakeup).category {
            NavigationStack { cat.destination }
        } else {
            WakeUpView()
        }
    }

    /// Onglet vivant : glisse horizontalement vers la section choisie avec animation fluide
    private func tabPane(_ view: some View, index: Int, screenWidth: CGFloat) -> some View {
        let isCurrent = currentTabIndex == index
        let isAdjacent = abs(currentTabIndex - index) <= 1
        let offset = CGFloat(index - currentTabIndex) * screenWidth

        return view
            .offset(x: offset)
            .scaleEffect(isCurrent ? 1.0 : (isAdjacent ? 0.95 : 0.90))
            .opacity(isCurrent ? 1 : (isAdjacent ? 0.4 : 0))
            .allowsHitTesting(isCurrent)
    }
}

// MARK: - Syncer invisible habitudes → widget

private struct HabitWidgetSyncer: View {
    @Environment(\.modelContext) private var ctx
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
        // Un seul ecrivain de l'instantane des habitudes: HabitSync.
        HabitSync.ensureIDs(ctx)
        HabitSync.publish(ctx)
        guard let defaults = LifeOSGroup.defaults else { return }
        defaults.set(Theme.currentTheme.accentHex, forKey: "widget_accent_hex")

        // Initialisation & synchronisation des nouveaux widgets
        if defaults.string(forKey: "tabata_last_preset") == nil {
            defaults.set("Cardio HIIT", forKey: "tabata_last_preset")
            defaults.set(30, forKey: "tabata_work")
            defaults.set(15, forKey: "tabata_rest")
            defaults.set(4, forKey: "tabata_sets")
        }
        if defaults.object(forKey: "water_today_ml") == nil {
            defaults.set(1800, forKey: "water_today_ml")
            defaults.set(2500, forKey: "water_goal_ml")
        }
        if defaults.string(forKey: "gym_today_title") == nil {
            defaults.set("Pectoraux & Triceps", forKey: "gym_today_title")
            defaults.set("Développé couché · Dips · Écartés", forKey: "gym_today_focus")
            defaults.set(false, forKey: "gym_today_is_rest")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Syncer invisible fitness → shared defaults (pour le coach)

private struct FitnessWidgetSyncer: View {
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { sync() }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                sync()
            }
            .onChange(of: sets.count) { _, _ in sync() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in sync() }
    }

    private func sync() {
        guard let defaults = UserDefaults(suiteName: "group.com.chifandco.lifeos") else { return }
        let cal = Calendar.current
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) else { return }
        let recent = sets.filter { $0.date >= weekAgo }

        let daysTrained = Set(recent.map { cal.startOfDay(for: $0.date) }).count
        let totalSets = recent.count
        let totalVolumeKg = Int(recent.reduce(0.0) { $0 + $1.volume })

        let summary = "Séances muscu 7 derniers jours: \(daysTrained) jour\(daysTrained > 1 ? "s" : ""), \(totalSets) séries, \(totalVolumeKg) kg de volume"
        defaults.set(summary, forKey: "fitness_summary_7d")

        // Top 5 exos par nombre de séries
        var counts: [String: Int] = [:]
        for s in recent where !s.exercise.isEmpty {
            counts[s.exercise, default: 0] += 1
        }
        let topExos = counts.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key) (\($0.value)s)" }
            .joined(separator: ", ")
        defaults.set(topExos, forKey: "fitness_last_exercises")

        // PR récent (1RM estimé max sur les 30 derniers jours)
        guard let monthAgo = cal.date(byAdding: .day, value: -30, to: .now) else { return }
        let recent30 = sets.filter { $0.date >= monthAgo }
        if let best = recent30.max(by: { $0.estimated1RM < $1.estimated1RM }), !best.exercise.isEmpty {
            let pr = String(format: "%@ 1RM ≈ %.0f kg (%.1fkg × %d reps)",
                            best.exercise, best.estimated1RM, best.weightKg, best.reps)
            defaults.set(pr, forKey: "fitness_top_lift")
        } else {
            defaults.set("", forKey: "fitness_top_lift")
        }
    }
}

// MARK: - Barre flottante : [2 onglets] [assistant] [2 onglets]

// MARK: - Géométrie de la barre, adaptée à la taille de l'écran
//
// Règle : le vide à GAUCHE, en BAS et à DROITE doit être EXACTEMENT le même.
// La barre flotte donc depuis le vrai bord de l'écran, pas depuis la safe area.
// Le conteneur (MainTabView) fait déjà `.ignoresSafeArea(.container, edges: .bottom)`,
// donc `padding(.bottom, margin)` part bien du bord physique.
//
// L'indicateur d'accueil (home indicator) vit à ~8pt du bas et fait ~5pt de haut.
// Avec une marge >= 14pt la barre passe toujours au-dessus, sans jamais le toucher.
struct TabBarMetrics {
    let margin: CGFloat        // gauche == bas == droite
    let height: CGFloat
    let icon: CGFloat
    let label: CGFloat

    /// Un seul point de vérité : tout dérive de la largeur de l'écran.
    static func forWidth(_ w: CGFloat) -> TabBarMetrics {
        // ~4.5% de la largeur, borné pour rester sain du SE au Pro Max.
        let m = min(22, max(14, (w * 0.045).rounded()))
        switch w {
        case ..<380:            // iPhone SE, 13 mini
            return .init(margin: m, height: 56, icon: 19, label: 10)
        case 380..<420:         // iPhone 15 / 16 / 17
            return .init(margin: m, height: 60, icon: 20, label: 10.5)
        default:                // Plus, Pro Max
            return .init(margin: m, height: 64, icon: 21, label: 11)
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var onOpenAssistant: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var serverStatus = ServerStatusMonitor.shared
    @State private var showServerConfig = false
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppStorageKeys.appTheme) private var themeRaw = "classic"
    /// Lu ici pour redessiner le libelle et l'icone du 2e onglet quand il change.
    @AppStorage(AppStorageKeys.secondTab) private var secondTabRaw = SecondTab.wakeup.rawValue

    private let tabs: [AppTab] = [.home, .wakeup, .categories, .profile]

    var body: some View {
        GeometryReader { geo in
            let m = TabBarMetrics.forWidth(geo.size.width)
            let horizontalMargin = max(24, m.margin + 16)
            let barWidth = geo.size.width - (horizontalMargin * 2)

            HStack(spacing: 4) {
                ForEach(tabs) { t in
                    tabBtn(t, m: m)
                }
                assistantBtn(m: m)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: m.height + 4)
            .raisedSurface(Capsule(), .floating)
            .padding(.horizontal, horizontalMargin)
            .padding(.bottom, m.margin + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: selected)
            .animation(.easeInOut(duration: 0.3), value: serverStatus.isOnline)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        let usefulWidth = barWidth - 16
                        guard usefulWidth > 0 else { return }
                        let x = value.location.x - 8
                        let segW = usefulWidth / 5.0
                        let rawIndex = Int(x / segW)
                        let idx = max(0, min(rawIndex, 4))
                        if idx < tabs.count {
                            let target = tabs[idx]
                            if selected != target {
                                Haptics.soft()
                                withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.28)) {
                                    selected = target
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        let usefulWidth = barWidth - 16
                        guard usefulWidth > 0 else { return }
                        let x = value.location.x - 8
                        let segW = usefulWidth / 5.0
                        let rawIndex = Int(x / segW)
                        let idx = max(0, min(rawIndex, 4))
                        if idx == 4 {
                            Haptics.tap()
                            serverStatus.pingNow()
                            onOpenAssistant()
                        }
                    }
            )
        }
        .frame(height: TabBarMetrics.forWidth(UIScreen.main.bounds.width).height
                     + TabBarMetrics.forWidth(UIScreen.main.bounds.width).margin + 12)
        #if DEBUG
        .sheet(isPresented: $showServerConfig) {
            ServerConfigView {
                showServerConfig = false
                serverStatus.pingNow()
            }
        }
        #endif
    }

    /// L'assistant devient le 5e onglet intégré dans l'îlot
    private func assistantBtn(m: TabBarMetrics) -> some View {
        Button {
            Haptics.tap()
            serverStatus.pingNow()
            onOpenAssistant()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Image(systemName: "infinity")
                        .font(.system(size: m.icon, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.60))
                    if serverStatus.isOnline != nil {
                        Circle()
                            .fill(serverStatus.dotColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 11, y: -8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text("Assistant")
                    .font(AppFont.body(size: m.label, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.60))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(LifeOSPressStyle(scale: 0.92, opacity: 0.82))
        .accessibilityLabel("Assistant")
    }

    private func tabBtn(_ t: AppTab, m: TabBarMetrics) -> some View {
        let isOn = selected == t
        return Button {
            let anim: Animation? = reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.28)
            withAnimation(anim) { selected = t }
            if t == .profile { Haptics.medium() } else { Haptics.tap() }
        } label: {
            ZStack {
                // Pastille dépolie Apple Preview enveloppant l'onglet actif (#E8E8ED)
                if isOn {
                    Capsule()
                        .fill(scheme == .dark ? Color.white.opacity(0.14) : Color(hex: 0xE8E8ED))
                        .matchedGeometryEffect(id: "activeTabPill", in: ns)
                }

                VStack(spacing: 3) {
                    Image(systemName: isOn ? t.iconFill : t.icon)
                        .font(.system(size: m.icon, weight: isOn ? .bold : .medium))
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: isOn)
                    Text(t.label)
                        .font(AppFont.body(size: m.label, weight: isOn ? .bold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? Color.primary : Color.primary.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(LifeOSPressStyle(scale: 0.92, opacity: 0.82))
        .accessibilityLabel(t.label)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Tableau de bord du jour

struct HomeDashboardContent: View {
    @Query private var waters: [WaterEntry]
    @Query private var foods: [FoodEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @Query private var moods: [MoodEntry]

    @AppStorage(AppStorageKeys.stepGoal) private var stepGoal = 10000
    @AppStorage(AppStorageKeys.waterGoal) private var waterGoal = 2500
    @AppStorage(AppStorageKeys.kcalGoal) private var kcalGoal = 2200
    @AppStorage(AppStorageKeys.fastTarget) private var fastTarget = 16

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
                            .accessibilityLabel("Graphique habitudes 7 derniers jours")
                            .accessibilityValue(weekChartA11ySummary)
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
                            .accessibilityLabel("Graphique humeur 14 derniers jours")
                            .accessibilityValue(moodChartA11ySummary)
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
                // Lecture silencieuse (pas de pop-up Santé au lancement).
                async let s = HealthService.shared.cachedStepsToday()
                async let w = HealthService.shared.workoutsThisWeek()
                steps = await s
                weekWorkouts = await w
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

    // A11y — descriptions vocalisées pour les Charts (VoiceOver n'annonce sinon
    // rien d'utile sur un BarMark/LineMark).
    private var weekChartA11ySummary: String {
        let total = weekData.reduce(0) { $0 + $1.1 }
        let best = weekData.max(by: { $0.1 < $1.1 })
        let bestDay = best.flatMap {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "EEEE"
            return "\(fmt.string(from: $0.0)) avec \($0.1)"
        } ?? "aucun"
        return "\(total) habitudes validées sur 7 jours. Meilleur jour : \(bestDay)."
    }

    private var moodChartA11ySummary: String {
        guard !recentMoods.isEmpty else { return "Aucune humeur récente." }
        let avg = Double(recentMoods.reduce(0) { $0 + $1.score }) / Double(recentMoods.count)
        return "\(recentMoods.count) entrées humeur, moyenne \(String(format: "%.1f", avg)) sur 5."
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
        let pct = goal > 0 ? Int((value / goal * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(value)) / \(Int(goal))")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.spring(duration: 0.4), value: value)
            }
            ProgressView(value: min(value, goal), total: max(1, goal))
                .tint(color)
                .animation(.spring(duration: 0.6, bounce: 0.1), value: value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) — \(Int(value)) sur \(Int(goal)), \(pct) pourcent")
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

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Dynamic Type — l'anneau et le chiffre grossissent avec la taille système
    // pour rester lisibles en Larger Text sans clipping.
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 84
    @ScaledMetric(relativeTo: .footnote) private var deltaSize: CGFloat = 10

    private var deltaLabel: String? {
        guard let d = delta, d != 0 else { return nil }
        return d > 0 ? "+\(d)" : "\(d)"
    }
    private var deltaColor: Color { (delta ?? 0) >= 0 ? Theme.success : Theme.danger }

    private var accessibilitySummary: String {
        let progress = goal > 0 ? "\(Int(value)) sur \(Int(goal)) \(unit)" : "\(Int(value)) \(unit)"
        if let d = deltaLabel { return "\(label): \(progress), variation \(d)" }
        return "\(label): \(progress)"
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: appeared && goal > 0 ? value / goal : 0, lineWidth: 9, tint: color)
                    .frame(width: ringSize, height: ringSize)
                VStack(spacing: 1) {
                    Image(systemName: icon).font(.caption).foregroundStyle(color)
                    Text("\(Int(value))")
                        .font(.title3.bold().monospacedDigit())
                        .contentTransition(.numericText(value: value))
                        .animation(.spring(duration: 0.4), value: value)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .onAppear {
                if reduceMotion { appeared = true }
                else { withAnimation(.spring(duration: 0.8, bounce: 0.12).delay(0.1)) { appeared = true } }
            }
            VStack(spacing: 2) {
                Text(label).font(.subheadline.weight(.medium))
                Text(goal > 0 ? "/ \(Int(goal)) \(unit)" : "").font(.caption2).foregroundStyle(.secondary)
                if let dl = deltaLabel {
                    Text(dl)
                        .font(.system(size: deltaSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(deltaColor)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .liquidGlassCard(cornerRadius: Theme.radius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
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
