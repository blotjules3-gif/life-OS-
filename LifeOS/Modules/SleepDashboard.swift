import SwiftUI
import SwiftData

// MARK: - Tableau de bord Sommeil (pro)

struct SleepDashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SleepNight.date, order: .reverse) private var nights: [SleepNight]
    @AppStorage("sleepGoalHours") private var sleepGoal = 8.0
    @State private var showLog = false

    private let cal = Calendar.current
    private let tint = Color(hex: 0x6B7FD4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let last = nights.first {
                    lastNightCard(last)
                    debtCard
                    chartCard
                } else {
                    EmptyState(icon: "moon.zzz.fill", title: "Aucune nuit enregistrée",
                               message: "Note ta nuit chaque matin pour suivre ta durée, ta dette de sommeil et ta régularité.")
                    logButton
                }
                cyclesLink
                if nights.count > 1 { recentList }
            }
            .padding(Theme.pad)
        }
        .background(Theme.bg)
        .navigationTitle("Sommeil").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showLog = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
        } }
        .sheet(isPresented: $showLog) { SleepLogSheet() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(tint)
                Text("Sommeil").nikeTitle()
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").foregroundStyle(Theme.volt)
                Text("\(streak)").font(.headline.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.cardFill, in: Capsule())
        }
    }

    // MARK: Dernière nuit

    private func lastNightCard(_ n: SleepNight) -> some View {
        let frac = min(1, n.hours / max(1, sleepGoal))
        return HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: frac, lineWidth: 11, tint: tint)
                VStack(spacing: 0) {
                    Text(fmtH(n.hours)).font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    Text("/ \(fmtH(sleepGoal))").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 8) {
                Text(cal.isDateInToday(n.date) ? "Cette nuit" : n.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.textSecondary)
                Text("\(n.bedtime.formatted(date: .omitted, time: .shortened)) → \(n.wake.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { s in
                        Image(systemName: s <= n.quality ? "moon.fill" : "moon")
                            .font(.system(size: 13)).foregroundStyle(s <= n.quality ? tint : Theme.textSecondary.opacity(0.4))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 18, radius: 26)
    }

    // MARK: Dette de sommeil (7 nuits)

    private var debtCard: some View {
        let last7 = nightsByDay(7)
        let debt = last7.reduce(0.0) { $0 + max(0, sleepGoal - $1.hours) }
        let logged = last7.filter { $0.hours > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0.0) { $0 + $1.hours } / Double(logged.count)
        return HStack(spacing: 14) {
            stat("Dette 7j", debt < 0.1 ? "à jour" : "-\(fmtH(debt))", debt > 3 ? Color(hex: 0xF0584B) : Theme.textPrimary)
            Divider().frame(height: 40)
            stat("Moyenne", avg > 0 ? fmtH(avg) : "—", Theme.textPrimary)
            Divider().frame(height: 40)
            stat("Objectif", fmtH(sleepGoal), tint)
        }
        .card(padding: 16)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 19, weight: .black, design: .rounded)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Chart 7 nuits

    private var chartCard: some View {
        let data = nightsByDay(7)
        let maxV = max(sleepGoal, data.map(\.hours).max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("7 dernières nuits").nikeTitle(20)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, e in
                    let good = e.hours >= sleepGoal * 0.9
                    VStack(spacing: 6) {
                        Text(e.hours > 0 ? fmtH(e.hours) : "")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(e.hours == 0 ? AnyShapeStyle(Color.primary.opacity(0.08))
                                              : AnyShapeStyle(good ? tint : Color(hex: 0xF2A03D)))
                            .frame(height: max(4, 92 * CGFloat(e.hours) / CGFloat(maxV)))
                        Text(dayLetter(e.day)).font(.system(size: 11, weight: .bold))
                            .foregroundStyle(cal.isDateInToday(e.day) ? Theme.textPrimary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 124, alignment: .bottom)
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("Objectif \(fmtH(sleepGoal))").font(.caption2).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var cyclesLink: some View {
        NavigationLink { BedtimeCalculatorView() } label: {
            HStack(spacing: 14) {
                IconBadge(icon: "bed.double.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heure de coucher optimale").font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text("Cycles de 90 min · réveil léger").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .card(padding: 14)
        }.buttonStyle(.plain)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historique").nikeTitle(20)
            ForEach(nights.prefix(10)) { n in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.date.formatted(.dateTime.weekday(.abbreviated).day().month())).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(n.bedtime.formatted(date: .omitted, time: .shortened)) → \(n.wake.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(fmtH(n.hours)).font(.subheadline.bold()).foregroundStyle(tint)
                }
                .padding(.vertical, 6)
                .swipeActions { Button(role: .destructive) { ctx.delete(n) } label: { Label("Suppr", systemImage: "trash") } }
            }
        }.card()
    }

    private var logButton: some View {
        Button { showLog = true } label: {
            Text("Enregistrer une nuit").font(.system(size: 17, weight: .black)).foregroundStyle(Theme.onVolt)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Theme.volt, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(PressableButtonStyle())
    }

    // MARK: Données

    /// Les 7 (ou n) derniers jours avec la nuit rattachée (0h si non renseignée).
    private func nightsByDay(_ n: Int) -> [(day: Date, hours: Double, quality: Int)] {
        (0..<n).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: cal.startOfDay(for: .now))!
            if let night = nights.first(where: { cal.isDate($0.date, inSameDayAs: d) }) {
                return (d, night.hours, night.quality)
            }
            return (d, 0, 0)
        }
    }

    private var streak: Int {
        var c = 0
        var day = cal.startOfDay(for: .now)
        let has: (Date) -> Bool = { d in nights.contains { cal.isDate($0.date, inSameDayAs: d) } }
        if !has(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while has(day) { c += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return c
    }

    private func fmtH(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60)h\(m % 60 == 0 ? "" : String(format: "%02d", m % 60))"
    }
    private func dayLetter(_ d: Date) -> String { ["D", "L", "M", "M", "J", "V", "S"][cal.component(.weekday, from: d) - 1] }
}

// MARK: - Enregistrer une nuit

struct SleepLogSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var quality = 3
    @State private var note = ""

    private let cal = Calendar.current
    private let tint = Color(hex: 0x6B7FD4)

    private func mins(_ d: Date) -> Int { let c = cal.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    private var durationMin: Int { let diff = mins(wake) - mins(bedtime); return diff <= 0 ? diff + 1440 : diff }
    private var durationStr: String { "\(durationMin / 60)h\(durationMin % 60 == 0 ? "" : String(format: "%02d", durationMin % 60))" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nuit") {
                    DatePicker("Coucher", selection: $bedtime, displayedComponents: .hourAndMinute)
                    DatePicker("Réveil", selection: $wake, displayedComponents: .hourAndMinute)
                    HStack { Text("Durée").foregroundStyle(.secondary); Spacer(); Text(durationStr).font(.body.weight(.bold)) }
                }
                Section("Qualité") {
                    HStack {
                        Spacer()
                        ForEach(1...5, id: \.self) { s in
                            Button { quality = s; Haptics.tap() } label: {
                                Image(systemName: s <= quality ? "moon.fill" : "moon")
                                    .font(.title2).foregroundStyle(s <= quality ? tint : .secondary.opacity(0.4))
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
                Section("Note (optionnel)") {
                    TextField("Réveils, rêves, ressenti…", text: $note, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("Enregistrer une nuit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.bold()
                }
            }
        }
    }

    private func save() {
        let today = cal.startOfDay(for: .now)
        let wakeDate = cal.date(byAdding: .minute, value: mins(wake), to: today)!
        let bedDate = cal.date(byAdding: .minute, value: -durationMin, to: wakeDate)!
        ctx.insert(SleepNight(date: today, bedtime: bedDate, wake: wakeDate, quality: quality, note: note))
        Haptics.success(); dismiss()
    }
}
