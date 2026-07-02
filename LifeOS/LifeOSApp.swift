import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarm = AlarmManager.shared

    @State private var container: ModelContainer? = nil
    @State private var migrationFailed = false
    @State private var storeWasReset = false
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
        AIMessage.self,
        // Santé médicale
        Medication.self, MedicalAppointment.self, VitalRecord.self, Vaccination.self,
        // Rappels perso (centre de notifications) + programme de sport
        CustomReminder.self, GymDay.self
    ])

    var body: some Scene {
        WindowGroup {
            ZStack {
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
            .preferredColorScheme(appTheme.scheme)
            .tint(appTheme.accent)
            .task { await buildContainer() }
            .alert("Problème de données", isPresented: $migrationFailed) {
                Button("Réessayer") { Task { await buildContainer() } }
                Button("Continuer (données perdues)", role: .destructive) { migrationFailed = false }
            } message: {
                Text("LifeOS n'a pas pu charger ta base de données. Tes données sont en sécurité — réessaie ou contacte le support.")
            }
            .alert("Données réinitialisées", isPresented: $storeWasReset) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Tes données n'ont pas pu être migrées après une mise à jour. Une copie de sauvegarde a été conservée sur l'appareil et l'app repart sur une base vide. Contacte le support pour restaurer la sauvegarde.")
            }
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
            MorningReminder.checkAndArm()
        }
        .onChange(of: onboardingDone) { _, done in
            if done { ContextualNotifications.shared.reschedule() }
        }
        .onChange(of: recommendedModulesRaw) { _, _ in
            ContextualNotifications.shared.reschedule()
        }
        .fullScreenCover(isPresented: Binding(get: { alarm.showAlarmScreen }, set: { if !$0 { alarm.stopRinging() } })) {
            AlarmFullScreenView()
        }
        .sheet(isPresented: $showSleepCheckFromWidget) {
            SleepCheckSheet {
                showSleepCheckFromWidget = false
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
        .sheet(isPresented: Binding(get: { alarm.showSleepCheck }, set: { if !$0 { alarm.phase = .idle } })) {
            SleepCheckSheet { alarm.sleepCheckDone() }
        }
        .fullScreenCover(isPresented: Binding(get: { alarm.showBriefing }, set: { if !$0 { alarm.dismissBriefing() } })) {
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

    // MARK: - Création container

    private func buildContainer() async {
        let schema = Self.schema
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let result = await Task.detached(priority: .userInitiated) {
            Result { try ModelContainer(for: schema, configurations: [config]) }
        }.value

        switch result {
        case .success(let mc):
            migrationFailed = false
            container = mc
        case .failure:
            // Schéma incompatible (ex. colonnes ajoutées) — le store est déplacé
            // dans un backup horodaté, jamais supprimé : les données restent
            // récupérables et l'utilisateur est prévenu via storeWasReset.
            let storeURL = config.url
            let fm = FileManager.default
            let backupDir = storeURL
                .deletingLastPathComponent()
                .appendingPathComponent("LifeOSBackup-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = backupDir.appendingPathComponent(src.lastPathComponent)
                if (try? fm.moveItem(at: src, to: dst)) == nil {
                    // Dernier recours : sans libérer le chemin, l'app ne démarre plus du tout.
                    try? fm.removeItem(at: src)
                }
            }

            if let fresh = try? ModelContainer(for: schema, configurations: [config]) {
                migrationFailed = false
                storeWasReset = true
                container = fresh
            } else {
                migrationFailed = true
                container = try? ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            }
        }
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
