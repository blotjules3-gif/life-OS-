import SwiftUI
import SwiftData

// MARK: - Routage « ajout rapide » vers le VRAI outil du pôle
// Chaque mention d'objectif (calories, protéines, eau…) ouvre l'outil dédié
// où l'on ajoute/ajuste vraiment cette donnée — pas un formulaire générique.

enum QuickTool: String, Identifiable {
    case calories, water, workout, habits, tasks, mood, sleep
    var id: String { rawValue }

    /// Depuis un libellé de métrique du score.
    static func from(metric label: String) -> QuickTool? {
        switch label {
        case "Calories", "Protéines": return .calories
        case "Eau":       return .water
        case "Activité":  return .workout
        case "Habitudes": return .habits
        case "Tâches":    return .tasks
        case "Humeur":    return .mood
        case "Sommeil":   return .sleep
        default:          return nil
        }
    }

    var destination: some View { toolView.floatingBarClearance() }

    @ViewBuilder private var toolView: some View {
        switch self {
        case .calories: CalAIView()
        case .water:    HydrationView()
        case .workout:  StrengthView()
        case .habits:   HabitTrackerView()
        case .tasks:    TodoView()
        case .mood:     MoodJournalView()
        case .sleep:    SleepDashboardView()
        }
    }
}

// MARK: - Métrique d'un objectif du jour

struct DayMetric: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let value: String
    let fraction: Double   // 0…1
    let color: Color
}

// MARK: - Modèle d'élément sur le cadran 24h

struct DailyClockItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let hour: Int
    let minute: Int
    let isHabit: Bool
    let isDone: Bool
    let isOverdue: Bool

    var timeFormatted: String {
        String(format: "%02dh%02d", hour, minute)
    }

    var angleDegrees: Double {
        let totalMinutes = Double(hour * 60 + minute)
        return (totalMinutes / 1440.0) * 360.0 - 90.0
    }
}

// MARK: - Moteur : calcule les objectifs d'un jour donné (aujourd'hui OU passé)

enum DailyScoreEngine {
    static func metrics(for day: Date,
                        foods: [FoodEntry], waters: [WaterEntry], habits: [Habit],
                        steps: [StepEntry], todos: [TodoItem], workouts: [WorkoutSet],
                        moods: [MoodEntry], dreams: [DreamEntry], nights: [SleepNight] = [],
                        kcalGoal: Int, proteinGoal: Int, waterGoal: Int, stepGoal: Int,
                        sleepGoalHours: Double = 8,
                        hiddenGoalIDs: Set<String> = []) -> [DayMetric] {
        let cal = Calendar.current
        func here(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: day) }
        if cal.startOfDay(for: day) > cal.startOfDay(for: .now) { return [] }  // futur

        var out: [DayMetric] = []
        let dayFoods = foods.filter { here($0.date) }

        if kcalGoal > 0 && !hiddenGoalIDs.contains("kcal") && !hiddenGoalIDs.contains("calories") {
            let k = dayFoods.reduce(0) { $0 + $1.calories }
            out.append(.init(label: "Calories", icon: "flame.fill", value: "\(k)/\(kcalGoal)",
                             fraction: min(1, Double(k) / Double(kcalGoal)), color: Color(hex: 0xF1746C)))
        }
        if proteinGoal > 0 && !hiddenGoalIDs.contains("protein") {
            let p = dayFoods.reduce(0.0) { $0 + $1.protein }
            out.append(.init(label: "Protéines", icon: "fork.knife", value: "\(Int(p))/\(proteinGoal) g",
                             fraction: min(1, p / Double(proteinGoal)), color: Color(hex: 0xE0A23C)))
        }
        if waterGoal > 0 && !hiddenGoalIDs.contains("water") && !hiddenGoalIDs.contains("glasses") {
            let w = waters.filter { here($0.date) }.reduce(0) { $0 + $1.amountML }
            out.append(.init(label: "Eau", icon: "drop.fill", value: "\(w)/\(waterGoal) ml",
                             fraction: min(1, Double(w) / Double(waterGoal)), color: Color(hex: 0x3CB2E0)))
        }
        if !hiddenGoalIDs.contains("steps") && !hiddenGoalIDs.contains("activity") {
            let sc = steps.filter { here($0.day) }.reduce(0) { $0 + $1.steps }
            let didW = workouts.contains { here($0.date) }
            let af = max(min(1, Double(sc) / Double(max(1, stepGoal))), didW ? 1 : 0)
            out.append(.init(label: "Activité", icon: "figure.walk",
                             value: didW ? "Séance" : "\(sc)/\(stepGoal) pas", fraction: af, color: Color(hex: 0x4CD07A)))
        }

