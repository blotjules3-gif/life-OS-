import SwiftUI
import SwiftData

// MARK: - Chat / Assistant

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

struct ChatView: View {
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500

    @State private var input = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(fromUser: false, text: "Salut 👋 Je suis ton assistant LifeOS. Demande-moi par ex. « combien de calories aujourd'hui ? », « combien d'eau ? », ou « où suivre mon jeûne ? ».")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(messages) { m in
                                HStack {
                                    if m.fromUser { Spacer(minLength: 40) }
                                    Text(m.text)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(m.fromUser ? Color.accentColor : Theme.card,
                                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .foregroundStyle(m.fromUser ? .white : .primary)
                                    if !m.fromUser { Spacer(minLength: 40) }
                                }
                                .id(m.id)
                            }
                            IntegrationNotice(text: "Cet assistant répond en local à partir de tes données. Pour des réponses libres et un vrai coaching, on peut le brancher sur l'API Claude (un appel réseau avec tes données en contexte).")
                                .padding(.top, 6)
                        }
                        .padding(Theme.pad)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                HStack(spacing: 10) {
                    TextField("Écris un message…", text: $input)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.bg2, in: Capsule())
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Color.accentColor)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, Theme.pad).padding(.vertical, 10)
                .background(.bar)
            }
            .background(Theme.bg)
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        messages.append(ChatMessage(fromUser: true, text: q))
        input = ""
        let reply = answer(for: q.lowercased())
        messages.append(ChatMessage(fromUser: false, text: reply))
    }

    private func answer(for q: String) -> String {
        let kcal = foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
        let water = waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
        if q.contains("calor") || q.contains("manger") || q.contains("mangé") {
            return "Tu es à \(kcal) kcal aujourd'hui, objectif \(kcalGoal). Il te reste \(max(0, kcalGoal - kcal)) kcal."
        }
        if q.contains("eau") || q.contains("hydrat") || q.contains("bois") || q.contains("bu") {
            return "Tu as bu \(water) ml sur \(waterGoal) ml. \(water >= waterGoal ? "Objectif atteint 💧" : "Encore \(waterGoal - water) ml à boire.")"
        }
        if q.contains("jeûn") || q.contains("jeun") || q.contains("fast") {
            if let a = fasts.first(where: { $0.isActive }) {
                return "Jeûne en cours depuis \(Int(a.elapsed/3600))h\(Int(a.elapsed.truncatingRemainder(dividingBy: 3600)/60))min, objectif \(a.targetHours)h. Va dans Catégories › Nutrition › Jeûne."
            }
            return "Aucun jeûne en cours. Lance-le dans Catégories › Nutrition › Jeûne intermittent."
        }
        if q.contains("habitude") || q.contains("streak") {
            let done = habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
            return "Tu as validé \(done)/\(habits.count) habitudes aujourd'hui. Continue 🔥"
        }
        if q.contains("dormir") || q.contains("sommeil") || q.contains("coucher") {
            return "Pour ton heure de coucher idéale, va dans Catégories › Sommeil › Heure de coucher optimale."
        }
        if q.contains("bonjour") || q.contains("salut") || q.contains("hello") || q.contains("hey") {
            return "Hello 👋 Je peux te dire tes calories, ton eau, ton jeûne ou tes habitudes du jour. Demande !"
        }
        if q.contains("merci") { return "Avec plaisir 🙌" }
        return "Je peux t'aider sur : calories, hydratation, jeûne, habitudes, sommeil. Reformule avec un de ces mots, ou ouvre le pôle concerné dans Catégories."
    }
}

// MARK: - Photo / Scanner

struct CameraView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ToolRow(icon: "fork.knife", title: "Scanner un plat",
                            subtitle: "Estimer les calories par photo", tint: Color(hex: 0x4CC38A)) { PhotoCalorieScaffold() }
                    ToolRow(icon: "barcode.viewfinder", title: "Scanner un code-barres",
                            subtitle: "Note santé + alternative", tint: Color(hex: 0x4CC38A)) { BarcodeScaffold() }
                    ToolRow(icon: "doc.viewfinder", title: "Scanner un document",
                            subtitle: "Coffre-fort + OCR", tint: Color(hex: 0x8A93A8)) { DocScanScaffold() }
                } header: {
                    Text("Capture")
                } footer: {
                    Text("Sur un vrai iPhone, ces outils ouvrent l'appareil photo. Sur simulateur, la caméra n'est pas disponible.")
                }
            }
            .navigationTitle("Scanner")
        }
    }
}


