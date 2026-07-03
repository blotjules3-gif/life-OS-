import SwiftUI
import SwiftData
import Charts

// MARK: - Onglets (chat retiré — input intégré dans la barre)

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

// MARK: - Dégagement pour la barre d'onglets flottante
// La barre flotte AU-DESSUS du contenu. Le safeAreaInset posé sur le conteneur ne
// traverse pas les NavigationStack internes des pages → il faut réserver l'espace
// DIRECTEMENT sur chaque vue défilante racine (accueil, réveil, profil, chaque outil).
extension View {
    func floatingBarClearance(_ height: CGFloat = 96) -> some View {
        safeAreaInset(edge: .bottom) { Color.clear.frame(height: height) }
    }
}

// MARK: - Conteneur principal

struct MainTabView: View {
    @State private var tab: AppTab = .home
    @State private var catPath: [AppCategory] = []
    @State private var chatInput = ""
    @State private var chatMessages: [ChatMessage] = [
        ChatMessage(fromUser: false, text: "Salut ! Je suis ton assistant LifeOS. Dis-moi « retiens que... » pour que je mémorise quelque chose. Je peux aussi t'aider sur calories, eau, jeûne et habitudes.")
    ]
    @State private var showChat = false
    @State private var showAIAssistant = false
    @State private var aiPrefill: String? = nil

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @Query(sort: \MemoryEntry.created, order: .reverse) private var memories: [MemoryEntry]
    @Environment(\.modelContext) private var ctx
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("appTheme") private var appThemeRaw = "classic"
    private var theme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 118) }
            FloatingTabBar(
                selected: $tab,
                chatInput: $chatInput,
                onSend: sendChat,
                onOpenAssistant: { showAIAssistant = true }
            )
        }
        // La barre est alignée en bas de ce ZStack : c'est ICI qu'il faut ignorer
        // la safe area pour que le pill colle à 10pt du vrai bord (sinon +34pt d'inset).
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showChat) {
            ChatHistorySheet(messages: chatMessages)
        }
        .fullScreenCover(isPresented: $showAIAssistant) {
            AIAssistantView(prefill: aiPrefill)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenAIChat)) { note in
            aiPrefill = note.userInfo?["prefill"] as? String
            showAIAssistant = true
        }
    }

    @ViewBuilder private var content: some View {
        ZStack {
            // Fond thématique unique, partagé par TOUS les onglets (Accueil / Réveil /
            // Catégories / Profil) — l'app a la même identité visuelle partout.
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

    // MARK: Envoi message

    private func sendChat() {
        let q = chatInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        chatMessages.append(ChatMessage(fromUser: true, text: q))
        chatInput = ""
        let ql = q.lowercased()

        // Détection mémorisation
        let memPrefixes = ["retiens que ", "souviens-toi que ", "note que ", "mémorise que ", "remember that "]
        if let prefix = memPrefixes.first(where: { ql.hasPrefix($0) }) {
            let content = String(q.dropFirst(prefix.count))
            let category = detectMemoryCategory(ql)
            let entry = MemoryEntry(content: content, category: category, source: "chat")
            ctx.insert(entry)
            chatMessages.append(ChatMessage(fromUser: false, text: "Mémorisé ✓ — Je me souviendrai que \"\(content)\". Tu peux retrouver ça dans l'onglet Profil."))
            showChat = true
            return
        }

        chatMessages.append(ChatMessage(fromUser: false, text: answer(for: ql)))
        showChat = true
    }

    private func detectMemoryCategory(_ q: String) -> String {
        if q.contains("objectif") || q.contains("but ") || q.contains("veux ") || q.contains("voudrais") { return "objectif" }
        if q.contains("aime") || q.contains("préfère") || q.contains("adore") || q.contains("déteste") { return "préférence" }
        if q.contains("habitude") || q.contains("chaque jour") || q.contains("tous les") { return "habitude" }
        if q.contains("santé") || q.contains("allergie") || q.contains("médic") || q.contains("douleur") { return "santé" }
        return "fait"
    }

    private func answer(for q: String) -> String {
        let kcal  = foods.filter  { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
        let water = waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }

        if q.contains("mémoire") || q.contains("souviens") || q.contains("retiens") || q.contains("mémorisé") {
            if memories.isEmpty { return "Je n'ai encore rien mémorisé. Dis-moi « retiens que... » pour stocker quelque chose." }
            let list = memories.prefix(5).map { "• \($0.content)" }.joined(separator: "\n")
            return "Voici ce que je mémorise sur toi :\n\(list)"
        }
        if q.contains("calor") || q.contains("manger") || q.contains("mangé") {
            return "Tu es à \(kcal) kcal aujourd'hui, objectif \(kcalGoal). Il te reste \(max(0, kcalGoal - kcal)) kcal."
        }
        if q.contains("eau") || q.contains("hydrat") || q.contains("bois") || q.contains("bu") {
            return "Tu as bu \(water) ml sur \(waterGoal) ml. \(water >= waterGoal ? "Objectif atteint !" : "Encore \(waterGoal - water) ml à boire.")"
        }
        if q.contains("jeûn") || q.contains("jeun") || q.contains("fast") {
            if let a = fasts.first(where: { $0.isActive }) {
                return "Jeûne en cours depuis \(Int(a.elapsed/3600))h\(Int(a.elapsed.truncatingRemainder(dividingBy: 3600)/60))min. Va dans Catégories › Nutrition › Jeûne."
            }
            return "Aucun jeûne en cours. Lance-le dans Catégories › Nutrition › Jeûne."
        }
        if q.contains("habitude") || q.contains("streak") {
            let done = habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
            return "Tu as validé \(done)/\(habits.count) habitudes aujourd'hui."
        }
        if q.contains("bonjour") || q.contains("salut") || q.contains("hello") || q.contains("hey") {
            return "Hello ! Je peux te dire tes calories, ton eau, ton jeûne ou tes habitudes. Dis aussi « retiens que... » pour que je mémorise quelque chose."
        }
        if q.contains("merci") { return "Avec plaisir !" }
        return "Je peux t'aider sur : calories, hydratation, jeûne, habitudes — ou mémoriser quelque chose (« retiens que... »)."
    }
}

// MARK: - Historique chat (sheet)

struct ChatHistorySheet: View {
    let messages: [ChatMessage]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(messages) { m in
                            HStack {
                                if m.fromUser { Spacer(minLength: 40) }
                                Text(m.text)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(
                                        m.fromUser ? Color.accentColor : Theme.card,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                                    .foregroundStyle(m.fromUser ? .white : .primary)
                                if !m.fromUser { Spacer(minLength: 40) }
                            }
                            .id(m.id)
                        }
                    }
                    .padding(Theme.pad)
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Barre flottante : [2 onglets] [chat direct] [2 onglets]

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    @Binding var chatInput: String
    let onSend: () -> Void
    var onOpenAssistant: () -> Void = {}

    @FocusState private var inputFocused: Bool
    @State private var chatMode = false
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appTheme") private var themeRaw = "classic"

    private static let barBg  = Color(uiColor: .secondarySystemBackground)   // blanc en clair, sombre en dark
    private static let selBg  = Color(uiColor: .systemGray5)
    private static let fieldBg = Color(uiColor: .tertiarySystemFill)
    private static let barInset: CGFloat = 18   // gauche = droite = bas, identiques (marge flottante)

    private let leftTabs:  [AppTab] = [.home, .wakeup]
    private let rightTabs: [AppTab] = [.categories, .profile]

    var body: some View {
        HStack(spacing: 6) {

            // Onglets gauche — masqués quand clavier ouvert
            if !chatMode {
                HStack(spacing: 0) {
                    ForEach(leftTabs) { t in tabBtn(t) }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // AI Chat au centre — pastille RONDE qui INVERSE ses couleurs selon le thème
            // (clair : noir + logo blanc / sombre : blanc + logo noir), débordant en haut et en bas.
            Button {
                Haptics.medium()
                onOpenAssistant()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .label))          // noir en clair, blanc en dark
                        .frame(width: 70, height: 70)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.22), radius: 8, y: 3)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))   // blanc en clair, noir en dark
                }
                .frame(width: 70, height: 70)
            }
            .buttonStyle(PressableButtonStyle())
            .frame(maxWidth: .infinity)
            .zIndex(1)

            // Onglets droite — masqués quand clavier ouvert
            if !chatMode {
                HStack(spacing: 0) {
                    ForEach(rightTabs) { t in tabBtn(t) }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 10)
        // iOS 26 : barre flottante en verre (Liquid Glass), coins concentriques.
        // En thème Verre → matériau plus fin/translucide pour un vrai effet dépoli.
        .background(themeRaw == "glass" ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial),
                    in: ConcentricRectangle(corners: .concentric, isUniform: true))
        .overlay(ConcentricRectangle(corners: .concentric, isUniform: true)
            .stroke(Theme.hairline, lineWidth: 0.5))
        .softElevation(true)
        .padding(.horizontal, Self.barInset)
        .padding(.bottom, Self.barInset)
        .animation(.spring(duration: 0.32, bounce: 0.2), value: chatMode)
    }

    private func tabBtn(_ t: AppTab) -> some View {
        Button {
            withAnimation(.spring(duration: 0.28, bounce: 0.35)) { selected = t }
            inputFocused = false
            if t == .profile { Haptics.medium() } else { Haptics.tap() }
        } label: {
            ZStack {
                if selected == t {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.volt)
                        .frame(width: 52, height: 42)
                        .shadow(color: Theme.volt.opacity(0.45), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "sel", in: ns)
                }
                Image(systemName: selected == t ? t.iconFill : t.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selected == t ? Theme.onVolt : Color.primary.opacity(0.55))
                    .animation(.spring(duration: 0.28), value: selected)
            }
            .frame(width: 58, height: 58)
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
    private var kcalToday: Int  { foods.filter  { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
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
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: goal > 0 ? value / goal : 0, lineWidth: 9, tint: Theme.volt)
                    .frame(width: 86, height: 86)
                VStack(spacing: 1) {
                    Image(systemName: icon).font(.caption).foregroundStyle(.primary)
                    Text("\(Int(value))").font(.title3.weight(.bold).monospacedDigit())
                }
            }
            VStack(spacing: 1) {
                Text(label).font(.system(size: 13, weight: .bold)).textCase(.uppercase).kerning(0.3)
                Text(goal > 0 ? "/ \(Int(goal)) \(unit)" : "").monoLabel(9).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .softElevation()
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