        if !habits.isEmpty && !hiddenGoalIDs.contains("habits") {
            let d = habits.filter { h in h.completions.contains { here($0.date) } }.count
            out.append(.init(label: "Habitudes", icon: "checkmark.seal.fill", value: "\(d)/\(habits.count)",
                             fraction: Double(d) / Double(habits.count), color: Color(hex: 0x9B6CF1)))
        }
        if !hiddenGoalIDs.contains("todos") && !hiddenGoalIDs.contains("tasks") {
            let due = todos.filter { if let dd = $0.due { return here(dd) } else { return false } }
            if !due.isEmpty {
                let d = due.filter { $0.done }.count
                out.append(.init(label: "Tâches", icon: "checklist", value: "\(d)/\(due.count)",
                                 fraction: Double(d) / Double(due.count), color: Color(hex: 0x5B8DEF)))
            }
        }
        if !hiddenGoalIDs.contains("mood"), let m = moods.first(where: { here($0.date) }) {
            out.append(.init(label: "Humeur", icon: "face.smiling", value: "\(m.score)/5",
                             fraction: Double(m.score) / 5, color: Color(hex: 0xEC6FB0)))
        }
        if !hiddenGoalIDs.contains("sleep") {
            if let n = nights.first(where: { here($0.date) }) {
                let m = Int((n.hours * 60).rounded())
                out.append(.init(label: "Sommeil", icon: "moon.zzz.fill", value: "\(m / 60)h\(m % 60 == 0 ? "" : String(format: "%02d", m % 60))",
                                 fraction: min(1, n.hours / max(1, sleepGoalHours)), color: Color(hex: 0x7C93C8)))
            } else if let s = dreams.first(where: { here($0.date) }) {
                out.append(.init(label: "Sommeil", icon: "moon.zzz.fill", value: "\(s.mood)/5",
                                 fraction: Double(s.mood) / 5, color: Color(hex: 0x7C93C8)))
            }
        }
        return out
    }

    static func score(_ m: [DayMetric]) -> Int {
        guard !m.isEmpty else { return 0 }
        return Int((m.reduce(0) { $0 + $1.fraction } / Double(m.count) * 100).rounded())
    }
}

// MARK: - Hero : Double Cercle (Score + Cadran 24h Habitudes/Tâches)

