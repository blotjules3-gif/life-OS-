import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Modèle cycle

@Model
final class CycleEntry {
    var date: Date
    var flow: Int        // 0 = aucun, 1 = léger, 2 = moyen, 3 = abondant
    var symptoms: [String]
    var mood: Int        // 0 = non renseigné, 1–5
    var note: String
    /// Intensites des symptomes, "Crampes=2" (1 léger, 2 moyen, 3 fort).
    /// Ajoute le 1er oct.: les anciennes entrees n'en ont pas, ce qui se lit
    /// "intensite non notee", jamais "léger".
    var intensityCodes: [String] = []
    /// Bornes explicites des regles. Sans elles, les regles se deduisent des
    /// jours de flux qui se suivent.
    var isPeriodStart: Bool = false
    var isPeriodEnd: Bool = false

    init(date: Date = .now, flow: Int = 1, symptoms: [String] = [], mood: Int = 0, note: String = "",
         intensityCodes: [String] = [], isPeriodStart: Bool = false, isPeriodEnd: Bool = false) {
        self.date = date
        self.flow = flow
        self.symptoms = symptoms
        self.mood = mood
        self.note = note
        self.intensityCodes = intensityCodes
        self.isPeriodStart = isPeriodStart
        self.isPeriodEnd = isPeriodEnd
    }
}

// MARK: - Hub Cycle


extension ShapeStyle where Self == Color { static var cycleTint: Color { AppCategory.cycle.tint } }

/// Jour ouvert dans l'editeur.
struct CycleEditTarget: Identifiable {
    let day: Date
    var presetStart = false
    var id: TimeInterval { day.timeIntervalSince1970 }
}

/// Recalcule le cycle partage depuis la base, apres une ecriture.
@MainActor
func refreshCycleContext(_ ctx: ModelContext) {
    let rows = (try? ctx.fetch(FetchDescriptor<CycleEntry>())) ?? []
    CycleContext.shared.refresh(entries: rows.map(\.snapshot))
}

enum CycleFormat {
    static func day(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }
    static func longDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
    }
    static func range(_ a: Date, _ b: Date) -> String {
        Calendar.current.isDate(a, inSameDayAs: b) ? "le \(day(a))" : "entre le \(day(a)) et le \(day(b))"
    }
    /// En mode contraception, on ne nomme pas l'ovulation.
    static func phaseLabel(_ p: CyclePhase, mode: CycleMode) -> String {
        (p == .ovulatory && !mode.showsOvulationPhase) ? "Milieu de cycle" : p.label
    }
}

// MARK: - Grille du mois

enum CycleCalendarGrid {
    /// Cases du mois, lundi en premier: `nil` pour les cases vides du debut.
    static func cells(month: Date, calendar: Calendar = .current) -> [Date?] {
        var cal = calendar
        cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = cal.component(.weekday, from: interval.start)   // 1 = dimanche
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }

    static let weekdays = ["L", "M", "M", "J", "V", "S", "D"]
}

struct CycleMonthCalendar: View {
    let entries: [CycleEntrySnapshot]
    let prediction: CyclePrediction?
    let mode: CycleMode
    let onSelect: (Date) -> Void

    @State private var month = Date()
    private let cal = Calendar.current

    private var byDay: [Date: CycleEntrySnapshot] {
        var out: [Date: CycleEntrySnapshot] = [:]
        for e in entries {
            let d = cal.startOfDay(for: e.date)
            if let cur = out[d] {
                var m = cur
                m.flow = max(m.flow, e.flow)
                m.symptoms += e.symptoms
                m.isStart = m.isStart || e.isStart
                m.isEnd = m.isEnd || e.isEnd
                if !e.note.isEmpty { m.note = e.note }
                out[d] = m
            } else { out[d] = e }
        }
        return out
    }

    private var predicted: (period: Set<Date>, fertile: Set<Date>) {
        prediction?.predictedDays(cycles: 4, calendar: cal) ?? ([], [])
    }

    private let flowColors: [Color] = [.clear, Color(hex: UInt(0xF9C0D8)), Color(hex: UInt(0xE85D9A)), Color(hex: UInt(0xB5136A))]

