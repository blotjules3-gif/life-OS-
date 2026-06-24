import SwiftUI
import SwiftData
import Charts

// MARK: - Onglets (chat retiré — input intégré dans la barre)

enum AppTab: String, CaseIterable, Identifiable {
    case camera, home, categories, profile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .camera:     return "Photo"
        case .home:       return "Accueil"
        case .categories: return "Catégories"
        case .profile:    return "Profil"
        }
    }
    var icon: String {
        switch self {
        case .camera:     return "camera"
        case .home:       return "house"
        case .categories: return "square.grid.2x2"
        case .profile:    return "person.crop.circle"
        }
    }
    var iconFill: String {
        switch self {
        case .camera:     return "camera.fill"
        case .home:       return "house.fill"
        case .categories: return "square.grid.2x2.fill"
        case .profile:    return "person.crop.circle.fill"
        }
    }
}

// MARK: - Conteneur principal

struct MainTabView: View {
    @State private var tab: AppTab = .home
    @State private var chatInput = ""
    @State private var chatMessages: [ChatMessage] = [
        ChatMessage(fromUser: false, text: "Salut ! Je suis ton assistant LifeOS. Demande-moi par ex. « combien de calories aujourd'hui ? » ou « combien d'eau ? ».")
    ]
    @State private var showChat = false

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 56) }
            FloatingTabBar(
                selected: $tab,
                chatInput: $chatInput,
                onSend: sendChat
            )
        }
        .sheet(isPresented: $showChat) {
            ChatHistorySheet(messages: chatMessages)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .camera:     CameraView()
        case .home:       ShortcutsHomeView()        // vue de ton pote
        case .categories: HoneycombCategoriesView()  // vue de ton pote
        case .profile:    ProfileView()
        }
    }

    // MARK: Envoi message

    private func sendChat() {
        let q = chatInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        chatMessages.append(ChatMessage(fromUser: true, text: q))
        chatInput = ""
        chatMessages.append(ChatMessage(fromUser: false, text: answer(for: q.lowercased())))
        showChat = true
    }

    private func answer(for q: String) -> String {
        let kcal  = foods.filter  { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
        let water = waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
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
            return "Aucun jeûne en cours. Lance-le dans Catégories › Nutrition › Jeûne intermittent."
        }
        if q.contains("habitude") || q.contains("streak") {
            let done = habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
            return "Tu as validé \(done)/\(habits.count) habitudes aujourd'hui."
        }
        if q.contains("bonjour") || q.contains("salut") || q.contains("hello") || q.contains("hey") {
            return "Hello ! Je peux te dire tes calories, ton eau, ton jeûne ou tes habitudes du jour."
        }
        if q.contains("merci") { return "Avec plaisir !" }
        return "Je peux t'aider sur : calories, hydratation, jeûne, habitudes. Reformule avec un de ces mots."
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

// MARK: - Barre flottante avec chat intégré

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    @Binding var chatInput: String
    let onSend: () -> Void

    private let leftTabs:  [AppTab] = [.camera, .home]
    private let rightTabs: [AppTab] = [.categories, .profile]

    @FocusState private var inputFocused: Bool
    @State private var chatMode = false

    var body: some View {
        HStack(spacing: 6) {

            // Onglets gauche — disparaissent en mode chat
            if !chatMode {
                HStack(spacing: 0) {
                    ForEach(leftTabs) { t in tabBtn(t) }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Input chat central
            HStack(spacing: 6) {
                // Bouton retour visible seulement en mode chat
                if chatMode {
                    Button {
                        withAnimation(.spring(duration: 0.4)) { chatMode = false }
                        inputFocused = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                TextField("Message…", text: $chatInput)
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.bg2, in: Capsule())
                    .focused($inputFocused)
                    .onSubmit(onSend)
                    .submitLabel(.send)

                if !chatInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.25), value: chatInput.isEmpty)
            .animation(.spring(duration: 0.25), value: chatMode)

            // Onglets droite — disparaissent en mode chat
            if !chatMode {
                HStack(spacing: 0) {
                    ForEach(rightTabs) { t in tabBtn(t) }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.bar)                                          // fond plat comme Instagram
        .overlay(alignment: .top) {
            Divider()                                              // séparateur fin en haut
        }
        .padding(.bottom, 0)
        // Focus → entre en mode chat
        .onChange(of: inputFocused) { _, focused in
            withAnimation(.spring(duration: 0.4)) { chatMode = focused }
        }
        // Slide haut ou bas → quitte le mode chat
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    if abs(v.translation.height) > 40 {
                        withAnimation(.spring(duration: 0.4)) { chatMode = false }
                        inputFocused = false
                    }
                }
        )
    }

    @ViewBuilder
    private func tabBtn(_ t: AppTab) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { selected = t }
            inputFocused = false
            Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected == t ? t.iconFill : t.icon)
                    .font(.system(size: selected == t ? 22 : 20, weight: .semibold))
                    .scaleEffect(selected == t ? 1.18 : 1.0)
                    .animation(.spring(duration: 0.3, bounce: 0.5), value: selected == t)
                Text(t.label)
                    .font(.system(size: 9, weight: selected == t ? .semibold : .regular))
            }
            .foregroundStyle(selected == t ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
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
