import SwiftUI
import SwiftData
import Charts

// MARK: - Sections de Navigation Desktop macOS

enum DesktopNavSection: Hashable, Identifiable {
    case dashboard
    case habits
    case wakeup
    case assistant
    case tabata
    case category(AppCategory)
    case allCategories
    case profile

    var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .habits: return "habits"
        case .wakeup: return "wakeup"
        case .assistant: return "assistant"
        case .tabata: return "tabata"
        case .category(let cat): return "category_\(cat.rawValue)"
        case .allCategories: return "allCategories"
        case .profile: return "profile"
        }
    }

    var label: String {
        switch self {
        case .dashboard: return "Tableau de bord"
        case .habits: return "Habitudes & Routines"
        case .wakeup: return "Réveil & Sommeil"
        case .assistant: return "Ton coach"
        case .tabata: return "HIIT & Tabata"
        case .category(let cat): return cat.title
        case .allCategories: return "Toutes les catégories"
        case .profile: return "Profil & Paramètres"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .habits: return "checkmark.seal.fill"
        case .wakeup: return "alarm.fill"
        case .assistant: return "sparkles"
        case .tabata: return "timer"
        case .category(let cat): return cat.icon
        case .allCategories: return "square.grid.2x2.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var color: Color {
        Color.primary
    }
}

// MARK: - Conteneur Principal macOS Desktop

struct MacDesktopMainView: View {
    var availableWidth: CGFloat? = nil
    var availableHeight: CGFloat? = nil

    @State private var sidebarCollapsed = false
    @State private var selection: DesktopNavSection? = .dashboard
    @State private var routedTool: CategoryTool?
    @Namespace private var sidebarNamespace
    @State private var showNewHabitModal = false
    @State private var showAssistantSheet = false
    @State private var showTabataFullScreen = false
    @State private var showOrderSheet = false
    @State private var assistantPrefill: String?

