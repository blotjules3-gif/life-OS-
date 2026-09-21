import SwiftUI
import SwiftData
import WatchKit

// MARK: - Aujourd'hui

struct TodayPage: View {
    @Query private var habits: [Habit]
    @Query private var waters: [WaterEntry]

    init() {
        // Seulement l'eau du jour: charger tout l'historique sur une montre
        // pour additionner la journee serait du gachis de batterie.
        let start = Calendar.current.startOfDay(for: .now)
        _waters = Query(filter: #Predicate<WaterEntry> { $0.date >= start })
    }

    private var active: [Habit] { habits.filter { !$0.isArchived && !$0.isPending } }
    private var done: Int { active.filter(WatchDay.isDoneToday).count }
    private var water: Int { waters.reduce(0) { $0 + $1.amountML } }

    var body: some View {
        VStack(spacing: 10) {
            Text("Aujourd'hui").font(.headline)
            Gauge(value: Double(done), in: 0...Double(max(1, active.count))) {
                EmptyView()
            } currentValueLabel: {
                Text("\(done)/\(active.count)")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.green)
            Text(active.isEmpty ? "Aucune habitude" : "habitudes faites")
                .font(.footnote).foregroundStyle(.secondary)
            Label("\(water) ml", systemImage: "drop.fill")
                .foregroundStyle(.cyan)
        }
    }
}

// MARK: - Habitudes

struct HabitsPage: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Habit.scheduledHour) private var habits: [Habit]
    private var active: [Habit] { habits.filter { !$0.isArchived && !$0.isPending } }

    var body: some View {
        List {
            if active.isEmpty {
                Text("Crée tes habitudes sur l'iPhone, elles arrivent ici.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(active) { h in
                Button { toggle(h) } label: {
                    HStack {
                        Image(systemName: WatchDay.isDoneToday(h) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(WatchDay.isDoneToday(h) ? .green : .secondary)
                        Text(h.name).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Habitudes")
    }

    /// Meme regle que l'iPhone: une habitude est faite aujourd'hui si elle a
    /// une coche datee d'aujourd'hui. Retoucher la retire.
    private func toggle(_ h: Habit) {
        if let c = h.completions.first(where: { Calendar.current.isDateInToday($0.date) }) {
            h.completions.removeAll { $0.persistentModelID == c.persistentModelID }
            ctx.delete(c)
        } else {
            h.completions.append(HabitCompletion(date: .now))
        }
        WatchDay.save(ctx)
    }
}

// MARK: - Eau

struct WaterPage: View {
    @Environment(\.modelContext) private var ctx
    @Query private var waters: [WaterEntry]

    /// L'objectif vit dans les reglages de l'iPhone, qui ne voyagent pas par
    /// iCloud. 2,5 L est la valeur par defaut de l'app.
    private let goal = 2500

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        _waters = Query(filter: #Predicate<WaterEntry> { $0.date >= start })
    }

    private var total: Int { waters.reduce(0) { $0 + $1.amountML } }

    var body: some View {
        VStack(spacing: 8) {
            Text("\(total) ml").font(.title2.bold())
            ProgressView(value: min(1, Double(total) / Double(goal))).tint(.cyan)
            HStack {
                add(250)
                add(500)
            }
        }
        .padding(.horizontal, 4)
    }

    private func add(_ ml: Int) -> some View {
        Button("+\(ml)") {
            ctx.insert(WaterEntry(date: .now, amountML: ml))
            WatchDay.save(ctx)
        }
        .tint(.cyan)
    }
}

// MARK: - Aides

enum WatchDay {
    static func isDoneToday(_ h: Habit) -> Bool {
        h.completions.contains { Calendar.current.isDateInToday($0.date) }
    }

    /// Enregistre et le dit au poignet: une vibration de reussite, ou d'echec
    /// si l'ecriture rate, plutot qu'un bouton qui semble marcher.
    static func save(_ ctx: ModelContext) {
        do {
            try ctx.save()
            WKInterfaceDevice.current().play(.success)
        } catch {
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
