import SwiftUI
import SwiftData
import Charts
import UIKit

// MARK: - Bilan de semaine

struct WeeklyBilanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var waters: [WaterEntry]
    @Query private var foods: [FoodEntry]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]

    @State private var aiBilan: String?
    @State private var bilanLoading = false
    @State private var shareImage: UIImage?
    @AppStorage(AppStorageKeys.lastWeeklyBilanText) private var cachedBilan = ""
    @AppStorage(AppStorageKeys.lastWeeklyBilanDate) private var cachedBilanDate = 0.0

    private var activeHabits: [Habit] { habits.filter { !$0.isPending } }
    private var cal: Calendar { Calendar.current }

    private var weekDays: [Date] {
        (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now))! }
    }
    private func done(_ habit: Habit, on day: Date) -> Bool {
        habit.completions.contains { cal.isDate($0.date, inSameDayAs: day) }
    }
    private func ratio(for day: Date) -> Double {
        guard !activeHabits.isEmpty else { return 0 }
        return Double(activeHabits.filter { done($0, on: day) }.count) / Double(activeHabits.count)
    }
    private var weeklyScore: Double {
        guard !activeHabits.isEmpty else { return 0 }
        return weekDays.reduce(0.0) { $0 + ratio(for: $1) } / 7.0
    }
    private var perfectDays: Int { weekDays.filter { ratio(for: $0) >= 1 && !activeHabits.isEmpty }.count }
    private var avgWater: Int {
        // Divisé par 7 (semaine entière) — jours sans données comptent comme 0
        let total = weekDays.reduce(0) { acc, d in
            acc + waters.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.amountML }
        }
        return total / 7
    }
    private var avgKcal: Int {
        // Divisé par 7 (semaine entière) — jours sans données comptent comme 0
        let total = weekDays.reduce(0) { acc, d in
            acc + foods.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.calories }
        }
        return total / 7
    }
    private var avgMood: Double {
        let week = moods.filter { m in weekDays.contains { cal.isDate(m.date, inSameDayAs: $0) } }
        return week.isEmpty ? 0 : Double(week.reduce(0) { $0 + $1.score }) / Double(week.count)
    }
    private var weekMoods: [(Date, Int)] {
        weekDays.compactMap { day -> (Date, Int)? in
            guard let entry = moods.first(where: { cal.isDate($0.date, inSameDayAs: day) }) else { return nil }
            return (day, entry.score)
        }
    }
    private var scoreColor: Color {
        let p = Int(weeklyScore * 100)
        if p >= 80 { return Color(hex: 0x4CC38A) }
        if p >= 50 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0x9B6CF1)
    }
    private var message: String {
        let p = Int(weeklyScore * 100)
        switch p {
        case 90...100: return "Semaine exceptionnelle. Tu es en feu."
        case 70..<90:  return "Très bonne semaine. Continue sur cette lancée."
        case 50..<70:  return "Semaine correcte. Un peu plus de régularité et tu explooses."
        case 1..<50:   return "Semaine difficile. L'important c'est de repartir."
        default:       return "Semaine vierge. Tout commence maintenant."
        }
    }

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Score global
                    VStack(spacing: 6) {
                        Text("\(Int(weeklyScore * 100))%")
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .foregroundStyle(scoreColor)
                            .contentTransition(.numericText())
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Dots semaine
                    HStack(spacing: 14) {
                        ForEach(0..<7, id: \.self) { i in
                            let day = weekDays[i]
                            let r = ratio(for: day)
                            let isToday = cal.isDateInToday(day)
                            VStack(spacing: 6) {
                                Text(dayLetters[i])
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isToday ? Color.primary : Color.secondary)
                                Circle()
                                    .fill(r >= 1 ? Color(hex: 0x4CC38A) : (r > 0 ? Color(hex: 0xFF9F0A) : Color.secondary.opacity(0.2)))
                                    .frame(width: 12, height: 12)
                                    .overlay(isToday ? Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1.5) : nil)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                    // Bilan IA
                    aiBilanCard

                    // Stats rapides
                    if avgWater > 0 || avgKcal > 0 || avgMood > 0 {
                        HStack(spacing: 12) {
                            if avgWater > 0 { statPill("drop.fill", "\(avgWater) ml", Color(hex: 0x3CB2E0)) }
                            if avgKcal > 0  { statPill("flame.fill", "\(avgKcal) kcal", Color(hex: 0x4CC38A)) }
                            if avgMood > 0  { statPill("face.smiling", String(format: "%.1f/5", avgMood), Color(hex: 0x9B6CF1)) }
                        }
                    }

                    // Graphe humeur 7 jours
                    if !weekMoods.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("HUMEUR — 7 JOURS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                            Chart(weekMoods, id: \.0) { item in
                                LineMark(
                                    x: .value("Jour", item.0, unit: .day),
                                    y: .value("Humeur", item.1)
                                )
                                .foregroundStyle(Color(hex: 0x9B6CF1))
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Jour", item.0, unit: .day),
                                    y: .value("Humeur", item.1)
                                )
                                .foregroundStyle(Color(hex: 0x9B6CF1))
                                .symbolSize(40)
                            }
                            .frame(height: 100)
                            .chartYScale(domain: 1...5)
                            .chartYAxis {
                                AxisMarks(values: [1, 3, 5]) { v in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        let labels = ["😞", "😐", "😄"]
                                        let idx = min(v.index, labels.count - 1)
                                        Text(labels[idx]).font(.caption)
                                    }
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }

                    // Habitudes détaillées
                    if !activeHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("HABITUDES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            ForEach(Array(activeHabits.enumerated()), id: \.element.id) { idx, habit in
                                habitBilanRow(habit, isLast: idx == activeHabits.count - 1)
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }

                    if perfectDays > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xFF9F0A))
                            Text("\(perfectDays) jour\(perfectDays > 1 ? "s" : "") avec 100% des habitudes cette semaine")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFF9F0A).opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Bilan de semaine")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let ui = shareImage {
                        ShareLink(
                            item: Image(uiImage: ui),
                            preview: SharePreview("Mon bilan de semaine", image: Image(uiImage: ui))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .task {
                renderShareCard()
                await loadAIBilan()
            }
        }
    }

    // MARK: Partage

    private var shareDateRange: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM"
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(df.string(from: first)) — \(df.string(from: last))"
    }

    @MainActor
    private func renderShareCard() {
        let card = WeeklyShareCard(
            score: Int(weeklyScore * 100),
            dayRatios: weekDays.map { ratio(for: $0) },
            perfectDays: perfectDays,
            avgWater: avgWater,
            avgKcal: avgKcal,
            avgMood: avgMood,
            message: message,
            dateRange: shareDateRange
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    // MARK: Bilan IA

    private var aiBilanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Analyse du coach")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                Spacer()
                if bilanLoading { ProgressView().scaleEffect(0.7) }
            }
            if let text = aiBilan {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !bilanLoading && !cachedBilan.isEmpty {
                Text(cachedBilan)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !bilanLoading {
                Text("Connexion requise pour générer l'analyse.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private func loadAIBilan() async {
        // Use cache if generated today
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        if cachedBilanDate >= today && !cachedBilan.isEmpty {
            aiBilan = cachedBilan
            return
        }
        bilanLoading = true
        let habitNames = activeHabits.map { $0.name }.joined(separator: ", ")
        let prompt = """
        [BILAN_SEMAINE]
        Score habitudes: \(Int(weeklyScore * 100))%
        Jours parfaits: \(perfectDays)/7
        Habitudes: \(habitNames.isEmpty ? "aucune" : habitNames)
        Eau moy: \(avgWater) ml/j
        Calories moy: \(avgKcal) kcal/j
        Humeur moy: \(avgMood > 0 ? String(format: "%.1f/5", avgMood) : "non renseignée")
        Instruction: Fais un bilan de semaine motivant en 2-3 phrases. Sois direct, précis, encourage sans être artificiel.
        """
        let reply = await OnDeviceLLM.respond(to: prompt, ctx: ctx)
        aiBilan = reply.text
        cachedBilan = reply.text
        cachedBilanDate = today
        bilanLoading = false
    }

    private func statPill(_ icon: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func habitBilanRow(_ habit: Habit, isLast: Bool) -> some View {
        let count = weekDays.filter { done(habit, on: $0) }.count
        return HStack(spacing: 12) {
            Image(systemName: habit.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: UInt(habit.colorHex)))
                .frame(width: 30, height: 30)
                .background(Color(hex: UInt(habit.colorHex)).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(habit.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(done(habit, on: weekDays[i])
                              ? Color(hex: UInt(habit.colorHex))
                              : Color.secondary.opacity(0.15))
                        .frame(width: 8, height: 18)
                }
            }
            Text("\(count)/7")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(count >= 5 ? Color(hex: 0x4CC38A) : .secondary)
                .frame(width: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().padding(.leading, 58) }
        }
    }
}

// MARK: - Carte de partage du bilan (rendue en image, format story)

// Couleurs fixes (pas de tokens adaptatifs) : ImageRenderer rend hors écran,
// la carte doit être identique quel que soit le thème ou le mode clair/sombre.
private struct WeeklyShareCard: View {
    let score: Int
    let dayRatios: [Double]
    let perfectDays: Int
    let avgWater: Int
    let avgKcal: Int
    let avgMood: Double
    let message: String
    let dateRange: String

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private var scoreColor: Color {
        if score >= 80 { return Color(hex: 0x4CC38A) }
        if score >= 50 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0x9B6CF1)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("BILAN DE SEMAINE")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(2.5)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(dateRange)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.top, 52)

            Spacer()

            VStack(spacing: 14) {
                Text("\(score)%")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()

            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 8) {
                            Text(dayLetters[i])
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                            Circle()
                                .fill(dayRatios[i] >= 1 ? Color(hex: 0x4CC38A)
                                      : (dayRatios[i] > 0 ? Color(hex: 0xFF9F0A) : Color.white.opacity(0.12)))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 10) {
                    if perfectDays > 0 {
                        sharePill("star.fill", "\(perfectDays) jour\(perfectDays > 1 ? "s" : "") parfait\(perfectDays > 1 ? "s" : "")", Color(hex: 0xFF9F0A))
                    }
                    if avgWater > 0 { sharePill("drop.fill", "\(avgWater) ml/j", Color(hex: 0x3CB2E0)) }
                    if avgMood > 0 { sharePill("face.smiling", String(format: "%.1f/5", avgMood), Color(hex: 0x9B6CF1)) }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("LifeOS")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.bottom, 44)
        }
        .frame(width: 360, height: 640)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x0E1120), Color(hex: 0x1A1D33)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func sharePill(_ icon: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}