// MARK: - Briefing du jour (plein écran, lancé depuis Réveil)

struct DailyBriefingView: View {
    let modules: [AppCategory]
    @AppStorage("userName") private var userName = ""
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }

    private var todayTasks: [(icon: String, title: String, subtitle: String, color: Color, done: Bool)] {
        var tasks: [(icon: String, title: String, subtitle: String, color: Color, done: Bool)] = []
        for mod in modules {
            switch mod {
            case .nutrition:
                tasks.append(("fork.knife", "Petit-déjeuner", "Ajouter ton repas du matin", Color(hex: 0x4CC38A), kcalToday > 0))
                tasks.append(("drop.fill", "Hydratation", "\(waterToday) / \(waterGoal) ml buvés", Color(hex: 0x3CB2E0), waterToday >= waterGoal))
            case .fitness:
                tasks.append(("figure.run", "Activité physique", "Enregistrer une séance ou des pas", Color(hex: 0xF1746C), false))
            case .sleep:
                tasks.append(("moon.stars.fill", "Qualité du sommeil", "Évaluer ta nuit", Color(hex: 0x6C7BF1), false))
            case .mind:
                tasks.append(("brain.head.profile", "Focus mental", "5 min de méditation ou breathing", Color(hex: 0x9B6CF1), false))
            case .productivity:
                tasks.append(("checklist", "Habitudes", "\(habitsDone) / \(habits.count) complétées", Color(hex: 0x3CB2E0), habitsDone == habits.count && !habits.isEmpty))
            case .finance:
                tasks.append(("creditcard.fill", "Budget du jour", "Vérifier tes dépenses", Color(hex: 0x4CC38A), false))
            default:
                break
            }
        }
        return Array(tasks.prefix(6))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFFF3E0), Color(hex: 0xFFFAF2), Theme.bg],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 56)

                        Text("\(greeting)\(userName.isEmpty ? "" : ", \(userName)") !")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text(Date.now.formatted(date: .complete, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Progress rings
                    HStack(spacing: 10) {
                        briefingRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Kcal", color: Color(hex: 0x4CC38A), icon: "flame.fill")
                        briefingRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", color: Color(hex: 0x3CB2E0), icon: "drop.fill")
                        briefingRing(value: Double(habitsDone), goal: max(1, Double(habits.count)), label: "Habits", color: Color(hex: 0xE0A23C), icon: "checkmark.seal.fill")
                    }

                    // Task list
                    if !todayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("À faire aujourd'hui")
                                .font(.headline)

                            ForEach(Array(todayTasks.enumerated()), id: \.offset) { _, task in
                                HStack(spacing: 14) {
                                    Image(systemName: task.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(task.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title).font(.subheadline.weight(.semibold))
                                        Text(task.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if task.done {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    task.done ? Color.green.opacity(0.06) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(task.done ? Color.green.opacity(0.18) : Color.clear, lineWidth: 1)
                                )
                            }
                        }
                    }

                    // Quick actions
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Actions rapides").font(.headline)
                        HStack(spacing: 10) {
                            quickActionBtn(icon: "drop.fill", label: "+250 ml", color: Color(hex: 0x3CB2E0)) {
                                ctx.insert(WaterEntry(amountML: 250))
                            }
                            quickActionBtn(icon: "drop.fill", label: "+500 ml", color: Color(hex: 0x3CB2E0)) {
                                ctx.insert(WaterEntry(amountML: 500))
                            }
                        }
                    }

                    Button { dismiss() } label: {
                        Text("Commencer la journée")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private func briefingRing(value: Double, goal: Double, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(progress: goal > 0 ? min(1, value / goal) : 0, lineWidth: 7, tint: color)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func quickActionBtn(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profil & objectifs (redesigné)

struct ProfileView: View {
    @AppStorage("userName") private var name = ""
    @AppStorage("stepGoal") private var stepGoal = 10000
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 150
    @AppStorage("fastTarget") private var fastTarget = 16
    @AppStorage("onboardingGoalsRaw") private var onboardingGoalsRaw = ""
    @AppStorage("wakeupEnabled") private var wakeupEnabled = false
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Environment(\.modelContext) private var ctx

    @State private var steps = 0
    @State private var healthConnected = false
    @State private var showGoalEditor = false
    @State private var showWakeupDetail = false
    @State private var showBriefing = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    private var onboardingGoals: [OnboardingGoal] {
        onboardingGoalsRaw.split(separator: ",").compactMap { OnboardingGoal(rawValue: String($0)) }
    }
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var proteinToday: Double { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.protein } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    userCard
                    dailyProgressSection
                    quickLogSection
                    wakeupSection
                    Button { showGoalEditor = true } label: { goalEditorRow }
                        .buttonStyle(.plain)
                    systemSection
                }
                .padding(Theme.pad)
            }
            .background(Theme.bg)
            .navigationTitle("Profil")
            .sheet(isPresented: $showGoalEditor) {
                GoalEditorSheet(stepGoal: $stepGoal, waterGoal: $waterGoal,
                                kcalGoal: $kcalGoal, proteinGoal: $proteinGoal,
                                fastTarget: $fastTarget)
            }
            .sheet(isPresented: $showWakeupDetail) {
                WakeUpPersonalizationSheet(
                    hour: $wakeupHour,
                    minute: $wakeupMinute,
                    enabled: $wakeupEnabled,
                    modulesRaw: $recommendedModulesRaw,
                    onSchedule: scheduleWakeupAlarm
                )
            }
            .fullScreenCover(isPresented: $showBriefing) {
                DailyBriefingView(modules: recommendedModules)
            }
            .task {
                if await HealthService.shared.requestAuthorization() {
                    steps = await HealthService.shared.stepsToday()
                    healthConnected = true
                }
            }
        }
    }

    // MARK: Wakeup section

    private var wakeupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Réveil & matin").font(.headline)
                Spacer()
                Button { showWakeupDetail = true } label: {
                    Text("Personnaliser")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xE07B3C))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0xE07B3C).opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0xE07B3C), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%02d:%02d", wakeupHour, wakeupMinute))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    Text(wakeupEnabled ? "Réveil quotidien activé" : "Réveil désactivé")
                        .font(.caption)
                        .foregroundStyle(wakeupEnabled ? Color(hex: 0xE07B3C) : .secondary)
                }
                Spacer()
                Toggle("", isOn: $wakeupEnabled)
                    .tint(Color(hex: 0xE07B3C))
                    .labelsHidden()
                    .onChange(of: wakeupEnabled) { _, on in
                        if on { scheduleWakeupAlarm() } else { NotificationManager.shared.cancel(id: "lifeos.wakeup") }
                    }
            }

            Divider()

            Button { showBriefing = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                        .frame(width: 40, height: 40)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lancer ma journée")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Voir mon plan et mes priorités du matin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func scheduleWakeupAlarm() {
        Task {
            guard await NotificationManager.shared.requestAuthorization() else { return }
            NotificationManager.shared.scheduleDaily(
                id: "lifeos.wakeup",
                title: "Bonjour \(name.isEmpty ? "" : name) !",
                body: "C'est l'heure de lancer ta journée.",
                hour: wakeupHour,
                minute: wakeupMinute
            )
        }
    }

    // MARK: User card

    private var userCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                let initial = String(name.prefix(1)).uppercased()
                Text(initial.isEmpty ? "?" : initial)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                if name.isEmpty {
                    TextField("Ton prénom", text: $name)
                        .font(.title3.weight(.semibold))
                } else {
                    Text(name).font(.title3.weight(.semibold))
                }
                Text("Membre LifeOS").font(.caption).foregroundStyle(.secondary)
                if !onboardingGoals.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(onboardingGoals.prefix(3)) { g in
                            HStack(spacing: 4) {
                                Image(systemName: g.icon).font(.system(size: 9, weight: .semibold))
                                Text(String(g.label.split(separator: " ").first ?? "")).font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(g.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(g.color)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Daily progress

    private var dailyProgressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Objectifs du jour").font(.headline)
                Spacer()
                Button { showGoalEditor = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            progressRow("Pas", icon: "figure.walk", value: Double(steps), goal: Double(stepGoal), unit: "pas", color: Color(hex: 0xF1746C))
            progressRow("Eau", icon: "drop.fill", value: Double(waterToday), goal: Double(waterGoal), unit: "ml", color: Color(hex: 0x3CB2E0))
            progressRow("Calories", icon: "flame.fill", value: Double(kcalToday), goal: Double(kcalGoal), unit: "kcal", color: Color(hex: 0x4CC38A))
            progressRow("Protéines", icon: "fork.knife", value: proteinToday, goal: Double(proteinGoal), unit: "g", color: Color(hex: 0xE0A23C))
            if !habits.isEmpty {
                progressRow("Habitudes", icon: "checkmark.seal.fill", value: Double(habitsDone), goal: Double(habits.count), unit: "/ \(habits.count)", color: Color(hex: 0x9B6CF1))
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func progressRow(_ label: String, icon: String, value: Double, goal: Double, unit: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(value)) / \(Int(goal)) \(unit)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(value >= goal ? color : .secondary)
            }
            ProgressView(value: min(value, goal), total: max(1, goal)).tint(color)
        }
    }

    // MARK: Quick log

    private var quickLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ma journée").font(.headline)
            HStack(spacing: 10) {
                quickLogBtn(icon: "drop.fill", label: "+250 ml", sub: "Eau", color: Color(hex: 0x3CB2E0)) {
                    ctx.insert(WaterEntry(amountML: 250))
                }
                quickLogBtn(icon: "drop.fill", label: "+500 ml", sub: "Eau", color: Color(hex: 0x3CB2E0)) {
                    ctx.insert(WaterEntry(amountML: 500))
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quickLogBtn(icon: String, label: String, sub: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(label).font(.system(size: 13, weight: .semibold))
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Goal editor row

    private var goalEditorRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Modifier mes objectifs").font(.subheadline.weight(.medium))
                Text("Pas, eau, calories, protéines, jeûne").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: System section

    private var systemSection: some View {
        VStack(spacing: 10) {
            Button {
                Task { healthConnected = await HealthService.shared.requestAuthorization() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color(hex: 0xF1746C), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(healthConnected ? "Apple Santé connecté" : "Connecter Apple Santé")
                        .font(.subheadline)
                        .foregroundStyle(healthConnected ? .secondary : .primary)
                    Spacer()
                    if healthConnected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { _ = await NotificationManager.shared.requestAuthorization() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color(hex: 0xE0A23C), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Activer les rappels").font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LifeOS 1.0").font(.caption.weight(.medium))
                    Text("Données stockées sur l'appareil").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text("15 pôles").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }
}

// MARK: - Éditeur d'objectifs (sheet)

struct GoalEditorSheet: View {
    @Binding var stepGoal: Int
    @Binding var waterGoal: Int
    @Binding var kcalGoal: Int
    @Binding var proteinGoal: Int
    @Binding var fastTarget: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Activité") {
                    Stepper("Pas : \(stepGoal)", value: $stepGoal, in: 2000...30000, step: 500)
                }
                Section("Nutrition") {
                    Stepper("Eau : \(waterGoal) ml", value: $waterGoal, in: 500...5000, step: 250)
                    Stepper("Calories : \(kcalGoal) kcal", value: $kcalGoal, in: 1000...5000, step: 50)
                    Stepper("Protéines : \(proteinGoal) g", value: $proteinGoal, in: 30...300, step: 5)
                    Stepper("Jeûne : \(fastTarget) h", value: $fastTarget, in: 12...24, step: 1)
                }
            }
            .navigationTitle("Mes objectifs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { dismiss() }
                }
            }
        }
    }
}
