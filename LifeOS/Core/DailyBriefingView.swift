import SwiftUI
import SwiftData

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
    @State private var aiBriefing: String?
    @State private var briefingFailed = false
    @State private var briefingLoading = false
    @State private var briefingGoals: [GoalOut] = []
    @State private var briefingChallenges: [ChallengeOut] = []
    @State private var morningMood = 0
    @State private var morningFatigue = 0
    @State private var checkinSubmitting = false
    @State private var checkinDone = false
    @State private var behavioralInsights: [String] = []

    private static let waveBars: [Double] = [8, 20, 12, 24, 10, 18, 8, 22, 14, 8]

    private var kcalToday: Int  { foods.caloriesToday }
    private var waterToday: Int { waters.mlToday }
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
                tasks.append(("flame.fill",  "Calories",     "Ajouter ton repas du matin",       Color(hex: 0xF1746C), kcalToday > 0))
                tasks.append(("drop.fill",   "Hydratation",  "\(waterToday) / \(waterGoal) ml",  Color(hex: 0x3CB2E0), waterToday >= waterGoal))
            case .fitness:
                tasks.append(("figure.run",  "Activité",     "Enregistrer une séance ou des pas", Color(hex: 0x4CC38A), false))
            case .sleep:
                tasks.append(("moon.stars.fill", "Sommeil",  "Évaluer ta nuit",                  Color(hex: 0x6C7BF1), false))
            case .mind:
                tasks.append(("brain.head.profile", "Focus", "5 min de méditation",              Color(hex: 0x9B6CF1), false))
            case .productivity:
                tasks.append(("checklist",   "Habitudes",    "\(habitsDone) / \(habits.count) complétées", Color(hex: 0x9B6CF1), habitsDone == habits.count && !habits.isEmpty))
            case .finance:
                tasks.append(("creditcard.fill", "Budget",   "Vérifier tes dépenses",            Color(hex: 0x618EF1), false))
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
                            .foregroundStyle(Color(hex: 0xFF9F0A))
                            .padding(.top, 56)

                        Text("\(greeting)\(userName.isEmpty ? "" : ", \(userName.prefix(1).uppercased() + userName.dropFirst())") !")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "fr_FR"))))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    voiceBanner

                    morningCheckinCard

                    aiBriefingCard
                        .animation(.spring(duration: 0.3, bounce: 0.05), value: aiBriefing != nil)
                        .animation(.spring(duration: 0.3, bounce: 0.05), value: briefingLoading)

                    HStack(spacing: 10) {
                        briefingRing(value: Double(kcalToday), goal: Double(kcalGoal), label: "Kcal", color: Color(hex: 0xF1746C), icon: "flame.fill")
                        briefingRing(value: Double(waterToday), goal: Double(waterGoal), label: "Eau", color: Color(hex: 0x3CB2E0), icon: "drop.fill")
                        briefingRing(value: Double(habitsDone), goal: max(1, Double(habits.count)), label: "Habits", color: Color(hex: 0x9B6CF1), icon: "checkmark.seal.fill")
                    }

                    if !todayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("À faire aujourd'hui")
                            .font(.system(size: 15, weight: .semibold))
                            ForEach(Array(todayTasks.enumerated()), id: \.offset) { _, task in
                                HStack(spacing: 14) {
                                    Image(systemName: task.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(task.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title).font(.system(size: 14, weight: .semibold))
                                        Text(task.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if task.done {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(task.color)
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    task.done ? task.color.opacity(0.08) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                        .stroke(task.done ? task.color.opacity(0.25) : Color.clear, lineWidth: 1)
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Actions rapides")
                        .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 10) {
                            quickActionBtn(icon: "drop.fill", label: "1 verre", color: Color(hex: 0x3CB2E0)) {
                                ctx.insert(WaterEntry(amountML: 250))
                            }
                            quickActionBtn(icon: "drop.fill", label: "2 verres", color: Color(hex: 0x3CB2E0)) {
                                ctx.insert(WaterEntry(amountML: 500))
                            }
                        }
                    }

                    if !behavioralInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ce qu'on a appris sur toi")
                                .font(.system(size: 15, weight: .semibold))
                            VStack(spacing: 8) {
                                ForEach(behavioralInsights, id: \.self) { insight in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0xE0A23C))
                                            .frame(width: 22, height: 22)
                                            .background(Color(hex: 0xE0A23C).opacity(0.14), in: Circle())
                                        Text(insight)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                                }
                            }
                        }
                    }

                    Button { dismiss() } label: {
                        Text("Commencer la journée")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(LifeOSPressStyle())
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 22)
            }
        }
        .task {
            lastBriefingContent = todayTasks.prefix(4).map { $0.title }.joined(separator: "|||")
            briefingLoading = true
            briefingFailed = false

            async let goalsTask = (try? await AgentAPI.shared.listGoals()) ?? []
            async let challengesTask = (try? await AgentAPI.shared.fetchChallenges()) ?? []
            async let insightsTask = (try? await AgentAPI.shared.fetchBehavioralInsights()) ?? []
            let (g, c, ins) = await (goalsTask, challengesTask, insightsTask)
            briefingGoals = g
            briefingChallenges = c
            behavioralInsights = ins

            let prompt = buildBriefingPrompt(goals: g, challenges: c)
            let reply = await OnDeviceLLM.respond(to: prompt, ctx: ctx)
            aiBriefing = reply.text
            UserDefaults.standard.set(reply.text, forKey: "lastAIBriefing")
            lastBriefingDate = Date.now.timeIntervalSince1970
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

    // MARK: - Check-in matin

    @ViewBuilder private var morningCheckinCard: some View {
        if checkinDone || todayEnergyScore > 0 {
            energyScoreDisplayCard
                .transition(.scale(scale: 0.88, anchor: .top).combined(with: .opacity))
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bilan du matin")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Qualité du sommeil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                sleepQuality = s
                                Haptics.soft()
                            } label: {
                                Image(systemName: s <= sleepQuality ? "moon.stars.fill" : "moon.stars")
                                    .font(.system(size: 24))
                                    .foregroundStyle(s <= sleepQuality ? Color(hex: 0x6C7BF1) : Color.secondary.opacity(0.4))
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(LifeOSPressStyle())
                        }
                    }
                }

                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Humeur")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
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
                            }.buttonStyle(LifeOSPressStyle())
                        }
                    }
                }

                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Niveau d'énergie")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                morningFatigue = 6 - s
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
                            }.buttonStyle(LifeOSPressStyle())
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
                    .padding(.vertical, 14)
                    .background(
                        sleepQuality > 0 && morningMood > 0 && morningFatigue > 0
                        ? Color.accentColor
                        : Color.secondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    )
                }
                .buttonStyle(LifeOSPressStyle())
                .disabled(sleepQuality == 0 || morningMood == 0 || morningFatigue == 0 || checkinSubmitting)
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    @ViewBuilder private var energyScoreDisplayCard: some View {
        let scoreColor: Color = {
            switch todayEnergyScore {
            case 85...100: return Color(hex: 0x4CC38A)
            case 70..<85:  return Color(hex: 0x5DCFA8)
            case 50..<70:  return Color(hex: 0xFF9F0A)
            case 30..<50:  return Color(hex: 0xE07B3C)
            default:       return Color(hex: 0xF1746C)
            }
        }()

        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(todayEnergyScore)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.6, bounce: 0.15), value: todayEnergyScore)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Score d'Énergie")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(todayEnergyLabel.isEmpty ? "—" : todayEnergyLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(scoreColor)
                }
                Spacer()
            }
            ProgressView(value: Double(todayEnergyScore) / 100)
                .tint(scoreColor)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)
                .animation(.spring(duration: 0.8, bounce: 0.1), value: todayEnergyScore)
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
        // Écriture locale + calcul score on-device. Aucun POST réseau.
        if sleepQuality > 0 || sleepHours > 0 {
            UserDefaults.standard.set(sleepQuality, forKey: "lastSleepQuality")
            UserDefaults.standard.set(Double(sleepHours), forKey: "lastSleepHours")
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastSleepCheckDate")
        }
        if morningMood > 0 { ctx.insert(MoodEntry(score: morningMood, note: "")) }
        do { try ctx.save() } catch { print("[SwiftData] saveBriefingCheckin failed: \(error)") }

        let manual = EnergyScore.Input(
            sleepHours: sleepHours > 0 ? Double(sleepHours) : nil,
            sleepQuality: sleepQuality > 0 ? sleepQuality : nil,
            mood: morningMood > 0 ? morningMood : nil,
            fatigue: morningFatigue > 0 ? morningFatigue : nil,
            waterML: waterToday > 0 ? waterToday : nil,
            habitsDone: habitsDone,
            habitsTotal: habits.count > 0 ? habits.count : nil
        )
        let result = EnergyScore.compute(manual)
        todayEnergyScore = result.score
        todayEnergyLabel = result.label

        checkinSubmitting = false
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { checkinDone = true }
    }

    // MARK: - Bandeau voix

    @ViewBuilder private var voiceBanner: some View {
        if alarm.isSpeaking {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(Array(Self.waveBars.enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(hex: 0xFF9F0A))
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
                        .foregroundStyle(Color(hex: 0xFF9F0A).opacity(0.8))
                }
                .buttonStyle(LifeOSPressStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: 0xFF9F0A).opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .stroke(Color(hex: 0xFF9F0A).opacity(0.18), lineWidth: 1)
            )
            .transition(.scale(scale: 0.88, anchor: .top).combined(with: .opacity))
            .onAppear { waveActive = true }
        } else if !speakOnAppear {
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
                        .foregroundStyle(Color(hex: 0xFF9F0A))
                    Text("Écouter mon plan du jour")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())
            .transition(.opacity)
        }
    }

    @ViewBuilder private var aiBriefingCard: some View {
        if briefingLoading {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF9F0A))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xFF9F0A).opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)
                    }
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if briefingFailed && aiBriefing == nil {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Briefing indisponible")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Réessayer") {
                        briefingFailed = false
                        briefingLoading = true
                        Task {
                            let prompt = buildBriefingPrompt(goals: briefingGoals, challenges: briefingChallenges)
                            let reply = await OnDeviceLLM.respond(to: prompt, ctx: ctx)
                            aiBriefing = reply.text
                            UserDefaults.standard.set(reply.text, forKey: "lastAIBriefing")
                            lastBriefingDate = Date.now.timeIntervalSince1970
                            briefingLoading = false
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let text = aiBriefing {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF9F0A))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xFF9F0A).opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.scale(scale: 0.88, anchor: .top).combined(with: .opacity))
        }
    }

    private func buildBriefingPrompt(goals: [GoalOut], challenges: [ChallengeOut]) -> String {
        var lines = ["[BRIEFING_MATIN]"]
        lines.append("Heure du réveil : \(String(format: "%02d:%02d", wakeupHour, wakeupMinute))")
        if !userName.isEmpty { lines.append("Utilisateur : \(userName)") }

        var yesterdayLines: [String] = []
        if sleepQuality > 0 {
            let q = ["", "mauvaise", "passable", "correcte", "bonne", "excellente"][sleepQuality]
            yesterdayLines.append("Sommeil : qualité \(q)\(sleepHours > 0 ? ", \(sleepHours)h" : "")")
        }
        if kcalYesterday > 0 {
            let pct = kcalGoal > 0 ? Int(100 * Double(kcalYesterday) / Double(kcalGoal)) : 0
            yesterdayLines.append("Calories : \(kcalYesterday)/\(kcalGoal) kcal (\(pct)%)")
        }
        if waterYesterday > 0 {
            let pct = waterGoal > 0 ? Int(100 * Double(waterYesterday) / Double(waterGoal)) : 0
            yesterdayLines.append("Eau : \(waterYesterday)/\(waterGoal) ml (\(pct)%)")
        }
        if !habits.isEmpty {
            yesterdayLines.append("Habitudes : \(habitsDoneYesterday)/\(habits.count) complétées")
        }
        if !yesterdayLines.isEmpty {
            lines.append("Données d'hier :")
            lines.append(contentsOf: yesterdayLines.map { "- \($0)" })
        }

        if !challenges.isEmpty {
            lines.append("Habitudes actives :")
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
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private func quickActionBtn(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                Text(label).font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(LifeOSPressStyle())
    }
}
