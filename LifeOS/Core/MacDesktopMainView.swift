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
        case .assistant: return "Coach Personnel IA"
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
        switch self {
        case .dashboard: return Color.accentColor
        case .habits: return Color(hex: 0x4CC38A)
        case .wakeup: return Color(hex: 0x6C7BF1)
        case .assistant: return Color(hex: 0x9B6CF1)
        case .tabata: return Color(hex: 0xF1746C)
        case .category(let cat): return cat.tint
        case .allCategories: return .secondary
        case .profile: return .primary
        }
    }
}

// MARK: - Conteneur Principal macOS Desktop

struct MacDesktopMainView: View {
    @State private var selection: DesktopNavSection? = .dashboard
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
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            detailContent
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenModule)) { notif in
            if let module = notif.userInfo?["module"] as? String,
               let cat = AppCategory(rawValue: module) {
                selection = .category(cat)
            }
        }
    }

    // MARK: - Barre latérale macOS

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Header Desktop
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "infinity")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("LifeOS")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Système Personnel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))

            Divider()

            // Navigation List avec ordre personnalisé des catégories
            List(selection: $selection) {
                Section("ESPACE DE TRAVAIL") {
                    navRow(.dashboard)
                    navRow(.habits)
                    navRow(.assistant)
                    navRow(.tabata)
                }

                Section {
                    ForEach(categoryOrderManager.order) { cat in
                        navRow(.category(cat))
                    }
                } header: {
                    HStack {
                        Text("CATÉGORIES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showOrderSheet = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text("Trier")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Trier l'ordre des catégories")
                    }
                }

                Section("VUE D'ENSEMBLE") {
                    navRow(.allCategories)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Profil & Réglages en bas de la barre latérale
            Button {
                selection = .profile
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(userEmail.isEmpty ? "Compte local" : userEmail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(selection == .profile ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private func navRow(_ section: DesktopNavSection) -> some View {
        NavigationLink(value: section) {
            Label {
                Text(section.label)
                    .font(.system(size: 14, weight: selection == section ? .semibold : .regular))
            } icon: {
                Image(systemName: section.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(section.color)
            }
        }
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
                    onOpenAssistant: { selection = .assistant },
                    onSelectCategory: { cat in selection = .category(cat) }
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
                cat.destination
            case .allCategories:
                MacDesktopCategoriesOverview(
                    categories: categoryOrderManager.order,
                    onSelectCategory: { cat in
                        selection = .category(cat)
                    },
                    onOpenSort: {
                        showOrderSheet = true
                    }
                )
            case .profile:
                ProfileView()
            }
        }
        .toolbar {
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
                    Label("Coach IA", systemImage: "sparkles")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: 1. Hero Header Desktop
                headerHero

                // MARK: 2. Modules prioritaires (Sport, Nutrition, Tâches...)
                topPriorityCategoriesStrip

                // MARK: 3. Grille Desktop 2 Colonnes
                HStack(alignment: .top, spacing: 24) {
                    // Colonne de Gauche (60%) : Tâches quotidiennes To-Do & Habitudes
                    VStack(alignment: .leading, spacing: 24) {
                        todosSection
                        habitsSection
                    }
                    .frame(maxWidth: .infinity)

                    // Colonne de Droite (40%) : Métriques, Outils rapides, Coach
                    VStack(alignment: .leading, spacing: 24) {
                        metricsPanel
                        quickToolsGrid
                        coachInsightCard
                    }
                    .frame(width: 360)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Bandeau Modules Prioritaires Desktop

    private var topPriorityCategoriesStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.yellow)
                    Text("Modules Prioritaires")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
                Text("Classés selon vos préférences")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(CategoryOrderManager.shared.order.prefix(6)) { cat in
                    Button {
                        onSelectCategory(cat)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(cat.tint.gradient)
                                    .frame(width: 36, height: 36)
                                Image(systemName: cat.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(cat.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - 1. Hero Header

    private var headerHero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentDateString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                    .kerning(1)

                Text("Bonjour, \(displayName)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Tu as complété \(doneHabitsCount) sur \(activeHabits.count) habitudes prévues aujourd'hui.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Energy Card
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(energyScore, 10), 100)) / 100.0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))

                    Text("\(energyScore)")
                        .font(AppFont.sans(size: 18, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Score Énergie")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(energyLabel.isEmpty ? "Excellente forme" : energyLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

    // MARK: - Habitudes du Jour

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: 0x4CC38A))
                    Text("Habitudes du jour")
                        .font(.system(size: 20, weight: .bold))
                }

                Spacer()

                // Filtres de temps
                HStack(spacing: 4) {
                    ForEach(HabitFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: selectedFilter == filter ? .semibold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedFilter == filter ? Color.accentColor : Color.clear)
                                .foregroundStyle(selectedFilter == filter ? .white : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

                Button {
                    onOpenHabitCreator()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Ajouter")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if filteredHabits.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("Aucune habitude pour ce moment de la journée.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Créer une nouvelle habitude") {
                        onOpenHabitCreator()
                    }
                    .font(.footnote.bold())
                    .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(filteredHabits) { habit in
                        desktopHabitCard(habit)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func desktopHabitCard(_ habit: Habit) -> some View {
        let isDone = habit.completions.contains { Calendar.current.isDateInToday($0.date) }
        let color = Color(hex: UInt(habit.colorHex))

        return HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDone ? color : color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: habit.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isDone ? .white : color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary.opacity(0.6))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(String(format: "%02dh%02d", habit.scheduledHour, habit.scheduledMinute))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if habit.completions.count > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("🔥 \(habit.completions.count) j")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Bouton validation
            Button {
                toggleHabit(habit)
            } label: {
                ZStack {
                    Circle()
                        .stroke(isDone ? color : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 30, height: 30)

                    if isDone {
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDone ? color.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
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

    // MARK: - To-Do & Priorités

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: 0x3CB2E0))
                    Text("Objectifs & Tâches")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Text("\(todos.filter { !$0.done }.count) restantes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            // Champ d'ajout rapide
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 20))
                TextField("Nouvelle tâche à accomplir...", text: $newTaskTitle)
                    .font(.subheadline)
                    .onSubmit(addNewTask)
                if !newTaskTitle.isEmpty {
                    Button("Ajouter", action: addNewTask)
                        .font(.footnote.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            // Liste des 5 premières tâches
            VStack(spacing: 8) {
                let pending = todos.filter { !$0.done }
                if pending.isEmpty {
                    Text("Toutes les tâches sont terminées ! Bravo 🎉")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(pending.prefix(6)) { todo in
                        HStack(spacing: 12) {
                            Button {
                                todo.done = true
                                try? ctx.save()
                                Haptics.soft()
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(todo.priority >= 2 ? Color.red : Color.secondary)
                            }
                            .buttonStyle(.plain)

                            Text(todo.title)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)

                            Spacer()

                            if !todo.project.isEmpty {
                                Text(todo.project)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func addNewTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ctx.insert(TodoItem(title: trimmed, due: Date()))
        try? ctx.save()
        newTaskTitle = ""
        Haptics.soft()
    }

    // MARK: - Panneau Métriques (Colonne Droite)

    private var metricsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Métriques du Jour")
                .font(.system(size: 18, weight: .bold))

            // Eau
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Hydratation", systemImage: "drop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x3CD0C8))
                    Spacer()
                    Text("\(waterToday) / \(waterGoal) ml")
                        .font(.system(size: 13, weight: .bold))
                }
                ProgressView(value: min(Double(waterToday), Double(waterGoal)), total: Double(waterGoal))
                    .tint(Color(hex: 0x3CD0C8))

                HStack {
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
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: 0x3CD0C8).opacity(0.15))
                        .foregroundStyle(Color(hex: 0x3CD0C8))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            // Calories
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Calories consommées", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xF1746C))
                    Spacer()
                    Text("\(kcalToday) / \(kcalGoal) kcal")
                        .font(.system(size: 13, weight: .bold))
                }
                ProgressView(value: min(Double(kcalToday), Double(kcalGoal)), total: Double(kcalGoal))
                    .tint(Color(hex: 0xF1746C))
            }
            .padding(14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            // Jeûne & Statut
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jeûne Intermittent")
                        .font(.system(size: 13, weight: .semibold))
                    Text(activeFast != nil ? "En cours · \(Int((activeFast?.elapsed ?? 0) / 3600))h écoulées" : "Aucun jeûne actif")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Raccourcis Outils Rapides

    private var quickToolsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Outils Rapides")
                .font(.system(size: 18, weight: .bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                toolTile(title: "HIIT / Tabata", icon: "timer", color: Color(hex: 0xF1746C), action: onOpenTabata)
                toolTile(title: "Coach IA", icon: "sparkles", color: Color(hex: 0x9B6CF1), action: onOpenAssistant)
                toolTile(title: "Focus Pomodoro", icon: "brain.head.profile", color: Color(hex: 0x3CB2E0), action: onOpenAssistant)
                toolTile(title: "Bilan Soir", icon: "sunset.fill", color: Color(hex: 0xE0A23C), action: onOpenAssistant)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func toolTile(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Carte Coach IA Proactif

    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: 0x9B6CF1))
                Text("Conseil Coach LifeOS")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x9B6CF1))
            }

            Text("Tu as maintenu une excellente régularité cette semaine. Prends 5 minutes pour ta séance de respiration en fin d'après-midi.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Button(action: onOpenAssistant) {
                HStack(spacing: 6) {
                    Text("Discuter avec le coach")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x9B6CF1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x9B6CF1).opacity(0.12), Color(hex: 0x9B6CF1).opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0x9B6CF1).opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Modale Ajout Rapide d'Habitude

struct NewHabitQuickSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var name = ""
    @State private var selectedIcon = "figure.run"
    @State private var selectedColorHex = 0x4CC38A
    @State private var hour = 9
    @State private var minute = 0

    let icons = ["figure.run", "fork.knife", "moon.stars.fill", "brain.head.profile", "book.fill", "drop.fill", "dumbbell.fill", "bed.double.fill", "checklist"]
    let colors = [0x4CC38A, 0xF1746C, 0x6C7BF1, 0x9B6CF1, 0xE0A23C, 0x3CB2E0, 0xF97316]

    var body: some View {
        Form {
            Section("Nom de l'habitude") {
                TextField("Ex: Méditation du matin, Salle de sport...", text: $name)
            }

            Section("Icône & Couleur") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color(uiColor: .tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(selectedIcon == icon ? RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2) : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 12) {
                    ForEach(colors, id: \.self) { c in
                        Button {
                            selectedColorHex = c
                        } label: {
                            Circle()
                                .fill(Color(hex: UInt(c)))
                                .frame(width: 30, height: 30)
                                .overlay(selectedColorHex == c ? Circle().stroke(Color.primary, lineWidth: 2) : nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Heure de rappel") {
                HStack {
                    Stepper("Heure : \(hour)h", value: $hour, in: 0...23)
                    Stepper("Minute : \(minute)", value: $minute, in: 0...55, step: 5)
                }
            }
        }
        .navigationTitle("Nouvelle habitude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
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
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Tous vos modules LifeOS organisés selon vos priorités")
                            .font(.system(size: 14))
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
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Modifier l'ordre d'affichage des catégories")
                }

                // Barre de filtre rapide
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filtrer une catégorie ou un outil...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Grille de cartes
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Array(filteredCategories.enumerated()), id: \.element.id) { index, cat in
                        Button {
                            onSelectCategory(cat)
                        } label: {
                            categoryCard(cat, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(32)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func categoryCard(_ cat: AppCategory, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                // Numéro de rang
                Text(String(format: "#%02d", rank))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Icône
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cat.tint.gradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: cat.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cat.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Text(cat.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text("Ouvrir le module")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cat.tint)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(cat.tint.opacity(0.8))
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

