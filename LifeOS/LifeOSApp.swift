import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarm = AlarmManager.shared

    @State private var container: ModelContainer? = nil
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @AppStorage("appTheme") private var appThemeRaw = "classic"
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }
    @State private var showBriefingFromWidget = false
    @State private var showSleepCheckFromWidget = false
    @State private var showWeeklyBilan = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    private static let schema = Schema([
        // Santé
        DreamEntry.self, FoodEntry.self, FastingSession.self, WaterEntry.self,
        Supplement.self, PantryItem.self, ShoppingItem.self, WorkoutSet.self, StepEntry.self,
        // Vie
        ProgressPhoto.self, WardrobeItem.self, MoodEntry.self, TodoItem.self,
        Habit.self, HabitCompletion.self, Note.self, MemoryEntry.self,
        Account.self, Txn.self, Envelope.self, Subscription.self, SavingsGoal.self, SplitExpense.self,
        // Patrimoine & reste
        Holding.self, NetWorthItem.self, Property.self, JobApplication.self, SkillGap.self,
        Flashcard.self, BookSummary.self, Chore.self, Pet.self, PetCare.self, Maintenance.self,
        Vehicle.self, FuelLog.self, Contact.self, SocialEvent.self, DocVault.self, Deadline.self,
        Trip.self, PackingItem.self,
        // Cycle
        CycleEntry.self,
        // Assistant IA
        AIMessage.self
    ])

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Couche 0 — fond système rendu avant toute autre chose.
                // Empêche le flash blanc sur iPhone en mode sombre.
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let container {
                    appContent(container: container)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    SplashView()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .zIndex(0)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: container != nil)
            .preferredColorScheme(appTheme.scheme)   // thème : Couleur de l'app
            .tint(appTheme.accent)
            .task { await buildContainer() }
        }
    }

    // MARK: - Contenu principal

    @ViewBuilder
    private func appContent(container: ModelContainer) -> some View {
        ZStack {
            if !onboardingDone {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(0)
            } else {
                MainTabView()
                    .tint(appTheme.accent)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .modelContainer(container)
        .animation(.easeInOut(duration: 0.35), value: onboardingDone)
        .onAppear {
            resetDailyValuesIfNeeded()
            EngagementTracker.shared.recordOpen()
            Task.detached(priority: .background) {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    await MainActor.run {
                        ContextualNotifications.shared.reschedule()
                        NotificationManager.shared.scheduleWeeklyBilan()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            resetDailyValuesIfNeeded()
        }
        .onChange(of: onboardingDone) { _, done in
            if done { ContextualNotifications.shared.reschedule() }
        }
        .onChange(of: recommendedModulesRaw) { _, _ in
            ContextualNotifications.shared.reschedule()
        }
        .fullScreenCover(isPresented: $alarm.showAlarmScreen) {
            AlarmFullScreenView()
        }
        .sheet(isPresented: $showSleepCheckFromWidget) {
            SleepCheckSheet {
                showSleepCheckFromWidget = false
                // Bref délai pour laisser la sheet se fermer avant d'ouvrir le briefing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showBriefingFromWidget = true
                }
            }
        }
        .fullScreenCover(isPresented: $showBriefingFromWidget) {
            DailyBriefingView(modules: recommendedModules, speakOnAppear: false)
        }
        .onOpenURL { url in
            guard url.scheme == "lifeos", url.host == "briefing" else { return }
            showSleepCheckFromWidget = true
        }
        .sheet(isPresented: $alarm.showSleepCheck) {
            SleepCheckSheet { alarm.sleepCheckDone() }
        }
        .fullScreenCover(isPresented: $alarm.showBriefing) {
            DailyBriefingView(modules: recommendedModules, speakOnAppear: true)
        }
        .sheet(isPresented: $showWeeklyBilan) {
            WeeklyBilanView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenWeeklyBilan)) { _ in
            showWeeklyBilan = true
        }
    }

    // MARK: - Reset journalier à minuit

    private func resetDailyValuesIfNeeded() {
        let key = "lifeos.daily.lastReset"
        let today = Calendar.current.startOfDay(for: Date())
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard !Calendar.current.isDate(last, inSameDayAs: today) else { return }
        UserDefaults.standard.set(0,    forKey: "todayEnergyScore")
        UserDefaults.standard.set("",   forKey: "todayEnergyLabel")
        UserDefaults.standard.set(0,    forKey: "lastSleepQuality")
        UserDefaults.standard.set(0,    forKey: "lastSleepHours")
        UserDefaults.standard.set(0.0,  forKey: "lastSleepCheckDate")
        UserDefaults.standard.set(today, forKey: key)
    }

    // MARK: - Création container (thread de fond, Swift concurrency natif)

    private func buildContainer() async {
        let schema = Self.schema
        let built = await Task.detached(priority: .userInitiated) {
            if let mc = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            ) {
                return mc
            }
            // Fallback mémoire si la migration échoue
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }.value

        container = built
    }
}

// MARK: - Écran de chargement

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.08))
                            .frame(width: 110, height: 110)
                            .scaleEffect(pulse ? 1.08 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                value: pulse
                            )
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 88, height: 88)
                        Image(systemName: "sparkles")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: 5) {
                        Text("LifeOS")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Ton système de vie")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.accentColor)
                    .padding(.bottom, 60)
            }
        }
        .onAppear { pulse = true }
    }
}
