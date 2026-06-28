import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Réveil iPhone-style (plein écran)

struct AlarmFullScreenView: View {
    @ObservedObject private var alarm = AlarmManager.shared
    @AppStorage("snoozeMinutes") private var snoozeMinutes = 9
    @State private var bellPulse = false
    @State private var ringsPulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Anneaux + cloche animés
                ZStack {
                    alarmRing(index: 0, pulse: ringsPulse)
                    alarmRing(index: 1, pulse: ringsPulse)
                    alarmRing(index: 2, pulse: ringsPulse)
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 140, height: 140)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(bellPulse ? 18 : -18))
                        .animation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true), value: bellPulse)
                }
                .frame(height: 320)

                // Heure
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 96, weight: .thin, design: .default).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.top, 20)

                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)

                // Compteur
                Text("Briefing automatique dans \(alarm.secondsLeft)s")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 18)

                Spacer()

                // Boutons
                VStack(spacing: 14) {
                    Button {
                        Haptics.success()
                        alarm.stopAndShowBriefing()
                    } label: {
                        Text("Arrêter")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        alarm.snooze(minutes: snoozeMinutes)
                    } label: {
                        Text("Rappel dans \(snoozeMinutes) min")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
        .onAppear {
            bellPulse = true
            ringsPulse = true
        }
    }

    private func alarmRing(index: Int, pulse: Bool) -> some View {
        let size = CGFloat(180 + index * 70)
        let opacity = pulse ? (0.06 - Double(index) * 0.015) : (0.12 - Double(index) * 0.03)
        let duration = 0.8 + Double(index) * 0.15
        let delay = Double(index) * 0.12
        return Circle()
            .stroke(Color.white.opacity(opacity), lineWidth: 1)
            .frame(width: size, height: size)
            .scaleEffect(pulse ? 1.06 : 0.96)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay), value: pulse)
    }
}

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
                            subtitle: "Note santé + alternative", tint: Color(hex: 0x4CC38A)) { ScanProductView() }
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


// MARK: - Réveil (onglet dédié)

struct WakeUpView: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("wakeupEnabled") private var wakeupEnabled = false
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @State private var alarmTime: Date = {
        var c = Calendar.current
        return c.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    }()
    @State private var showBriefing = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    alarmCard
                    planPreviewSection
                }
                .padding(Theme.pad)
            }
            .background(Theme.bg)
            .navigationTitle("Réveil")
            .fullScreenCover(isPresented: $showBriefing) {
                DailyBriefingView(modules: recommendedModules)
            }
        }
    }

    private var alarmCard: some View {
        VStack(spacing: 18) {
            DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: alarmTime) { _, val in
                    let c = Calendar.current
                    wakeupHour = c.component(.hour, from: val)
                    wakeupMinute = c.component(.minute, from: val)
                    if wakeupEnabled { scheduleWakeupAlarm() }
                }

            Divider()

            Toggle("Réveil quotidien activé", isOn: $wakeupEnabled)
                .tint(Color.accentColor)
                .onChange(of: wakeupEnabled) { _, on in
                    if on { scheduleWakeupAlarm() } else { cancelAlarm() }
                }
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var planPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan du jour").font(.headline)

            Button { showBriefing = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 42, height: 42)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lancer ma journée")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Voir mes priorités et objectifs du jour")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if !recommendedModules.isEmpty {
                Text("Modules prioritaires")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(recommendedModules.prefix(5)) { cat in
                    NavigationLink { cat.destination } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(cat.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cat.title).font(.subheadline.weight(.medium))
                                Text(cat.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func scheduleWakeupAlarm() {
        Task {
            guard await NotificationManager.shared.requestAuthorization() else { return }
            NotificationManager.shared.scheduleAlarm(hour: wakeupHour, minute: wakeupMinute, userName: userName)
            let timeString = String(format: "%02d:%02d", wakeupHour, wakeupMinute)
            if #available(iOS 16.1, *) {
                await AlarmLiveActivityManager.shared.startScheduled(alarmTimeString: timeString)
            }
        }
    }

    private func cancelAlarm() {
        NotificationManager.shared.cancel(id: "lifeos.wakeup")
        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.end()
        }
    }
}

// MARK: - Briefing du jour (plein écran, lancé depuis Réveil)

struct DailyBriefingView: View {
    let modules: [AppCategory]
    var speakOnAppear: Bool = false

    @ObservedObject private var alarm = AlarmManager.shared
    @AppStorage("userName") private var userName = ""
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("lastBriefingDate") private var lastBriefingDate: Double = 0
    @AppStorage("lastBriefingContent") private var lastBriefingContent = ""
    @AppStorage("lastSleepQuality") private var sleepQuality = 0
    @AppStorage("lastSleepHours") private var sleepHours = 0
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("todayEnergyScore") private var todayEnergyScore = 0
    @AppStorage("todayEnergyLabel") private var todayEnergyLabel = ""
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var waveActive = false
    @State private var aiBriefing: String? = nil
    @State private var briefingLoading = false
    @State private var briefingGoals: [GoalOut] = []
    @State private var briefingChallenges: [ChallengeOut] = []
    @State private var morningMood = 0
    @State private var morningFatigue = 0
    @State private var checkinSubmitting = false
    @State private var checkinDone = false
    @State private var behavioralInsights: [String] = []

    private static let waveBars: [Double] = [8, 20, 12, 24, 10, 18, 8, 22, 14, 8]

    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

