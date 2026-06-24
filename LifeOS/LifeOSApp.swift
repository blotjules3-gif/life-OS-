import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            // Santé
            DreamEntry.self, FoodEntry.self, FastingSession.self, WaterEntry.self,
            Supplement.self, PantryItem.self, ShoppingItem.self, WorkoutSet.self, StepEntry.self,
            // Vie
            ProgressPhoto.self, WardrobeItem.self, MoodEntry.self, TodoItem.self,
            Habit.self, HabitCompletion.self, Note.self,
            Account.self, Txn.self, Envelope.self, Subscription.self, SavingsGoal.self, SplitExpense.self,
            // Patrimoine & reste
            Holding.self, NetWorthItem.self, Property.self, JobApplication.self, SkillGap.self,
            Flashcard.self, BookSummary.self, Chore.self, Pet.self, PetCare.self, Maintenance.self,
            Vehicle.self, FuelLog.self, Contact.self, SocialEvent.self, DocVault.self, Deadline.self,
            Trip.self, PackingItem.self
        ])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)])
        } catch {
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
    }()

    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var ready = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !onboardingDone {
                    // Première utilisation → onboarding
                    OnboardingView()
                        .transition(.opacity)
                } else if !ready {
                    // Retour dans l'app → splash de chargement
                    SplashView()
                        .transition(.opacity)
                } else {
                    // App prête
                    HoneycombCategoriesView()
                        .tint(Theme.accent)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: onboardingDone)
            .animation(.easeInOut(duration: 0.45), value: ready)
            .task(id: onboardingDone) {
                guard onboardingDone else { return }
                _ = await NotificationManager.shared.requestAuthorization()
                try? await Task.sleep(for: .milliseconds(1200))
                ready = true
            }
        }
        .modelContainer(container)
    }
}

// MARK: - Écran de chargement

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 88, height: 88)
                            .scaleEffect(pulse ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("LifeOS")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Ton système de vie")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Color.accentColor)
                    Text("Chargement…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 52)
            }
        }
        .onAppear { pulse = true }
    }
}
