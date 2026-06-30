import SwiftUI
import SwiftData

/// Écran calories façon Cal AI : calories restantes + anneau, macros, bande de dates, streak, repas du jour.
struct CalAIView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]

    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 150
    @AppStorage("carbGoal") private var carbGoal = 250
    @AppStorage("fatGoal") private var fatGoal = 70

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showAdd = false

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dateStrip
                caloriesCard
                macrosRow
                mealsSection
            }
            .padding(Theme.pad)
        }
        .background(Theme.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
        } }
        .sheet(isPresented: $showAdd) { FoodEditor() }
        .task { syncNutritionToContext() }
        .onChange(of: foods.count) { _, _ in syncNutritionToContext() }
    }

    private func syncNutritionToContext() {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else { return }
        grp.set(totals.kcal, forKey: "today_kcal")
        grp.set(Int(totals.p), forKey: "today_protein_g")
    }

    // MARK: En-tête + streak

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "flame.circle.fill").font(.largeTitle).foregroundStyle(.orange)
                Text("Calories").font(.largeTitle.bold())
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(streak)").font(.headline.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.card, in: Capsule())
        }
    }

    // MARK: Bande de dates

    private var dateStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                let isSel = cal.isDate(day, inSameDayAs: selectedDay)
                let isFuture = day > cal.startOfDay(for: .now)
                Button { selectedDay = day } label: {
                    VStack(spacing: 6) {
                        Text(weekdayShort(day)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(isSel ? Color.primary : Color.clear)
                                .overlay(Circle().stroke(isSel ? Color.clear : Color.secondary.opacity(0.3),
                                                         style: StrokeStyle(lineWidth: 1.5, dash: isFuture ? [3] : [])))
                            Text("\(cal.component(.day, from: day))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSel ? Color(uiColor: .systemBackground) : (isFuture ? .secondary : .primary))
                        }
                        .frame(width: 38, height: 38)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
            }
        }
    }

    // MARK: Carte calories

    private var caloriesCard: some View {
        let consumed = totals.kcal
        let left = kcalGoal - consumed
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(left)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(left < 0 ? .red : .primary)
                    .contentTransition(.numericText())
                Text(left >= 0 ? "Calories restantes" : "Calories dépassées")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                ProgressRing(progress: kcalGoal == 0 ? 0 : Double(consumed) / Double(kcalGoal), lineWidth: 11, tint: .orange)
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(.orange)
            }
            .frame(width: 92, height: 92)
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: Macros

    private var macrosRow: some View {
        HStack(spacing: 12) {
            macroCard("Protéines", left: proteinGoal - Int(totals.p), goal: proteinGoal, value: Int(totals.p),
                      icon: "fork.knife", color: Color(hex: 0xF0584B))
            macroCard("Glucides", left: carbGoal - Int(totals.c), goal: carbGoal, value: Int(totals.c),
                      icon: "leaf.fill", color: Color(hex: 0xE0A23C))
            macroCard("Lipides", left: fatGoal - Int(totals.f), goal: fatGoal, value: Int(totals.f),
                      icon: "drop.fill", color: Color(hex: 0x4FA8E0))
        }
    }

    private func macroCard(_ label: String, left: Int, goal: Int, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(max(0, left))g").font(.title3.bold())
            Text("\(label) restant").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            ZStack {
                ProgressRing(progress: goal == 0 ? 0 : Double(value) / Double(goal), lineWidth: 7, tint: color)
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            .frame(width: 50, height: 50)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Repas du jour

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repas du jour").font(.title3.bold())
            if dayFoods.isEmpty {
                Button { showAdd = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Touche + pour ajouter ton premier repas").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }.buttonStyle(.plain)
            } else {
                ForEach(dayFoods) { f in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(f.name).font(.subheadline.weight(.semibold))
                            Text("\(f.meal) · P\(Int(f.protein)) G\(Int(f.carbs)) L\(Int(f.fat))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(f.calories) kcal").font(.subheadline.bold()).foregroundStyle(.orange)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contextMenu { Button(role: .destructive) { ctx.delete(f) } label: { Label("Supprimer", systemImage: "trash") } }
                }
            }
            IntegrationNotice(text: "Le « scan photo → calories » (le cœur de Cal AI) se branche ici : photo du plat → modèle de vision → kcal + macros pré-remplis dans un FoodEntry. Tout l'écran est déjà prêt à recevoir le résultat.")
        }
    }

    // MARK: Données

    private var dayFoods: [FoodEntry] { foods.filter { cal.isDate($0.date, inSameDayAs: selectedDay) } }
    private var totals: (kcal: Int, p: Double, c: Double, f: Double) {
        dayFoods.reduce((0, 0.0, 0.0, 0.0)) { ($0.0 + $1.calories, $0.1 + $1.protein, $0.2 + $1.carbs, $0.3 + $1.fat) }
    }
    private var weekDays: [Date] {
        (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0 + 1, to: cal.startOfDay(for: .now))! }
    }
    private var streak: Int {
        var c = 0
        var day = cal.startOfDay(for: .now)
        let hasFood: (Date) -> Bool = { d in foods.contains { cal.isDate($0.date, inSameDayAs: d) } }
        if !hasFood(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while hasFood(day) { c += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return c
    }
    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE"
        return String(f.string(from: d).prefix(3)).capitalized
    }
}
