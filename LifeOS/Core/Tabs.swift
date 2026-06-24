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
    var speakOnAppear: Bool = false

    @ObservedObject private var alarm = AlarmManager.shared
    @AppStorage("userName") private var userName = ""
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var waveActive = false

    private static let waveBars: [Double] = [8, 20, 12, 24, 10, 18, 8, 22, 14, 8]

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

                    // Bandeau voix
                    voiceBanner

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
        .onAppear {
            if speakOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    alarm.speakDailyPlan(
                        userName: userName,
                        modules: modules,
                        waterGoal: waterGoal,
                        kcalGoal: kcalGoal
                    )
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
                alarm.speakDailyPlan(userName: userName, modules: modules, waterGoal: waterGoal, kcalGoal: kcalGoal)
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
    @State private var appeared = false

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
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    heroSection
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                        .animation(.spring(duration: 0.5, bounce: 0.2), value: appeared)

                    progressSection
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.08), value: appeared)

                    quickActionsSection
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.16), value: appeared)

                    wakeupSection
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.24), value: appeared)

                    settingsSection
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.32), value: appeared)
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.bg)
            .navigationTitle("Profil")
            .onAppear { withAnimation { appeared = true } }
            .sheet(isPresented: $showGoalEditor) {
                GoalEditorSheet(stepGoal: $stepGoal, waterGoal: $waterGoal,
                                kcalGoal: $kcalGoal, proteinGoal: $proteinGoal,
                                fastTarget: $fastTarget)
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
            .task {
                if await HealthService.shared.requestAuthorization() {
                    steps = await HealthService.shared.stepsToday()
                    healthConnected = true
                }
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 84, height: 84)
                let initial = String(name.prefix(1)).uppercased()
                Text(initial.isEmpty ? "?" : initial)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            .shadow(color: Color.accentColor.opacity(0.2), radius: 14, x: 0, y: 6)
            .padding(.top, 6)

            VStack(spacing: 5) {
                if name.isEmpty {
                    TextField("Entre ton prénom", text: $name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                } else {
                    Text("\(greeting), \(name)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !onboardingGoals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(onboardingGoals.prefix(3)) { g in
                        Label(String(g.label.split(separator: " ").first ?? ""), systemImage: g.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(g.color)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(g.color.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.1), Color.accentColor.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    // MARK: Progression

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Aujourd'hui").font(.headline)
                Spacer()
                Button { showGoalEditor = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                ringCell(
                    icon: "figure.walk",
                    value: Double(steps), goal: Double(stepGoal),
                    label: "Pas",
                    displayValue: steps >= 1000 ? String(format: "%.1f", Double(steps) / 1000.0) + "k" : "\(steps)",
                    color: Color(hex: 0xF1746C)
                )
                ringCell(
                    icon: "drop.fill",
                    value: Double(waterToday), goal: Double(waterGoal),
                    label: "Eau",
                    displayValue: "\(waterToday)",
                    color: Color(hex: 0x3CB2E0)
                )
                ringCell(
                    icon: "flame.fill",
                    value: Double(kcalToday), goal: Double(kcalGoal),
                    label: "Kcal",
                    displayValue: "\(kcalToday)",
                    color: Color(hex: 0x4CC38A)
                )
            }

            HStack(spacing: 10) {
                miniBar(
                    label: "Habitudes", icon: "checkmark.seal.fill",
                    value: Double(habitsDone), goal: Double(max(1, habits.count)),
                    unit: "/ \(habits.count)", color: Color(hex: 0x9B6CF1)
                )
                miniBar(
                    label: "Protéines", icon: "fork.knife",
                    value: proteinToday, goal: Double(proteinGoal),
                    unit: "g", color: Color(hex: 0xE0A23C)
                )
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func ringCell(icon: String, value: Double, goal: Double, label: String, displayValue: String, color: Color) -> some View {
        VStack(spacing: 7) {
            ZStack {
                ProgressRing(progress: goal > 0 ? min(1.0, value / goal) : 0, lineWidth: 7, tint: color)
                    .frame(width: 68, height: 68)
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                    Text(displayValue)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            let pct = goal > 0 ? min(100, Int(value / goal * 100)) : 0
            Text("\(pct)%")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(value >= goal ? color : Color(uiColor: .tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func miniBar(label: String, icon: String, value: Double, goal: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(value >= goal ? color : Theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12)).frame(height: 5)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1.0, goal > 0 ? value / goal : 0), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Actions rapides

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions rapides").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                actionBtn(icon: "drop.fill", label: "+250 ml", sub: "Eau", color: Color(hex: 0x3CB2E0)) {
                    ctx.insert(WaterEntry(amountML: 250))
                    Haptics.tap()
                }
                actionBtn(icon: "drop.fill", label: "+500 ml", sub: "Eau", color: Color(hex: 0x3CB2E0)) {
                    ctx.insert(WaterEntry(amountML: 500))
                    Haptics.tap()
                }
                actionBtn(icon: "sunrise.fill", label: "Ma journée", sub: "Lancer le briefing", color: .orange) {
                    showBriefing = true
                }
                actionBtn(icon: "target", label: "Objectifs", sub: "Modifier", color: Color.accentColor) {
                    showGoalEditor = true
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func actionBtn(icon: String, label: String, sub: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Réveil

    private var wakeupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Réveil", systemImage: "alarm.fill").font(.headline)
                Spacer()
                Toggle("", isOn: $wakeupEnabled)
                    .tint(Color(hex: 0xE07B3C))
                    .labelsHidden()
                    .onChange(of: wakeupEnabled) { _, on in
                        if on { scheduleWakeupAlarm() } else { NotificationManager.shared.cancel(id: "lifeos.wakeup") }
                    }
            }

            HStack(alignment: .bottom) {
                Text(String(format: "%02d:%02d", wakeupHour, wakeupMinute))
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(wakeupEnabled ? Color(hex: 0xE07B3C) : .secondary)
                    .animation(.spring(duration: 0.3), value: wakeupEnabled)
                Spacer()
                Button { showWakeupDetail = true } label: {
                    Text("Personnaliser")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE07B3C))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(hex: 0xE07B3C).opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }

            Text(wakeupEnabled ? "Réveil quotidien activé" : "Désactivé — active pour lancer le briefing auto")
                .font(.caption)
                .foregroundStyle(wakeupEnabled ? Color(hex: 0xE07B3C).opacity(0.8) : .secondary)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(wakeupEnabled ? Color(hex: 0xE07B3C).opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.3), value: wakeupEnabled)
    }

    // MARK: Paramètres

    private var settingsSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "heart.fill", iconColor: Color(hex: 0xF1746C),
                    label: healthConnected ? "Apple Santé connecté" : "Connecter Apple Santé"
                ) {
                    if healthConnected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                } action: {
                    Task { healthConnected = await HealthService.shared.requestAuthorization() }
                }

                Divider().padding(.leading, 52)

                settingsRow(
                    icon: "bell.fill", iconColor: Color(hex: 0xE0A23C),
                    label: "Activer les rappels"
                ) {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                } action: {
                    Task { _ = await NotificationManager.shared.requestAuthorization() }
                }

                Divider().padding(.leading, 52)

                settingsRow(
                    icon: "slider.horizontal.3", iconColor: Color.accentColor,
                    label: "Modifier mes objectifs"
                ) {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                } action: {
                    showGoalEditor = true
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack {
                Text("LifeOS 1.0 · Données locales")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text("15 modules")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func settingsRow<T: View>(
        icon: String, iconColor: Color, label: String,
        @ViewBuilder trailing: () -> T,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
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
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(on ? Color(hex: 0xE07B3C) : Theme.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(on ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
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