struct DailyScoreRing: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var ctx
    @AppStorage(AppStorageKeys.kcalGoal) private var kcalGoal = 2200
    @AppStorage(AppStorageKeys.proteinGoal) private var proteinGoal = 0
    @AppStorage(AppStorageKeys.waterGoal) private var waterGoal = 2500
    @AppStorage(AppStorageKeys.stepGoal) private var stepGoal = 10000
    @AppStorage(AppStorageKeys.sleepGoalHours) private var sleepGoalHours = 8.0
    @AppStorage(AppStorageKeys.hiddenGoalIDsRaw) private var hiddenGoalIDsRaw = ""

    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var habits: [Habit]
    @Query private var steps: [StepEntry]
    @Query private var todos: [TodoItem]
    @Query private var workouts: [WorkoutSet]
    @Query private var moods: [MoodEntry]
    @Query private var dreams: [DreamEntry]
    @Query private var nights: [SleepNight]

    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var showDetail = false
    @State private var selectedClockItem: DailyClockItem?

    private var hiddenIDs: Set<String> {
        Set(hiddenGoalIDsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let wd = cal.component(.weekday, from: today)      // 1=dim … 7=sam
        let fromMonday = (wd + 5) % 7
        let monday = cal.date(byAdding: .day, value: -fromMonday, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private func metrics(_ day: Date) -> [DayMetric] {
        DailyScoreEngine.metrics(for: day, foods: foods, waters: waters, habits: habits,
                                 steps: steps, todos: todos, workouts: workouts, moods: moods, dreams: dreams, nights: nights,
                                 kcalGoal: kcalGoal, proteinGoal: proteinGoal, waterGoal: waterGoal, stepGoal: stepGoal,
                                 sleepGoalHours: sleepGoalHours, hiddenGoalIDs: hiddenIDs)
    }
    private func score(_ day: Date) -> Int { DailyScoreEngine.score(metrics(day)) }

    private func hasData(_ day: Date) -> Bool {
        let cal = Calendar.current
        func here(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: day) }
        return foods.contains { here($0.date) } || waters.contains { here($0.date) }
            || workouts.contains { here($0.date) } || moods.contains { here($0.date) }
            || dreams.contains { here($0.date) } || nights.contains { here($0.date) }
            || habits.contains { h in h.completions.contains { here($0.date) } }
            || todos.contains { if let d = $0.due { return here(d) && $0.done } else { return false } }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selected) }

    private var clockItems: [DailyClockItem] {
        let cal = Calendar.current
        var items: [DailyClockItem] = []

        // Habitudes actives
        for habit in habits.filter({ !$0.isPending && !$0.isArchived }) {
            let done = habit.completions.contains { cal.isDate($0.date, inSameDayAs: selected) }
            let isOverdue = !done && isToday && (cal.component(.hour, from: .now) > habit.scheduledHour || (cal.component(.hour, from: .now) == habit.scheduledHour && cal.component(.minute, from: .now) > habit.scheduledMinute))
            items.append(DailyClockItem(
                id: "habit-\(habit.persistentModelID)",
                title: habit.name,
                icon: habit.icon,
                color: Color(hex: UInt(habit.colorHex)),
                hour: habit.scheduledHour,
                minute: habit.scheduledMinute,
                isHabit: true,
                isDone: done,
                isOverdue: isOverdue
            ))
        }

        // Tâches avec heure fixée
        for todo in todos.filter({ $0.due != nil && $0.applies(to: selected) }) {
            guard let due = todo.due else { continue }
            let h = cal.component(.hour, from: due)
            let m = cal.component(.minute, from: due)
            items.append(DailyClockItem(
                id: "todo-\(todo.persistentModelID)",
                title: todo.title,
                icon: "checklist",
                color: todo.priority >= 2 ? Color.red : (todo.priority == 1 ? Color.orange : Color(hex: 0x5B8DEF)),
                hour: h,
                minute: m,
                isHabit: false,
                isDone: todo.done,
                isOverdue: todo.isOverdue && isToday
            ))
        }

        return items
    }

    var body: some View {
        VStack(spacing: 14) {
            doubleCircleHub
            streakPill
            weekStrip
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .sheet(isPresented: $showDetail) {
            DailyScoreDetailSheet(date: selected, metrics: metrics(selected), score: score(selected))
                .presentationDetents([.large])
        }
    }

    private var iridescent: AngularGradient {
        if scheme == .dark {
            return AngularGradient(
                colors: [Color.white, Color(white: 0.85), Color(white: 0.45), Color(white: 0.80), Color.white],
                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
        } else {
            return AngularGradient(
                colors: [Color.black, Color(white: 0.30), Color(white: 0.60), Color(white: 0.25), Color.black],
                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
        }
    }

    // MARK: - Double Cercle : Score (extérieur) + Cadran 24h Habitudes & Tâches (intérieur)

    private var doubleCircleHub: some View {
        let s = score(selected)
        let frac = Double(s) / 100
        let f = max(0.0001, frac)
        let done = metrics(selected).filter { $0.fraction >= 1 }.count
        let total = metrics(selected).count
        let items = clockItems

        return ZStack {
            // Halo diffus monochrome ambiant adaptatif
            Circle().fill(Color.primary)
                .frame(width: 290, height: 290).blur(radius: 40)
                .opacity((scheme == .dark ? 0.05 : 0.03) + 0.08 * frac)
                .animation(.easeOut(duration: 0.8), value: frac)

            // Piste score extérieure
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 8)
                .frame(width: 236, height: 236)

            // Arc de score monochrome extérieur
            Circle().trim(from: 0, to: f)
                .stroke(iridescent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 236, height: 236)
                .animation(.spring(response: 0.85, dampingFraction: 0.82), value: frac)

            // Anneau intérieur : Cadran 24h
            Circle()
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [2, 6]))
                .frame(width: 172, height: 172)

            // Repères 0h, 6h, 12h, 18h
            dialMarkers

            // Aiguille heure courante (si affichage d'aujourd'hui)
            if isToday {
                currentTimeNeedle
            }

            // Icônes des habitudes et tâches positionnées à leur heure
            ForEach(items) { item in
                clockItemBadge(item)
            }

            // Disque central interactif
            centerGlassDisc(s: s, done: done, total: total)
        }
        .frame(width: 260, height: 260)
    }

    private var dialMarkers: some View {
        Group {
            Text("0h").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).offset(y: -92)
            Text("6h").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).offset(x: 92)
            Text("12h").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).offset(y: 92)
            Text("18h").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).offset(x: -92)
        }
    }

    private var currentTimeNeedle: some View {
        let cal = Calendar.current
        let h = cal.component(.hour, from: .now)
        let m = cal.component(.minute, from: .now)
        let angle = (Double(h * 60 + m) / 1440.0) * 360.0 - 90.0
        let rad = angle * .pi / 180.0
        let x = 86.0 * cos(rad)
        let y = 86.0 * sin(rad)
        return Circle()
            .fill(Color.primary)
            .frame(width: 7, height: 7)
            .shadow(color: Color.primary.opacity(0.60), radius: 4)
            .offset(x: x, y: y)
    }

    private func clockItemBadge(_ item: DailyClockItem) -> some View {
        let rad = item.angleDegrees * .pi / 180.0
        let x = 86.0 * cos(rad)
        let y = 86.0 * sin(rad)
        let isSelected = selectedClockItem?.id == item.id
        let doneFill = Color.primary
        let undoneFill = scheme == .dark ? (isSelected ? Color.white.opacity(0.20) : Color.black.opacity(0.55)) : (isSelected ? Color.black.opacity(0.12) : Color.white.opacity(0.92))
        let strokeColor = isSelected ? Color.primary : Color.primary.opacity(0.35)
        let iconColor = item.isDone ? (scheme == .dark ? Color.black : Color.white) : Color.primary

        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                if selectedClockItem?.id == item.id {
                    selectedClockItem = nil
                } else {
                    selectedClockItem = item
                }
            }
            Haptics.soft()
        } label: {
            ZStack {
                Circle()
                    .fill(item.isDone ? doneFill : undoneFill)
                    .frame(width: isSelected ? 26 : 22, height: isSelected ? 26 : 22)
                    .overlay(Circle().stroke(strokeColor, lineWidth: isSelected ? 2 : 1.2))
                    .shadow(color: Color.primary.opacity(isSelected ? 0.35 : 0.1), radius: 3)

                Image(systemName: item.isDone ? "checkmark" : (item.isOverdue ? "exclamationmark" : item.icon))
                    .font(.system(size: isSelected ? 11 : 9, weight: .bold))
                    .foregroundStyle(iconColor)
            }
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
    }

    private func centerGlassDisc(s: Int, done: Int, total: Int) -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .frame(width: 124, height: 124)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            if let item = selectedClockItem {
                VStack(spacing: 3) {
                    Text(item.timeFormatted)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(item.isOverdue ? .red : item.color)

                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)

                    Button {
                        toggleClockItem(item)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            Text(item.isDone ? "Fait" : (item.isOverdue ? "En retard" : "Valider"))
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(item.isDone ? Color.green : Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            item.isDone ? Color.green.opacity(0.15) : (item.isOverdue ? Color.red.opacity(0.15) : Color.primary.opacity(0.08)),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    Haptics.tap()
                    showDetail = true
                } label: {
                    VStack(spacing: 1) {
                        Text(isToday ? "SCORE" : shortDate(selected).uppercased())
                            .font(.system(size: 10, weight: .semibold)).kerning(1.6)
                            .foregroundStyle(Theme.textSecondary)
                        Text("\(s)")
                            .font(.system(size: 42, weight: .black)).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text(total == 0 ? "%" : "\(done)/\(total) validés")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func toggleClockItem(_ item: DailyClockItem) {
        let cal = Calendar.current
        if item.isHabit {
            if let habit = habits.first(where: { "habit-\($0.persistentModelID)" == item.id }) {
                if let ex = habit.completions.first(where: { cal.isDate($0.date, inSameDayAs: selected) }) {
                    habit.completions.removeAll { $0.id == ex.id }
                    ctx.delete(ex)
                } else {
                    habit.completions.append(HabitCompletion(date: selected))
                }
                try? ctx.save()
                Haptics.success()
                withAnimation(.spring(duration: 0.25)) {
                    selectedClockItem = clockItems.first(where: { $0.id == item.id })
                }
            }
        } else {
            if let todo = todos.first(where: { "todo-\($0.persistentModelID)" == item.id }) {
                todo.done.toggle()
                try? ctx.save()
                Haptics.success()
                withAnimation(.spring(duration: 0.25)) {
                    selectedClockItem = clockItems.first(where: { $0.id == item.id })
                }
            }
        }
    }

    // Série : jours consécutifs (jusqu'à aujourd'hui) avec un score « bonne journée ».
    // La journée en cours ne casse pas la série tant qu'elle n'est pas finie.
    private func computeStreak(threshold: Int = 50) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if score(day) < threshold { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while score(day) >= threshold, n < 400 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    private var streakPill: some View {
        let n = computeStreak()
        let on = n > 0
        return HStack(spacing: 6) {
            Image(systemName: "flame.fill").font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? Color.primary : Color.secondary.opacity(0.60))
            Text(on ? "\(n) jour\(n > 1 ? "s" : "") de série" : "Démarre ta série aujourd'hui")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .liquidGlassPill()
    }

    // Bande des 7 jours de la semaine
    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                dayBubble(day, letter: dayLetters[idx])
            }
        }
        .padding(.horizontal, 4)
    }

    private func dayBubble(_ day: Date, letter: String) -> some View {
        let cal = Calendar.current
        let future = cal.startOfDay(for: day) > cal.startOfDay(for: .now)
        let isSel = cal.isDate(day, inSameDayAs: selected)
        let today = cal.isDateInToday(day)
        let m = metrics(day)
        let sc = DailyScoreEngine.score(m)
        let showScore = !future && (today || hasData(day))   // pas de « 0 » pour les jours non suivis
        return VStack(spacing: 6) {
            Button {
                Haptics.tap(); withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = day }
            } label: {
                ZStack {
                    // Pastilles de la semaine : elles peignaient un aplat
                    // `Color.primary.opacity(...)` avec un contour dessine a la main, donc
                    // elles n'avaient ni l'arete optique ni la matiere du reste de l'app.
                    // Le jour SELECTIONNE reste un aplat plein : c'est une couleur
                    // semantique, elle doit rester franche.
                    if isSel {
                        Circle().fill(Color.primary)
                    } else {
                        Circle().fill(.clear)
                            .glassControl(Circle())
                            .opacity(future ? 0.55 : 1.0)
                            .overlay(today ? Circle().strokeBorder(Color.primary, lineWidth: 1.5) : nil)
                    }
                    if showScore {
                        Text("\(sc)").font(.system(size: 13, weight: .black)).monospacedDigit()
                            .foregroundStyle(isSel ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
                    } else {
                        Image(systemName: "circle.dashed").font(.caption).foregroundStyle(Color.primary.opacity(0.35))
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            Text(letter).font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSel ? Color.primary : Color.secondary)
        }
    }

    private func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

// MARK: - Détail (au tap sur l'orbe) : tous les objectifs du jour

struct DailyScoreDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let metrics: [DayMetric]
    let score: Int
    @State private var showCustomizer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("\(score)%")
                        .font(.system(size: 54, weight: .black)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8)
                    if metrics.isEmpty {
                        Text("Aucun objectif actif pour ce jour.").font(.subheadline).foregroundStyle(.secondary).padding(.top, 40)
                    } else {
                        Text("Touche un objectif pour l'ouvrir")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                    ForEach(metrics) { m in
                        if let t = QuickTool.from(metric: m.label) {
                            NavigationLink { t.destination } label: { metricRow(m, tappable: true) }
                                .buttonStyle(.plain)
                        } else {
                            metricRow(m, tappable: false)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.screenBG)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCustomizer = true
                    } label: {
                        Label("Filtres", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Personnaliser les métriques suivies")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $showCustomizer) {
                MetricCustomizerSheet()
            }
        }
    }

    private func metricRow(_ m: DayMetric, tappable: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: m.icon).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(m.color).frame(width: 22)
                Text(m.label).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(m.value).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(m.fraction >= 1 ? Color.accentColor : Theme.textSecondary)
                if m.fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.system(size: 14))
                }
                if tappable {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                    Capsule().fill(m.fraction >= 1 ? Color.accentColor : m.color)
                        .frame(width: max(8, geo.size.width * m.fraction), height: 8)
                }
            }
            .frame(height: 8)
        }
        .card(padding: 14)
    }
}

