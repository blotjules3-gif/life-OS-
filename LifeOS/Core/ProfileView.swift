import SwiftUI
import SwiftData

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
    @AppStorage("sportHour") private var sportHour = 18
    @AppStorage("bedHour") private var bedHour = 23
    @AppStorage("bedMinute") private var bedMinute = 0
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Environment(\.modelContext) private var ctx

    @State private var steps = 0
    @State private var healthConnected = false
    @State private var showGoalEditor = false
    @State private var showNotificationSettings = false
    @State private var showWakeupDetail = false
    @State private var showBriefing = false
    @State private var appeared = false
    @State private var challenges: [ChallengeOut] = []
    @State private var challengesLoading = true
    @State private var profileSection = 0
    @State private var showOnboardingReset = false
    @State private var showServerConfig = false
    @State private var checkinToast: String? = nil
    @State private var energyScore: EnergyScoreOut? = nil
    @State private var energyHistory: [EnergyScoreOut] = []
    @ObservedObject private var serverStatus = ServerStatusMonitor.shared
    @Namespace private var pickerNS

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var proteinToday: Int { Int(foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0.0) { $0 + $1.protein }) }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

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

    private var activeNotifCount: Int {
        let mods = recommendedModules
        var n = 1
        if mods.contains(.sleep) || mods.contains(.fitness) || mods.contains(.mind) { n += 1 }
        if mods.contains(.fitness) { n += 1 }
        if mods.contains(.nutrition) { n += 1 }
        if mods.contains(.productivity) || mods.contains(.fitness) || mods.contains(.mind) || mods.contains(.sleep) { n += 1 }
        if mods.contains(.sleep) { n += 1 }
        return n
    }

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

    private func parseEndDates() -> [String: Date] {
        guard let data = goalEndDatesRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        profileHeader
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                            .animation(.spring(duration: 0.45, bounce: 0.1), value: appeared)
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
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                        removal: .opacity
                                    ))
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
                                                    guard let result = try? await AgentAPI.shared.checkinChallenge(id: challenge.id),
                                                          let idx = challenges.firstIndex(where: { $0.id == challenge.id })
                                                    else { return }

                                                    let status = result["status"]?.value as? String ?? ""
                                                    if status == "already_checked_in" {
                                                        let streak = (result["streak_days"]?.value as? Int) ?? challenge.streak_days
                                                        checkinToast = "Déjà validé aujourd'hui — streak \(streak)j"
                                                        Task { try? await Task.sleep(nanoseconds: 2_500_000_000); checkinToast = nil }
                                                        return
                                                    }

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
                                            })
                                        }
                                        .transition(.opacity)
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
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
                    steps = await HealthService.shared.cachedStepsToday()
                }
                async let challengesTask = (try? await AgentAPI.shared.fetchChallenges()) ?? []
                async let energyTask = try? await AgentAPI.shared.fetchEnergyScore()
                async let historyTask = (try? await AgentAPI.shared.fetchEnergyHistory(days: 7)) ?? []
                let ch = await challengesTask
                challenges = ch
                challengesLoading = false
                saveChallengesForWidget(challenges)
                energyScore = await energyTask
                energyHistory = await historyTask
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
            .sheet(isPresented: $showNotificationSettings) {
                NotificationSettingsSheet(
                    modules: recommendedModules,
                    sportHour: $sportHour,
                    bedHour: $bedHour,
                    bedMinute: $bedMinute,
                    wakeupHour: $wakeupHour,
                    wakeupMinute: $wakeupMinute
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
            .sheet(isPresented: $showServerConfig) {
                ServerConfigView {
                    showServerConfig = false
                    serverStatus.pingNow()
                }
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .overlay(alignment: .bottom) {
                if let msg = checkinToast {
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial.opacity(0), in: Capsule())
                        .background(Color.secondary.opacity(0.85), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(duration: 0.3), value: msg)
                }
            }
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
                            .animation(.spring(duration: 0.38, bounce: 0.1), value: ctx.date)
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
                    .foregroundStyle(progress >= 1 ? color : .primary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.38, bounce: 0.1), value: value)
                    .animation(.spring(duration: 0.5, bounce: 0.1), value: progress >= 1)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(progress >= 1 ? color.opacity(0.7) : .secondary)
                    .animation(.spring(duration: 0.5, bounce: 0.1), value: progress >= 1)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: mod?.icon ?? "star.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text((mod?.title ?? "Module").uppercased())
                    .font(.system(size: 10, weight: .bold))
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
                        .animation(.spring(duration: 0.38, bounce: 0.1), value: ctx.date)
                    Text("restantes")
                        .font(.system(size: 10, weight: .semibold))
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
        case .medical:      return "Prends soin de ta santé — médicaments, RDV, constantes."
        }
    }

    // MARK: - Night Island

    private var nightIsland: some View {
        let accentColor = Color(hex: 0xE07B3C)
        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RÉVEIL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor.opacity(0.8))
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
                            .foregroundStyle(accentColor.opacity(0.8))
                            .transition(.scale(scale: 0.25).combined(with: .opacity))
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
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
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

    // MARK: - Section Picker

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
                        .padding(.vertical, 12)
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

    // MARK: - Challenges helpers

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
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 64, height: 64)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.75))
            }
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
                .frame(minHeight: 44)
                .padding(.horizontal, 20)
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
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                            .animation(.spring(duration: 0.38, bounce: 0.1), value: task.progress)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    if let end = endDate {
                        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 0)
                        Text(days > 0 ? "J-\(days)" : "Échu")
                            .font(.system(size: 10, weight: .bold))
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
        .padding(16)
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
        .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(task.color.opacity(task.progress >= 1 ? 0.4 : 0), lineWidth: 1.5)
                .animation(.spring(duration: 0.38, bounce: 0.1), value: task.progress >= 1)
        )
    }

    // MARK: - Bento eau

    private var bentoRow: some View {
        let waterColor = Color(hex: 0x3CB2E0)
        let waterProgress = min(1.0, Double(waterToday) / Double(max(1, waterGoal)))
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(waterColor.opacity(waterProgress >= 1 ? 0.22 : 0.14))
                        .frame(width: 44, height: 44)
                        .animation(.spring(duration: 0.5, bounce: 0.1), value: waterProgress >= 1)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(waterColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("EAU")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(waterProgress >= 1 ? waterColor : .secondary)
                        .kerning(1.2)
                        .animation(.spring(duration: 0.5, bounce: 0.1), value: waterProgress >= 1)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(glassesToday)")
                            .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(waterProgress >= 1 ? waterColor : .primary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.38, bounce: 0.1), value: glassesToday)
                            .animation(.spring(duration: 0.5, bounce: 0.1), value: waterProgress >= 1)
                        Text("/ \(glassesGoalCalc) verres")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(waterProgress >= 1 ? waterColor.opacity(0.7) : .secondary)
                            .animation(.spring(duration: 0.5, bounce: 0.1), value: waterProgress >= 1)
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
                            .background(waterColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(LifeOSPressStyle())
                    Button {
                        ctx.insert(WaterEntry(amountML: 750)); Haptics.tap()
                    } label: {
                        Text("+3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(waterColor)
                            .frame(minWidth: 52, minHeight: 44)
                            .background(waterColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .animation(.spring(duration: 1.0).delay(0.2), value: appeared)
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
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                Text(todayTip)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
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
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                    }
                } action: {
                    Task {
                        let result = await HealthService.shared.requestAuthorization()
                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { healthConnected = result }
                    }
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1).padding(.leading, 50)
                settingsRow(icon: "bell.fill", iconColor: Color(hex: 0xE0A23C), label: "Gérer mes rappels") {
                    HStack(spacing: 6) {
                        Text("\(activeNotifCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color(hex: 0xE0A23C), in: Capsule())
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                    }
                } action: {
                    showNotificationSettings = true
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1).padding(.leading, 50)
                settingsRow(icon: "slider.horizontal.3", iconColor: Color.accentColor, label: "Modifier mes objectifs") {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                } action: {
                    showGoalEditor = true
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1).padding(.leading, 50)
                settingsRow(icon: "sparkles", iconColor: Color.accentColor, label: "Assistant IA — serveur") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(serverStatus.dotColor == .clear ? Color.secondary.opacity(0.3) : serverStatus.dotColor)
                            .frame(width: 8, height: 8)
                        Text(serverStatus.isOnline == true ? "En ligne" : serverStatus.isOnline == false ? "Hors ligne" : "…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(serverStatus.isOnline == true ? Color.green : serverStatus.isOnline == false ? Color.orange : Color.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                    }
                } action: {
                    showServerConfig = true
                }
            }
            .background(neoCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
            .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)

            Button { showOnboardingReset = true } label: {
                Text("Refaire l'onboarding")
                    .font(.system(size: 15, weight: .medium))
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
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(AppCategory.allCases.count) modules").font(.system(size: 12)).foregroundStyle(.tertiary)
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
                                .overlay(
                                    Circle()
                                        .stroke(th.accent, lineWidth: selected ? 2.5 : 0)
                                        .animation(.spring(duration: 0.38, bounce: 0.15), value: selected)
                                )
                                .padding(2)
                                Text(th.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(selected ? .primary : .secondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }
                }
                Text("Thème actif dans toute l'app — modifiable à tout moment.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text(label).font(.system(size: 15, weight: .regular)).foregroundStyle(.primary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
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
            let timeString = String(format: "%02d:%02d", wakeupHour, wakeupMinute)
            if #available(iOS 16.1, *) {
                await AlarmLiveActivityManager.shared.startScheduled(alarmTimeString: timeString)
            }
        }
    }
}
