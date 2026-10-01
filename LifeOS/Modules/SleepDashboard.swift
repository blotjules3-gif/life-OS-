import SwiftUI
import SwiftData
import Charts
import CoreTransferable

// MARK: - Tableau de bord Sommeil (pro)

struct SleepDashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SleepNight.date, order: .reverse) private var nights: [SleepNight]
    @AppStorage(AppStorageKeys.sleepGoalHours) private var sleepGoal = 8.0
    @State private var showLog = false
    @State private var editing: SleepNight?

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
            Button { showLog = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }.accessibilityLabel("Ajouter")
        } }
        .sheet(isPresented: $showLog) { SleepLogSheet() }
        .sheet(item: $editing) { n in SleepLogSheet(editing: n) }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(tint)
                Text("Sommeil").nikeTitle()
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").foregroundStyle(Color.accentColor)
                Text("\(streak)").font(.headline.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 7).raisedSurface(Capsule())
        }
    }

    // MARK: Dernière nuit

    private func lastNightCard(_ n: SleepNight) -> some View {
        let frac = min(1, n.hours / max(1, sleepGoal))
        return HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: frac, lineWidth: 11, tint: tint)
                VStack(spacing: 0) {
                    Text(fmtH(n.hours)).font(AppFont.sans(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary)
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
                            .font(.footnote).foregroundStyle(s <= n.quality ? tint : Theme.textSecondary.opacity(0.4))
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
        // Une nuit non notee (0 h ici) n'est pas une nuit blanche: elle ne
        // compte plus comme 8 h de dette.
        let (debt, counted) = SleepDebt.compute(hours: last7.map { $0.hours > 0 ? $0.hours : nil }, goal: sleepGoal)
        let logged = last7.filter { $0.hours > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0.0) { $0 + $1.hours } / Double(logged.count)
        return HStack(spacing: 14) {
            stat(counted == 7 ? "Dette 7j" : "Dette · \(counted) nuit\(counted > 1 ? "s" : "")",
                 debt < 0.1 ? "à jour" : "-\(fmtH(debt))", debt > 3 ? Color(hex: 0xF0584B) : Theme.textPrimary)
            Divider().frame(height: 40)
            stat("Moyenne", avg > 0 ? fmtH(avg) : "-", Theme.textPrimary)
            Divider().frame(height: 40)
            stat("Objectif", fmtH(sleepGoal), tint)
        }
        .card(padding: 16)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(AppFont.sans(size: 19, weight: .bold)).foregroundStyle(color)
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
                .contentShape(Rectangle())
                // swipeActions ne marche que dans une List: ici la ligne
                // n'avait AUCUN moyen d'etre modifiee ou supprimee.
                .onTapGesture { editing = n }
                .contextMenu {
                    Button { editing = n } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) { SleepNightStore.delete(n, in: ctx) } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
        }.card()
    }

    private var logButton: some View {
        Button { showLog = true } label: {
            Text("Enregistrer une nuit").font(.system(size: 17, weight: .black)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .glassControl(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

/// Dette de sommeil sur les nuits NOTEES seulement. `nil` = nuit inconnue,
/// pas zero heure dormie.
enum SleepDebt {
    static func compute(hours: [Double?], goal: Double) -> (hours: Double, nights: Int) {
        let known = hours.compactMap { $0 }
        return (known.reduce(0.0) { $0 + max(0, goal - $1) }, known.count)
    }
}

// MARK: - Logique Sleep Circle (pure, testee dans Lot7SleepTests)

/// Reglages propres aux outils Sommeil. Hors AppStorageKeys (fichier d'un
/// autre lot); ces noms ne doivent plus changer, ils sont chez l'utilisateur.
enum SleepKeys {
    static let fallAsleepMinutes = "sleep.fallAsleepMinutes"
    static let napMinutes = "nap.minutes"
    static let napWakeSound = "nap.wakeSound"
    static let napSoundscape = "nap.soundscape"
    static let realityHours = "dream.realityHours"
    static let rizeWakeMinutes = "rize.wakeMinutes"
    static let rizeSeeded = "rize.checklistSeeded"
}

/// Cycles de 90 min + delai d'endormissement reglable (avant: 15 min en dur).
enum SleepCycles {
    static let cycleMinutes = 90
    static let latencyRange = 0...90
    static func clampLatency(_ m: Int) -> Int { min(latencyRange.upperBound, max(latencyRange.lowerBound, m)) }

    static func bedtime(wake: Date, cycles: Int, latencyMinutes: Int) -> Date {
        wake.addingTimeInterval(-TimeInterval((cycles * cycleMinutes + clampLatency(latencyMinutes)) * 60))
    }
    static func wakeTime(bedtime: Date, cycles: Int, latencyMinutes: Int) -> Date {
        bedtime.addingTimeInterval(TimeInterval((cycles * cycleMinutes + clampLatency(latencyMinutes)) * 60))
    }
}

/// Chronologie d'une nuit: coucher, endormissement, reveil.
enum SleepTimeline {
    struct Points: Equatable {
        let bed: Date
        let asleep: Date
        let wake: Date
        let awakeMinutes: Int
        var inBedHours: Double { wake.timeIntervalSince(bed) / 3600 }
        /// Sommeil = du moment endormi au reveil, moins les eveils connus.
        var asleepHours: Double { max(0, wake.timeIntervalSince(asleep) - Double(awakeMinutes) * 60) / 3600 }
        /// Position 0...1 de l'endormissement sur la barre.
        var asleepFraction: Double {
            let t = wake.timeIntervalSince(bed)
            return t > 0 ? asleep.timeIntervalSince(bed) / t : 0
        }
    }

    /// nil si le reveil ne suit pas le coucher: jamais de nuit inventee.
    static func points(bedtime: Date, wake: Date, latencyMinutes: Int, awakeMinutes: Int = 0) -> Points? {
        guard wake > bedtime else { return nil }
        let asleep = min(wake, bedtime.addingTimeInterval(TimeInterval(SleepCycles.clampLatency(latencyMinutes) * 60)))
        return Points(bed: bedtime, asleep: asleep, wake: wake, awakeMinutes: max(0, awakeMinutes))
    }
}

/// Saisie d'une nuit: heures d'horloge + jour du reveil -> vraies dates.
enum SleepLogRules {
    static func minutes(_ d: Date, cal: Calendar = .current) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    static func durationMinutes(bedMinutes: Int, wakeMinutes: Int) -> Int {
        let diff = wakeMinutes - bedMinutes
        return diff <= 0 ? diff + 1440 : diff
    }
    /// Le coucher tombe la veille quand il est apres l'heure du reveil (23:00 puis 07:00).
    /// Avant, le jour etait toujours "aujourd'hui": impossible de noter la nuit d'hier.
    static func dates(day: Date, bedMinutes: Int, wakeMinutes: Int, cal: Calendar = .current) -> (day: Date, bed: Date, wake: Date) {
        let start = cal.startOfDay(for: day)
        let wake = cal.date(byAdding: .minute, value: wakeMinutes, to: start) ?? start
        let bed = wake.addingTimeInterval(-TimeInterval(durationMinutes(bedMinutes: bedMinutes, wakeMinutes: wakeMinutes) * 60))
        return (start, bed, wake)
    }
    /// Nuit deja notee pour ce jour (hors celle qu'on modifie): elle est
    /// remplacee, sinon le tableau de bord comptait deux nuits le meme matin.
    static func conflict<ID: Equatable>(_ items: [(id: ID, day: Date)], day: Date, excluding: ID?, cal: Calendar = .current) -> ID? {
        items.first { $0.id != excluding && cal.isDate($0.day, inSameDayAs: day) }?.id
    }
}

/// Nuit lue dans Sante (API existante sleepBreakdownLastNight).
enum SleepHealthImport {
    /// Les deux heures doivent exister, se suivre et faire moins de 16 h.
    static func night(bedtime: Date?, wake: Date?) -> (bed: Date, wake: Date)? {
        guard let bedtime, let wake, wake > bedtime, wake.timeIntervalSince(bedtime) <= 16 * 3600 else { return nil }
        return (bedtime, wake)
    }
}

/// Tendance des nuits notees: une valeur par jour, jamais de jour invente.
enum SleepTrend {
    struct Point: Identifiable, Equatable {
        let day: Date
        let hours: Double
        let quality: Int
        var id: Date { day }
    }

    static func points(_ nights: [(date: Date, hours: Double, quality: Int)], days: Int,
                       now: Date = .now, cal: Calendar = .current) -> [Point] {
        let end = cal.startOfDay(for: now)
        guard days > 0, let start = cal.date(byAdding: .day, value: -(days - 1), to: end) else { return [] }
        var best: [Date: Point] = [:]
        for n in nights {
            let d = cal.startOfDay(for: n.date)
            guard d >= start, d <= end else { continue }
            // Deux saisies le meme jour: la plus longue, choix stable.
            if let cur = best[d], cur.hours >= n.hours { continue }
            best[d] = Point(day: d, hours: n.hours, quality: min(5, max(1, n.quality)))
        }
        return best.values.sorted { $0.day < $1.day }
    }

    static func averageQuality(_ p: [Point]) -> Double? {
        p.isEmpty ? nil : Double(p.reduce(0) { $0 + $1.quality }) / Double(p.count)
    }
}

/// Export CSV des nuits (separateur ";", lisible par Excel en francais).
enum SleepCSV {
    struct Row {
        let day: Date
        let bed: Date
        let asleep: Date
        let wake: Date
        let hours: Double
        let quality: Int
        let source: String
        let note: String
    }

    static let header = "date;coucher;endormissement;reveil;sommeil_h;qualite_sur_5;source;note"

    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f
    }

    static func decimal(_ v: Double) -> String {
        String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func make(_ rows: [Row]) -> String {
        let df = formatter("yyyy-MM-dd"), tf = formatter("HH:mm")
        let lines = rows.sorted { $0.day < $1.day }.map { r in
            [df.string(from: r.day), tf.string(from: r.bed), tf.string(from: r.asleep), tf.string(from: r.wake),
             decimal(r.hours), "\(r.quality)", field(r.source), field(r.note)].joined(separator: ";")
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }
}

/// Fichier CSV partage par ShareLink, ecrit dans tmp au moment du partage.
struct SleepCSVFile: Transferable {
    let name: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// Acces aux infos compagnon d'une nuit (SleepNightDetails).
enum SleepNightStore {
    static func details(for n: SleepNight, in all: [SleepNightDetails]) -> SleepNightDetails? {
        all.first { $0.night?.persistentModelID == n.persistentModelID }
    }
    static func fetchDetails(for n: SleepNight, in ctx: ModelContext) -> SleepNightDetails? {
        details(for: n, in: (try? ctx.fetch(FetchDescriptor<SleepNightDetails>())) ?? [])
    }
    /// Supprime la nuit ET ses infos: la relation a sens unique ne s'en charge pas.
    static func delete(_ n: SleepNight, in ctx: ModelContext) {
        if let d = fetchDetails(for: n, in: ctx) { ctx.delete(d) }
        ctx.delete(n)
    }
    static func points(for n: SleepNight, details d: SleepNightDetails?, defaultLatency: Int) -> SleepTimeline.Points? {
        SleepTimeline.points(bedtime: n.bedtime, wake: n.wake,
                             latencyMinutes: d?.latencyMinutes ?? defaultLatency,
                             awakeMinutes: d?.awakeMinutes ?? 0)
    }
    static func csvRows(_ nights: [SleepNight], details all: [SleepNightDetails], defaultLatency: Int) -> [SleepCSV.Row] {
        nights.map { n in
            let d = details(for: n, in: all)
            let p = points(for: n, details: d, defaultLatency: defaultLatency)
            return SleepCSV.Row(day: n.date, bed: n.bedtime, asleep: p?.asleep ?? n.bedtime, wake: n.wake,
                                hours: p?.asleepHours ?? n.hours, quality: n.quality,
                                source: d?.source == "sante" ? "Santé" : "manuel", note: n.note)
        }
    }
}

// MARK: - Barre de chronologie

struct SleepTimelineBar: View {
    let points: SleepTimeline.Points
    var tint: Color = .sleepTint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(tint.opacity(0.28)).frame(width: geo.size.width * CGFloat(points.asleepFraction))
                    Rectangle().fill(tint)
                }
                .clipShape(Capsule())
            }
            .frame(height: 18)
            HStack(alignment: .top) {
                mark("Coucher", points.bed, .leading)
                Spacer(minLength: 4)
                mark("Endormi", points.asleep, .center)
                Spacer(minLength: 4)
                mark("Réveil", points.wake, .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func mark(_ label: String, _ d: Date, _ align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 1) {
            Text(d.formatted(date: .omitted, time: .shortened)).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Enregistrer ou modifier une nuit

/// Nuit lue dans Sante, proposee avant d'entrer dans l'historique.
struct SleepLogPrefill: Identifiable {
    let id = UUID()
    var bed: Date
    var wake: Date
    var latency: Int
    var source: String
    var awakeMinutes: Int
}

struct SleepLogSheet: View {
    var editing: SleepNight? = nil
    var prefill: SleepLogPrefill? = nil

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allNights: [SleepNight]
    @AppStorage(SleepKeys.fallAsleepMinutes) private var defaultLatency = 15

    @State private var day = Date()
    @State private var bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var quality = 3
    @State private var note = ""
    @State private var latency = 15
    @State private var source = "manuel"
    @State private var awakeMinutes = 0
    @State private var loaded = false

    private let cal = Calendar.current
    private let tint = Color(hex: 0x6B7FD4)

    private var durationMin: Int {
        SleepLogRules.durationMinutes(bedMinutes: SleepLogRules.minutes(bedtime), wakeMinutes: SleepLogRules.minutes(wake))
    }
    private var durationStr: String { "\(durationMin / 60)h\(durationMin % 60 == 0 ? "" : String(format: "%02d", durationMin % 60))" }

    /// Nuit deja notee pour le jour choisi, hors celle qu'on modifie.
    private var replaced: SleepNight? {
        let items = allNights.map { (id: $0.persistentModelID, day: $0.date) }
        guard let id = SleepLogRules.conflict(items, day: day, excluding: editing?.persistentModelID) else { return nil }
        return allNights.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nuit") {
                    DatePicker("Jour du réveil", selection: $day, in: ...Date(), displayedComponents: .date)
                    DatePicker("Coucher", selection: $bedtime, displayedComponents: .hourAndMinute)
                    DatePicker("Réveil", selection: $wake, displayedComponents: .hourAndMinute)
                    HStack { Text("Au lit").foregroundStyle(.secondary); Spacer(); Text(durationStr).font(.body.weight(.bold)) }
                    Stepper("Endormissement : \(latency) min", value: $latency, in: SleepCycles.latencyRange, step: 5)
                    if source == "sante" {
                        Text("Heures lues dans Santé. Éveils pendant la nuit : \(awakeMinutes) min.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if replaced != nil {
                        Text("Une nuit est déjà notée pour ce jour : elle sera remplacée.")
                            .font(.caption).foregroundStyle(Theme.warning)
                    }
                }
                Section("Qualité") {
                    HStack {
                        Spacer()
                        ForEach(1...5, id: \.self) { s in
                            Button { quality = s; Haptics.tap() } label: {
                                Image(systemName: s <= quality ? "moon.fill" : "moon")
                                    .font(.title2).foregroundStyle(s <= quality ? tint : .secondary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Qualité \(s) sur 5")
                        }
                        Spacer()
                    }
                }
                Section("Note (optionnel)") {
                    TextField("Réveils, rêves, ressenti…", text: $note, axis: .vertical).lineLimit(1...4)
                }
                if let editing {
                    Section {
                        Button("Supprimer cette nuit", role: .destructive) {
                            SleepNightStore.delete(editing, in: ctx)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Enregistrer une nuit" : "Modifier la nuit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.bold()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let n = editing {
            day = n.date; bedtime = n.bedtime; wake = n.wake; quality = n.quality; note = n.note
            let d = SleepNightStore.fetchDetails(for: n, in: ctx)
            latency = d?.latencyMinutes ?? defaultLatency
            source = d?.source ?? "manuel"
            awakeMinutes = d?.awakeMinutes ?? 0
        } else if let p = prefill {
            day = cal.startOfDay(for: p.wake); bedtime = p.bed; wake = p.wake
            latency = p.latency; source = p.source; awakeMinutes = p.awakeMinutes
        } else {
            latency = defaultLatency
        }
    }

    private func save() {
        let r = SleepLogRules.dates(day: day, bedMinutes: SleepLogRules.minutes(bedtime), wakeMinutes: SleepLogRules.minutes(wake))
        let other = replaced
        let target: SleepNight
        if let n = editing ?? other {
            n.date = r.day; n.bedtime = r.bed; n.wake = r.wake; n.quality = quality; n.note = note
            target = n
            // Nuit modifiee deplacee sur un jour deja pris: l'autre disparait.
            if editing != nil, let other { SleepNightStore.delete(other, in: ctx) }
        } else {
            target = SleepNight(date: r.day, bedtime: r.bed, wake: r.wake, quality: quality, note: note)
            ctx.insert(target)
        }
        if let d = SleepNightStore.fetchDetails(for: target, in: ctx) {
            d.latencyMinutes = latency; d.source = source; d.awakeMinutes = awakeMinutes
        } else {
            ctx.insert(SleepNightDetails(night: target, latencyMinutes: latency, source: source, awakeMinutes: awakeMinutes))
        }
        Haptics.success(); dismiss()
    }
}

// MARK: - Sleep Circle (calcul + nuits + tendances)

struct BedtimeCalculatorView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SleepNight.date, order: .reverse) private var nights: [SleepNight]
    @Query private var allDetails: [SleepNightDetails]
    @AppStorage(SleepKeys.fallAsleepMinutes) private var latency = 15
    @State private var mode = 0            // 0 = je connais mon réveil, 1 = je me couche maintenant
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var health: HealthService.SleepBreakdown?
    @State private var healthState = HealthLoad.idle
    @State private var showLog = false
    @State private var prefill: SleepLogPrefill?
    @State private var editing: SleepNight?

    enum HealthLoad { case idle, loading, none, found }

    private var trend: [SleepTrend.Point] {
        SleepTrend.points(nights.map { n in
            let p = SleepNightStore.points(for: n, details: SleepNightStore.details(for: n, in: allDetails), defaultLatency: latency)
            return (n.date, p?.asleepHours ?? n.hours, n.quality)
        }, days: 30)
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    calculatorCard
                    healthCard
                    if let last = nights.first { lastNightCard(last) }
                    if !trend.isEmpty { trendCard }
                    historyCard
                    IntegrationNotice(text: "Le réveil « intelligent » qui sonne pendant ton sommeil léger demande une analyse des mouvements la nuit, que LifeOS ne fait pas encore. Ici on calcule la fenêtre idéale par cycles de 90 min.")
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Sleep Circle").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showLog = true } label: { Image(systemName: "plus") }.accessibilityLabel("Noter une nuit")
        } }
        .sheet(isPresented: $showLog) { SleepLogSheet() }
        .sheet(item: $prefill) { p in SleepLogSheet(prefill: p) }
        .sheet(item: $editing) { n in SleepLogSheet(editing: n) }
        .task {
            // Sante deja autorisee en contexte: lecture silencieuse. Sinon on
            // attend le geste de l'utilisateur pour ne pas surgir avec la feuille.
            if healthState == .idle, UserDefaults.standard.bool(forKey: "healthAuthRequested") { await loadHealth() }
        }
    }

    // MARK: Calcul

    private var calculatorCard: some View {
        VStack(spacing: 12) {
            Picker("", selection: $mode) {
                Text("Je veux me réveiller à…").tag(0)
                Text("Je me couche maintenant").tag(1)
            }
            .pickerStyle(.segmented)
            Stepper("Je m'endors en \(latency) min", value: $latency, in: SleepCycles.latencyRange, step: 5)
                .font(.subheadline)
            if mode == 0 {
                DatePicker("Heure de réveil", selection: $wake, displayedComponents: .hourAndMinute)
                    .adaptiveWheelDatePicker()
                    .labelsHidden()
                Text("Couche-toi à l'une de ces heures pour te réveiller en fin de cycle :")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                ForEach([6, 5, 4], id: \.self) { c in
                    cycleRow(time: SleepCycles.bedtime(wake: wake, cycles: c, latencyMinutes: latency), cycles: c)
                }
            } else {
                Text("Si tu te couches maintenant, vise un réveil à :")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                ForEach([6, 5, 4], id: \.self) { c in
                    cycleRow(time: SleepCycles.wakeTime(bedtime: .now, cycles: c, latencyMinutes: latency), cycles: c)
                }
            }
        }
        .card()
    }

    private func cycleRow(time: Date, cycles: Int) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(time, style: .time).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                Text("\(cycles) cycles · \(Double(cycles) * 1.5, specifier: "%.1f")h de sommeil")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if cycles == 5 {
                Text("Recommandé").font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.sleepTint.opacity(0.2), in: Capsule())
                    .foregroundStyle(Color.sleepTint)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Sante

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cette nuit dans Santé")
            switch healthState {
            case .idle:
                Text("Si ton Apple Watch ou une autre app suit ton sommeil, LifeOS peut lire la nuit dernière dans Santé.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                PrimaryButton(title: "Lire ma nuit dans Santé", icon: "heart.text.square", tint: .sleepTint) {
                    Task { await loadHealth() }
                }
            case .loading:
                ProgressView().tint(.sleepTint).frame(maxWidth: .infinity)
            case .none:
                Text("Aucune nuit trouvée dans Santé. Si tu n'as pas autorisé LifeOS : Réglages › Santé › Accès aux données › LifeOS. Sinon, note ta nuit à la main.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    PrimaryButton(title: "Noter à la main", icon: "square.and.pencil", tint: .sleepTint) { showLog = true }
                    PrimaryButton(title: "Réessayer", icon: "arrow.clockwise", tint: Theme.bg2) { Task { await loadHealth() } }
                }
            case .found:
                if let b = health, let n = SleepHealthImport.night(bedtime: b.bedtime, wake: b.wakeTime),
                   let p = SleepTimeline.points(bedtime: n.bed, wake: n.wake, latencyMinutes: 0, awakeMinutes: Int(b.awakeHours * 60)) {
                    SleepTimelineBar(points: p)
                    Text(healthLine(b, p)).font(.caption).foregroundStyle(Theme.textSecondary)
                    if alreadyLogged(n.wake) {
                        Label("Déjà dans ton historique", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.success)
                    } else {
                        PrimaryButton(title: "Ajouter à mon historique", icon: "plus", tint: .sleepTint) {
                            prefill = SleepLogPrefill(bed: n.bed, wake: n.wake, latency: 0, source: "sante",
                                                      awakeMinutes: Int((b.awakeHours * 60).rounded()))
                        }
                    }
                } else {
                    Text("Santé a des données cette nuit mais pas d'heure d'endormissement et de réveil exploitables.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .card()
    }

    private func healthLine(_ b: HealthService.SleepBreakdown, _ p: SleepTimeline.Points) -> String {
        var parts = ["Sommeil \(fmtH(p.asleepHours))"]
        if b.deepHours > 0 { parts.append("profond \(fmtH(b.deepHours))") }
        if b.remHours > 0 { parts.append("paradoxal \(fmtH(b.remHours))") }
        if b.awakenings > 0 { parts.append("\(b.awakenings) réveil\(b.awakenings > 1 ? "s" : "")") }
        return parts.joined(separator: " · ") + ". Phases mesurées par ta montre, pas par LifeOS."
    }

    private func alreadyLogged(_ wake: Date) -> Bool {
        nights.contains { Calendar.current.isDate($0.date, inSameDayAs: wake) }
    }

    private func loadHealth() async {
        healthState = .loading
        _ = await HealthService.shared.requestAuthorization()
        let b = await HealthService.shared.sleepBreakdownLastNight()
        health = b
        healthState = b == nil ? .none : .found
    }

    // MARK: Derniere nuit

    private func lastNightCard(_ n: SleepNight) -> some View {
        let d = SleepNightStore.details(for: n, in: allDetails)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: Calendar.current.isDateInToday(n.date) ? "Cette nuit" : "Dernière nuit notée",
                              subtitle: n.date.formatted(.dateTime.weekday(.wide).day().month()))
                Button { editing = n } label: { Image(systemName: "pencil") }.accessibilityLabel("Modifier la nuit")
            }
            if let p = SleepNightStore.points(for: n, details: d, defaultLatency: latency) {
                SleepTimelineBar(points: p)
                Text("Sommeil \(fmtH(p.asleepHours)) · au lit \(fmtH(p.inBedHours))\(d == nil ? " · endormissement estimé avec ton réglage (\(latency) min)" : "")")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { s in
                    Image(systemName: s <= n.quality ? "moon.fill" : "moon").font(.footnote)
                        .foregroundStyle(s <= n.quality ? Color.sleepTint : Theme.textSecondary.opacity(0.4))
                }
                if d?.source == "sante" { Text("· Santé").font(.caption2).foregroundStyle(Theme.textSecondary) }
            }
            if !n.note.isEmpty { Text(n.note).font(.subheadline).foregroundStyle(Theme.textPrimary.opacity(0.9)) }
        }
        .card()
    }

    // MARK: Tendances

    private var trendCard: some View {
        let pts = trend
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tendance 30 jours",
                          subtitle: "\(pts.count) nuit\(pts.count > 1 ? "s" : "") notée\(pts.count > 1 ? "s" : "")"
                          + (SleepTrend.averageQuality(pts).map { " · qualité moyenne \(String(format: "%.1f", $0))/5" } ?? ""))
            Chart(pts) { p in
                BarMark(x: .value("Nuit", p.day, unit: .day), y: .value("Heures", p.hours))
                    .foregroundStyle(Color.sleepTint)
            }
            .chartYAxisLabel("heures")
            .frame(height: 140)
            Chart(pts) { p in
                LineMark(x: .value("Nuit", p.day, unit: .day), y: .value("Qualité", p.quality))
                    .foregroundStyle(Theme.learning)
                PointMark(x: .value("Nuit", p.day, unit: .day), y: .value("Qualité", p.quality))
                    .foregroundStyle(Theme.learning)
            }
            .chartYScale(domain: 1...5)
            .chartYAxisLabel("qualité /5")
            .frame(height: 110)
        }
        .card()
    }

    // MARK: Historique

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Historique")
                if !nights.isEmpty {
                    ShareLink(item: SleepCSVFile(name: "LifeOS-nuits.csv",
                                                 text: SleepCSV.make(SleepNightStore.csvRows(nights, details: allDetails, defaultLatency: latency))),
                              preview: SharePreview("Nuits de sommeil (CSV)")) {
                        Label("Exporter", systemImage: "square.and.arrow.up").font(.subheadline)
                    }
                }
            }
            if nights.isEmpty {
                Text("Aucune nuit notée. Ajoute ta nuit chaque matin, ou importe-la depuis Santé.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                PrimaryButton(title: "Noter une nuit", icon: "plus", tint: .sleepTint) { showLog = true }
            }
            ForEach(nights.prefix(30)) { n in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(n.bedtime.formatted(date: .omitted, time: .shortened)) → \(n.wake.formatted(date: .omitted, time: .shortened)) · qualité \(n.quality)/5")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        if !n.note.isEmpty {
                            Text(n.note).font(.caption).foregroundStyle(Theme.textPrimary.opacity(0.8)).lineLimit(2)
                        }
                    }
                    Spacer()
                    Text(fmtH(n.hours)).font(.subheadline.bold()).foregroundStyle(Color.sleepTint)
                    Menu {
                        Button { editing = n } label: { Label("Modifier", systemImage: "pencil") }
                        Button(role: .destructive) { SleepNightStore.delete(n, in: ctx) } label: { Label("Supprimer", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Actions pour cette nuit")
                }
                .padding(.vertical, 4)
            }
        }
        .card()
    }

    private func fmtH(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60)h\(m % 60 == 0 ? "" : String(format: "%02d", m % 60))"
    }
}