    private var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now }
    private var kcalYesterday: Int { foods.filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }.reduce(0) { $0 + $1.calories } }
    private var waterYesterday: Int { waters.filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDoneYesterday: Int { habits.filter { h in h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: yesterday) } }.count }

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

                    // Bandeau voix
                    voiceBanner

                    // Check-in matin → Score d'Énergie
                    morningCheckinCard

                    // Brief IA personnalisé
                    aiBriefingCard
                        .animation(.easeOut(duration: 0.3), value: aiBriefing != nil)
                        .animation(.easeOut(duration: 0.3), value: briefingLoading)

                    // Progress rings
                    HStack(spacing: 10) {
                        briefingRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Kcal", color: Color(hex: 0x4CC38A), icon: "flame.fill")
                        briefingRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", color: Color(hex: 0x3CB2E0), icon: "drop.fill")
                        briefingRing(value: Double(habitsDone), goal: max(1, Double(habits.count)), label: "Habits", color: Color(hex: 0xE0A23C), icon: "checkmark.seal.fill")
                    }

                    // Task list
                    if !todayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("À faire aujourd'hui").font(.headline)
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
                            quickActionBtn(icon: "drop.fill", label: "1 verre", color: Color(hex: 0x3CB2E0)) {
                                ctx.insert(WaterEntry(amountML: 250))
                            }
                            quickActionBtn(icon: "drop.fill", label: "2 verres", color: Color(hex: 0x3CB2E0)) {
                                ctx.insert(WaterEntry(amountML: 500))
                            }
                        }
                    }

                    // Insights comportementaux
                    if !behavioralInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ce qu'on a appris sur toi")
                                .font(.headline)
                            VStack(spacing: 8) {
                                ForEach(behavioralInsights, id: \.self) { insight in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0xFFBF00))
                                            .frame(width: 22, height: 22)
                                            .background(Color(hex: 0xFFBF00).opacity(0.12), in: Circle())
                                        Text(insight)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
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
        .task {
            lastBriefingDate = Date.now.timeIntervalSince1970
            lastBriefingContent = todayTasks.prefix(4).map { $0.title }.joined(separator: "|||")
            briefingLoading = true

            async let goalsTask = (try? await AgentAPI.shared.listGoals()) ?? []
            async let challengesTask = (try? await AgentAPI.shared.fetchChallenges()) ?? []
            async let insightsTask = (try? await AgentAPI.shared.fetchBehavioralInsights()) ?? []
            let (g, c, ins) = await (goalsTask, challengesTask, insightsTask)
            briefingGoals = g
            briefingChallenges = c
            behavioralInsights = ins

            let prompt = buildBriefingPrompt(goals: g, challenges: c)
            if let resp = try? await AgentAPI.shared.chat(message: prompt, module: nil, conversationID: nil) {
                aiBriefing = resp.reply
                UserDefaults.standard.set(resp.reply, forKey: "lastAIBriefing")
            }
            briefingLoading = false

            if speakOnAppear {
                try? await Task.sleep(for: .milliseconds(400))
                if let text = aiBriefing {
                    alarm.speakText(text)
                } else {
                    alarm.speakDailyPlan(userName: userName, modules: modules, waterGoal: waterGoal, kcalGoal: kcalGoal)
                }
            }
        }
        .onDisappear {
            alarm.stopSpeaking()
        }
        .onChange(of: alarm.isSpeaking) { _, speaking in
            waveActive = speaking
        }
    }

    // MARK: Check-in matin

    @ViewBuilder private var morningCheckinCard: some View {
        if checkinDone || todayEnergyScore > 0 {
            energyScoreDisplayCard
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("Bilan du matin")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                // Sommeil
                VStack(alignment: .leading, spacing: 8) {
                    Text("Qualité du sommeil")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                sleepQuality = s
                                Haptics.soft()
                            } label: {
                                Image(systemName: s <= sleepQuality ? "moon.stars.fill" : "moon.stars")
                                    .font(.system(size: 24))
                                    .foregroundStyle(s <= sleepQuality ? Color(hex: 0x6B7FD4) : Color.secondary.opacity(0.4))
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                // Humeur
                VStack(alignment: .leading, spacing: 8) {
                    Text("Humeur")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                morningMood = s
                                Haptics.soft()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(["😞", "😕", "😐", "🙂", "😄"][s - 1])
                                        .font(.system(size: 26))
                                    Circle()
                                        .fill(s == morningMood ? Color.accentColor : Color.clear)
                                        .frame(width: 6, height: 6)
                                }
                                .frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                // Énergie / fatigue
                VStack(alignment: .leading, spacing: 8) {
                    Text("Niveau d'énergie")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 0) {
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                morningFatigue = 6 - s   // 1=épuisé → fatigue=5, 5=énergique → fatigue=1
                                Haptics.soft()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: energyIcon(s))
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle((6 - s) == morningFatigue ? Color(hex: 0x4CC38A) : Color.secondary.opacity(0.4))
                                    Text(energyLabel(s))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    (6 - s) == morningFatigue
                                    ? Color(hex: 0x4CC38A).opacity(0.12)
                                    : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    submitCheckin()
                } label: {
                    Group {
                        if checkinSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Calculer mon score")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        sleepQuality > 0 && morningMood > 0 && morningFatigue > 0
                        ? Color.accentColor
                        : Color.secondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(sleepQuality == 0 || morningMood == 0 || morningFatigue == 0 || checkinSubmitting)
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    @ViewBuilder private var energyScoreDisplayCard: some View {
        let scoreColor: Color = {
            switch todayEnergyScore {
            case 85...100: return Color(hex: 0x34C759)
            case 70..<85:  return Color(hex: 0x30D158)
            case 50..<70:  return Color(hex: 0xFF9F0A)
            case 30..<50:  return Color(hex: 0xFF6B35)
            default:       return Color(hex: 0xFF3B30)
            }
        }()

        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(todayEnergyScore)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Score d'Énergie").font(.headline)
                    Text(todayEnergyLabel.isEmpty ? "—" : todayEnergyLabel)
                        .font(.subheadline)
                        .foregroundStyle(scoreColor)
                }
                Spacer()
            }
            ProgressView(value: Double(todayEnergyScore) / 100)
                .tint(scoreColor)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)
        }
        .padding(18)
        .background(
            scoreColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(scoreColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func energyIcon(_ s: Int) -> String {
        ["bolt.slash", "minus.circle", "equal.circle", "bolt", "bolt.fill"][s - 1]
    }

    private func energyLabel(_ s: Int) -> String {
        ["Épuisé", "Faible", "Correct", "Bien", "Plein"][s - 1]
    }

    private func submitCheckin() {
        checkinSubmitting = true
        Task {
            if let result = try? await AgentAPI.shared.logCheckin(
                sleepQuality: sleepQuality > 0 ? sleepQuality : nil,
                sleepHours: sleepHours > 0 ? Double(sleepHours) : nil,
                mood: morningMood > 0 ? morningMood : nil,
                fatigue: morningFatigue > 0 ? morningFatigue : nil,
                waterML: waterToday > 0 ? waterToday : nil,
                habitsDone: habitsDone,
                habitsTotal: habits.count > 0 ? habits.count : nil
            ) {
                await MainActor.run {
                    todayEnergyScore = result.energy_score ?? 0
                    todayEnergyLabel = result.label ?? ""
                }
            }
            await MainActor.run {
                checkinSubmitting = false
                withAnimation(.spring(response: 0.4)) { checkinDone = true }
            }
        }
    }

    // MARK: Bandeau voix

    @ViewBuilder private var voiceBanner: some View {
        if alarm.isSpeaking {
            HStack(spacing: 12) {
                // Visualiseur
                HStack(spacing: 3) {
                    ForEach(Array(Self.waveBars.enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.orange)
                            .frame(width: 3, height: waveActive ? h : h * 0.3)
                            .animation(
                                .easeInOut(duration: 0.28 + Double(i) * 0.04)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.06),
                                value: waveActive
                            )
                    }
                }
                .frame(height: 28)

                Text("Lecture vocale…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    alarm.stopSpeaking()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .onAppear { waveActive = true }
        } else if !speakOnAppear {
            // Bouton relance manuelle
            Button {
                if let text = aiBriefing {
                    alarm.speakText(text)
                } else {
                    alarm.speakDailyPlan(userName: userName, modules: modules, waterGoal: waterGoal, kcalGoal: kcalGoal)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Écouter mon plan du jour")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    @ViewBuilder private var aiBriefingCard: some View {
        if briefingLoading {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                            .frame(maxWidth: i == 2 ? .infinity * 0.6 : .infinity)
                            .frame(height: 11)
                    }
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let text = aiBriefing {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private func buildBriefingPrompt(goals: [GoalOut], challenges: [ChallengeOut]) -> String {
        var lines = ["[BRIEFING_MATIN]"]
        lines.append("Heure du réveil : \(String(format: "%02d:%02d", wakeupHour, wakeupMinute))")
        if !userName.isEmpty { lines.append("Utilisateur : \(userName)") }

        var yesterday: [String] = []
        if sleepQuality > 0 {
            let q = ["", "mauvaise", "passable", "correcte", "bonne", "excellente"][sleepQuality]
            yesterday.append("Sommeil : qualité \(q)\(sleepHours > 0 ? ", \(sleepHours)h" : "")")
        }
        if kcalYesterday > 0 {
            let pct = kcalGoal > 0 ? Int(100 * Double(kcalYesterday) / Double(kcalGoal)) : 0
            yesterday.append("Calories : \(kcalYesterday)/\(kcalGoal) kcal (\(pct)%)")
        }
        if waterYesterday > 0 {
            let pct = waterGoal > 0 ? Int(100 * Double(waterYesterday) / Double(waterGoal)) : 0
            yesterday.append("Eau : \(waterYesterday)/\(waterGoal) ml (\(pct)%)")
        }
        if !habits.isEmpty {
            yesterday.append("Habitudes : \(habitsDoneYesterday)/\(habits.count) complétées")
        }
        if !yesterday.isEmpty {
            lines.append("Données d'hier :")
            lines.append(contentsOf: yesterday.map { "- \($0)" })
        }

        if !challenges.isEmpty {
            lines.append("Défis actifs :")
            for ch in challenges.prefix(3) {
                var info = "- \"\(ch.title)\" — streak \(ch.streak_days) jour\(ch.streak_days > 1 ? "s" : "")"
                if let dur = ch.duration_days { info += ", J\(ch.days_elapsed)/\(dur)" }
                if ch.checkedInToday { info += " (validé aujourd'hui)" }
                lines.append(info)
            }
        }

        if !goals.isEmpty {
            lines.append("Objectifs en cours :")
            for g in goals.prefix(3) {
                lines.append("- \(g.title) (\(Int(g.progress_pct))%)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func briefingRing(value: Double, goal: Double, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(progress: goal > 0 ? min(1, value / goal) : 0, lineWidth: 7, tint: color)
                    .frame(width: 64, height: 64)
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
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
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                Text(label).font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profil utilisateur

private struct ProfileTaskItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let progress: Double
    var done: Bool { progress >= 0.99 }
}

struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appTheme") private var appThemeRaw = "classic"
    @AppStorage("userName") private var name = ""
    @AppStorage("stepGoal") private var stepGoal = 10000
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 150
    @AppStorage("fastTarget") private var fastTarget = 16
    @AppStorage("budgetGoal") private var budgetGoal = 1500
    @AppStorage("glassesGoal") private var glassesGoal = 8
    @AppStorage("focusMinGoal") private var focusMinGoal = 90
    @AppStorage("socialMaxMin") private var socialMaxMin = 60
    @AppStorage("hiddenGoalIDsRaw") private var hiddenGoalIDsRaw = ""
    @AppStorage("goalEndDatesRaw") private var goalEndDatesRaw = "{}"
    @AppStorage("profileHiddenRaw") private var profileHiddenRaw = ""
    @AppStorage("profilePinnedRaw") private var profilePinnedRaw = ""
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
    @State private var appeared = false
    @State private var challenges: [ChallengeOut] = []
    @State private var challengesLoading = true
    @State private var profileSection = 0
    @State private var showOnboardingReset = false
    @Namespace private var pickerNS

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var proteinToday: Int { Int(foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0.0) { $0 + $1.protein }) }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

    // Tâches du jour calculées depuis les modules actifs de l'utilisateur
    private var todayTasks: [ProfileTaskItem] {
        var tasks: [ProfileTaskItem] = []
        let mods = recommendedModules.isEmpty ? [AppCategory.nutrition, .fitness, .productivity] : recommendedModules
        for mod in mods {
            switch mod {
            case .nutrition:
                let kp = min(1.0, Double(kcalToday) / Double(max(1, kcalGoal)))
                tasks.append(ProfileTaskItem(icon: "flame.fill", title: "Calories", subtitle: "\(kcalToday) / \(kcalGoal) kcal", color: Color(hex: 0xF1746C), progress: kp))
                let wp = min(1.0, Double(waterToday) / Double(max(1, waterGoal)))
                tasks.append(ProfileTaskItem(icon: "drop.fill", title: "Hydratation", subtitle: "\(glassesToday) / \(glassesGoalCalc) verres", color: Color(hex: 0x3CB2E0), progress: wp))
                if proteinGoal > 0 {
                    let pp = min(1.0, Double(proteinToday) / Double(proteinGoal))
                    tasks.append(ProfileTaskItem(icon: "fork.knife", title: "Protéines", subtitle: "\(proteinToday) / \(proteinGoal) g", color: Color(hex: 0xE0A23C), progress: pp))
                }
            case .fitness:
                let sp = min(1.0, Double(steps) / Double(max(1, stepGoal)))
                tasks.append(ProfileTaskItem(icon: "figure.run", title: "Activité", subtitle: "\(steps) / \(stepGoal) pas", color: Color(hex: 0x4CC38A), progress: sp))
            case .productivity:
                let hp = habits.isEmpty ? 0.0 : min(1.0, Double(habitsDone) / Double(habits.count))
                let hSub = habits.isEmpty ? "Aucune habitude active" : "\(habitsDone)/\(habits.count) complétées"
                tasks.append(ProfileTaskItem(icon: "checklist", title: "Habitudes", subtitle: hSub, color: Color(hex: 0x9B6CF1), progress: hp))
            case .sleep:
                tasks.append(ProfileTaskItem(icon: "moon.stars.fill", title: "Sommeil", subtitle: "Évaluer ta nuit", color: Color(hex: 0x6C7BF1), progress: 0))
            case .mind:
                tasks.append(ProfileTaskItem(icon: "brain.head.profile", title: "Focus", subtitle: "5 min de méditation", color: Color(hex: 0x9B6CF1), progress: 0))
            case .finance:
                tasks.append(ProfileTaskItem(icon: "creditcard.fill", title: "Budget", subtitle: "Vérifier mes dépenses", color: Color(hex: 0x618EF1), progress: 0))
            case .invest:
                tasks.append(ProfileTaskItem(icon: "chart.line.uptrend.xyaxis", title: "Portefeuille", subtitle: "Consulter tes positions", color: Color(hex: 0x5DCFA8), progress: 0))
            case .looks:
                tasks.append(ProfileTaskItem(icon: "face.smiling", title: "Looksmaxx", subtitle: "Routine beauté du jour", color: Color(hex: 0xE0A23C), progress: 0))
            case .career:
                tasks.append(ProfileTaskItem(icon: "briefcase.fill", title: "Carrière", subtitle: "Candidatures & suivi", color: Color(hex: 0xE07B3C), progress: 0))
            case .learning:
                tasks.append(ProfileTaskItem(icon: "graduationcap.fill", title: "Apprendre", subtitle: "Flashcards & résumés", color: Color(hex: 0xE0C13C), progress: 0))
            case .social:
                tasks.append(ProfileTaskItem(icon: "person.2.fill", title: "Social", subtitle: "Contacts & événements", color: Color(hex: 0xE05A7A), progress: 0))
            case .home:
                tasks.append(ProfileTaskItem(icon: "house.fill", title: "Maison", subtitle: "Tâches & quotidien", color: Color(hex: 0x6CA0F1), progress: 0))
            default: break
            }
        }
        return Array(tasks.prefix(6))
    }

    private let tips = [
        "Chaque verre d'eau compte. L'hydratation est la base de tout.",
        "Un pas de plus qu'hier. C'est tout ce qui compte.",
        "Tes habitudes d'aujourd'hui sont ta santé de demain.",
        "Le succès, c'est la somme de petits efforts répétés.",
        "La discipline, c'est choisir ce que tu veux vraiment plutôt que ce que tu veux maintenant.",
        "L'énergie suit l'attention. Mets-la au bon endroit.",
        "Une journée complète commence par 5 min pour toi."
    ]
    private var todayTip: String { tips[Calendar.current.component(.day, from: .now) % tips.count] }

    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }

    private var topModule: AppCategory? { recommendedModules.first }

    private let glassML = 250
    private var glassesToday: Int { waterToday / glassML }
    private var glassesGoalCalc: Int { max(1, waterGoal / glassML) }

    private var alarmRingsNextDay: Bool {
        guard wakeupEnabled else { return false }
        let cal = Calendar.current
        let h = cal.component(.hour, from: .now)
        let m = cal.component(.minute, from: .now)
        return wakeupHour < h || (wakeupHour == h && wakeupMinute <= m)
    }

    // MARK: - Neomorphism helpers

    private var neoBackground: Color {
        colorScheme == .dark ? Color(hex: 0x1C1C1F) : Color(hex: 0xECEBE8)
    }
    private var neoCard: Color {
        colorScheme == .dark ? Color(hex: 0x252528) : Color(hex: 0xECEBE8)
    }
    private var neoShadowLight: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.85)
    }
    private var neoShadowDark: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color(hex: 0xB0ADA8).opacity(0.6)
    }

    // MARK: - Computed helpers

    private func parseEndDates() -> [String: Date] {
        guard let data = goalEndDatesRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                neoBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        profileHeader
                        Group {
                            if let mod = topModule {
                                NavigationLink(value: mod) {
                                    topModuleIsland
                                }
                                .buttonStyle(LifeOSPressStyle())
                            } else {
                                topModuleIsland
                            }
                        }
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                        .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.05), value: appeared)

                        nightIsland
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.12), value: appeared)

                        sectionPicker
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.18), value: appeared)

                        Group {
                            if profileSection == 0 {
                                activeGoalsSection
                                    .transition(.opacity)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("MES DÉFIS")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .kerning(1.2)
                                        if !challenges.isEmpty {
                                            Spacer()
                                            Text("\(challenges.count) actif\(challenges.count > 1 ? "s" : "")")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 4)

                                    if challengesLoading {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 36)
                                            .background(neoCard)
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                            .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
                                            .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
                                            .transition(.opacity)
                                    } else if challenges.isEmpty {
                                        challengesEmptyState
                                            .transition(.opacity)
                                    } else {
                                        ForEach(challenges) { challenge in
                                            ChallengeCard(challenge: challenge, onCheckin: {
                                                Task {
                                                    if let result = try? await AgentAPI.shared.checkinChallenge(id: challenge.id),
                                                       let idx = challenges.firstIndex(where: { $0.id == challenge.id }) {
                                                        let newStreak = (result["streak_days"]?.value as? Int) ?? challenges[idx].streak_days + 1
                                                        let updated = challenges[idx]
                                                        challenges[idx] = ChallengeOut(
                                                            id: updated.id, title: updated.title,
                                                            challenge_type: updated.challenge_type,
                                                            daily_target: updated.daily_target, unit: updated.unit,
                                                            duration_days: updated.duration_days, streak_days: newStreak,
                                                            days_elapsed: updated.days_elapsed, days_since_checkin: 0,
                                                            last_checkin_at: ISO8601DateFormatter().string(from: .now),
                                                            notes: updated.notes, is_active: updated.is_active,
                                                            started_at: updated.started_at
                                                        )
                                                        saveChallengesForWidget(challenges)
                                                    }
                                                }
                                            })
                                        }
                                        .transition(.opacity)
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                        .animation(.spring(duration: 0.35, bounce: 0.1), value: profileSection)
                        .animation(.spring(duration: 0.35, bounce: 0.1), value: challengesLoading)

                        bentoRow
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.24), value: appeared)

                        tipCard
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.30), value: appeared)

                        settingsSection
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.36), value: appeared)

                        appearanceSection
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1).delay(0.40), value: appeared)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(neoBackground, for: .navigationBar)
            .onAppear { appeared = true }
            .task {
                if await HealthService.shared.requestAuthorization() {
                    healthConnected = true
                    steps = await HealthService.shared.stepsToday()
                }
                async let challengesTask = (try? await AgentAPI.shared.fetchChallenges()) ?? []
                let ch = await challengesTask
                challenges = ch
                challengesLoading = false
                saveChallengesForWidget(challenges)
            }
            .sheet(isPresented: $showGoalEditor) {
                GoalEditorSheet(
                    stepGoal: $stepGoal, waterGoal: $waterGoal,
                    kcalGoal: $kcalGoal, proteinGoal: $proteinGoal,
                    fastTarget: $fastTarget, budgetGoal: $budgetGoal,
                    glassesGoal: $glassesGoal, focusMinGoal: $focusMinGoal,
                    socialMaxMin: $socialMaxMin,
                    hiddenGoalIDsRaw: $hiddenGoalIDsRaw,
                    goalEndDatesRaw: $goalEndDatesRaw
                )
            }
            .sheet(isPresented: $showWakeupDetail) {
                WakeUpPersonalizationSheet(
                    hour: $wakeupHour, minute: $wakeupMinute,
                    enabled: $wakeupEnabled, modulesRaw: $recommendedModulesRaw,
                    onSchedule: scheduleWakeupAlarm
                )
            }
            .fullScreenCover(isPresented: $showBriefing) {
                DailyBriefingView(modules: recommendedModules)
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            TimelineView(.everyMinute) { ctx in
                let hour = Calendar.current.component(.hour, from: ctx.date)
                let greetingText: String = {
                    switch hour {
                    case 5..<12: return "Bonjour"
                    case 12..<18: return "Bon après-midi"
                    default: return "Bonsoir"
                    }
                }()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greetingText.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(2)
                        Text(name.isEmpty ? "Mon profil" : name)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 0) {
                quickStat(icon: "flame.fill", value: "\(kcalToday)", unit: "kcal",
                          color: Color(hex: 0xF1746C),
                          progress: min(1, Double(kcalToday) / Double(max(1, kcalGoal))))
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1, height: 40)
                quickStat(icon: "drop.fill", value: "\(glassesToday)", unit: "verres",
                          color: Color(hex: 0x3CB2E0),
                          progress: min(1, Double(waterToday) / Double(max(1, waterGoal))))
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1, height: 40)
                quickStat(icon: "figure.run", value: "\(steps)", unit: "pas",
                          color: Color(hex: 0x4CC38A),
                          progress: min(1, Double(steps) / Double(max(1, stepGoal))))
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1, height: 40)
                quickStat(icon: "checkmark.seal.fill",
                          value: habits.isEmpty ? "0" : "\(habitsDone)/\(habits.count)",
                          unit: "habitudes",
                          color: Color(hex: 0x9B6CF1),
                          progress: habits.isEmpty ? 0 : min(1, Double(habitsDone) / Double(habits.count)))
            }
            .padding(.vertical, 14)

            TimelineView(.everyMinute) { ctx in
                let progress: Double = {
                    let cal = Calendar.current
                    let start = cal.startOfDay(for: ctx.date)
                    let end = cal.date(byAdding: .day, value: 1, to: start) ?? ctx.date
                    return (ctx.date.timeIntervalSince(start)) / (end.timeIntervalSince(start))
                }()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 3)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.accentColor.opacity(0.45), Color.accentColor],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.spring(duration: 1.4).delay(0.2), value: appeared)
                            .animation(.spring(duration: 0.8), value: progress)
                    }
                }
                .frame(height: 3)
                .clipShape(Capsule())
            }
        }
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: neoShadowLight, radius: 10, x: -5, y: -5)
        .shadow(color: neoShadowDark, radius: 10, x: 5, y: 5)
    }

    private func quickStat(icon: String, value: String, unit: String, color: Color, progress: Double) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(progress >= 1 ? color.opacity(0.10) : Color.clear)
                    .frame(width: 36, height: 36)
                    .animation(.spring(duration: 0.38, bounce: 0.1), value: progress >= 1)
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 1.2).delay(0.15), value: appeared)
                    .animation(.spring(duration: 0.6), value: progress)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top Module Island

    private var topModuleIsland: some View {
        let mod = topModule
        let color: Color = mod?.tint ?? appTheme.accent

        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: mod?.icon ?? "star.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text((mod?.title ?? "Module").uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color.opacity(0.8))
                    .kerning(1.2)
                Text(moduleContextLine(mod))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            TimelineView(.everyMinute) { ctx in
                let cal = Calendar.current
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ctx.date)) ?? ctx.date
                let totalMin = max(0, Int(end.timeIntervalSince(ctx.date) / 60))
                let h = totalMin / 60
                let m = totalMin % 60
                VStack(alignment: .trailing, spacing: 0) {
                    Text(h > 0 ? "\(h)h" : m > 0 ? "\(m)m" : "0h")
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                    Text("restantes")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: neoShadowLight, radius: 10, x: -5, y: -5)
        .shadow(color: neoShadowDark, radius: 10, x: 5, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1.5)
        )
    }

    private func moduleContextLine(_ mod: AppCategory?) -> String {
        guard let mod else { return "Navigue pour personnaliser ton expérience." }
        switch mod {
        case .sleep:        return "Ton sommeil façonne ta journée. Évalue ta nuit."
        case .nutrition:    return "\(kcalToday) kcal · \(glassesToday)/\(glassesGoalCalc) verres · tu avances."
        case .fitness:      return "\(steps) pas aujourd'hui · continue sur ta lancée."
        case .looks:        return "Ta routine beauté, c'est un investissement quotidien."
        case .mind:         return "Quelques minutes de calme font toute la différence."
        case .productivity: return habits.isEmpty ? "Crée tes premières habitudes pour les suivre ici." : "\(habitsDone)/\(habits.count) habitudes complétées aujourd'hui."
        case .finance:      return "Garde un œil sur ton budget — chaque euro compte."
        case .invest:       return "Les marchés n'attendent pas — consulte ton portefeuille."
        case .career:       return "Une action pour ta carrière aujourd'hui suffit."
        case .learning:     return "La régularité bat l'intensité. Avance un peu."
        case .home:         return "Maison organisée, esprit libéré."
        case .mobility:     return "Optimise tes trajets et gagne du temps."
        case .social:       return "Prends des nouvelles de quelqu'un aujourd'hui."
        case .admin:        return "Une démarche réglée = une charge mentale en moins."
        case .travel:       return "Prépare bien pour profiter encore mieux."
        case .cycle:        return "Écoute ton corps — chaque phase a ses besoins."
        }
    }

    // MARK: - Night Island (Réveil)

    private var nightIsland: some View {
        let accentColor = Color(hex: 0xE07B3C)
        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RÉVEIL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor.opacity(0.75))
                        .kerning(1.2)
                    Text(String(format: "%02d:%02d", wakeupHour, wakeupMinute))
                        .font(.system(size: 48, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(wakeupEnabled ? accentColor : .primary)
                        .opacity(wakeupEnabled ? 1.0 : 0.35)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: wakeupEnabled)
                        .animation(.spring(duration: 0.38, bounce: 0.1), value: wakeupHour)
                        .animation(.spring(duration: 0.38, bounce: 0.1), value: wakeupMinute)
                    if alarmRingsNextDay {
                        Text("demain")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accentColor.opacity(0.75))
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.spring(duration: 0.35), value: alarmRingsNextDay)
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Toggle("", isOn: $wakeupEnabled)
                        .tint(accentColor)
                        .labelsHidden()
                        .onChange(of: wakeupEnabled) { _, on in
                            if on { scheduleWakeupAlarm() }
                            else { NotificationManager.shared.cancel(id: "lifeos.wakeup") }
                        }
                    Button { showWakeupDetail = true } label: {
                        Text("Personnaliser")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 14)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            Button { showBriefing = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lancer ma journée")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Briefing vocal + priorités")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
            .buttonStyle(LifeOSPressStyle())
        }
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: neoShadowLight, radius: 10, x: -5, y: -5)
        .shadow(color: neoShadowDark, radius: 10, x: 5, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(wakeupEnabled ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.3), value: wakeupEnabled)
    }

    // MARK: - Section picker (Aujourd'hui / Objectifs)

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach([(0, "Aujourd'hui"), (1, "Défis")], id: \.0) { idx, label in
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { profileSection = idx }
                } label: {
                    ZStack {
                        if profileSection == idx {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(neoCard)
                                .shadow(color: neoShadowLight, radius: 5, x: -2, y: -2)
                                .shadow(color: neoShadowDark, radius: 5, x: 2, y: 2)
                                .matchedGeometryEffect(id: "pickerPill", in: pickerNS)
                        }
                        HStack(spacing: 5) {
                            Text(label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(profileSection == idx ? .primary : .secondary)
                            if idx == 1 && !challenges.isEmpty {
                                Text("\(challenges.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .contentTransition(.numericText())
                                    .animation(.spring(duration: 0.38, bounce: 0.1), value: challenges.count)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor, in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                    }
                }
                .buttonStyle(LifeOSPressStyle())
            }
        }
        .padding(5)
        .background(neoBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 6, x: -3, y: -3)
        .shadow(color: neoShadowDark, radius: 6, x: 3, y: 3)
    }

    // MARK: - Active Challenges

    private func saveChallengesForWidget(_ list: [ChallengeOut]) {
        guard let top = list.first else { return }
        let defaults = UserDefaults(suiteName: "group.lifeos.app") ?? .standard
        defaults.set(top.title, forKey: "widget_challenge_title")
        defaults.set(top.streak_days, forKey: "widget_challenge_streak")
        defaults.set(top.duration_days ?? 30, forKey: "widget_challenge_duration")
        defaults.set(top.days_elapsed, forKey: "widget_challenge_elapsed")
        defaults.set(top.challenge_type, forKey: "widget_challenge_type")
    }

    private var challengesEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.5))
            VStack(spacing: 6) {
                Text("Aucun défi actif")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Crée un défi avec ton assistant IA.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                NotificationCenter.default.post(name: Notification.Name("lifeOSOpenAIChat"), object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Ouvrir l'assistant")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.1), in: Capsule())
            }
            .buttonStyle(LifeOSPressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
        .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
    }

    // MARK: - Active Goals

    private var hiddenGoals: Set<String> {
        Set(profileHiddenRaw.split(separator: ",").map(String.init))
    }

    private func toggleHideGoal(_ key: String) {
        var hidden = hiddenGoals
        if hidden.contains(key) { hidden.remove(key) } else { hidden.insert(key) }
        profileHiddenRaw = hidden.joined(separator: ",")
    }

    private func pinGoal(_ key: String) {
        var pinned = Set(profilePinnedRaw.split(separator: ",").map(String.init))
        if pinned.contains(key) { pinned.remove(key) } else { pinned.insert(key) }
        profilePinnedRaw = pinned.joined(separator: ",")
    }

    private var activeGoalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AUJOURD'HUI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Button { showGoalEditor = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Modifier")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
                .buttonStyle(LifeOSPressStyle())
            }
            .padding(.horizontal, 4)

            let endDates = parseEndDates()
            let pinned = Set(profilePinnedRaw.split(separator: ",").map(String.init))
            let tasks = todayTasks
                .sorted { a, _ in pinned.contains(a.icon + a.title) }
                .filter { !hiddenGoals.contains($0.icon + $0.title) }

            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Text("Aucun module à suivre aujourd'hui.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if !hiddenGoals.isEmpty {
                        Button {
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { profileHiddenRaw = "" }
                        } label: {
                            Text("Afficher tous les modules masqués")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(neoCard)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
                .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
            } else {
                VStack(spacing: 12) {
                    ForEach(stride(from: 0, to: tasks.count, by: 2).map { $0 }, id: \.self) { rowStart in
                        HStack(spacing: 12) {
                            let task0 = tasks[rowStart]
                            let key0 = task0.icon + task0.title
                            goalCard(task: task0, endDate: endDates[key0])
                                .frame(maxWidth: .infinity)
                                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                                .animation(.spring(duration: 0.45, bounce: 0.1).delay(Double(rowStart) * 0.07 + 0.08), value: appeared)
                                .contextMenu {
                                    Button {
                                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { pinGoal(key0) }
                                    } label: {
                                        Label(pinned.contains(key0) ? "Désépingler" : "Épingler en haut",
                                              systemImage: pinned.contains(key0) ? "pin.slash" : "pin.fill")
                                    }
                                    Button(role: .destructive) {
                                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { toggleHideGoal(key0) }
                                    } label: { Label("Masquer", systemImage: "eye.slash") }
                                }
                            if rowStart + 1 < tasks.count {
                                let task1 = tasks[rowStart + 1]
                                let key1 = task1.icon + task1.title
                                goalCard(task: task1, endDate: endDates[key1])
                                    .frame(maxWidth: .infinity)
                                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                                    .animation(.spring(duration: 0.45, bounce: 0.1).delay(Double(rowStart + 1) * 0.07 + 0.08), value: appeared)
                                    .contextMenu {
                                        Button {
                                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { pinGoal(key1) }
                                        } label: {
                                            Label(pinned.contains(key1) ? "Désépingler" : "Épingler en haut",
                                                  systemImage: pinned.contains(key1) ? "pin.slash" : "pin.fill")
                                        }
                                        Button(role: .destructive) {
                                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { toggleHideGoal(key1) }
                                        } label: { Label("Masquer", systemImage: "eye.slash") }
                                    }
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                if !hiddenGoals.isEmpty {
                    Button {
                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { profileHiddenRaw = "" }
                    } label: {
                        Text("Afficher \(hiddenGoals.count) module\(hiddenGoals.count > 1 ? "s" : "") masqué\(hiddenGoals.count > 1 ? "s" : "")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(neoCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: neoShadowLight, radius: 6, x: -3, y: -3)
                            .shadow(color: neoShadowDark, radius: 6, x: 3, y: 3)
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
            }
        }
    }

    private func goalCard(task: ProfileTaskItem, endDate: Date?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(task.color.opacity(task.progress >= 1 ? 0.22 : 0.14))
                            .frame(width: 40, height: 40)
                            .animation(.spring(duration: 0.38, bounce: 0.1), value: task.progress >= 1)
                        Image(systemName: task.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(task.color)
                    }
                    if task.progress >= 1 {
                        ZStack {
                            Circle().fill(neoCard).frame(width: 16, height: 16)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(task.color)
                        }
                        .offset(x: 5, y: 5)
                        .transition(.scale(scale: 0.25).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.38, bounce: 0.25), value: task.progress >= 1)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if task.progress > 0 {
                        Text("\(min(100, Int(task.progress * 100)))%")
                            .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(task.progress >= 1 ? task.color : .secondary)
                            .contentTransition(.numericText())
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    if let end = endDate {
                        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 0)
                        Text(days > 0 ? "J-\(days)" : "Échu")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(days <= 3 ? Color(hex: 0xF1746C) : task.color)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background((days <= 3 ? Color(hex: 0xF1746C) : task.color).opacity(0.12), in: Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text(task.subtitle)
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if task.progress > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(task.color.opacity(0.12))
                            .frame(height: 4)
                        Capsule()
                            .fill(task.color)
                            .frame(width: g.size.width * min(1, max(0, task.progress)), height: 4)
                            .animation(.spring(duration: 1.0).delay(0.2), value: appeared)
                            .animation(.spring(duration: 0.5), value: task.progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(14)
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: neoShadowLight, radius: 7, x: -3, y: -3)
        .shadow(color: neoShadowDark, radius: 7, x: 3, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(task.color.opacity(task.progress >= 1 ? 0.4 : 0), lineWidth: 1.5)
                .animation(.spring(duration: 0.38, bounce: 0.1), value: task.progress >= 1)
        )
    }

    // MARK: - Eau rapide

    private var bentoRow: some View {
        let waterColor = Color(hex: 0x3CB2E0)
        let waterProgress = min(1.0, Double(waterToday) / Double(max(1, waterGoal)))
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(waterColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(waterColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("EAU")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(glassesToday)")
                            .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text("/ \(glassesGoalCalc) verres")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        ctx.insert(WaterEntry(amountML: 250)); Haptics.tap()
                    } label: {
                        Text("+1")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(waterColor)
                            .frame(minWidth: 52, minHeight: 44)
                            .background(waterColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(LifeOSPressStyle())
                    Button {
                        ctx.insert(WaterEntry(amountML: 750)); Haptics.tap()
                    } label: {
                        Text("+3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(waterColor)
                            .frame(minWidth: 52, minHeight: 44)
                            .background(waterColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(waterColor.opacity(0.10)).frame(height: 3)
                    Capsule()
                        .fill(waterColor)
                        .frame(width: g.size.width * waterProgress, height: 3)
                        .animation(.spring(duration: 0.6), value: waterProgress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
        .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
    }

    // MARK: - Tip Card

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONSEIL DU JOUR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(1.2)
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                Text(todayTip)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
        .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
    }

    // MARK: - Paramètres

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RÉGLAGES")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(1.2)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                settingsRow(icon: "heart.fill", iconColor: Color(hex: 0xF1746C),
                            label: healthConnected ? "Apple Santé connecté" : "Connecter Apple Santé") {
                    if healthConnected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x4CC38A))
                    } else {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                } action: {
                    Task {
                        let result = await HealthService.shared.requestAuthorization()
                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { healthConnected = result }
                    }
                }
                Divider().opacity(0.1).padding(.leading, 50)
                settingsRow(icon: "bell.fill", iconColor: Color(hex: 0xE0A23C), label: "Activer les rappels") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                } action: {
                    Task { _ = await NotificationManager.shared.requestAuthorization() }
                }
                Divider().opacity(0.1).padding(.leading, 50)
                settingsRow(icon: "slider.horizontal.3", iconColor: Color.accentColor, label: "Modifier mes objectifs") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                } action: {
                    showGoalEditor = true
                }
            }
            .background(neoCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
            .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)

            Button { showOnboardingReset = true } label: {
                Text("Refaire l'onboarding")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(hex: 0xF1746C))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: 0xF1746C).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
                    .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
            }
            .buttonStyle(LifeOSPressStyle())
            .confirmationDialog("Réinitialiser le profil ?", isPresented: $showOnboardingReset, titleVisibility: .visible) {
                Button("Recommencer", role: .destructive) {
                    let ud = UserDefaults.standard
                    for key in ["onboardingDone", "userName", "userGender", "onboardingGoalsRaw",
                                "recommendedModules", "wakeupEnabled", "wakeupHour", "wakeupMinute",
                                "wakeupRepeatDays", "wakeupMessage", "snoozeMinutes",
                                "stepGoal", "kcalGoal", "waterGoal", "proteinGoal",
                                "fastTarget", "budgetGoal", "glassesGoal", "focusMinGoal", "socialMaxMin",
                                "hiddenGoalIDsRaw", "goalEndDatesRaw",
                                "profileHiddenRaw", "profilePinnedRaw"] {
                        ud.removeObject(forKey: key)
                    }
                }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Toutes tes préférences seront supprimées.")
            }

            HStack {
                Text("LifeOS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · Données stockées localement")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text("\(AppCategory.allCases.count) modules").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APPARENCE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(1.2)
                .padding(.horizontal, 4)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { th in
                        let selected = appThemeRaw == th.rawValue
                        Button {
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { appThemeRaw = th.rawValue }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(th.accent.gradient)
                                        .frame(width: 42, height: 42)
                                        .shadow(color: selected ? th.accent.opacity(0.35) : .clear, radius: 6, x: 2, y: 3)
                                    Image(systemName: th.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .overlay(Circle().stroke(th.accent, lineWidth: selected ? 2.5 : 0))
                                .padding(2)
                                Text(th.label)
                                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .primary : .secondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }
                }
                Text("Thème actif dans toute l'app — modifiable à tout moment.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(neoCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
            .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
        }
    }

    private func settingsRow<T: View>(icon: String, iconColor: Color, label: String,
                                      @ViewBuilder trailing: () -> T, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(label).font(.subheadline).foregroundStyle(.primary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
        .buttonStyle(LifeOSPressStyle())
    }


    private func scheduleWakeupAlarm() {
        Task {
            guard await NotificationManager.shared.requestAuthorization() else { return }
            NotificationManager.shared.scheduleAlarm(
                hour: wakeupHour,
                minute: wakeupMinute,
                userName: name
            )
            // Start Live Activity NOW so the widget appears on Lock Screen immediately
            let timeString = String(format: "%02d:%02d", wakeupHour, wakeupMinute)
            if #available(iOS 16.1, *) {
                await AlarmLiveActivityManager.shared.startScheduled(alarmTimeString: timeString)
            }
        }
    }
}

// MARK: - Press scale button style

private struct LifeOSPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(duration: 0.15, bounce: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Personnalisation réveil (sheet avancée)

struct WakeUpPersonalizationSheet: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var enabled: Bool
    @Binding var modulesRaw: String
    let onSchedule: () -> Void

    @AppStorage("userName") private var userName = ""
    @AppStorage("wakeupRepeatDays") private var repeatDaysRaw = "1,2,3,4,5,6,7"
    @AppStorage("wakeupMessage") private var customMessage = ""
    @AppStorage("snoozeMinutes") private var snoozeMinutes = 9
    @Environment(\.dismiss) private var dismiss

    @State private var alarmTime: Date = .now

    private let allModules: [(AppCategory, String, String)] = [
        (.nutrition, "Nutrition", "fork.knife"),
        (.fitness,   "Fitness",   "figure.run"),
        (.sleep,     "Sommeil",   "moon.stars.fill"),
        (.mind,      "Mental",    "brain.head.profile"),
        (.productivity, "Productivité", "checklist"),
        (.finance,   "Finance",   "creditcard.fill"),
    ]

    private let dayNames = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private var selectedDays: Set<Int> {
        Set(repeatDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var selectedModules: Set<String> {
        Set(modulesRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            alarmTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
                        }
                        .onChange(of: alarmTime) { _, val in
                            let c = Calendar.current
                            hour = c.component(.hour, from: val)
                            minute = c.component(.minute, from: val)
                        }
                    Toggle("Réveil activé", isOn: $enabled)
                        .tint(Color(hex: 0xE07B3C))
                } header: { Text("Heure de réveil") }

                Section {
                    HStack(spacing: 6) {
                        ForEach(Array(dayNames.enumerated()), id: \.offset) { idx, name in
                            let day = idx + 1
                            let on = selectedDays.contains(day)
                            Button {
                                var days = selectedDays
                                if on { days.remove(day) } else { days.insert(day) }
                                repeatDaysRaw = days.sorted().map(String.init).joined(separator: ",")
                            } label: {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(on ? Color(hex: 0xE07B3C) : Theme.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(on ? .white : .secondary)
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(LifeOSPressStyle())
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Jours actifs") }

                Section {
                    ForEach(allModules, id: \.0.rawValue) { cat, label, icon in
                        let on = selectedModules.contains(cat.rawValue)
                        Button {
                            var mods = selectedModules
                            if on { mods.remove(cat.rawValue) } else { mods.insert(cat.rawValue) }
                            modulesRaw = mods.joined(separator: ",")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(cat.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? cat.tint : Color.secondary)
                                    .font(.system(size: 18))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Plan du matin") }
                  footer: { Text("Ces pôles apparaissent en priorité dans ton briefing du matin.") }

                Section {
                    TextField("Ex: C'est ton moment. Fonce.", text: $customMessage)
                        .foregroundStyle(.primary)
                    Stepper("Rappel snooze : \(snoozeMinutes) min", value: $snoozeMinutes, in: 5...30, step: 5)
                } header: { Text("Personnalisation") }
            }
            .navigationTitle("Mon réveil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        if enabled { onSchedule() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Éditeur d'objectifs (sheet)

struct GoalEditorSheet: View {

    // MARK: - Valeurs (bindings existants)
    @Binding var stepGoal: Int
    @Binding var waterGoal: Int
    @Binding var kcalGoal: Int
    @Binding var proteinGoal: Int
    @Binding var fastTarget: Int
    @Binding var budgetGoal: Int
    @Binding var glassesGoal: Int
    @Binding var focusMinGoal: Int
    @Binding var socialMaxMin: Int

    // MARK: - Nouveaux bindings
    @Binding var hiddenGoalIDsRaw: String
    @Binding var goalEndDatesRaw: String

    @Environment(\.dismiss) private var dismiss
    @State private var endDates: [String: Date] = [:]
    @State private var expandedID: String? = nil

    // MARK: - Catalogue

    struct GoalDef: Identifiable {
        let id: String
        let title: String
        let icon: String
        let colorHex: UInt
        let section: String
    }

    private let catalog: [GoalDef] = [
        GoalDef(id: "steps",   title: "Pas quotidiens",     icon: "figure.run",          colorHex: 0x4CC38A, section: "Activité"),
        GoalDef(id: "glasses", title: "Verres d'eau",        icon: "cup.and.saucer.fill", colorHex: 0x3CB2E0, section: "Nutrition"),
        GoalDef(id: "water",   title: "Volume eau",           icon: "drop.fill",           colorHex: 0x3CB2E0, section: "Nutrition"),
        GoalDef(id: "kcal",    title: "Calories",             icon: "flame.fill",          colorHex: 0xF1746C, section: "Nutrition"),
        GoalDef(id: "protein", title: "Protéines",            icon: "fork.knife",          colorHex: 0xE0A23C, section: "Nutrition"),
        GoalDef(id: "fast",    title: "Jeûne intermittent",   icon: "clock",               colorHex: 0x5DCFA8, section: "Nutrition"),
        GoalDef(id: "focus",   title: "Temps de focus",       icon: "brain.head.profile",  colorHex: 0x9B6CF1, section: "Focus"),
        GoalDef(id: "social",  title: "Réseaux sociaux max",  icon: "iphone.slash",        colorHex: 0xE05A7A, section: "Focus"),
        GoalDef(id: "budget",  title: "Budget mensuel",       icon: "creditcard.fill",     colorHex: 0x618EF1, section: "Finances"),
    ]

    private var hiddenIDs: Set<String> {
        Set(hiddenGoalIDsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
    private var active: [GoalDef] { catalog.filter { !hiddenIDs.contains($0.id) } }
    private var inactive: [GoalDef] { catalog.filter { hiddenIDs.contains($0.id) } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(active) { goal in goalRow(goal) }
                        .onDelete { idx in
                            var hidden = hiddenIDs
                            idx.map { active[$0].id }.forEach { hidden.insert($0) }
                            hiddenGoalIDsRaw = hidden.joined(separator: ",")
                        }
                } header: {
                    Text("Objectifs actifs")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(nil)
                } footer: {
                    Text("Glissez vers la gauche pour retirer un objectif.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                if !inactive.isEmpty {
                    Section {
                        ForEach(inactive) { goal in addRow(goal) }
                    } header: {
                        Text("Ajouter un objectif")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mes objectifs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { persistEndDates(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { endDates = loadEndDates() }
        }
    }

    // MARK: - Ligne objectif actif

    @ViewBuilder
    private func goalRow(_ goal: GoalDef) -> some View {
        let color = Color(hex: goal.colorHex)
        let isExpanded = expandedID == goal.id
        let endDate = endDates[goal.id]
        let expired = endDate.map { $0 < .now } ?? false

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Icône
                Image(systemName: goal.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                // Titre + date fin
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    if let d = endDate {
                        Text(expired ? "Expiré" : "Jusqu'au \(d.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(expired ? Color(hex: 0xF1746C) : color.opacity(0.8))
                    }
                }

                Spacer()

                // Valeur + boutons +/-
                VStack(alignment: .trailing, spacing: 6) {
                    Text(valueText(for: goal.id))
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(expired ? Color(hex: 0xF1746C) : color)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25, bounce: 0.1), value: valueText(for: goal.id))
                    stepperView(for: goal.id)
                }

                // Bouton calendrier
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                        expandedID = isExpanded ? nil : goal.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "calendar.badge.minus" : "calendar.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isExpanded ? color : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            isExpanded ? color.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(LifeOSPressStyle())
            }
            .padding(.vertical, 6)

            // Panneau date
            if isExpanded {
                Divider().padding(.top, 8)
                datePicker(for: goal.id, color: color)
                    .padding(.bottom, 8)
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.15), value: isExpanded)
    }

    // MARK: - Panneau choix de date

    @ViewBuilder
    private func datePicker(for id: String, color: Color) -> some View {
        let presets: [(label: String, days: Int)] = [
            ("1 sem", 7), ("2 sem", 14), ("1 mois", 30), ("3 mois", 90)
        ]
        VStack(alignment: .leading, spacing: 12) {
            Text("Durée de l'objectif")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Presets
                    ForEach(presets, id: \.days) { preset in
                        let target = Calendar.current.date(byAdding: .day, value: preset.days, to: .now)!
                        let selected = matchesPreset(endDates[id], days: preset.days)
                        Button {
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { endDates[id] = target }
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selected ? .white : color)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(selected ? color : color.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }

                    // Sans limite
                    let noLimit = endDates[id] == nil
                    Button {
                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { _ = endDates.removeValue(forKey: id) }
                    } label: {
                        Text("Sans limite")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(noLimit ? .white : .secondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(noLimit ? Color.secondary : Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
                .padding(.horizontal, 2)
            }

            // DatePicker personnalisé (si une date est déjà choisie)
            if endDates[id] != nil {
                DatePicker(
                    "Date précise",
                    selection: Binding(
                        get: { endDates[id] ?? Calendar.current.date(byAdding: .day, value: 7, to: .now)! },
                        set: { endDates[id] = $0 }
                    ),
                    in: Calendar.current.date(byAdding: .day, value: 1, to: .now)!...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(color)
            }
        }
    }

    // MARK: - Ligne ajout

    @ViewBuilder
    private func addRow(_ goal: GoalDef) -> some View {
        let color = Color(hex: goal.colorHex)
        Button {
            var hidden = hiddenIDs
            hidden.remove(goal.id)
            hiddenGoalIDsRaw = hidden.joined(separator: ",")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title).font(.system(size: 14)).foregroundStyle(.primary)
                    Text(goal.section).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Boutons +/- personnalisés

    @ViewBuilder
    private func stepperView(for id: String) -> some View {
        switch id {
        case "steps":   customStepper(value: $stepGoal,    min: 1000,  max: 30000, step: 500)
        case "water":   customStepper(value: $waterGoal,   min: 500,   max: 5000,  step: 250)
        case "kcal":    customStepper(value: $kcalGoal,    min: 1000,  max: 5000,  step: 50)
        case "protein": customStepper(value: $proteinGoal, min: 30,    max: 300,   step: 5)
        case "fast":    customStepper(value: $fastTarget,  min: 12,    max: 24,    step: 1)
        case "budget":  customStepper(value: $budgetGoal,  min: 100,   max: 20000, step: 50)
        case "glasses": customStepper(value: $glassesGoal, min: 1,     max: 20,    step: 1)
        case "focus":   customStepper(value: $focusMinGoal,min: 15,    max: 480,   step: 15)
        case "social":  customStepper(value: $socialMaxMin,min: 5,     max: 300,   step: 5)
        default:        EmptyView()
        }
    }

    private func customStepper(value: Binding<Int>, min: Int, max: Int, step: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                if value.wrappedValue - step >= min {
                    value.wrappedValue -= step
                    Haptics.tap()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(value.wrappedValue - step >= min ? .primary : .tertiary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())

            Button {
                if value.wrappedValue + step <= max {
                    value.wrappedValue += step
                    Haptics.tap()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(value.wrappedValue + step <= max ? .primary : .tertiary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())
            .padding(.leading, 6)
        }
    }

    // MARK: - Texte valeur

    private func valueText(for id: String) -> String {
        switch id {
        case "steps":   return "\(stepGoal) pas"
        case "water":   return "\(waterGoal) ml"
        case "kcal":    return "\(kcalGoal) kcal"
        case "protein": return "\(proteinGoal) g"
        case "fast":    return "\(fastTarget) h"
        case "budget":  return "\(budgetGoal) €"
        case "glasses": return "\(glassesGoal) verres/j"
        case "focus":   return "\(focusMinGoal) min/j"
        case "social":  return "\(socialMaxMin) min max"
        default:        return ""
        }
    }

    // MARK: - Persistence end dates

    private func matchesPreset(_ date: Date?, days: Int) -> Bool {
        guard let d = date else { return false }
        let diff = d.timeIntervalSince(.now) / 86400
        return abs(diff - Double(days)) < 1.0
    }

    private func loadEndDates() -> [String: Date] {
        guard let data = goalEndDatesRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return dict.compactMapValues { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    }

    private func persistEndDates() {
        let dict = endDates.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(dict),
           let str = String(data: data, encoding: .utf8) {
            goalEndDatesRaw = str
        }
    }
}

// MARK: - Check sommeil → humeur → score (parcours matin complet)

struct SleepCheckSheet: View {
    let onContinue: () -> Void

    @Environment(\.modelContext) private var ctx
    @AppStorage("todayEnergyScore") private var todayEnergyScore = 0
    @AppStorage("todayEnergyLabel") private var todayEnergyLabel = ""

    @State private var step = 1
    @State private var quality = 0
    @State private var hours = 7
    @State private var note = ""
    @State private var mood = 0
    @State private var fatigue = 0
    @State private var appeared = false
    @State private var submitting = false
    @State private var displayScore = 0

    private let qualities: [(label: String, icon: String, color: Color)] = [
        ("Terrible", "cloud.rain.fill", Color(hex: 0xF1746C)),
        ("Mauvais",  "cloud.fill",      Color(hex: 0xE0A23C)),
        ("Correct",  "cloud.sun.fill",  Color(hex: 0x4CC38A).opacity(0.7)),
        ("Bien",     "sun.max.fill",    Color(hex: 0x4CC38A)),
        ("Excellent","sparkles",        Color(hex: 0x3CB2E0)),
    ]
    private let moodEmoji = ["😞", "😕", "😐", "🙂", "😄"]
    private let eIcons    = ["bolt.slash","minus.circle","equal.circle","bolt","bolt.fill"]
    private let eLabels   = ["Épuisé","Faible","Correct","Bien","Plein"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if step == 1 {
                    sleepStep
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                if step == 2 {
                    feelStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                if step == 3 {
                    revealStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(duration: 0.38, bounce: 0.08), value: step)
            .onAppear { withAnimation { appeared = true } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onContinue() }.foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: — Étape 1 : Sommeil

    private var sleepStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                stepHeader(icon: "moon.stars.fill", color: Color(hex: 0x6C7BF1),
                           title: "Comment tu as dormi ?",
                           subtitle: "Cette info personnalise ton briefing")
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(duration: 0.5, bounce: 0.3), value: appeared)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { i in
                        let q = qualities[i - 1]; let sel = quality == i
                        Button {
                            withAnimation(.spring(duration: 0.25, bounce: 0.35)) { quality = i }
                            Haptics.tap()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: q.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(sel ? q.color : Color.secondary.opacity(0.4))
                                    .scaleEffect(sel ? 1.15 : 1)
                                Text(q.label)
                                    .font(.system(size: 9, weight: sel ? .semibold : .regular))
                                    .foregroundStyle(sel ? q.color : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(sel ? q.color.opacity(0.1) : Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(sel ? q.color.opacity(0.5) : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
                .animation(.spring(duration: 0.5).delay(0.16), value: appeared)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Heures de sommeil", systemImage: "clock.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        Button { if hours > 1 { hours -= 1; Haptics.tap() } } label: {
                            Image(systemName: "minus").font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48).contentShape(Rectangle())
                        }.foregroundStyle(.primary)
                        Text("\(hours)h")
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .frame(maxWidth: .infinity)
                        Button { if hours < 14 { hours += 1; Haptics.tap() } } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48).contentShape(Rectangle())
                        }.foregroundStyle(.primary)
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).animation(.spring(duration: 0.5).delay(0.22), value: appeared)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Note rapide (optionnel)", systemImage: "text.alignleft")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("Cauchemar, réveil nocturne, rêve…", text: $note, axis: .vertical)
                        .font(.system(size: 14)).lineLimit(3).padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).animation(.spring(duration: 0.5).delay(0.28), value: appeared)

                VStack(spacing: 10) {
                    Button {
                        saveSleep()
                        withAnimation(.spring(duration: 0.35)) { step = 2 }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Continuer").font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right").font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(quality > 0 ? Color.accentColor : Color.secondary.opacity(0.2),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(quality > 0 ? .white : .secondary)
                    }
                    .buttonStyle(LifeOSPressStyle()).disabled(quality == 0)

                    Button { onContinue() } label: {
                        Text("Passer").font(.system(size: 14)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).animation(.spring(duration: 0.5).delay(0.34), value: appeared)

                Spacer(minLength: 20)
            }
            .padding(.top, 20)
        }
    }

    // MARK: — Étape 2 : Humeur + Énergie

    private var feelStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    stepHeader(icon: "face.smiling.fill", color: Color(hex: 0xFF9F0A),
                               title: "Comment tu te sens ?",
                               subtitle: "2 questions rapides")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Humeur du matin")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        HStack(spacing: 0) {
                            ForEach(1...5, id: \.self) { s in
                                Button {
                                    withAnimation(.spring(duration: 0.2, bounce: 0.4)) { mood = s }
                                    Haptics.soft()
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(moodEmoji[s - 1]).font(.system(size: 32))
                                            .scaleEffect(mood == s ? 1.25 : 0.9)
                                            .opacity(mood == 0 || mood == s ? 1 : 0.35)
                                        Circle().fill(mood == s ? Color.accentColor : Color.clear)
                                            .frame(width: 5, height: 5)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Niveau d'énergie")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { s in
                                let sel = (6 - s) == fatigue
                                Button {
                                    withAnimation(.spring(duration: 0.2, bounce: 0.3)) { fatigue = 6 - s }
                                    Haptics.soft()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: eIcons[s - 1])
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundStyle(sel ? Color(hex: 0x4CC38A) : Color.secondary.opacity(0.4))
                                            .scaleEffect(sel ? 1.15 : 1)
                                        Text(eLabels[s - 1])
                                            .font(.system(size: 10, weight: sel ? .semibold : .regular))
                                            .foregroundStyle(sel ? Color(hex: 0x4CC38A) : .secondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(sel ? Color(hex: 0x4CC38A).opacity(0.1) : Theme.card))
                                }.buttonStyle(LifeOSPressStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 24)
            }

            VStack(spacing: 10) {
                Button { submitAndReveal() } label: {
                    Group {
                        if submitting {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill").font(.system(size: 14))
                                Text("Voir mon score").font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(mood > 0 && fatigue > 0 ? Color.accentColor : Color.secondary.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(mood > 0 && fatigue > 0 ? .white : .secondary)
                }
                .buttonStyle(LifeOSPressStyle())
                .disabled(mood == 0 || fatigue == 0 || submitting)

                Button { onContinue() } label: {
                    Text("Passer").font(.system(size: 14)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
            .background(Theme.bg)
        }
    }

    // MARK: — Étape 3 : Révélation du score

    private var revealStep: some View {
        let sc = scoreColor
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 36) {
                ZStack {
                    Circle().stroke(sc.opacity(0.12), lineWidth: 12).frame(width: 180, height: 180)
                    Circle()
                        .trim(from: 0, to: CGFloat(displayScore) / 100)
                        .stroke(sc, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 1.2), value: displayScore)
                    VStack(spacing: 2) {
                        Text("\(displayScore)")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(sc)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 1.2), value: displayScore)
                        Text("/ 100").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 8) {
                    Text(todayEnergyLabel.isEmpty ? "—" : todayEnergyLabel)
                        .font(.system(size: 26, weight: .bold))
                    Text(scoreMessage)
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button { onContinue() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill").font(.system(size: 14))
                    Text("Lancer mon briefing").font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(sc, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(LifeOSPressStyle())
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .onAppear { animateScore() }
    }

    // MARK: — Helpers partagés

    @ViewBuilder
    private func stepHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(color)
            }
            Text(title).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var scoreColor: Color {
        switch todayEnergyScore {
        case 85...100: return Color(hex: 0x34C759)
        case 70..<85:  return Color(hex: 0x30D158)
        case 50..<70:  return Color(hex: 0xFF9F0A)
        case 30..<50:  return Color(hex: 0xFF6B35)
        default:       return Color(hex: 0xFF3B30)
        }
    }

    private var scoreMessage: String {
        switch todayEnergyScore {
        case 85...100: return "Excellente forme. Tu es prêt(e) à tout."
        case 70..<85:  return "Belle énergie. Bonne journée en vue."
        case 50..<70:  return "Énergie correcte. Rythme doux pour commencer."
        case 30..<50:  return "Besoin de récupérer. Sois indulgent(e) avec toi."
        default:       return "Journée difficile. L'essentiel, pas le surplus."
        }
    }

    private func saveSleep() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSleepCheckDate")
        UserDefaults.standard.set(quality, forKey: "lastSleepQuality")
        UserDefaults.standard.set(hours, forKey: "lastSleepHours")
        guard !note.isEmpty else { return }
        let dream = DreamEntry(title: "Nuit du \(Date.now.formatted(.dateTime.day().month()))",
                               text: note, mood: quality)
        ctx.insert(dream)
    }

    private func submitAndReveal() {
        submitting = true
        Task {
            if let result = try? await AgentAPI.shared.logCheckin(
                sleepQuality: quality > 0 ? quality : nil,
                sleepHours: Double(hours),
                mood: mood > 0 ? mood : nil,
                fatigue: fatigue > 0 ? fatigue : nil
            ) {
                await MainActor.run {
                    todayEnergyScore = result.energy_score ?? 0
                    todayEnergyLabel = result.label ?? ""
                }
            }
            await MainActor.run {
                submitting = false
                if mood > 0 { ctx.insert(MoodEntry(score: mood, note: "")) }
                withAnimation(.spring(duration: 0.35)) { step = 3 }
            }
        }
    }

    private func animateScore() {
        let target = todayEnergyScore
        guard target > 0 else { return }
        withAnimation(.easeOut(duration: 1.2)) { displayScore = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { Haptics.tap() }
    }
}

// MARK: - ChallengeCard

struct ChallengeCard: View {
    let challenge: ChallengeOut
    let onCheckin: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var neoCard: Color {
        colorScheme == .dark ? Color(hex: 0x252528) : Color(hex: 0xECEBE8)
    }
    private var neoShadowLight: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.85)
    }
    private var neoShadowDark: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color(hex: 0xB0ADA8).opacity(0.6)
    }

    private var typeColor: Color {
        switch challenge.challenge_type {
        case "water":     return Color(hex: 0x3CB2E0)  // bleu = hydratation
        case "sport":     return Color(hex: 0x4CC38A)  // vert = activité physique (= steps)
        case "smoking":   return Color(hex: 0xE05A7A)  // rose = cessation (distinct)
        case "meditation":return Color(hex: 0x9B6CF1)  // violet = mental/focus
        case "nutrition": return Color(hex: 0xF1746C)  // rouge = calories/énergie
        case "sleep":     return Color(hex: 0x6C7BF1)  // indigo = nuit
        default:          return Color.accentColor
        }
    }

    private var typeIcon: String {
        switch challenge.challenge_type {
        case "water":      return "drop.fill"
        case "sport":      return "figure.run"
        case "smoking":    return "smoke.fill"
        case "meditation": return "brain.head.profile"
        case "nutrition":  return "leaf.fill"
        case "sleep":      return "moon.stars.fill"
        default:           return "flame.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icône type
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(typeColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(typeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let days = challenge.duration_days {
                            Text("J\(challenge.days_elapsed)/\(days)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if challenge.streak_days > 0 {
                            Label("\(challenge.streak_days)j", systemImage: "flame.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0xE07B3C))
                        }
                    }
                }

                Spacer()

                // Bouton check-in
                Button(action: onCheckin) {
                    ZStack {
                        Circle()
                            .fill(challenge.checkedInToday ? typeColor : typeColor.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: challenge.checkedInToday ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(challenge.checkedInToday ? .white : typeColor)
                            .scaleEffect(challenge.checkedInToday ? 1.0 : 0.85)
                    }
                    .animation(.spring(duration: 0.38, bounce: 0.25), value: challenge.checkedInToday)
                }
                .buttonStyle(LifeOSPressStyle())
                .disabled(challenge.checkedInToday)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Barre de progression
            if let total = challenge.duration_days, total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(typeColor.opacity(0.1)).frame(height: 3)
                        Capsule()
                            .fill(typeColor)
                            .frame(width: geo.size.width * challenge.progressFraction, height: 3)
                            .animation(.spring(duration: 0.6, bounce: 0.1), value: challenge.progressFraction)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
        .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    challenge.checkedInToday ? typeColor.opacity(0.55) :
                    challenge.isAbandoned ? Color(hex: 0xF1746C).opacity(0.45) : Color.clear,
                    lineWidth: 1.5
                )
                .animation(.spring(duration: 0.38, bounce: 0.1), value: challenge.checkedInToday)
                .animation(.spring(duration: 0.38, bounce: 0.1), value: challenge.isAbandoned)
        )
    }
}
