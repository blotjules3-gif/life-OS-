import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarm = AlarmManager.shared

    @State private var container: ModelContainer? = nil
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @State private var showBriefingFromWidget = false
    @State private var showSleepCheckFromWidget = false

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
        Trip.self, PackingItem.self
    ])

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let container {
                    appContent(container: container)
                } else {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: container != nil)
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
            } else {
                MainTabView()
                    .tint(Theme.accent)
                    .transition(.opacity)
            }
        }
        .modelContainer(container)
        .animation(.easeInOut(duration: 0.35), value: onboardingDone)
        .onAppear {
            // Notification auth en arrière-plan — ne bloque rien
            Task.detached(priority: .background) {
                _ = await NotificationManager.shared.requestAuthorization()
            }
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
        .fullScreenCover(isPresented: $alarm.showBriefing) {
            DailyBriefingView(modules: recommendedModules, speakOnAppear: true)
        }
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
            Theme.bg.ignoresSafeArea()

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