    @ObservedObject private var categoryOrderManager = CategoryOrderManager.shared

    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.userDisplayName) private var userDisplayName = ""
    @AppStorage(AppStorageKeys.userEmail) private var userEmail = ""
    @AppStorage(AppStorageKeys.appTheme) private var appThemeRaw = "system"

    private var displayName: String {
        if !userDisplayName.isEmpty { return userDisplayName }
        if !userName.isEmpty { return userName }
        if !userEmail.isEmpty { return userEmail.components(separatedBy: "@").first?.capitalized ?? "Utilisateur" }
        return "Theo"
    }

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                sidebarContent
                    .frame(width: 260)
                    .background(Theme.bg.ignoresSafeArea())
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .ignoresSafeArea()
            }

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showNewHabitModal) {
            NavigationStack {
                NewHabitQuickSheet()
            }
        }
        .sheet(isPresented: $showOrderSheet) {
            CategoryOrderSheet()
        }
        .fullScreenCover(isPresented: $showTabataFullScreen) {
            TabataView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenAIChat)) { note in
            assistantPrefill = note.userInfo?["prefill"] as? String
            selection = .assistant
        }
        .sheet(item: $routedTool) { t in NavigationStack { t.dest() } }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenModule)) { notif in
            if let module = notif.userInfo?["module"] as? String,
               let cat = AppCategory(rawValue: module) {
                selection = .category(cat)
                if let name = notif.userInfo?["tool"] as? String, let t = ToolRoute.tool(name, in: cat) { routedTool = t }
            }
        }
    }

    // MARK: - Barre latérale macOS Monochrome Unifiée

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Header Desktop
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 38, height: 38)
                        .raisedSurface(Circle(), .nested)
                    Image(systemName: "infinity")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("LifeOS")
                        .font(AppFont.heading(size: 19, weight: .black))
                        .foregroundStyle(Color.primary)
                    Text("Système Personnel")
                        .font(AppFont.body(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sidebarCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Masquer la barre latérale")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.primary.opacity(0.08)),
                alignment: .bottom
            )

            // Navigation List fluide monochrome
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Section ESPACE DE TRAVAIL
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ESPACE DE TRAVAIL")
                            .font(AppFont.body(size: 10, weight: .bold))
                            .foregroundStyle(Color.secondary.opacity(0.80))
                            .kerning(0.8)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)

                        sidebarButton(.dashboard)
                        sidebarButton(.habits)
                        sidebarButton(.assistant)
                        sidebarButton(.tabata)
                    }

                    // Section CATÉGORIES
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("CATÉGORIES")
                                .font(AppFont.body(size: 10, weight: .bold))
                                .foregroundStyle(Color.secondary.opacity(0.80))
                                .kerning(0.8)
                            Spacer()
                            Button {
                                showOrderSheet = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text("Trier")
                                }
                                .font(AppFont.body(size: 11, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.plain)
                            .help("Trier l'ordre des catégories")
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                        ForEach(categoryOrderManager.order) { cat in
                            sidebarButton(.category(cat))
                        }
                    }

                    // Section VUE D'ENSEMBLE
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VUE D'ENSEMBLE")
                            .font(AppFont.body(size: 10, weight: .bold))
                            .foregroundStyle(Color.secondary.opacity(0.80))
                            .kerning(0.8)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)

                        sidebarButton(.allCategories)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }

            // Profil & Réglages en bas de la barre latérale
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    selection = .profile
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 34, height: 34)
                        .raisedSurface(Circle(), .nested)
                        .overlay(
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(AppFont.heading(size: 14, weight: .black))
                                .foregroundStyle(Color.primary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(AppFont.heading(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text(userEmail.isEmpty ? "Compte local" : userEmail)
                            .font(AppFont.body(size: 11, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .liquidGlassCard(cornerRadius: 12)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .background(Color.primary.opacity(0.02))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.primary.opacity(0.07)),
            alignment: .trailing
        )
    }

    private func sidebarButton(_ section: DesktopNavSection) -> some View {
        let isSelected = selection == section
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 22)

                Text(section.label)
                    .font(AppFont.body(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Color.clear.glassControl(Capsule())
                        .matchedGeometryEffect(id: "sidebarSelectionPill", in: sidebarNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LifeOSPressStyle(scale: 0.98, opacity: 0.92))
    }

    // MARK: - Contenu de Détail Desktop

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch selection ?? .dashboard {
            case .dashboard:
                MacDesktopDashboardView(
                    onOpenTabata: { showTabataFullScreen = true },
                    onOpenHabitCreator: { showNewHabitModal = true },
                    onOpenAssistant: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selection = .assistant
                        }
                    },
                    onSelectCategory: { cat in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selection = .category(cat)
                        }
                    }
                )
            case .habits:
                HabitTrackerView()
            case .wakeup:
                WakeUpView()
            case .assistant:
                AIAssistantView(prefill: assistantPrefill)
            case .tabata:
                TabataView()
            case .category(let cat):
                // Sans conteneur de navigation, chaque NavigationLink du hub est MORT:
                // Stepometer, Fitbot, Hevvy, GOMOB, Yuko ne s'ouvraient pas, seul
                // TabaTime marchait parce qu'il passe par un fullScreenCover. Mesure au
                // simulateur le 28 septembre, en tapant chaque tuile. Le telephone, lui,
                // enveloppe deja les categories dans NavigationStack(path:).
                NavigationStack { cat.destination }
            case .allCategories:
                MacDesktopCategoriesOverview(
                    categories: categoryOrderManager.order,
                    onSelectCategory: { cat in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selection = .category(cat)
                        }
                    },
                    onOpenSort: {
                        showOrderSheet = true
                    }
                )
            case .profile:
                ProfileView()
            }
        }
        .id(selection?.id ?? "dashboard")
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
        ))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selection)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if sidebarCollapsed {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sidebarCollapsed = false
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Afficher la barre latérale")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewHabitModal = true
                } label: {
                    Label("Ajouter une habitude", systemImage: "plus")
                }
                .help("Créer une nouvelle habitude")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showOrderSheet = true
                } label: {
                    Label("Trier", systemImage: "arrow.up.arrow.down")
                }
                .help("Trier l'ordre des catégories")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection = .assistant
                } label: {
                    Label("Ton coach", systemImage: "sparkles")
                        .foregroundStyle(Color(hex: 0x9B6CF1))
                }
                .help("Discuter avec le Coach")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection = .profile
                } label: {
                    Label("Mon Profil", systemImage: "person.crop.circle")
                }
                .help("Ouvrir le profil et les réglages")
            }
        }
    }
}

