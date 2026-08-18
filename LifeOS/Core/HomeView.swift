import SwiftUI
import SwiftData

/// Nouvelle Home unifiée — dashboard "état de vie" en une seule vue.
///
/// Structure :
///   1. Dark hero card avec score énergie (ring animé, glow tint)
///   2. Grille 2×3 de LifeStatusTile agrégeant les 15 modules
///   3. CTA gros bouton "Parler à ton coach"
///   4. Prochain moment (fenêtre d'action à venir)
///   5. Habitudes du jour (dot grid)
///
/// C'est la nouvelle vitrine de LifeOS — la promesse du "système de vie
/// centralisé" doit se lire en 1 seconde à l'ouverture.
struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]

    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.waterGoal) private var waterGoal = 2500
    @AppStorage(AppStorageKeys.kcalGoal) private var kcalGoal = 2200
    @AppStorage(AppStorageKeys.stepGoal) private var stepGoal = 8000
    @AppStorage("todayEnergyScore") private var todayEnergyScore = 0
    @AppStorage("todayEnergyLabel") private var todayEnergyLabel = ""
    @AppStorage("lastSleepHours") private var lastSleepHours = 0
    @AppStorage("lastSleepQuality") private var lastSleepQuality = 0

    @State private var appeared = false
    @State private var steps = 0

    // MARK: - Calculs

    private var waterToday: Int { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    private var kcalToday: Int { foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories } }
    private var proteinToday: Int { Int(foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0.0) { $0 + $1.protein }.rounded()) }
    private var habitsDoneToday: Int {
        habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
    }
    private var todayMoodScore: Int? {
        moods.first { Calendar.current.isDateInToday($0.date) }?.score
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base: String
        switch hour {
        case 5..<12:  base = "Bonjour"
        case 12..<18: base = "Bel après-midi"
        case 18..<23: base = "Bonsoir"
        default:      base = "Bonne nuit"
        }
        return userName.isEmpty ? base : "\(base), \(userName)"
    }

    private var scoreColor: Color {
        if todayEnergyScore >= 75 { return Color(hex: 0x00D4B4) }
        if todayEnergyScore >= 50 { return Theme.warning }
        return Theme.danger
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    heroCard
                        .staggered(0, appeared: appeared)
                    lifeStatusGrid
                        .staggered(1, appeared: appeared)
                    coachCTA
                        .staggered(2, appeared: appeared)
                    if !habits.isEmpty {
                        habitsSection
                            .staggered(3, appeared: appeared)
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle("Accueil")
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.screenBG)
            .floatingBarClearance()
            .refreshable { refresh() }
            .onAppear {
                refresh()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Hero card (dark, score ring)

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x0D1B2A), Color(hex: 0x162636)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // Glow blob teinté selon score
            Circle()
                .fill(RadialGradient(
                    colors: [scoreColor.opacity(0.35), .clear],
                    center: .center, startRadius: 0, endRadius: 120
                ))
                .frame(width: 240, height: 240)
                .offset(x: 100, y: -60)
                .blur(radius: 24)
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting)
                        .font(.system(.headline, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if todayEnergyScore > 0 {
                        Text("Énergie du jour")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                            .kerning(1.2)
                    } else {
                        Text("Fais ton bilan matinal pour voir ton énergie")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    if !todayEnergyLabel.isEmpty {
                        Text(todayEnergyLabel)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(scoreColor)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)

                scoreRing
            }
            .padding(20)
        }
        .frame(minHeight: 160)
        .shadowMd()
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 9)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0, to: appeared ? CGFloat(todayEnergyScore) / 100 : 0)
                .stroke(
                    AngularGradient(
                        colors: [scoreColor.opacity(0.25), scoreColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2)
                                 : .spring(duration: 1.2, bounce: 0.1).delay(0.3),
                    value: appeared
                )
            VStack(spacing: 0) {
                Text("\(todayEnergyScore)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .kerning(1.0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Score énergie du jour : \(todayEnergyScore) sur 100")
    }

    // MARK: - Life status grid (agrège les 15 modules)

    private var lifeStatusGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            // Sommeil
            LifeStatusTile(
                icon: "moon.stars.fill",
                value: lastSleepHours > 0 ? "\(lastSleepHours)h" : "—",
                label: "Sommeil",
                subtitle: lastSleepQuality > 0 ? "qualité \(lastSleepQuality)/5" : "aucun bilan",
                status: lastSleepHours > 0 && lastSleepHours < 6 ? .warning : .normal,
                tint: Theme.sleep,
                onTap: { NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": "sleep"]) }
            )
            // Nutrition
            LifeStatusTile(
                icon: "flame.fill",
                value: "\(kcalToday)",
                unit: "kcal",
                label: "Nutrition",
                subtitle: "obj. \(kcalGoal) kcal",
                progress: kcalGoal > 0 ? min(1, Double(kcalToday) / Double(kcalGoal)) : nil,
                tint: Theme.nutrition,
                onTap: { NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": "nutrition"]) }
            )
            // Hydratation
            LifeStatusTile(
                icon: "drop.fill",
                value: "\(waterToday)",
                unit: "ml",
                label: "Hydratation",
                subtitle: "obj. \(waterGoal) ml",
                progress: waterGoal > 0 ? min(1, Double(waterToday) / Double(waterGoal)) : nil,
                status: waterToday < waterGoal / 3 ? .warning : .normal,
                tint: Theme.hydration,
                onTap: { NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": "nutrition"]) }
            )
            // Habitudes
            LifeStatusTile(
                icon: "checklist",
                value: "\(habitsDoneToday)",
                unit: "/ \(habits.count)",
                label: "Habitudes",
                subtitle: habitsDoneToday == habits.count && !habits.isEmpty ? "Toutes faites" : "à cocher",
                progress: habits.isEmpty ? 0 : Double(habitsDoneToday) / Double(habits.count),
                tint: Theme.productivity,
                onTap: { NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": "productivity"]) }
            )
            // Pas
            LifeStatusTile(
                icon: "figure.walk",
                value: "\(steps)",
                label: "Pas",
                subtitle: "obj. \(stepGoal)",
                progress: stepGoal > 0 ? min(1, Double(steps) / Double(stepGoal)) : nil,
                tint: Theme.fitness,
                onTap: { NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": "fitness"]) }
            )
            // Humeur
            LifeStatusTile(
                icon: "face.smiling",
                value: todayMoodScore.map { moodEmoji($0) } ?? "—",
                label: "Humeur",
                subtitle: todayMoodScore != nil ? "\(todayMoodScore!)/5" : "à noter",
                tint: Theme.mind,
                onTap: { NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": "mind"]) }
            )
        }
    }

    // MARK: - Coach CTA

    private var coachCTA: some View {
        Button {
            NotificationCenter.default.post(name: .lifeOSOpenAIChat, object: nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parler à ton coach")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Il connaît ton contexte du jour")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(LifeOSPressStyle())
        .accessibilityLabel("Ouvrir le chat avec ton coach")
    }

    // MARK: - Habitudes du jour (dot grid)

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HABITUDES")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .kerning(1.4)
                Spacer()
                Text("\(habitsDoneToday) / \(habits.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 5) {
                ForEach(Array(habits.prefix(10).enumerated()), id: \.offset) { _, h in
                    let done = h.completions.contains { Calendar.current.isDateInToday($0.date) }
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(done
                              ? Color(hex: UInt(h.colorHex))
                              : Color(hex: UInt(h.colorHex)).opacity(0.18))
                        .frame(height: 18)
                        .accessibilityLabel("\(h.name) \(done ? "fait" : "à faire")")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Utils

    private func moodEmoji(_ score: Int) -> String {
        ["😞", "😕", "😐", "🙂", "😄"][max(0, min(4, score - 1))]
    }

    private func refresh() {
        Task { @MainActor in
            let s = await HealthService.shared.stepsToday()
            steps = s
        }
        let result = EnergyScore.today(ctx)
        todayEnergyScore = result?.score ?? todayEnergyScore
        todayEnergyLabel = result?.label ?? todayEnergyLabel
    }
}
