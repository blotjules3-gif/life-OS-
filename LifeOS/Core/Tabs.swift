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
    @AppStorage("lastBriefingDate") private var lastBriefingDate: Double = 0
    @AppStorage("lastBriefingContent") private var lastBriefingContent = ""
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
            // Stocker le contenu du briefing pour rappel dans le profil
            lastBriefingDate = Date.now.timeIntervalSince1970
            lastBriefingContent = todayTasks.prefix(4).map { $0.title }.joined(separator: "|||")
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
    @AppStorage("profileHiddenRaw") private var profileHiddenRaw = ""
    @AppStorage("lastBriefingDate") private var lastBriefingDate: Double = 0
    @AppStorage("lastBriefingContent") private var lastBriefingContent = ""

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Query(sort: \MemoryEntry.created, order: .reverse) private var memories: [MemoryEntry]
    @Environment(\.modelContext) private var ctx

    @State private var steps = 0
    @State private var activeCalories = 0.0
    @State private var healthConnected = false
    @State private var showGoalEditor = false
    @State private var showWakeupDetail = false
    @State private var showBriefing = false
    @State private var showCustomizer = false
    @State private var appeared = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }
    private var onboardingGoals: [OnboardingGoal] {
        onboardingGoalsRaw.split(separator: ",").compactMap { OnboardingGoal(rawValue: String($0)) }
    }
    private var hiddenSections: Set<String> {
        Set(profileHiddenRaw.split(separator: ",").map(String.init))
    }
    private var hasTodayBriefing: Bool {
        lastBriefingDate > 0 && Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastBriefingDate))
    }
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var proteinToday: Double { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.protein } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

    // Tâches du jour calculées depuis les modules actifs de l'utilisateur
    private var todayTasks: [ProfileTaskItem] {
        var tasks: [ProfileTaskItem] = []
        let mods = recommendedModules.isEmpty ? [AppCategory.nutrition, .fitness, .productivity] : recommendedModules
        for mod in mods {
            switch mod {
            case .nutrition:
                let kp = min(1.0, Double(kcalToday) / Double(max(1, kcalGoal)))
                tasks.append(ProfileTaskItem(icon: "flame.fill", title: "Calories", subtitle: "\(kcalToday) / \(kcalGoal) kcal", color: Color(hex: 0x4CC38A), progress: kp))
                let wp = min(1.0, Double(waterToday) / Double(max(1, waterGoal)))
                tasks.append(ProfileTaskItem(icon: "drop.fill", title: "Hydratation", subtitle: "\(waterToday) / \(waterGoal) ml", color: Color(hex: 0x3CB2E0), progress: wp))
            case .fitness:
                let sp = min(1.0, Double(steps) / Double(max(1, stepGoal)))
                tasks.append(ProfileTaskItem(icon: "figure.run", title: "Activité", subtitle: "\(steps) / \(stepGoal) pas", color: Color(hex: 0xF1746C), progress: sp))
            case .productivity:
                let hp = habits.isEmpty ? 1.0 : min(1.0, Double(habitsDone) / Double(habits.count))
                tasks.append(ProfileTaskItem(icon: "checklist", title: "Habitudes", subtitle: "\(habitsDone)/\(habits.count) complétées", color: Color(hex: 0x9B6CF1), progress: hp))
            case .sleep:
                tasks.append(ProfileTaskItem(icon: "moon.stars.fill", title: "Sommeil", subtitle: "Évaluer ta nuit", color: Color(hex: 0x6C7BF1), progress: 0))
            case .mind:
                tasks.append(ProfileTaskItem(icon: "brain.head.profile", title: "Focus", subtitle: "5 min de méditation", color: Color(hex: 0x9B6CF1), progress: 0))
            case .finance:
                tasks.append(ProfileTaskItem(icon: "creditcard.fill", title: "Budget", subtitle: "Vérifier mes dépenses", color: Color(hex: 0x4CC38A), progress: 0))
            default: break
            }
        }
        return Array(tasks.prefix(6))
    }

    private var lifeScore: Int {
        let w = min(1.0, Double(waterToday) / Double(max(1, waterGoal)))
        let k = min(1.0, Double(min(kcalToday, kcalGoal)) / Double(max(1, kcalGoal)))
        let h = habits.isEmpty ? 1.0 : min(1.0, Double(habitsDone) / Double(habits.count))
        let s = min(1.0, Double(steps) / Double(max(1, stepGoal)))
        return Int((w * 25 + k * 25 + h * 30 + s * 20).rounded())
    }
    private var scoreColor: Color {
        lifeScore >= 75 ? Color(hex: 0x00D4B4) : lifeScore >= 50 ? Color(hex: 0xE0A23C) : Color(hex: 0xF1746C)
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }
    private let tips = [
        "Chaque verre d'eau compte. L'hydratation est la base de tout.",
        "Un pas de plus qu'hier. C'est tout ce qui compte.",
        "Tes habitudes d'aujourd'hui sont ta santé de demain.",
        "Le succès, c'est la somme de petits efforts répétés.",
        "Discipline is choosing between what you want now and what you want most.",
        "L'énergie suit l'attention. Mets-la au bon endroit.",
        "Une journée complète commence par 5 min pour toi."
    ]
    private var todayTip: String { tips[Calendar.current.component(.day, from: .now) % tips.count] }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if !hiddenSections.contains("hero") {
                        heroDark
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 28)
                            .animation(.spring(duration: 0.6, bounce: 0.25), value: appeared)
                    }

                    if !healthConnected {
                        healthConnectBanner
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                            .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.06), value: appeared)
                    }

                    if !hiddenSections.contains("tasks") {
                        dailyTasksCard
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.07), value: appeared)
                    }

                    if hasTodayBriefing && !hiddenSections.contains("briefing") {
                        briefingRecallCard
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.1), value: appeared)
                    }

                    if !hiddenSections.contains("stats") {
                        statsRow
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.14), value: appeared)
                    }

                    if !memories.isEmpty && !hiddenSections.contains("memories") {
                        memoriesCard
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.18), value: appeared)
                    }

                    if !hiddenSections.contains("habits") {
                        habitsProteinsRow
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.21), value: appeared)
                    }

                    if !hiddenSections.contains("actions") {
                        quickActionsSection
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.28), value: appeared)
                    }

                    if !hiddenSections.contains("wakeup") {
                        wakeupSection
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.35), value: appeared)
                    }

                    if !hiddenSections.contains("tip") {
                        tipCard
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.42), value: appeared)
                    }

                    if !hiddenSections.contains("settings") {
                        settingsSection
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                            .animation(.spring(duration: 0.55, bounce: 0.2).delay(0.49), value: appeared)
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 52)
            }
            .background(Theme.bg)
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCustomizer = true } label: {
                        Text("Modifier")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .onAppear { withAnimation { appeared = true } }
            .task {
                if await HealthService.shared.requestAuthorization() {
                    healthConnected = true
                    steps = await HealthService.shared.stepsToday()
                    activeCalories = await HealthService.shared.activeCaloriesToday()
                }
            }
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
            .sheet(isPresented: $showCustomizer) {
                ProfileCustomizerSheet(hiddenRaw: $profileHiddenRaw)
            }
        }
    }

    // MARK: - Daily Tasks Card

    private var dailyTasksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AUJOURD'HUI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                let doneCnt = todayTasks.filter { $0.done }.count
                HStack(spacing: 4) {
                    Text("\(doneCnt)/\(todayTasks.count)")
                        .font(.system(size: 12, weight: .black).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(doneCnt == todayTasks.count ? Color(hex: 0x4CC38A) : Color.accentColor, in: Capsule())
            }

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            VStack(spacing: 12) {
                ForEach(todayTasks) { task in
                    taskRow(task)
                }
            }

            Button { showGoalEditor = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text("Ajuster mes objectifs").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func taskRow(_ task: ProfileTaskItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(task.done ? task.color : Color.secondary.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                if task.done {
                    Circle().fill(task.color).frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                } else if task.progress > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(task.progress))
                        .stroke(task.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(task.done ? .secondary : Theme.textPrimary)
                        .strikethrough(task.done)
                    Spacer()
                    Text(task.subtitle)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(task.done ? .secondary : task.color)
                        .lineLimit(1)
                }
                if !task.done && task.progress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(task.color.opacity(0.1)).frame(height: 3)
                            Capsule().fill(task.color)
                                .frame(width: geo.size.width * CGFloat(task.progress), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }

    // MARK: - Briefing Recall Card

    private var briefingRecallCard: some View {
        let tasks = lastBriefingContent.split(separator: "|||").map(String.init)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("BRIEFING DU MATIN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .kerning(1.0)
                    Text("Rappel de ce qui a été dit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(Date(timeIntervalSince1970: lastBriefingDate).formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(tasks.prefix(4).enumerated()), id: \.offset) { _, task in
                        HStack(spacing: 8) {
                            Circle().fill(Color.orange.opacity(0.4)).frame(width: 5, height: 5)
                            Text(task)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button { showBriefing = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Réécouter mon briefing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.orange.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.orange.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Hero dark card

    private var heroDark: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x070F18), Color(hex: 0x0E1E2E)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // Blob score — haut droite
            Circle()
                .fill(RadialGradient(colors: [scoreColor.opacity(0.38), .clear],
                                     center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300)
                .offset(x: 120, y: -120)
                .blur(radius: 32)
                .allowsHitTesting(false)

            // Blob froid — bas gauche
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x3CB2E0).opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: 90))
                .frame(width: 200, height: 200)
                .offset(x: -50, y: 180)
                .blur(radius: 36)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {

                // — LIGNE 1 : greeting + date
                HStack(alignment: .firstTextBaseline) {
                    Text(greeting.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .kerning(1.4)
                    Spacer()
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month()))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }

                // — LIGNE 2 : prénom
                Group {
                    if name.isEmpty {
                        TextField("Ton prénom", text: $name)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Text(name)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)

                Spacer().frame(height: 20)

                // — LIGNE 3 : ring gauche + métriques droite
                HStack(alignment: .center, spacing: 18) {

                    // Score ring (plus grand)
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.09), lineWidth: 11)
                            .frame(width: 126, height: 126)

                        Circle()
                            .trim(from: 0, to: appeared ? CGFloat(lifeScore) / 100.0 : 0)
                            .stroke(scoreColor.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 20, lineCap: .round))
                            .frame(width: 126, height: 126)
                            .rotationEffect(.degrees(-90))
                            .blur(radius: 9)
                            .animation(.spring(duration: 1.3, bounce: 0.08).delay(0.45), value: appeared)
                            .allowsHitTesting(false)

                        Circle()
                            .trim(from: 0, to: appeared ? CGFloat(lifeScore) / 100.0 : 0)
                            .stroke(
                                LinearGradient(colors: [scoreColor, scoreColor.opacity(0.55)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round)
                            )
                            .frame(width: 126, height: 126)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(duration: 1.3, bounce: 0.08).delay(0.45), value: appeared)

                        VStack(spacing: 1) {
                            Text("SCORE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.32))
                                .kerning(0.8)
                            Text("\(lifeScore)")
                                .font(.system(size: 36, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                            Text("/100")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.32))
                        }
                    }

                    // Métriques verticales
                    VStack(alignment: .leading, spacing: 12) {
                        heroMetricRow(
                            icon: "figure.run",
                            value: steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)",
                            label: "pas",
                            progress: min(1.0, Double(steps) / Double(max(1, stepGoal))),
                            color: Color(hex: 0xF1746C)
                        )
                        heroMetricRow(
                            icon: "drop.fill",
                            value: "\(waterToday) ml",
                            label: "eau",
                            progress: min(1.0, Double(waterToday) / Double(max(1, waterGoal))),
                            color: Color(hex: 0x3CB2E0)
                        )
                        heroMetricRow(
                            icon: "flame.fill",
                            value: "\(kcalToday) kcal",
                            label: "calories",
                            progress: min(1.0, Double(kcalToday) / Double(max(1, kcalGoal))),
                            color: Color(hex: 0x4CC38A)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer().frame(height: 20)

                // — LIGNE 4 : barre de progression + statut
                VStack(alignment: .leading, spacing: 7) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08)).frame(height: 3)
                            Capsule()
                                .fill(LinearGradient(colors: [scoreColor, scoreColor.opacity(0.55)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, geo.size.width * CGFloat(lifeScore) / 100.0), height: 3)
                                .animation(.spring(duration: 1.0).delay(0.5), value: appeared)
                        }
                    }
                    .frame(height: 3)

                    HStack(spacing: 6) {
                        Circle().fill(scoreColor).frame(width: 5, height: 5)
                        Text(lifeScore >= 75 ? "Excellente journée" :
                             lifeScore >= 50 ? "Bonne progression" : "Continue, tu peux mieux")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        if healthConnected {
                            Label("Santé", systemImage: "heart.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xF1746C).opacity(0.85))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(hex: 0xF1746C).opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
    }

    private func heroMetricRow(icon: String, value: String, label: String,
                                progress: Double, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08)).frame(height: 2)
                        Capsule()
                            .fill(color.opacity(0.7))
                            .frame(width: max(2, g.size.width * CGFloat(progress)), height: 2)
                            .animation(.spring(duration: 1.0).delay(0.5), value: appeared)
                    }
                }
                .frame(height: 2)
            }
        }
    }

    // MARK: - Mémoires

    private var memoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MÉMOIRE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: 0x9B6CF1).opacity(0.8))
                        .kerning(1.2)
                    Text("Ce que je retiens")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text("\(memories.count)")
                    .font(.system(size: 18, weight: .black).monospacedDigit())
                    .foregroundStyle(Color(hex: 0x9B6CF1))
            }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            ForEach(memories.prefix(4)) { m in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: m.categoryIcon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(m.categoryColor)
                        .frame(width: 22, height: 22)
                        .background(m.categoryColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.content)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(2)
                        Text(m.category.capitalized + " · " + m.created.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        ctx.delete(m)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color(.systemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if m.id != memories.prefix(4).last?.id {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 32)
                }
            }

            if memories.count > 4 {
                Text("+ \(memories.count - 4) autre\(memories.count - 4 > 1 ? "s" : "") souvenir\(memories.count - 4 > 1 ? "s" : "")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text("Dis « retiens que... » dans le chat pour mémoriser.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Bannière Apple Santé

    private var healthConnectBanner: some View {
        Button {
            Task {
                let ok = await HealthService.shared.requestAuthorization()
                healthConnected = ok
                if ok {
                    steps = await HealthService.shared.stepsToday()
                    activeCalories = await HealthService.shared.activeCaloriesToday()
                }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0xF1746C).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF1746C))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connecter Apple Santé")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Pas, calories et fréquence cardiaque en temps réel")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats 3 colonnes

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                icon: "figure.walk",
                value: steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)",
                label: "Pas",
                progress: Double(steps) / Double(max(1, stepGoal)),
                color: Color(hex: 0xF1746C)
            )
            statCard(
                icon: "drop.fill",
                value: "\(waterToday)",
                label: "ml eau",
                progress: Double(waterToday) / Double(max(1, waterGoal)),
                color: Color(hex: 0x3CB2E0)
            )
            statCard(
                icon: "flame.fill",
                value: "\(kcalToday)",
                label: "kcal",
                progress: Double(kcalToday) / Double(max(1, kcalGoal)),
                color: Color(hex: 0x4CC38A)
            )
        }
    }

    private func statCard(icon: String, value: String, label: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer()
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.12), lineWidth: 2.5)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: appeared ? min(1.0, max(0, progress)) : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 1.0, bounce: 0.05).delay(0.5), value: appeared)
                }
            }

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .kerning(0.5)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.1)).frame(height: 3)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(1.0, max(0, progress)), height: 3)
                        .animation(.spring(duration: 1.0).delay(0.5), value: appeared)
                }
            }
            .frame(height: 3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(color.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Habitudes + Protéines

    private var habitsProteinsRow: some View {
        HStack(spacing: 10) {
            // Habitudes avec dot grid
            let habitColor = Color(hex: 0x9B6CF1)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(habitColor)
                    Text("HABITUDES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(habitColor.opacity(0.8))
                        .kerning(0.5)
                    Spacer()
                    Text("\(habitsDone)/\(habits.count)")
                        .font(.system(size: 13, weight: .black).monospacedDigit())
                        .foregroundStyle(habitColor)
                }
                if habits.isEmpty {
                    Text("Aucune habitude")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 5) {
                        ForEach(Array(habits.prefix(8).enumerated()), id: \.offset) { _, h in
                            let done = h.completions.contains { Calendar.current.isDateInToday($0.date) }
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(done ? habitColor : habitColor.opacity(0.14))
                                .frame(width: 13, height: 13)
                        }
                    }
                }
                Text(habitsDone == habits.count && !habits.isEmpty ? "Toutes complétées" : habits.isEmpty ? "" : "\(habits.count - habitsDone) restantes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(habitsDone == habits.count && !habits.isEmpty ? habitColor : .secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(habitColor.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(habitColor.opacity(0.15), lineWidth: 1))
            )

            // Protéines
            let protColor = Color(hex: 0xE0A23C)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(protColor)
                    Text("PROTÉINES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(protColor.opacity(0.8))
                        .kerning(0.5)
                }
                Text("\(Int(proteinToday))")
                    .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("/ \(proteinGoal) g")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(protColor.opacity(0.1)).frame(height: 3)
                        Capsule().fill(protColor)
                            .frame(width: geo.size.width * min(1.0, proteinToday / Double(max(1, proteinGoal))), height: 3)
                            .animation(.spring(duration: 1.0).delay(0.5), value: appeared)
                    }
                }
                .frame(height: 3)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(protColor.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(protColor.opacity(0.15), lineWidth: 1))
            )
        }
    }

    // MARK: - Actions rapides

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ACTIONS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Text("Raccourcis rapides")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                actionBtn(icon: "drop.fill", label: "+250 ml", sub: "Eau", color: Color(hex: 0x3CB2E0)) {
                    ctx.insert(WaterEntry(amountML: 250)); Haptics.tap()
                }
                actionBtn(icon: "drop.fill", label: "+500 ml", sub: "Eau", color: Color(hex: 0x3CB2E0)) {
                    ctx.insert(WaterEntry(amountML: 500)); Haptics.tap()
                }
                actionBtn(icon: "sunrise.fill", label: "Ma journée", sub: "Lancer le briefing", color: .orange) {
                    showBriefing = true
                }
                actionBtn(icon: "target", label: "Objectifs", sub: "Modifier", color: Color.accentColor) {
                    showGoalEditor = true
                }
            }
        }
    }

    private func actionBtn(icon: String, label: String, sub: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(LifeOSPressStyle())
    }

    // MARK: - Réveil

    private var wakeupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RÉVEIL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: 0xE07B3C).opacity(0.8))
                        .kerning(1.2)
                    Text(String(format: "%02d:%02d", wakeupHour, wakeupMinute))
                        .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(wakeupEnabled ? Color(hex: 0xE07B3C) : Theme.textPrimary)
                        .animation(.spring(duration: 0.3), value: wakeupEnabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: $wakeupEnabled)
                        .tint(Color(hex: 0xE07B3C)).labelsHidden()
                        .onChange(of: wakeupEnabled) { _, on in
                            if on { scheduleWakeupAlarm() } else { NotificationManager.shared.cancel(id: "lifeos.wakeup") }
                        }
                    Button { showWakeupDetail = true } label: {
                        Text("Personnaliser")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xE07B3C))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(hex: 0xE07B3C).opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            Button { showBriefing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.orange)
                        .frame(width: 34, height: 34)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lancer ma journée")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Briefing + voix + priorités")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(wakeupEnabled ? Color(hex: 0xE07B3C).opacity(0.22) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.3), value: wakeupEnabled)
    }

    // MARK: - Citation du jour

    private var tipCard: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3, height: 42)
            Text(todayTip)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Paramètres

    private var settingsSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                settingsRow(icon: "heart.fill", iconColor: Color(hex: 0xF1746C),
                            label: healthConnected ? "Apple Santé connecté" : "Connecter Apple Santé") {
                    if healthConnected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                } action: {
                    Task { healthConnected = await HealthService.shared.requestAuthorization() }
                }
                Divider().padding(.leading, 50)
                settingsRow(icon: "bell.fill", iconColor: Color(hex: 0xE0A23C), label: "Activer les rappels") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                } action: {
                    Task { _ = await NotificationManager.shared.requestAuthorization() }
                }
                Divider().padding(.leading, 50)
                settingsRow(icon: "slider.horizontal.3", iconColor: Color.accentColor, label: "Modifier mes objectifs") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                } action: {
                    showGoalEditor = true
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack {
                Text("LifeOS 1.0 · Données stockées localement")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text("15 modules").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func settingsRow<T: View>(icon: String, iconColor: Color, label: String,
                                      @ViewBuilder trailing: () -> T, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(label).font(.subheadline).foregroundStyle(.primary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func scheduleWakeupAlarm() {
        Task {
            guard await NotificationManager.shared.requestAuthorization() else { return }
            NotificationManager.shared.scheduleAlarm(
                hour: wakeupHour,
                minute: wakeupMinute,
                userName: name
            )
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

// MARK: - Personnalisateur de profil

struct ProfileCustomizerSheet: View {
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss

    private var hidden: Set<String> {
        Set(hiddenRaw.split(separator: ",").map(String.init))
    }
    private func toggle(_ id: String) {
        var s = Set(hiddenRaw.split(separator: ",").map(String.init))
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        hiddenRaw = s.joined(separator: ",")
    }
    private var visibleCount: Int { sections.count - hidden.count }

    private let sections: [(id: String, label: String, sub: String, icon: String, color: Color)] = [
        ("hero",     "Score",          "Carte principale",   "star.fill",           Color(hex: 0x00D4B4)),
        ("tasks",    "Tâches",         "Ce qu'il te reste",  "checklist",           Color(hex: 0x9B6CF1)),
        ("briefing", "Briefing",       "Rappel du matin",    "sunrise.fill",        Color.orange),
        ("memories", "Mémoire",        "Ce que je retiens",  "brain",               Color(hex: 0x9B6CF1)),
        ("stats",    "Stats",          "Pas · eau · kcal",   "chart.bar.fill",      Color(hex: 0xF1746C)),
        ("habits",   "Habitudes",      "Suivi & protéines",  "checkmark.seal.fill", Color(hex: 0x9B6CF1)),
        ("actions",  "Actions",        "Raccourcis rapides", "bolt.fill",           Color(hex: 0x3CB2E0)),
        ("wakeup",   "Réveil",         "Alarme & briefing",  "alarm.fill",          Color(hex: 0xE07B3C)),
        ("tip",      "Citation",       "Inspiration du jour","quote.bubble.fill",   Color.accentColor),
        ("settings", "Paramètres",     "Santé · objectifs",  "slider.horizontal.3", Color(hex: 0x8A93A8)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Compteur
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mon profil")
                                .font(.system(size: 22, weight: .bold))
                            Text("\(visibleCount) section\(visibleCount > 1 ? "s" : "") affichée\(visibleCount > 1 ? "s" : "")")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Tout afficher") {
                            withAnimation { hiddenRaw = "" }
                            Haptics.tap()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Grille 2 colonnes
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(sections, id: \.id) { s in
                            let isVisible = !hidden.contains(s.id)
                            Button {
                                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { toggle(s.id) }
                                Haptics.tap()
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: s.icon)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(isVisible ? .white : s.color.opacity(0.5))
                                            .frame(width: 34, height: 34)
                                            .background(
                                                isVisible ? s.color : s.color.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )
                                        Spacer()
                                        Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(isVisible ? s.color : Color.secondary.opacity(0.3))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.label)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isVisible ? .primary : .secondary)
                                        Text(s.sub)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isVisible ? Theme.card : Color(.systemBackground).opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(isVisible ? s.color.opacity(0.25) : Color.secondary.opacity(0.1), lineWidth: 1.5)
                                        )
                                )
                                .scaleEffect(isVisible ? 1.0 : 0.97)
                                .opacity(isVisible ? 1.0 : 0.6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    Text("Appuie sur une carte pour afficher ou masquer la section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}
