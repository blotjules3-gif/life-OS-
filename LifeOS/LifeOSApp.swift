import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarm = AlarmManager.shared

    // Container optionnel — créé en background pour ne pas bloquer l'UI
    @State private var container: ModelContainer? = nil
    @State private var loadingStatus = "Démarrage…"
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @State private var ready = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    // Schéma déclaré statiquement (pas d'init au lancement)
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
                    SplashView(status: loadingStatus)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: container != nil)
            .task { await buildContainer() }
        }
    }

    // MARK: - Contenu principal (affiché une fois le container prêt)

    @ViewBuilder
    private func appContent(container: ModelContainer) -> some View {
        ZStack {
            if !onboardingDone {
                OnboardingView()
                    .transition(.opacity)
            } else if !ready {
                SplashView(status: loadingStatus)
                    .transition(.opacity)
            } else {
                MainTabView()
                    .tint(Theme.accent)
                    .transition(.opacity)
            }
        }
        .modelContainer(container)
        .animation(.easeInOut(duration: 0.4), value: onboardingDone)
        .animation(.easeInOut(duration: 0.4), value: ready)
        .task(id: onboardingDone) {
            guard onboardingDone else { return }
            loadingStatus = "Préparation de ton espace…"
            _ = await NotificationManager.shared.requestAuthorization()
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation { ready = true }
        }
        // Écran réveil iPhone-style — par dessus tout, avec modelContainer injecté
        .fullScreenCover(isPresented: $alarm.showAlarmScreen) {
            AlarmFullScreenView()
        }
        // Briefing quotidien avec voix — accède à @Query via modelContainer
        .fullScreenCover(isPresented: $alarm.showBriefing) {
            DailyBriefingView(modules: recommendedModules, speakOnAppear: true)
        }
    }

    // MARK: - Création container en background (ne bloque pas le thread principal)

    private func buildContainer() async {
        loadingStatus = "Initialisation de la base…"

        let built: ModelContainer = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let schema = Self.schema
                do {
                    let mc = try ModelContainer(
                        for: schema,
                        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
                    )
                    continuation.resume(returning: mc)
                } catch {
                    // Migration échouée → base en mémoire (mode dégradé)
                    let mc = try! ModelContainer(
                        for: schema,
                        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                    )
                    continuation.resume(returning: mc)
                }
            }
        }

        // Retour sur le thread principal pour mettre à jour l'UI
        await MainActor.run {
            loadingStatus = "Chargement…"
            container = built
        }
    }
}

// MARK: - Écran de chargement

struct SplashView: View {
    var status: String = "Chargement…"
    @State private var pulse = false
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    // Logo animé
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.08))
                            .frame(width: 110, height: 110)
                            .scaleEffect(pulse ? 1.1 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                value: pulse
                            )
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 88, height: 88)
                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: 6) {
                        Text("LifeOS")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Ton système de vie")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Barre de progression indéterminée + statut
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Color.accentColor)

                    Text(status + String(repeating: ".", count: dotCount))
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .animation(.none, value: dotCount)
                        .onReceive(timer) { _ in
                            dotCount = (dotCount + 1) % 4
                        }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear { pulse = true }
    }
}