// MARK: - Feuille de choix / désactivation des métriques suivies

struct MetricCustomizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.hiddenGoalIDsRaw) private var hiddenGoalIDsRaw = ""

    struct TrackableMetricItem: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
    }

    private let allTrackables: [TrackableMetricItem] = [
        .init(id: "steps",   title: "Pas & Activité",   icon: "figure.walk", color: Color(hex: 0x4CD07A)),
        .init(id: "water",   title: "Eau & Hydratation", icon: "drop.fill",   color: Color(hex: 0x3CB2E0)),
        .init(id: "kcal",    title: "Calories",          icon: "flame.fill",  color: Color(hex: 0xF1746C)),
        .init(id: "protein", title: "Protéines",         icon: "fork.knife",  color: Color(hex: 0xE0A23C)),
        .init(id: "habits",  title: "Habitudes du jour", icon: "checkmark.seal.fill", color: Color(hex: 0x9B6CF1)),
        .init(id: "todos",   title: "Tâches du jour",    icon: "checklist",   color: Color(hex: 0x5B8DEF)),
        .init(id: "sleep",   title: "Sommeil",           icon: "moon.zzz.fill", color: Color(hex: 0x7C93C8)),
        .init(id: "mood",    title: "Humeur",            icon: "face.smiling", color: Color(hex: 0xEC6FB0)),
    ]

    private var hiddenIDs: Set<String> {
        Set(hiddenGoalIDsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Décochez les métriques que vous ne souhaitez pas suivre. Elles seront exclues du calcul de votre score quotidien sans le pénaliser.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Métriques de la journée") {
                    ForEach(allTrackables) { item in
                        let isTracked = !hiddenIDs.contains(item.id)
                        Toggle(isOn: Binding(
                            get: { isTracked },
                            set: { enabled in
                                var next = hiddenIDs
                                if enabled { next.remove(item.id) } else { next.insert(item.id) }
                                hiddenGoalIDsRaw = next.joined(separator: ",")
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(item.color)
                                    .frame(width: 28, height: 28)
                                    .background(item.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(item.title)
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Personnaliser le suivi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminer") { dismiss() }
                }
            }
        }
    }
}
