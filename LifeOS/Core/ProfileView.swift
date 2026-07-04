import SwiftUI
import SwiftData
import WidgetKit

private struct OrbitSatellite: Identifiable {
    let category: AppCategory
    let progress: Double?
    var id: String { category.rawValue }
}

struct ProfileView: View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var steps = 0
    @State private var healthConnected = false
    @State private var showGoalEditor = false
    @State private var showNotificationSettings = false
    @State private var showWakeupDetail = false
    @State private var showBriefing = false
    @State private var appeared = false
    @State private var challenges: [ChallengeOut] = []
    @State private var challengesLoading = true
    @State private var showOnboardingReset = false
    @State private var showServerConfig = false
    @State private var showExportSheet = false
    @State private var appLockEnabled = AppLock.shared.isEnabled
    @State private var checkinToast: String? = nil
    @State private var energyScore: EnergyScoreOut? = nil
    @State private var facet = 0
    @Namespace private var facetNS
    @ObservedObject private var serverStatus = ServerStatusMonitor.shared

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }
    private var kcalToday: Int  { foods.caloriesToday }
    private var waterToday: Int { waters.mlToday }
    private var habitsDone: Int { habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count }

    // MARK: - Life Score (eau 25 % + kcal 25 % + habitudes 30 % + pas 20 %)

    private var waterRatio: Double { min(1, Double(waterToday) / Double(max(1, waterGoal))) }
    private var kcalRatio: Double  { min(1, Double(kcalToday) / Double(max(1, kcalGoal))) }
    private var habitRatio: Double { habits.isEmpty ? 0 : min(1, Double(habitsDone) / Double(habits.count)) }
    private var stepRatio: Double  { min(1, Double(steps) / Double(max(1, stepGoal))) }
    private var lifeScore: Int {
        Int((waterRatio * 0.25 + kcalRatio * 0.25 + habitRatio * 0.30 + stepRatio * 0.20) * 100)
    }
    private var habitsWeekCount: Int {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) else { return 0 }
        return habits.reduce(0) { $0 + $1.completions.filter { $0.date >= start }.count }
    }

    private func habitCompletionRate(on date: Date) -> Double {
        guard !habits.isEmpty else { return 0 }
        let done = habits.filter { h in h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: date) } }.count
        return Double(done) / Double(habits.count)
    }

    private var weekDelta: Int? {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        guard let weekStart = cal.date(byAdding: .day, value: -6, to: todayStart),
              let prevStart = cal.date(byAdding: .day, value: -13, to: todayStart) else { return nil }
        let thisWeek = habits.reduce(0) { $0 + $1.completions.filter { $0.date >= weekStart }.count }
        let lastWeek = habits.reduce(0) { $0 + $1.completions.filter { $0.date >= prevStart && $0.date < weekStart }.count }
        guard lastWeek > 0 else { return nil }
        return Int(Double(thisWeek - lastWeek) / Double(lastWeek) * 100)
    }

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

    private var alarmRingsNextDay: Bool {
        guard wakeupEnabled else { return false }
        let cal = Calendar.current
        let h = cal.component(.hour, from: .now)
        let m = cal.component(.minute, from: .now)
        return wakeupHour < h || (wakeupHour == h && wakeupMinute <= m)
    }

    // MARK: - Identité

    private var displayName: String {
        name.isEmpty ? "Mon profil" : name.prefix(1).uppercased() + name.dropFirst()
    }
    private var userInitial: String {
        name.isEmpty ? "L" : String(name.prefix(1)).uppercased()
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }

    // MARK: - Satellites

    private var orbitSatellites: [OrbitSatellite] {
        quickAccessModules.map { cat in
            let progress: Double?
            switch cat {
            case .nutrition:    progress = kcalRatio
            case .fitness:      progress = stepRatio
            case .productivity: progress = habitRatio
            default:            progress = nil
            }
            return OrbitSatellite(category: cat, progress: progress)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    OrbitHero(
                        displayName: displayName,
                        initial: userInitial,
                        greeting: greeting,
                        score: lifeScore,
                        streak: EngagementTracker.shared.consecutiveDays,
                        totalDays: EngagementTracker.shared.totalDays,
                        habitsWeek: habitsWeekCount,
                        satellites: orbitSatellites,
                        appeared: appeared,
                        pinnedIDs: Set(profilePinnedRaw.split(separator: ",").map(String.init)),
                        onPin: { cat in
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { pinGoal(cat.rawValue) }
                        },
                        onHide: { cat in
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { toggleHideGoal(cat.rawValue) }
                        }
                    )
                    .staggered(0, appeared: appeared)

                    if !hiddenGoals.isEmpty {
                        restoreHiddenButton
                    }

                    facetBar
                        .staggered(1, appeared: appeared)

                    facetContent
                        .staggered(2, appeared: appeared)
                        .scrollFade()
                }
                .padding(.horizontal, 16)
                .padding(.top, Theme.space8)
                .padding(.bottom, 80)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .onAppear { appeared = true }
            .task {
                if await HealthService.shared.requestAuthorization() {
                    healthConnected = true
                    steps = await HealthService.shared.cachedStepsToday()
                }
                async let challengesTask = (try? await AgentAPI.shared.fetchChallenges()) ?? []
                async let energyTask = try? await AgentAPI.shared.fetchEnergyScore()
                let ch = await challengesTask
                challenges = ch
                challengesLoading = false
                saveChallengesForWidget(challenges)
                energyScore = await energyTask
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
            .sheet(isPresented: $showExportSheet) {
                DataExportSheet()
            }
            #if DEBUG
            .sheet(isPresented: $showServerConfig) {
                ServerConfigView {
                    showServerConfig = false
                    serverStatus.pingNow()
                }
            }
            #endif
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

    // MARK: - Facettes

    private var facetBar: some View {
        HStack(alignment: .top, spacing: 28) {
            facetTab(0, "01", "Pulse")
            facetTab(1, "02", "Contrôle")
            Spacer()
        }
        .padding(.horizontal, 4)
        .sensoryFeedback(.selection, trigger: facet)
    }

    private func facetTab(_ idx: Int, _ code: String, _ title: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { facet = idx }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(code)
                    .monoLabel(9)
                    .foregroundStyle(facet == idx ? AnyShapeStyle(Theme.volt) : AnyShapeStyle(.tertiary))
                Text(title)
                    .font(.system(size: 20, weight: .black))
                    .textCase(.uppercase)
                    .kerning(-0.3)
                    .foregroundStyle(facet == idx ? Color.primary : Color.secondary.opacity(0.45))
                ZStack {
                    if facet == idx {
                        Capsule()
                            .fill(Theme.volt)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "facetline", in: facetNS)
                    } else {
                        Color.clear.frame(height: 3)
                    }
                }
            }
        }
        .buttonStyle(LifeOSPressStyle())
    }

    @ViewBuilder private var facetContent: some View {
        if facet == 0 {
            VStack(spacing: 24) {
                weekCard
                challengesSection
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        } else {
            VStack(spacing: 24) {
                wakeupCompact
                settingsSection
                appearanceSection
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private var restoreHiddenButton: some View {
        Button {
            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { profileHiddenRaw = "" }
        } label: {
            Text("Afficher \(hiddenGoals.count) module\(hiddenGoals.count > 1 ? "s" : "") masqué\(hiddenGoals.count > 1 ? "s" : "")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .surface(radius: 16)
        }
        .buttonStyle(LifeOSPressStyle())
    }

    // MARK: - Ma semaine

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ma semaine")
                    .font(.system(size: 20, weight: .black))
                    .textCase(.uppercase)
                    .kerning(-0.3)
                Spacer()
                if let delta = weekDelta {
                    let up = delta >= 0
                    HStack(spacing: 3) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(up ? "+" : "")\(delta) %")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(up ? Color(hex: 0x4CC38A) : Color(hex: 0xF1746C))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((up ? Color(hex: 0x4CC38A) : Color(hex: 0xF1746C)).opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 4)

            weekCardBody
        }
    }

    @ViewBuilder private var weekCardBody: some View {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        VStack(alignment: .leading, spacing: 14) {
            if habits.isEmpty {
                Text("Crée des habitudes pour suivre ta progression semaine par semaine.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<7, id: \.self) { i in
                        let date = cal.date(byAdding: .day, value: i - 6, to: todayStart) ?? todayStart
                        let rate = habitCompletionRate(on: date)
                        let isToday = i == 6
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                                    .frame(height: 56)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(rate >= 1 ? Color(hex: 0x4CC38A) : Color.accentColor.opacity(isToday ? 1 : 0.45))
                                    .frame(height: appeared ? max(5, 56 * rate) : 5)
                                    .animation(
                                        reduceMotion ? .easeOut(duration: 0.2)
                                                     : .spring(duration: 0.7, bounce: 0.15).delay(Double(i) * 0.05 + 0.15),
                                        value: appeared
                                    )
                            }
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 10, weight: isToday ? .bold : .medium))
                                .foregroundStyle(isToday ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if let score = energyScore?.energy_score {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(energyColor(score))
                    Text("Énergie")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let label = energyScore?.label {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(score)/100")
                        .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(energyColor(score))
                }
            }
        }
        .padding(16)
        .surface()
    }

    private func energyColor(_ score: Int?) -> Color {
        switch score ?? 0 {
        case 75...: return Color(hex: 0x4CC38A)
        case 50..<75: return Color(hex: 0xE0A23C)
        default: return Color(hex: 0xF1746C)
        }
    }

    // MARK: - Mes défis

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mes défis")
                    .font(.system(size: 20, weight: .black))
                    .textCase(.uppercase)
                    .kerning(-0.3)
                if !challenges.isEmpty {
                    Spacer()
                    Text("\(challenges.count) actif\(challenges.count > 1 ? "s" : "")")
                        .monoLabel(10)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if challengesLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .surface()
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
        .animation(.spring(duration: 0.35, bounce: 0.1), value: challengesLoading)
    }

    private func saveChallengesForWidget(_ list: [ChallengeOut]) {
        guard let top = list.first,
              let defaults = UserDefaults(suiteName: "group.lifeos.app") else { return }
        defaults.set(top.title, forKey: "widget_challenge_title")
        defaults.set(top.streak_days, forKey: "widget_challenge_streak")
        defaults.set(top.duration_days ?? 30, forKey: "widget_challenge_duration")
        defaults.set(top.days_elapsed, forKey: "widget_challenge_elapsed")
        defaults.set(top.challenge_type, forKey: "widget_challenge_type")
        WidgetCenter.shared.reloadTimelines(ofKind: "ChallengeStreakWidget")
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
                Text("Crée un défi avec ton coach.")
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
        .surface()
    }

    // MARK: - Modules (épingler / masquer)

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

    private var quickAccessModules: [AppCategory] {
        let base = recommendedModules.isEmpty
            ? [AppCategory.nutrition, .fitness, .productivity, .mind]
            : recommendedModules
        let pinned = Set(profilePinnedRaw.split(separator: ",").map(String.init))
        let visible = base.filter { !hiddenGoals.contains($0.rawValue) }
        let ordered = visible.enumerated().sorted { l, r in
            let lp = pinned.contains(l.element.rawValue)
            let rp = pinned.contains(r.element.rawValue)
            if lp != rp { return lp }
            return l.offset < r.offset
        }.map(\.element)
        return Array(ordered.prefix(6))
    }

    // MARK: - Réveil compact

    private var wakeupCompact: some View {
        let accentColor = Theme.volt
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { showWakeupDetail = true } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accentColor.opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: "alarm.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Réveil")
                                .monoLabel(10)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .lastTextBaseline, spacing: 5) {
                                Text(String(format: "%02d:%02d", wakeupHour, wakeupMinute))
                                    .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                                    .foregroundStyle(wakeupEnabled ? .primary : .secondary)
                                    .contentTransition(.numericText())
                                    .animation(.spring(duration: 0.38, bounce: 0.1), value: wakeupHour)
                                    .animation(.spring(duration: 0.38, bounce: 0.1), value: wakeupMinute)
                                if alarmRingsNextDay {
                                    Text("demain")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(LifeOSPressStyle())
                Spacer()
                Toggle("", isOn: $wakeupEnabled)
                    .tint(accentColor)
                    .labelsHidden()
                    .onChange(of: wakeupEnabled) { _, on in
                        if on { scheduleWakeupAlarm() }
                        else { NotificationManager.shared.cancel(id: "lifeos.wakeup") }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(LifeOSPressStyle())
        }
        .surface(radius: 20)
    }

    // MARK: - Paramètres

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Réglages")
                .font(.system(size: 20, weight: .black))
                .textCase(.uppercase)
                .kerning(-0.3)
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
                settingsRow(icon: "sparkles", iconColor: Color.accentColor, label: "Coach — serveur") {
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
                    #if DEBUG
                    showServerConfig = true
                    #else
                    serverStatus.pingNow()
                    #endif
                }
                if AppLock.shared.isAvailable {
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1).padding(.leading, 50)
                    settingsRow(icon: "faceid", iconColor: Color(hex: 0x4CC38A),
                                label: "Verrouiller avec \(AppLock.shared.biometryLabel)") {
                        Text(appLockEnabled ? "Activé" : "Désactivé")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(appLockEnabled ? Color(hex: 0x4CC38A) : .secondary)
                    } action: {
                        if appLockEnabled {
                            AppLock.shared.isEnabled = false
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { appLockEnabled = false }
                        } else {
                            Task {
                                if await AppLock.shared.enableAfterAuth() {
                                    withAnimation(.spring(duration: 0.38, bounce: 0.1)) { appLockEnabled = true }
                                }
                            }
                        }
                    }
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1).padding(.leading, 50)
                settingsRow(icon: "square.and.arrow.up", iconColor: Color(hex: 0x5B8DEF),
                            label: "Exporter mes données") {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                } action: {
                    showExportSheet = true
                }
            }
            .surface()

            Button { showOnboardingReset = true } label: {
                Text("Refaire l'onboarding")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0xF1746C))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: 0xF1746C).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            Text("Apparence")
                .font(.system(size: 20, weight: .black))
                .textCase(.uppercase)
                .kerning(-0.3)
                .padding(.horizontal, 4)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(AppTheme.selectable) { th in
                        let selected = appThemeRaw == th.rawValue
                        Button {
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { appThemeRaw = th.rawValue }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(th.previewFill)
                                        .frame(width: 42, height: 42)
                                        .shadow(color: selected ? Color.black.opacity(0.18) : .clear, radius: 6, x: 0, y: 3)
                                    Image(systemName: th.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(th.previewIcon)
                                }
                                .overlay(
                                    Circle()
                                        .stroke(selected ? Color.accentColor : Theme.hairline, lineWidth: selected ? 2.5 : 1)
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
            .surface()
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

// MARK: - OrbitHero — système orbital (orbe Life Score + satellites)

private struct OrbitHero: View {
    let displayName: String
    let initial: String
    let greeting: String
    let score: Int
    let streak: Int
    let totalDays: Int
    let habitsWeek: Int
    let satellites: [OrbitSatellite]
    let appeared: Bool
    let pinnedIDs: Set<String>
    let onPin: (AppCategory) -> Void
    let onHide: (AppCategory) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            identityRow
            orbitalField
                .frame(height: 340)
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
            statsRow
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x0D1B2A), Color(hex: 0x162636)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .shadowMd()
    }

    // MARK: Identité

    private var identityRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 40, height: 40)
                Text(initial)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .monoLabel(10)
                    .foregroundStyle(.white.opacity(0.55))
                Text(displayName)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0xE0A23C))
                    Text("\(streak)")
                        .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.10), in: Capsule())
            }
        }
    }

    // MARK: Champ orbital

    private var orbitalField: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { tl in
            let phase = reduceMotion ? 0.0
                : tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 360) * (2 * .pi / 360)
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                    .frame(width: 252, height: 252)

                connections(phase: phase)

                coreOrb

                ForEach(Array(satellites.enumerated()), id: \.element.id) { i, sat in
                    satelliteNode(sat, index: i)
                        .offset(x: cos(angle(i, phase)) * 126,
                                y: sin(angle(i, phase)) * 126)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func angle(_ i: Int, _ phase: Double) -> Double {
        -Double.pi / 2 + Double(i) * (2 * .pi / Double(max(1, satellites.count))) + phase
    }

    private func connections(phase: Double) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for (i, sat) in satellites.enumerated() {
                let a = angle(i, phase)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * 92, y: c.y + sin(a) * 92))
                p.addLine(to: CGPoint(x: c.x + cos(a) * 100, y: c.y + sin(a) * 100))
                ctx.stroke(p, with: .color(sat.category.tint.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Orbe central

    private var coreOrb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [scoreColor.opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 220, height: 220)
                .blur(radius: 18)
                .allowsHitTesting(false)

            ForEach(0..<60, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i % 5 == 0 ? 0.30 : 0.12))
                    .frame(width: 1.5, height: i % 5 == 0 ? 7 : 4)
                    .offset(y: -84)
                    .rotationEffect(.degrees(Double(i) * 6))
            }

            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 9)
                .frame(width: 144, height: 144)
            Circle()
                .trim(from: 0, to: appeared ? CGFloat(score) / 100 : 0)
                .stroke(AngularGradient(colors: [scoreColor.opacity(0.25), scoreColor], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 144, height: 144)
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2)
                                 : .spring(duration: 1.3, bounce: 0.1).delay(0.4),
                    value: appeared
                )

            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 118, height: 118)
            Circle()
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                .frame(width: 118, height: 118)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.5), value: score)
                Text("Life Score")
                    .monoLabel(8)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: Satellites

    private func satelliteNode(_ sat: OrbitSatellite, index i: Int) -> some View {
        NavigationLink(value: sat.category) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 52, height: 52)
                Circle()
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 52, height: 52)
                if let progress = sat.progress {
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(progress) : 0)
                        .stroke(sat.category.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.2)
                                         : .spring(duration: 0.9, bounce: 0.1).delay(0.5 + Double(i) * 0.08),
                            value: appeared
                        )
                }
                Image(systemName: sat.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sat.category.tint)
            }
            .overlay(alignment: .center) {
                Text(sat.category.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 36)
            }
        }
        .buttonStyle(LifeOSPressStyle())
        .contextMenu {
            Button {
                onPin(sat.category)
            } label: {
                Label(pinnedIDs.contains(sat.category.rawValue) ? "Désépingler" : "Épingler en premier",
                      systemImage: pinnedIDs.contains(sat.category.rawValue) ? "pin.slash" : "pin.fill")
            }
            Button(role: .destructive) {
                onHide(sat.category)
            } label: {
                Label("Masquer", systemImage: "eye.slash")
            }
        }
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                         : .spring(duration: 0.6, bounce: 0.25).delay(0.3 + Double(i) * 0.07),
            value: appeared
        )
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            heroStat("\(streak)", "d'affilée")
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 30)
            heroStat("\(totalDays)", "jours actifs")
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 30)
            heroStat("\(habitsWeek)", "habitudes / 7 j")
        }
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