// MARK: - Tableau de Bord Desktop Optimisé (Multi-Colonnes)

struct MacDesktopDashboardView: View {
    let onOpenTabata: () -> Void
    let onOpenHabitCreator: () -> Void
    let onOpenAssistant: () -> Void
    let onSelectCategory: (AppCategory) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.colorScheme) private var scheme

    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \TodoItem.priority, order: .reverse) private var todos: [TodoItem]
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]
    @Query(sort: \FastingSession.start, order: .reverse) private var fasts: [FastingSession]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]

    init(
        onOpenTabata: @escaping () -> Void,
        onOpenHabitCreator: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onSelectCategory: @escaping (AppCategory) -> Void = { _ in }
    ) {
        self.onOpenTabata = onOpenTabata
        self.onOpenHabitCreator = onOpenHabitCreator
        self.onOpenAssistant = onOpenAssistant
        self.onSelectCategory = onSelectCategory
    }

    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.userDisplayName) private var userDisplayName = ""
    @AppStorage("todayEnergyScore") private var energyScore = 82
    @AppStorage("todayEnergyLabel") private var energyLabel = "Excellente forme"
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal") private var kcalGoal = 2200

    @State private var newTaskTitle = ""
    @State private var selectedFilter: HabitFilter = .all
    @State private var habitDisplayMode: String = "timeline"

    enum HabitFilter: String, CaseIterable {
        case all = "Toutes"
        case morning = "Matin"
        case day = "Journée"
        case evening = "Soir"
    }

    private var activeHabits: [Habit] {
        habits.filter { !$0.isArchived && !$0.isPending }
    }

    private var filteredHabits: [Habit] {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let todayList = activeHabits.filter { h in
            let days = Set(h.activeDaysRaw.split(separator: ",").compactMap { Int($0) })
            return days.isEmpty || days.contains(weekday)
        }
        switch selectedFilter {
        case .all: return todayList
        case .morning: return todayList.filter { $0.scheduledHour < 12 }
        case .day: return todayList.filter { $0.scheduledHour >= 12 && $0.scheduledHour < 18 }
        case .evening: return todayList.filter { $0.scheduledHour >= 18 }
        }
    }

    private var doneHabitsCount: Int {
        activeHabits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
    }

    private var waterToday: Int {
        waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
    }

    private var kcalToday: Int {
        foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
    }

    private var activeFast: FastingSession? {
        fasts.first(where: { $0.isActive })
    }

    private var currentDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: Date()).capitalized
    }

    private var displayName: String {
        if !userDisplayName.isEmpty { return userDisplayName }
        if !userName.isEmpty { return userName }
        return "Theo"
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let isWide = availableWidth >= 960

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: 1. Hero Header Panoramique Desktop Adaptatif
                    headerHero(availableWidth: availableWidth)

                    // MARK: 2. Modules prioritaires (Sport, Nutrition, Tâches...)
                    topPriorityCategoriesStrip(availableWidth: availableWidth)

                    // MARK: 3. Grille Desktop Adaptative
                    if isWide {
                        HStack(alignment: .top, spacing: 24) {
                            // Colonne de Gauche (Flexible) : Tâches quotidiennes & Habitudes
                            VStack(alignment: .leading, spacing: 24) {
                                todosSection
                                habitsSection
                            }
                            .frame(maxWidth: .infinity)

                            // Colonne de Droite (Largeur adaptative) : Métriques, Outils rapides, Coach
                            VStack(alignment: .leading, spacing: 24) {
                                metricsPanel
                                quickToolsGrid
                                coachInsightCard
                            }
                            .frame(width: min(max(availableWidth * 0.36, 320), 400))
                        }
                    } else {
                        // Disposition 1 colonne fluide lorsque la largeur disponible < 960
                        VStack(alignment: .leading, spacing: 24) {
                            todosSection
                            habitsSection
                            metricsPanel
                            quickToolsGrid
                            coachInsightCard
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, availableWidth > 640 ? 32 : 16)
                .padding(.vertical, 24)
            }
        }
        .background(Color.clear)
    }

    // MARK: - Bandeau Modules Prioritaires Desktop (Monochrome)

    private func topPriorityCategoriesStrip(availableWidth: CGFloat) -> some View {
        let columnsCount = availableWidth >= 1100 ? 3 : (availableWidth >= 640 ? 2 : 1)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: columnsCount)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary)
                    Text("Modules Prioritaires")
                        .font(AppFont.heading(size: 17, weight: .black))
                        .foregroundStyle(Color.primary)
                }
                Spacer()
                Text("Classés selon vos préférences")
                    .font(AppFont.body(size: 12, weight: .regular))
                    .foregroundStyle(Color.secondary)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(CategoryOrderManager.shared.order.prefix(6)) { cat in
                    Button {
                        onSelectCategory(cat)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryGlassIcon(category: cat, size: 38, cornerRadius: 10, iconSize: 17)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.title)
                                    .font(AppFont.heading(size: 13, weight: .bold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                Text(cat.subtitle)
                                    .font(AppFont.body(size: 11, weight: .regular))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.60))
                        }
                        .padding(12)
                        .applePreviewInnerCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .applePreviewCard(cornerRadius: 26)
    }

    // MARK: - 1. Hero Header Panoramique avec DailyScoreRing (Monochrome & Équilibré)

    private func headerHero(availableWidth: CGFloat) -> some View {
        let isHeroWide = availableWidth >= 1060
        return Group {
            if isHeroWide {
                HStack(alignment: .center, spacing: 24) {
                    heroWelcomeSegment
                        .frame(minWidth: 260, maxWidth: 350, alignment: .leading)

                    Spacer(minLength: 8)

                    heroVitalsGrid
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 8)

                    DailyScoreRing()
                        .frame(width: 320)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 20) {
                        heroWelcomeSegment
                            .frame(maxWidth: .infinity, alignment: .leading)

                        DailyScoreRing()
                            .frame(width: min(availableWidth * 0.45, 300))
                    }

                    heroVitalsGrid
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24)
        .applePreviewCard(cornerRadius: 28)
    }

    private var heroWelcomeSegment: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
                Text(currentDateString.uppercased())
                    .font(AppFont.body(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .kerning(1.2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .applePreviewIsland()

            VStack(alignment: .leading, spacing: 6) {
                Text("Bonjour, \(displayName)")
                    .font(.system(size: 38, weight: .black))
                    .textCase(.uppercase)
                    .kerning(-1)
                    .foregroundStyle(Color.primary)

                Text("TON SYSTÈME PERSONNEL EN UN CADRAN · HABITUDES & TÂCHES")
                    .monoLabel(11)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.primary)
                    Text("\(doneHabitsCount) / \(activeHabits.count) validées")
                        .font(AppFont.body(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .applePreviewIsland()

                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.primary)
                    Text(energyLabel.isEmpty ? "Forme optimale" : energyLabel)
                        .font(AppFont.body(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .applePreviewIsland()
            }

            // Boutons d'actions rapides Apple Preview
            HStack(spacing: 10) {
                Button {
                    onOpenHabitCreator()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Nouvelle habitude")
                            .font(AppFont.heading(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .applePreviewPill(height: 38)
                }
                .buttonStyle(LifeOSPressStyle(scale: 0.96))

                Button {
                    onOpenAssistant()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Ton coach")
                            .font(AppFont.heading(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .applePreviewPill(height: 38)
                }
                .buttonStyle(LifeOSPressStyle(scale: 0.96))
            }
        }
    }

    private var heroVitalsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                heroVitalTile(
                    icon: "checklist",
                    title: "Tâches à faire",
                    value: "\(todos.filter { !$0.done }.count) restantes",
                    detail: "\(todos.filter { $0.done }.count) terminées"
                )
                heroVitalTile(
                    icon: "drop.fill",
                    title: "Hydratation",
                    value: "\(waterToday) ml",
                    detail: "Objectif \(waterGoal) ml"
                )
            }
            HStack(spacing: 10) {
                heroVitalTile(
                    icon: "flame.fill",
                    title: "Calories",
                    value: "\(kcalToday) kcal",
                    detail: "Objectif \(kcalGoal) kcal"
                )
                heroVitalTile(
                    icon: "bolt.fill",
                    title: "Score Énergie",
                    value: "\(energyScore) / 100",
                    detail: energyLabel.isEmpty ? "Optimal" : energyLabel
                )
            }
        }
    }

    private func heroVitalTile(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 32, height: 32)
                    .raisedSurface(Circle(), .nested)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(AppFont.heading(size: 13, weight: .black))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(AppFont.body(size: 10, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.80))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .applePreviewInnerCard(cornerRadius: 16)
    }

    // MARK: - Habitudes du Jour (Monochrome)

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.primary)
                    Text("Habitudes du jour")
                        .font(AppFont.sans(size: 19, weight: .black))
                        .foregroundStyle(Color.primary)
                }

                Spacer()

                // Bascule Frise 24h / Cartes
                HStack(spacing: 4) {
                    Button {
                        habitDisplayMode = "timeline"
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Frise 24h")
                        }
                        .font(AppFont.body(size: 11, weight: habitDisplayMode == "timeline" ? .bold : .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(habitDisplayMode == "timeline" ? Color.primary.opacity(0.12) : Color.clear)
                        .foregroundStyle(habitDisplayMode == "timeline" ? Color.primary : Color.secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        habitDisplayMode = "grid"
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                            Text("Cartes")
                        }
                        .font(AppFont.body(size: 11, weight: habitDisplayMode == "grid" ? .bold : .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(habitDisplayMode == "grid" ? Color.primary.opacity(0.12) : Color.clear)
                        .foregroundStyle(habitDisplayMode == "grid" ? Color.primary : Color.secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .applePreviewIsland()

                if habitDisplayMode == "grid" {
                    // Filtres de temps monochromes style Apple Preview
                    HStack(spacing: 4) {
                        ForEach(HabitFilter.allCases, id: \.self) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(AppFont.body(size: 11, weight: selectedFilter == filter ? .bold : .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedFilter == filter ? Color.primary.opacity(0.12) : Color.clear)
                                    .foregroundStyle(selectedFilter == filter ? Color.primary : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .applePreviewIsland()
                }

                Button {
                    onOpenHabitCreator()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Ajouter")
                    }
                    .font(AppFont.body(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .applePreviewPill(height: 32)
            }

            if habitDisplayMode == "timeline" {
                HabitTrackerTimelineView(showHeader: false, isEmbedded: true)
                    .frame(height: 520)
            } else {
                if filteredHabits.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.badge.questionmark")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.secondary)
                        Text("Aucune habitude pour ce moment de la journée.")
                            .font(AppFont.body(size: 13, weight: .medium))
                            .foregroundStyle(Color.secondary)
                        Button("Créer une nouvelle habitude") {
                            onOpenHabitCreator()
                        }
                        .font(AppFont.body(size: 12, weight: .bold))
                        .foregroundStyle(Color.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .applePreviewInnerCard(cornerRadius: 18)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 360), spacing: 14)], spacing: 14) {
                        ForEach(filteredHabits) { habit in
                            desktopHabitCard(habit)
                        }
                    }
                }
            }
        }
        .padding(20)
        .applePreviewCard(cornerRadius: 26)
    }

    private func desktopHabitCard(_ habit: Habit) -> some View {
        let isDone = habit.completions.contains { Calendar.current.isDateInToday($0.date) }

        return HStack(spacing: 14) {
            // Icon squircle épuré monochrome
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isDone ? 0.10 : 0.04))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(isDone ? 0.25 : 0.08), lineWidth: 0.8)
                    )
                Image(systemName: habit.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(AppFont.sans(size: 14, weight: .bold))
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                    .strikethrough(isDone, color: Color.secondary.opacity(0.50))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(String(format: "%02dh%02d", habit.scheduledHour, habit.scheduledMinute))
                        .font(AppFont.body(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)

                    if habit.completions.count > 0 {
                        Text("·")
                            .foregroundStyle(Color.secondary.opacity(0.60))
                        Text("🔥 \(habit.completions.count) j")
                            .font(AppFont.body(size: 11, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.85))
                    }
                }
            }

            Spacer()

            // Bouton validation monochrome
            Button {
                toggleHabit(habit)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(isDone ? 0.80 : 0.25), lineWidth: 1.5)
                        .frame(width: 30, height: 30)

                    if isDone {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 30, height: 30)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .applePreviewInnerCard(cornerRadius: 16)
    }

    private func toggleHabit(_ habit: Habit) {
        let isDone = habit.completions.contains { Calendar.current.isDateInToday($0.date) }
        if isDone {
            if let c = habit.completions.first(where: { Calendar.current.isDateInToday($0.date) }) {
                ctx.delete(c)
            }
        } else {
            habit.completions.append(HabitCompletion(date: .now))
        }
        try? ctx.save()
        Haptics.soft()
    }

    // MARK: - To-Do & Priorités (Monochrome & Comblement de l'espace)

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.primary)
                    Text("Objectifs & Tâches")
                        .font(AppFont.sans(size: 19, weight: .black))
                        .foregroundStyle(Color.primary)
                }
                Spacer()
                Text("\(todos.filter { !$0.done }.count) restantes")
                    .font(AppFont.body(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }

            // Champ d'ajout rapide style îlot Apple Preview
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.primary)
                    .font(.system(size: 18, weight: .bold))
                TextField("Nouvelle tâche à accomplir...", text: $newTaskTitle)
                    .font(AppFont.sans(size: 13, weight: .medium))
                    .textFieldStyle(.plain)
                    .onSubmit(addNewTask)
                if !newTaskTitle.isEmpty {
                    Button("Ajouter", action: addNewTask)
                        .font(AppFont.body(size: 12, weight: .bold))
                        .foregroundStyle(Color.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .applePreviewIsland()

            // Liste des tâches ou suggestions productives si vide (pour ne laisser aucun vide)
            let pending = todos.filter { !$0.done }
            if pending.isEmpty {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.primary)
                        Text("Toutes les tâches du jour sont accomplies ! ✦")
                            .font(AppFont.body(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }

                    Text("Rien d'urgent pour l'instant. Tu peux ajouter une tâche ou choisir un focus rapide :")
                        .font(AppFont.body(size: 11, weight: .regular))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        quickSuggestionChip("🏋️‍♂️ Séance de sport")
                        quickSuggestionChip("💧 Boire 500ml")
                        quickSuggestionChip("📖 20 min lecture")
                        quickSuggestionChip("🌙 Bilan de soirée")
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .applePreviewInnerCard(cornerRadius: 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(pending.prefix(6)) { todo in
                        HStack(spacing: 12) {
                            Button {
                                todo.done = true
                                try? ctx.save()
                                Haptics.soft()
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)

                            Text(todo.title)
                                .font(AppFont.sans(size: 14, weight: .bold))
                                .foregroundStyle(Color.primary)

                            Spacer()

                            if !todo.project.isEmpty {
                                Text(todo.project)
                                    .font(AppFont.body(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .applePreviewIsland()
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(11)
                        .applePreviewInnerCard(cornerRadius: 14)
                    }
                }
            }
        }
        .padding(20)
        .applePreviewCard(cornerRadius: 26)
    }

    private func quickSuggestionChip(_ title: String) -> some View {
        Button {
            ctx.insert(TodoItem(title: title, due: Date()))
            try? ctx.save()
            Haptics.soft()
        } label: {
            Text(title)
                .font(AppFont.body(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassPill()
        }
        .buttonStyle(.plain)
    }

    private func addNewTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ctx.insert(TodoItem(title: trimmed, due: Date()))
        try? ctx.save()
        newTaskTitle = ""
        Haptics.soft()
    }

    // MARK: - Panneau Métriques (Colonne Droite, Monochrome)

    private var metricsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Métriques du Jour")
                .font(AppFont.sans(size: 18, weight: .black))
                .foregroundStyle(Color.primary)

            // Eau
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Hydratation", systemImage: "drop.fill")
                        .font(AppFont.sans(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(waterToday) / \(waterGoal) ml")
                        .font(AppFont.body(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                }
                ProgressView(value: min(Double(waterToday), Double(waterGoal)), total: Double(waterGoal))
                    .tint(Color.primary)

                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        ctx.insert(WaterEntry(date: .now, amountML: 250))
                        try? ctx.save()
                        Haptics.soft()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("250 ml")
                        }
                        .font(AppFont.body(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassPill()

                    Button {
                        ctx.insert(WaterEntry(date: .now, amountML: 500))
                        try? ctx.save()
                        Haptics.soft()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("500 ml")
                        }
                        .font(AppFont.body(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .applePreviewIsland()
                }
            }
            .padding(14)
            .applePreviewInnerCard(cornerRadius: 16)

            // Calories
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Calories consommées", systemImage: "flame.fill")
                        .font(AppFont.sans(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(kcalToday) / \(kcalGoal) kcal")
                        .font(AppFont.body(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                }
                ProgressView(value: min(Double(kcalToday), Double(kcalGoal)), total: Double(kcalGoal))
                    .tint(Color.primary)
            }
            .padding(14)
            .applePreviewInnerCard(cornerRadius: 16)

            // Jeûne & Statut
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jeûne Intermittent")
                        .font(AppFont.sans(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(activeFast != nil ? "En cours · \(Int((activeFast?.elapsed ?? 0) / 3600))h écoulées" : "Aucun jeûne actif")
                        .font(AppFont.body(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
            .padding(14)
            .applePreviewInnerCard(cornerRadius: 14)
        }
        .padding(20)
        .applePreviewCard(cornerRadius: 26)
    }

    // MARK: - Raccourcis Outils Rapides (Monochrome)

    private var quickToolsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Outils Rapides")
                .font(AppFont.sans(size: 18, weight: .black))
                .foregroundStyle(Color.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                toolTile(title: "HIIT / Tabata", icon: "timer", action: onOpenTabata)
                toolTile(title: "Ton coach", icon: "sparkles", action: onOpenAssistant)
                toolTile(title: "Focus Pomodoro", icon: "brain.head.profile", action: onOpenAssistant)
                toolTile(title: "Bilan du Soir", icon: "sunset.fill", action: onOpenAssistant)
            }
        }
        .padding(20)
        .applePreviewCard(cornerRadius: 26)
    }

    private func toolTile(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 40, height: 40)
                        .raisedSurface(Circle(), .nested)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                Text(title)
                    .font(AppFont.sans(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .applePreviewInnerCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Carte Coach IA Proactif (Monochrome)

    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.primary)
                Text("Conseil Coach LifeOS")
                    .font(AppFont.sans(size: 14, weight: .black))
                    .foregroundStyle(Color.primary)
            }

            Text("Tu as maintenu une excellente régularité cette semaine. Prends 5 minutes pour ta séance de respiration en fin d'après-midi.")
                .font(AppFont.body(size: 12, weight: .regular))
                .foregroundStyle(Color.secondary)
                .lineSpacing(3)

            Button(action: onOpenAssistant) {
                HStack(spacing: 6) {
                    Text("Discuter avec le coach")
                    Image(systemName: "arrow.right")
                }
                .font(AppFont.body(size: 12, weight: .bold))
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .applePreviewCard(cornerRadius: 24)
    }
}

// MARK: - Modale Ajout Rapide d'Habitude

struct NewHabitQuickSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var name = ""
    @State private var selectedIcon = "figure.run"
    @State private var selectedColorHex = 0x47CC5C
    @State private var hour = 9
    @State private var minute = 0

    let icons = ["figure.run", "fork.knife", "moon.stars.fill", "brain.head.profile", "book.fill", "drop.fill", "dumbbell.fill", "bed.double.fill", "checklist", "heart.fill"]
    let colors = [0x47CC5C, 0xFF2E33, 0x2185FF, 0xA852F5, 0xFFB83D, 0x24C7CC, 0xFF338C]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Liquid Glass
            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(LifeOSPressStyle(scale: 0.95))

                Spacer()

                Text("Nouvelle habitude")
                    .font(AppFont.heading(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    save()
                } label: {
                    Text("Créer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(LifeOSPressStyle(scale: 0.95))
                .disabled(!isValid)
                .opacity(isValid ? 1.0 : 0.35)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Nom
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOM DE L'HABITUDE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        TextField("Ex: Méditation du matin, Salle de sport...", text: $name)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), .nested)
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 2: Icône & Couleur
                    VStack(alignment: .leading, spacing: 14) {
                        Text("ICÔNE & COULEUR")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                            ForEach(icons, id: \.self) { icon in
                                let isSel = selectedIcon == icon
                                Button {
                                    selectedIcon = icon
                                    Haptics.tap()
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 17, weight: isSel ? .bold : .medium))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                        .background(isSel ? Color(hex: UInt(selectedColorHex)).opacity(0.18) : Color.primary.opacity(0.03))
                                        .foregroundStyle(isSel ? Color(hex: UInt(selectedColorHex)) : Color.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(isSel ? Color(hex: UInt(selectedColorHex)) : Theme.stroke, lineWidth: isSel ? 2 : 0.6)
                                        )
                                }
                                .buttonStyle(LifeOSPressStyle(scale: 0.94))
                            }
                        }

                        Divider().padding(.vertical, 4)

                        HStack(spacing: 14) {
                            ForEach(colors, id: \.self) { c in
                                let isSel = selectedColorHex == c
                                Button {
                                    selectedColorHex = c
                                    Haptics.tap()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: UInt(c)))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: isSel ? 3 : 0)
                                        )
                                        .shadow(color: Color(hex: UInt(c)).opacity(isSel ? 0.45 : 0.15), radius: isSel ? 5 : 2, y: isSel ? 2 : 1)
                                        .scaleEffect(isSel ? 1.15 : 1.0)
                                        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 3: Heure de rappel
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HEURE DE RAPPEL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        HStack {
                            Label("Rappel quotidien", systemImage: "bell.badge.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            DatePicker("", selection: Binding(
                                get: {
                                    var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                                    c.hour = hour
                                    c.minute = minute
                                    return Calendar.current.date(from: c) ?? .now
                                },
                                set: { newDate in
                                    let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                    hour = c.hour ?? 9
                                    minute = c.minute ?? 0
                                }
                            ), displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)
                }
                .padding(20)
            }
        }
        .background(Color.white.ignoresSafeArea())
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let h = Habit(
            name: trimmed,
            icon: selectedIcon,
            colorHex: selectedColorHex,
            scheduledHour: hour,
            scheduledMinute: minute
        )
        ctx.insert(h)
        try? ctx.save()
        Haptics.medium()
        dismiss()
    }
}

// MARK: - Vue d'ensemble des Catégories sur macOS Desktop

struct MacDesktopCategoriesOverview: View {
    let categories: [AppCategory]
    let onSelectCategory: (AppCategory) -> Void
    let onOpenSort: () -> Void

    @State private var searchText = ""

    private var filteredCategories: [AppCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return categories
        }
        return categories.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Catégories & Modules")
                            .font(AppFont.heading(size: 28, weight: .black))
                            .foregroundStyle(.primary)
                        Text("Tous vos modules LifeOS organisés selon vos priorités")
                            .font(AppFont.body(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        onOpenSort()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("Trier les catégories")
                        }
                        .font(AppFont.body(size: 12, weight: .bold))
                        .padding(.horizontal, 16)
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .applePreviewPill(height: 38)
                    .help("Modifier l'ordre d'affichage des catégories")
                }

                // Barre de filtre rapide style îlot Apple Preview
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.secondary)
                    TextField("Filtrer une catégorie ou un outil...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AppFont.body(size: 13, weight: .regular))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .applePreviewIsland()

                // Grille de cartes
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Array(filteredCategories.enumerated()), id: \.element.id) { index, cat in
                        Button {
                            onSelectCategory(cat)
                        } label: {
                            categoryCard(cat, rank: index + 1)
                        }
                        .buttonStyle(LifeOSPressStyle(scale: 0.96))
                    }
                }
            }
            .padding(32)
        }
        .background(Color.clear)
    }

    private func categoryCard(_ cat: AppCategory, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                // Numéro de rang
                Text(String(format: "#%02d", rank))
                    .font(AppFont.body(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .applePreviewIsland()

                Spacer()

                // Icône en verre liquide translucide monochrome
                CategoryGlassIcon(category: cat, size: 44, cornerRadius: 12, iconSize: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cat.title)
                    .font(AppFont.heading(size: 17, weight: .black))
                    .foregroundStyle(Color.primary)

                Text(cat.subtitle)
                    .font(AppFont.body(size: 12, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text("Ouvrir le module")
                    .font(AppFont.body(size: 11, weight: .bold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
            .padding(.top, 4)
        }
        .padding(18)
        .applePreviewCard(cornerRadius: 24)
    }
}