    var body: some View {
        let logged = byDay
        let pred = predicted
        let today = cal.startOfDay(for: .now)
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Mois précédent")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR"))).capitalized)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Mois suivant")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.cycle)

            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(CycleCalendarGrid.weekdays.enumerated()), id: \.offset) { _, w in
                    Text(w).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(CycleCalendarGrid.cells(month: month, calendar: cal).enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day, entry: logged[day], today: today,
                             predictedPeriod: pred.period.contains(day),
                             fertile: mode.showsFertileWindow && pred.fertile.contains(day))
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }

            // Legende: le prevu et le note ne se ressemblent jamais.
            HStack(spacing: 12) {
                legend(Circle().fill(flowColors[2]), "Règles notées")
                legend(Circle().strokeBorder(Theme.cycle, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])), "Prévues")
                if mode.showsFertileWindow {
                    legend(Circle().fill(Color.teal.opacity(0.25)), "Fertile estimée")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend<S: View>(_ shape: S, _ text: String) -> some View {
        HStack(spacing: 4) { shape.frame(width: 10, height: 10); Text(text) }
    }

    private func shift(_ months: Int) {
        if let m = cal.date(byAdding: .month, value: months, to: month) { month = m }
    }

    @ViewBuilder
    private func cell(_ day: Date, entry: CycleEntrySnapshot?, today: Date, predictedPeriod: Bool, fertile: Bool) -> some View {
        let isFuture = day > today
        let flow = entry?.flow ?? 0
        let bleeding = flow > 0 || (entry?.isStart ?? false) || (entry?.isEnd ?? false)
        Button {
            onSelect(day)
        } label: {
            ZStack {
                if bleeding {
                    Circle().fill(flow > 0 ? flowColors[flow] : flowColors[1])
                } else if predictedPeriod {
                    Circle().strokeBorder(Theme.cycle, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                } else if fertile {
                    Circle().fill(Color.teal.opacity(0.25))
                }
                if cal.isDate(day, inSameDayAs: today) {
                    Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                }
                VStack(spacing: 1) {
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 14, weight: bleeding ? .bold : .regular))
                        .foregroundStyle(bleeding && flow >= 2 ? Color.white : (isFuture ? Color.secondary : Color.primary))
                    if let e = entry, !e.symptoms.isEmpty || !e.note.isEmpty || e.mood > 0 {
                        Circle().fill(bleeding && flow >= 2 ? Color.white : Theme.cycle).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Un jour futur ne se note pas: on ne saisit pas des regles a venir.
        .disabled(isFuture)
        .accessibilityLabel(accessibility(day, entry: entry, predictedPeriod: predictedPeriod, fertile: fertile))
    }

    private func accessibility(_ day: Date, entry: CycleEntrySnapshot?, predictedPeriod: Bool, fertile: Bool) -> String {
        var parts = [CycleFormat.longDay(day)]
        if let e = entry {
            if e.flow > 0 { parts.append("flux \(CycleCatalog.flowLabel(e.flow).lowercased())") }
            if e.isStart { parts.append("premier jour des règles") }
            if e.isEnd { parts.append("dernier jour des règles") }
            if !e.symptoms.isEmpty { parts.append(e.symptoms.joined(separator: ", ")) }
        } else if predictedPeriod { parts.append("règles prévues") }
        else if fertile { parts.append("fenêtre fertile estimée") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Tracker principal

struct CycleTrackerView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CycleEntry.date, order: .reverse) private var entries: [CycleEntry]
    @ObservedObject private var cycle = CycleContext.shared

    @AppStorage(CycleKeys.mode) private var modeRaw = CycleMode.tracking.rawValue
    @State private var editing: CycleEditTarget?
    @State private var showSettings = false

    private var mode: CycleMode { CycleMode(rawValue: modeRaw) ?? .tracking }
    private var snapshots: [CycleEntrySnapshot] { entries.map(\.snapshot) }
    private var phaseColor: Color { Color(hex: UInt(cycle.currentPhase.colorHex)) }

    var body: some View {
        Group { // pas de NavigationStack: ces ecrans sont POUSSES dans celui de la categorie.
            // Un second NavigationStack imbrique faisait retomber sur la liste des
            // categories au toucher (telephone) et plantait au retour (SwiftUI,
            // NavigationColumnState.boundPathChange). Mesure le 28 septembre.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    if let p = cycle.prediction {
                        statusCard(p)
                    } else {
                        onboardingCard
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calendrier")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        CycleMonthCalendar(entries: snapshots, prediction: cycle.prediction, mode: mode) { day in
                            editing = CycleEditTarget(day: day)
                        }
                        Text("Touche un jour passé pour noter ou corriger le flux, les symptômes, l'humeur et une note.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .raisedSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if cycle.prediction != nil, !cycle.isLate {
                        phaseTips
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Theme.bg)
            .navigationTitle("Suivi du cycle")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages du cycle")
                }
            }
            .sheet(item: $editing) { target in
                CycleDayEditor(target: target) { refreshCycleContext(ctx) }
            }
            .sheet(isPresented: $showSettings, onDismiss: { refreshCycleContext(ctx) }) {
                CycleSettingsView()
            }
            .onAppear {
                // Le jour du cycle n'etait recalcule qu'a une action: rouvert
                // le lendemain, l'ecran gardait le jour d'hier.
                cycle.refresh(entries: snapshots)
            }
            .onChange(of: entries.count) { _, _ in cycle.refresh(entries: snapshots) }
        }
    }

    // MARK: Etat du cycle

    private func statusCard(_ p: CyclePrediction) -> some View {
        let len = max(p.lengthDays, cycle.dayOfCycle)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 1) {
                ForEach(0..<len, id: \.self) { i in
                    Capsule()
                        .fill(i < cycle.dayOfCycle ? (i >= p.lengthDays ? Theme.warning : phaseColor) : Color.primary.opacity(0.08))
                        .frame(height: 6)
                }
            }
            .animation(.spring(duration: 0.8), value: cycle.dayOfCycle)

            VStack(alignment: .leading, spacing: 4) {
                Text("Jour \(cycle.dayOfCycle)")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                Text(CycleFormat.phaseLabel(cycle.currentPhase, mode: mode))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(phaseColor)
                Text(periodLine)
                    .font(.caption)
                    .foregroundStyle(cycle.isLate ? Theme.warning : .secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let a = p.earliestStart, let b = p.latestStart {
                    Label("Prochaines règles \(CycleFormat.range(a, b))", systemImage: "calendar")
                        .font(.subheadline)
                }
                Label("Règles d'environ \(p.periodLengthDays) jour\(p.periodLengthDays > 1 ? "s" : "")"
                      + (p.periodLengthFromHistory ? " (ta moyenne)" : " (durée réglée)"),
                      systemImage: "drop")
                    .font(.subheadline)
                if mode.showsFertileWindow, let a = p.fertileStart, let b = p.fertileEnd {
                    Label("Fenêtre fertile estimée du \(CycleFormat.day(a)) au \(CycleFormat.day(b))", systemImage: "sparkles")
                        .font(.subheadline)
                    Text("Estimation d'après tes cycles, pas une ovulation confirmée.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(basisLine(p))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if mode == .contraception {
                    Text("Ces prévisions ne sont pas une méthode de contraception.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    editing = CycleEditTarget(day: Calendar.current.startOfDay(for: .now))
                } label: {
                    Text("Noter aujourd'hui")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    editing = CycleEditTarget(day: Calendar.current.startOfDay(for: .now), presetStart: true)
                } label: {
                    Text("Mes règles commencent")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.cycle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.cycle.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var onboardingCard: some View {
        VStack(spacing: 12) {
            Text("Quand ont commencé tes dernières règles ?")
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Button {
                editing = CycleEditTarget(day: Calendar.current.startOfDay(for: .now), presetStart: true)
            } label: {
                Text("Mes règles ont commencé aujourd'hui")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)
            Button {
                showSettings = true
            } label: {
                Text("Choisir une date")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.cycle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.cycle.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Tu peux aussi toucher un jour passé du calendrier pour noter tes règles.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var phaseTips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CycleFormat.phaseLabel(cycle.currentPhase, mode: mode).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(phaseColor)
                .kerning(1.2)
            Text(cycle.currentPhase.energyDescription)
                .font(.system(size: 13, weight: .medium))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { fitness; Divider(); nutrients }
                VStack(alignment: .leading, spacing: 10) { fitness; nutrients }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(phaseColor.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(phaseColor.opacity(0.25), lineWidth: 1))
    }

    private var fitness: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Fitness", systemImage: "figure.run").font(.caption.bold()).foregroundStyle(.secondary)
            Text(cycle.currentPhase.fitnessAdvice).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var nutrients: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Nutriments", systemImage: "leaf.fill").font(.caption.bold()).foregroundStyle(.secondary)
            Text(cycle.currentPhase.keyNutrients.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func basisLine(_ p: CyclePrediction) -> String {
        switch p.basis {
        case .history(let n):
            return "Calculé sur tes \(n) derniers cycles notés (\(p.shortestDays) à \(p.longestDays) jours, moyenne \(p.lengthDays))."
        case .setting:
            return "Calculé sur la durée réglée (\(p.lengthDays) jours), fourchette de \(CyclePrediction.defaultSpread) jours. Note au moins 2 cycles complets pour des prévisions à ta mesure."
        }
    }

    private var periodLine: String {
        if cycle.isLate {
            return cycle.lateDays == 0
                ? "Règles attendues aujourd'hui · note le flux quand elles arrivent"
                : "Règles attendues depuis \(cycle.lateDays) jour\(cycle.lateDays > 1 ? "s" : "") · note le flux ou corrige la date"
        }
        return "Règles dans \(cycle.daysUntilPeriod) jour\(cycle.daysUntilPeriod > 1 ? "s" : "") (estimation)"
    }
}

// MARK: - Editeur d'un jour

struct CycleDayEditor: View {
    let target: CycleEditTarget
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CycleKeys.mode) private var modeRaw = CycleMode.tracking.rawValue
    @AppStorage(CycleKeys.customTags) private var tagsRaw = "[]"
    @AppStorage(CycleKeys.showAllCategories) private var showAll = false

    @State private var draft = CycleDayDraft()
    @State private var hadEntry = false
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private var mode: CycleMode { CycleMode(rawValue: modeRaw) ?? .tracking }
    private var customTags: [String] { CycleTags.decode(tagsRaw) }

    /// Categories du mode, plus celles d'un symptome deja note (une donnee
    /// enregistree ne disparait pas parce qu'on a change d'objectif).
    private var categories: [CycleSymptomCategory] {
        let base = showAll ? CycleSymptomCategory.allCases.filter { $0 != .custom } : mode.categories
        let fromData = draft.symptoms.map(CycleSymptomCategory.of)
        return CycleSymptomCategory.allCases.filter { c in
            c != .custom && (base.contains(c) || fromData.contains(c))
        }
    }

    private var customOptions: [String] {
        let extra = draft.symptoms.filter { CycleSymptomCategory.of($0) == .custom && !customTags.contains($0) }.sorted()
        return customTags + extra
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    chips(CycleCatalog.flows, selected: { CycleCatalog.flows[draft.flow] == $0 }) { label in
                        if let i = CycleCatalog.flows.firstIndex(of: label) { draft.flow = i }
                    }
                    Toggle("Premier jour des règles", isOn: $draft.isStart)
                    Toggle("Dernier jour des règles", isOn: $draft.isEnd)
                } header: {
                    Text("Règles")
                } footer: {
                    Text("Sans ces repères, les règles se déduisent des jours de flux qui se suivent. Un saignement noté moins de 15 jours après le début des règles ne démarre pas un nouveau cycle, sauf si tu marques le premier jour.")
                }

                ForEach(categories) { cat in
                    Section(cat.label) { symptomRows(cat.options, category: cat) }
                }

                Section {
                    if customOptions.isEmpty {
                        Text("Aucun tag pour l'instant.").foregroundStyle(.secondary)
                    } else {
                        symptomRows(customOptions, category: .custom)
                    }
                    NavigationLink("Gérer mes tags") { CycleTagsView() }
                } header: {
                    Text(CycleSymptomCategory.custom.label)
                }

                Section("Humeur") {
                    chips(Array(CycleCatalog.moods.dropFirst()), selected: { CycleCatalog.moods[draft.mood] == $0 }) { label in
                        if let i = CycleCatalog.moods.firstIndex(of: label) { draft.mood = draft.mood == i ? 0 : i }
                    }
                }

                Section("Note") {
                    TextField("Ce que tu veux retenir de ce jour", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if hadEntry {
                    Section {
                        Button("Effacer ce jour", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(CycleFormat.longDay(target.day).capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .confirmationDialog("Effacer tout ce qui est noté ce jour ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { remove() }
            }
            .alert("Enregistrement impossible", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        do {
            let rows = try CycleEntryStore.entries(on: target.day, in: ctx)
            hadEntry = !rows.isEmpty
            draft = CycleDayDraft.merged(rows.map(\.snapshot))
        } catch {
            errorMessage = "Lecture du jour impossible : \(error.localizedDescription)"
        }
        if target.presetStart && !draft.isStart { draft.isStart = true }
    }

    private func save() {
        do {
            try CycleEntryStore.save(draft, for: target.day, in: ctx)
            Haptics.tap()
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Tes changements n'ont pas été enregistrés : \(error.localizedDescription)"
        }
    }

    private func remove() {
        do {
            try CycleEntryStore.delete(day: target.day, in: ctx)
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Suppression impossible : \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func symptomRows(_ options: [String], category: CycleSymptomCategory) -> some View {
        chips(options, selected: { draft.symptoms.contains($0) }) { s in
            withAnimation(.spring(duration: 0.2)) { draft.toggle(s) }
        }
        if category.hasIntensity {
            ForEach(options.filter { draft.symptoms.contains($0) }, id: \.self) { s in
                Picker(s, selection: Binding(get: { draft.levels[s] ?? 0 },
                                             set: { draft.levels[s] = $0 == 0 ? nil : $0 })) {
                    Text("Non précisé").tag(0)
                    ForEach(1...3, id: \.self) { Text(CycleIntensity.label($0)).tag($0) }
                }
            }
        }
    }

    private func chips(_ options: [String], selected: @escaping (String) -> Bool,
                       tap: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { o in
                let on = selected(o)
                Button {
                    tap(o)
                    Haptics.tap()
                } label: {
                    Text(o)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(on ? Theme.onAccent : .primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.horizontal, 6)
                        .background(on ? Color.accentColor : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reglages

struct CycleSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CycleKeys.manualStart) private var manualTS: Double = 0
    @AppStorage(AppStorageKeys.cycleLengthDays) private var cycleLengthDays = 28
    @AppStorage(CycleKeys.periodLength) private var periodLength = 5
    @AppStorage(CycleKeys.mode) private var modeRaw = CycleMode.tracking.rawValue
    @AppStorage(CycleKeys.remindersOff) private var remindersOff = ""
    @AppStorage(CycleKeys.showAllCategories) private var showAll = false

    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private var mode: CycleMode { CycleMode(rawValue: modeRaw) ?? .tracking }

    private var manualDate: Binding<Date> {
        Binding(get: { manualTS > 0 ? Date(timeIntervalSince1970: manualTS) : Calendar.current.startOfDay(for: .now) },
                set: { manualTS = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Début des dernières règles", selection: manualDate, in: ...Date(), displayedComponents: .date)
                        .tint(Theme.cycle)
                } header: {
                    Text("Dernières règles")
                } footer: {
                    Text("Si tu notes des règles plus récentes dans le calendrier, elles passent avant cette date.")
                }

                Section {
                    Stepper("Durée du cycle : \(cycleLengthDays) jours", value: $cycleLengthDays, in: 21...45)
                    Stepper("Durée des règles : \(periodLength) jours", value: $periodLength, in: 2...10)
                } header: {
                    Text("Durées par défaut")
                } footer: {
                    Text("Utilisées tant que moins de 2 cycles complets sont notés. Ensuite, les prévisions suivent ta moyenne.")
                }

                Section {
                    Picker("Objectif", selection: $modeRaw) {
                        ForEach(CycleMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Objectif")
                } footer: {
                    Text(mode.explanation)
                }

                Section {
                    ForEach(CycleReminderKind.allCases.filter { $0.isAvailable(in: mode) }) { kind in
                        Toggle(kind.label(mode: mode), isOn: reminderBinding(kind))
                    }
                    if authStatus == .denied {
                        Text("Les notifications sont refusées pour LifeOS. Les rappels ne peuvent pas s'afficher.")
                            .font(.footnote).foregroundStyle(Theme.warning)
                        Button("Ouvrir les Réglages") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                    }
                } header: {
                    Text("Rappels")
                } footer: {
                    Text("Calculés sur tes prévisions. Rien n'est envoyé quand tes règles sont en retard.")
                }

                Section {
                    Toggle("Afficher toutes les catégories", isOn: $showAll)
                    NavigationLink("Mes tags") { CycleTagsView() }
                } header: {
                    Text("Saisie")
                } footer: {
                    Text("Par défaut, seules les catégories utiles à ton objectif sont proposées.")
                }
            }
            .navigationTitle("Réglages du cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task { await readAuth() }
        }
    }

    private func reminderBinding(_ kind: CycleReminderKind) -> Binding<Bool> {
        Binding(get: { !CycleReminderKind.disabled(defaultsFrom: remindersOff).contains(kind) },
                set: { on in
                    var off = CycleReminderKind.disabled(defaultsFrom: remindersOff)
                    if on { off.remove(kind) } else { off.insert(kind) }
                    remindersOff = off.map(\.rawValue).sorted().joined(separator: ",")
                    if on { Task { await askIfNeeded() } }
                })
    }

    private func readAuth() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// La permission est demandee quand on active un rappel, pas avant.
    private func askIfNeeded() async {
        await readAuth()
        if authStatus == .notDetermined {
            _ = await NotificationManager.shared.requestAuthorization()
            await readAuth()
        }
    }
}

extension CycleReminderKind {
    static func disabled(defaultsFrom raw: String) -> Set<CycleReminderKind> {
        Set(raw.split(separator: ",").compactMap { CycleReminderKind(rawValue: String($0)) })
    }
}

// MARK: - Tags personnels

struct CycleTagsView: View {
    @AppStorage(CycleKeys.customTags) private var tagsRaw = "[]"
    @State private var newTag = ""
    @State private var error: String?

    private var tags: [String] { CycleTags.decode(tagsRaw) }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nouveau tag", text: $newTag)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Ajouter", action: add)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            } footer: {
                Text("Un tag supprimé reste visible sur les jours où tu l'as déjà noté.")
            }
            Section("Mes tags") {
                if tags.isEmpty {
                    Text("Aucun tag.").foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.self) { Text($0) }
                        .onDelete { idx in
                            var t = tags
                            t.remove(atOffsets: idx)
                            tagsRaw = CycleTags.encode(t)
                        }
                }
            }
        }
        .navigationTitle("Mes tags")
    }

    private func add() {
        switch CycleTags.adding(newTag, to: tags) {
        case .success(let t):
            tagsRaw = CycleTags.encode(t); newTag = ""; error = nil
        case .failure(.empty): error = nil
        case .failure(.tooLong): error = "40 caractères au plus."
        case .failure(.duplicate): error = "Ce tag existe déjà."
        }
    }
}

// MARK: - Symptômes (vue dédiée)

struct CycleSymptomsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CycleEntry.date, order: .reverse) private var entries: [CycleEntry]
    @ObservedObject private var cycle = CycleContext.shared
    @State private var search = ""
    @State private var editing: CycleEditTarget?

    private var snapshots: [CycleEntrySnapshot] { entries.map(\.snapshot) }

    private var recentSymptoms: [(String, Int)] {
        CycleMath.recentSymptomCounts(entries.map { (date: $0.date, symptoms: $0.symptoms) })
    }

    private var associations: [CycleAssociation] {
        let starts = CycleStats.episodes(snapshots.map(\.mark)).map(\.start)
        return CycleInsights.phaseAssociations(snapshots, starts: starts, fallbackLength: cycle.predictionLength)
    }

    private var results: [CycleEntrySnapshot] {
        snapshots.filter { CycleInsights.matches($0, query: search) }
    }

    var body: some View {
        Group { // pas de NavigationStack: ces ecrans sont POUSSES dans celui de la categorie.
            // Un second NavigationStack imbrique faisait retomber sur la liste des
            // categories au toucher (telephone) et plantait au retour (SwiftUI,
            // NavigationColumnState.boundPathChange). Mesure le 28 septembre.
            List {
                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("\(results.count) résultat\(results.count > 1 ? "s" : "")") {
                        if results.isEmpty {
                            Text("Aucune entrée ne correspond.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(results.enumerated()), id: \.offset) { _, e in
                            CycleEntryRow(entry: e) { editing = CycleEditTarget(day: e.date) }
                        }
                    }
                } else {
                    Section("3 derniers jours") {
                        if recentSymptoms.isEmpty {
                            Text("Aucun symptôme noté ces 3 derniers jours.").foregroundStyle(.secondary)
                        }
                        ForEach(recentSymptoms, id: \.0) { s, count in
                            HStack {
                                Text(s)
                                Spacer()
                                Text("\(count)×").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        if associations.isEmpty {
                            Text("Note des symptômes sur au moins 3 jours, avec tes règles, pour voir à quelle phase ils reviennent.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(associations, id: \.symptom) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.symptom)
                                Text("Noté \(a.count) fois sur \(a.total) en phase \(CycleFormat.phaseLabel(a.phase, mode: CycleMode.stored()).lowercased())")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Symptômes et phases")
                    } footer: {
                        Text("Associations observées dans tes entrées, pas des causes. Les phases n'ont pas la même durée : la phase lutéale est la plus longue.")
                    }

                    Section {
                        NavigationLink("Mes tags") { CycleTagsView() }
                    }
                }
            }
            .searchable(text: $search, prompt: "Symptôme, note, mois")
            .navigationTitle("Symptômes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = CycleEditTarget(day: Calendar.current.startOfDay(for: .now)) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Noter aujourd'hui")
                }
            }
            .sheet(item: $editing) { t in CycleDayEditor(target: t) { refreshCycleContext(ctx) } }
            .onAppear { cycle.refresh(entries: snapshots) }
        }
    }
}

/// Ligne d'entree: date, flux, symptomes avec intensite, note.
struct CycleEntryRow: View {
    let entry: CycleEntrySnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.flow > 0 ? "drop.fill" : "circle")
                    .foregroundStyle(Theme.cycle.opacity(entry.flow > 0 ? 0.5 + Double(entry.flow) * 0.15 : 0.3))
                    .font(.footnote)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(CycleFormat.longDay(entry.date).capitalized).font(.subheadline)
                        if entry.isStart { Text("début").font(.caption2).foregroundStyle(Theme.cycle) }
                        if entry.isEnd { Text("fin").font(.caption2).foregroundStyle(Theme.cycle) }
                    }
                    if !entry.symptoms.isEmpty {
                        Text(entry.symptoms.sorted().map { s in
                            let l = CycleIntensity.label(entry.levels[s] ?? 0)
                            return l.isEmpty ? s : "\(s) (\(l.lowercased()))"
                        }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.mood > 0 {
                        Text("Humeur : \(CycleCatalog.moodLabel(entry.mood))").font(.caption).foregroundStyle(.secondary)
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Historique

/// Fichier CSV partage: cree au moment du partage, pas a l'affichage.
struct CycleCSVFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cycle-lifeos.csv")
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct CycleHistoryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CycleEntry.date, order: .reverse) private var entries: [CycleEntry]
    @ObservedObject private var cycle = CycleContext.shared
    @AppStorage(CycleKeys.manualStart) private var manualTS: Double = 0
    @AppStorage(AppStorageKeys.cycleLengthDays) private var cycleLengthDays = 28
    @AppStorage(CycleKeys.periodLength) private var periodLength = 5

    @State private var range: CycleRange = .sixMonths
    @State private var editing: CycleEditTarget?
    @State private var deleteError: String?

    private var snapshots: [CycleEntrySnapshot] { entries.map(\.snapshot) }

    /// Meme fonction que le suivi et le coach (CycleAnalytics.analyze).
    private var analysis: CycleAnalysis {
        CycleAnalytics.analyze(entries: snapshots,
                               manualStart: manualTS > 0 ? Date(timeIntervalSince1970: manualTS) : nil,
                               setLength: cycleLengthDays, setPeriodLength: periodLength, range: range)
    }

    private var rangeEntries: [CycleEntrySnapshot] {
        guard let from = range.start() else { return snapshots }
        return snapshots.filter { $0.date >= from }
    }

    var body: some View {
        let a = analysis
        let inRange = rangeEntries
        Group { // pas de NavigationStack: ces ecrans sont POUSSES dans celui de la categorie.
            // Un second NavigationStack imbrique faisait retomber sur la liste des
            // categories au toucher (telephone) et plantait au retour (SwiftUI,
            // NavigationColumnState.boundPathChange). Mesure le 28 septembre.
            List {
                Section {
                    Picker("Période", selection: $range) {
                        ForEach(CycleRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                predictionSection(a.prediction)
                rangeSection(a)

                if !a.distribution.isEmpty {
                    Section {
                        Chart(a.distribution) { bin in
                            BarMark(x: .value("Durée (jours)", "\(bin.days)"), y: .value("Cycles", bin.count))
                                .foregroundStyle(Theme.cycle.gradient)
                        }
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                        .frame(height: 160)
                        .accessibilityLabel("Répartition des durées de cycle")
                    } header: {
                        Text("Durées de cycle")
                    } footer: {
                        Text("Nombre de cycles par durée, sur la période.")
                    }

                    Section("Cycles") {
                        ForEach(a.rangeCycles.reversed(), id: \.start) { c in
                            HStack {
                                Text(CycleFormat.day(c.start))
                                Spacer()
                                Text("\(c.days) j").monospacedDigit()
                                if let p = c.periodDays {
                                    Text("· règles \(p) j").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                trendSection(inRange)

                Section("Entrées (\(inRange.count))") {
                    if inRange.isEmpty {
                        Text("Aucune entrée sur cette période.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(inRange.prefix(200).enumerated()), id: \.offset) { _, e in
                            CycleEntryRow(entry: e) { editing = CycleEditTarget(day: e.date) }
                                .swipeActions {
                                    Button("Supprimer", role: .destructive) { delete(e.date) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: CycleReport.text(analysis: a, rangeLabel: range.label, entries: inRange),
                                  preview: SharePreview("Rapport de cycle")) {
                            Label("Rapport (texte)", systemImage: "doc.text")
                        }
                        ShareLink(item: CycleCSVFile(text: CycleReport.csv(inRange)),
                                  preview: SharePreview("Entrées du cycle (CSV)")) {
                            Label("Entrées (CSV)", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Exporter")
                }
            }
            .sheet(item: $editing) { t in CycleDayEditor(target: t) { refreshCycleContext(ctx) } }
            .alert("Suppression impossible", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleteError ?? "") }
            .onAppear { cycle.refresh(entries: snapshots) }
        }
    }

    private func delete(_ day: Date) {
        do {
            try CycleEntryStore.delete(day: day, in: ctx)
            refreshCycleContext(ctx)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // Les memes chiffres que l'ecran de suivi, dits avec les memes mots.
    private func predictionSection(_ p: CyclePrediction) -> some View {
        Section {
            row("Durée utilisée pour les prévisions", "\(p.lengthDays) jours")
            if let a = p.earliestStart, let b = p.latestStart {
                row("Prochaines règles", a == b ? CycleFormat.day(a) : "\(CycleFormat.day(a)) au \(CycleFormat.day(b))")
            }
            row("Durée des règles", "\(p.periodLengthDays) jours")
        } header: {
            Text("Prévisions")
        } footer: {
            switch p.basis {
            case .history(let n):
                Text("Moyenne de tes \(n) derniers cycles notés, fourchette entre le plus court (\(p.shortestDays) j) et le plus long (\(p.longestDays) j).")
            case .setting:
                Text("Durée réglée tant que moins de 2 cycles complets sont notés, fourchette de \(CyclePrediction.defaultSpread) jours.")
            }
        }
    }

    @ViewBuilder
    private func rangeSection(_ a: CycleAnalysis) -> some View {
        Section {
            if let s = a.rangeSummary {
                row("Durée moyenne", "\(Int(s.averageDays.rounded())) jours")
                row("Plus court · plus long", "\(s.shortestDays) · \(s.longestDays) jours")
                HStack {
                    Text("Régularité")
                    Spacer()
                    Text(s.isRegular ? "Régulier" : "Irrégulier")
                        .foregroundStyle(s.isRegular ? Theme.success : Theme.warning)
                }
            } else {
                Text("Pas encore de cycle complet sur cette période : il faut deux débuts de règles notés.")
                    .foregroundStyle(.secondary)
            }
            if let p = a.rangePeriodAverage {
                row("Durée moyenne des règles", "\(Int(p.rounded())) jours")
            }
        } header: {
            Text("Sur \(range == .all ? "tout l'historique" : "les " + range.label)")
        } footer: {
            if let s = a.rangeSummary {
                // Une moyenne sur un seul cycle n'en est pas une: on dit sur
                // combien elle porte.
                Text(s.cycleCount == 1
                     ? "Sur 1 cycle observé. Enregistre encore quelques mois pour une moyenne fiable. Régulier = écart de 7 jours au plus."
                     : "Sur \(s.cycleCount) cycles observés. Régulier = écart de 7 jours au plus entre le plus court et le plus long.")
            }
        }
    }

    @ViewBuilder
    private func trendSection(_ inRange: [CycleEntrySnapshot]) -> some View {
        let top = CycleInsights.symptomCounts(inRange).prefix(4).map(\.0)
        if !top.isEmpty {
            let from = range.start() ?? inRange.map(\.date).min() ?? .now
            let points = CycleInsights.monthlyTrend(inRange, symptoms: Array(top), from: from, to: .now)
            Section {
                Chart(points) { pt in
                    LineMark(x: .value("Mois", pt.month, unit: .month), y: .value("Jours", pt.days))
                        .foregroundStyle(by: .value("Symptôme", pt.symptom))
                    PointMark(x: .value("Mois", pt.month, unit: .month), y: .value("Jours", pt.days))
                        .foregroundStyle(by: .value("Symptôme", pt.symptom))
                }
                .chartLegend(position: .bottom)
                .frame(height: 200)
                .accessibilityLabel("Tendance des symptômes par mois")
            } header: {
                Text("Tendance des symptômes")
            } footer: {
                Text("Jours notés par mois pour tes symptômes les plus fréquents.")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
