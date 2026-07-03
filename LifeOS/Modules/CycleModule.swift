import SwiftUI
import SwiftData

// MARK: - Modèle cycle

@Model
final class CycleEntry {
    var date: Date
    var flow: Int        // 0 = aucun, 1 = léger, 2 = moyen, 3 = abondant
    var symptoms: [String]
    var mood: Int        // 0 = non renseigné, 1–5
    var note: String

    init(date: Date = .now, flow: Int = 1, symptoms: [String] = [], mood: Int = 0, note: String = "") {
        self.date = date
        self.flow = flow
        self.symptoms = symptoms
        self.mood = mood
        self.note = note
    }
}

// MARK: - Hub Cycle

struct CycleHubView: View {
    var body: some View {
        HubScaffold(category: .cycle) {
            ToolRow(icon: "calendar.badge.clock", title: "Suivi du cycle",
                    subtitle: "Règles · durée · prédiction", tint: .cycleTint) { CycleTrackerView() }
            ToolRow(icon: "waveform.path.ecg", title: "Symptômes",
                    subtitle: "Crampes, humeur, énergie, peau", tint: .cycleTint) { CycleSymptomsView() }
            ToolRow(icon: "chart.bar.fill", title: "Historique",
                    subtitle: "Régularité · durée moyenne", tint: .cycleTint) { CycleHistoryView() }
        }
    }
}

extension ShapeStyle where Self == Color { static var cycleTint: Color { AppCategory.cycle.tint } }

// MARK: - Tracker principal

struct CycleTrackerView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CycleEntry.date, order: .reverse) private var entries: [CycleEntry]
    @ObservedObject private var cycle = CycleContext.shared

    @State private var selectedFlow = 1
    @State private var selectedSymptoms: Set<String> = []
    @State private var selectedMood = 0
    @State private var note = ""
    @State private var showSuccess = false
    @State private var showDatePicker = false
    @State private var pickedDate = Date()

    @AppStorage("cycleStartDate") private var cycleStartDateTS: Double = 0
    @AppStorage("cycleLengthDays") private var cycleLengthDays = 28

    private let flows = ["Aucun", "Léger", "Moyen", "Abondant"]
    private let flowColors: [Color] = [.secondary, Color(hex: UInt(0xF9C0D8)), Color(hex: UInt(0xE85D9A)), Color(hex: UInt(0xB5136A))]
    private let symptomsAll = ["Crampes", "Maux de tête", "Ballonnements", "Fatigue", "Acné", "Seins sensibles", "Nausées", "Dos douloureux"]
    private let moods = ["", "Triste", "Irritable", "Neutre", "Bien", "Super"]

    private var phaseColor: Color { Color(hex: UInt(cycle.currentPhase.colorHex)) }
    private var todayEntry: CycleEntry? {
        entries.first { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {

                    // Phase du cycle
                    VStack(spacing: 12) {
                        if cycleStartDateTS > 0 {
                            HStack(spacing: 1) {
                                ForEach(0..<cycleLengthDays, id: \.self) { i in
                                    Capsule()
                                        .fill(i < cycle.dayOfCycle ? phaseColor : Color.primary.opacity(0.08))
                                        .frame(height: 6)
                                }
                            }
                            .animation(.spring(duration: 0.8), value: cycle.dayOfCycle)

                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Jour \(cycle.dayOfCycle)")
                                        .font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.primary)
                                    Text(cycle.currentPhase.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(phaseColor)
                                    Text("Règles dans \(cycle.daysUntilPeriod) jour\(cycle.daysUntilPeriod > 1 ? "s" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    showDatePicker = true
                                } label: {
                                    Text("Modifier")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(phaseColor)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(phaseColor.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Text("Quand ont commencé tes dernières règles ?")
                                    .font(.system(size: 15, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                Button {
                                    cycleStartDateTS = Date.now.timeIntervalSince1970
                                    cycle.refresh()
                                } label: {
                                    Text("Mes règles ont commencé aujourd'hui")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.onVolt)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    showDatePicker = true
                                } label: {
                                    Text("Choisir une date")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0xE85D9A))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: 0xE85D9A).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Conseils de la phase
                    if cycleStartDateTS > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(cycle.currentPhase.label.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(phaseColor)
                                    .kerning(1.2)
                                Spacer()
                            }
                            Text(cycle.currentPhase.energyDescription)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Fitness", systemImage: "figure.run")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(cycle.currentPhase.fitnessAdvice)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Nutriments", systemImage: "leaf.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(cycle.currentPhase.keyNutrients.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(16)
                        .background(phaseColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(phaseColor.opacity(0.25), lineWidth: 1)
                        )
                    }

                    // Flux du jour
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Flux aujourd'hui")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(0..<flows.count, id: \.self) { i in
                                Button {
                                    withAnimation(.spring(duration: 0.2)) { selectedFlow = i }
                                    Haptics.tap()
                                } label: {
                                    Text(flows[i])
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selectedFlow == i ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedFlow == i ? flowColors[i] : Theme.card,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .scaleEffect(selectedFlow == i ? 1.03 : 1.0)
                                .animation(.spring(duration: 0.2), value: selectedFlow)
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Symptômes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Symptômes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(symptomsAll, id: \.self) { s in
                                Button {
                                    withAnimation(.spring(duration: 0.2)) {
                                        if selectedSymptoms.contains(s) { selectedSymptoms.remove(s) }
                                        else { selectedSymptoms.insert(s) }
                                    }
                                    Haptics.tap()
                                } label: {
                                    Text(s)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(selectedSymptoms.contains(s) ? Theme.onVolt : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedSymptoms.contains(s)
                                                ? Theme.volt
                                                : Theme.card,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Humeur
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Comment tu te sens ?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { i in
                                Button {
                                    withAnimation(.spring(duration: 0.2)) { selectedMood = i }
                                    Haptics.tap()
                                } label: {
                                    Text(moods[i])
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(selectedMood == i ? Theme.onVolt : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedMood == i ? Theme.volt : Theme.card,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Bouton enregistrer
                    Button {
                        saveEntry()
                    } label: {
                        Text("Enregistrer")
                            .font(.system(size: 15, weight: .black)).textCase(.uppercase).kerning(0.5)
                            .foregroundStyle(Theme.onVolt)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.volt, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Theme.bg)
            .navigationTitle("Suivi du cycle")
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    VStack(spacing: 24) {
                        DatePicker("Date des dernières règles", selection: $pickedDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Color(hex: 0xE85D9A))
                            .padding(.horizontal)
                        Stepper("Durée du cycle : \(cycleLengthDays) jours", value: $cycleLengthDays, in: 21...45)
                            .padding(.horizontal)
                            .onChange(of: cycleLengthDays) { _, _ in cycle.refresh() }
                    }
                    .navigationTitle("Paramètres cycle")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Enregistrer") {
                                cycleStartDateTS = pickedDate.timeIntervalSince1970
                                cycle.refresh()
                                showDatePicker = false
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuler") { showDatePicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                loadTodayEntry()
                pickedDate = cycleStartDateTS > 0 ? Date(timeIntervalSince1970: cycleStartDateTS) : Date()
            }
            .overlay {
                if showSuccess {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Enregistré").font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func loadTodayEntry() {
        guard let e = todayEntry else { return }
        selectedFlow = e.flow
        selectedSymptoms = Set(e.symptoms)
        selectedMood = e.mood
        note = e.note
    }

    private func saveEntry() {
        let entry: CycleEntry
        if let existing = todayEntry {
            existing.flow = selectedFlow
            existing.symptoms = Array(selectedSymptoms)
            existing.mood = selectedMood
            existing.note = note
            entry = existing
        } else {
            entry = CycleEntry(flow: selectedFlow, symptoms: Array(selectedSymptoms), mood: selectedMood, note: note)
            ctx.insert(entry)
        }
        if selectedFlow > 0 && cycleStartDateTS == 0 {
            cycleStartDateTS = Date.now.timeIntervalSince1970
        }
        cycle.refresh()
        Haptics.tap()
        withAnimation(.spring(duration: 0.3)) { showSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSuccess = false }
        }
    }
}

// MARK: - Symptômes (vue dédiée)

struct CycleSymptomsView: View {
    @Query(sort: \CycleEntry.date, order: .reverse) private var entries: [CycleEntry]

    private var recentSymptoms: [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in entries.prefix(3) {
            for s in e.symptoms { counts[s, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        NavigationStack {
            List {
                if recentSymptoms.isEmpty {
                    Text("Aucun symptôme enregistré récemment.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("3 derniers jours") {
                        ForEach(recentSymptoms, id: \.0) { s, count in
                            HStack {
                                Text(s).font(.body)
                                Spacer()
                                Text("\(count)×").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Symptômes")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Historique

struct CycleHistoryView: View {
    @Query(sort: \CycleEntry.date, order: .reverse) private var entries: [CycleEntry]

    private var avgCycle: Double {
        // Simplifié : durée moyenne entre les premières entrées consécutives avec flux
        let withFlow = entries.filter { $0.flow > 0 }
        guard withFlow.count >= 2 else { return 0 }
        var gaps: [Double] = []
        for i in 0..<min(withFlow.count - 1, 5) {
            let gap = withFlow[i].date.timeIntervalSince(withFlow[i + 1].date) / 86400
            if gap > 20 { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return 0 }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    var body: some View {
        NavigationStack {
            List {
                if avgCycle > 0 {
                    Section("Stats") {
                        HStack {
                            Text("Durée moyenne")
                            Spacer()
                            Text("\(Int(avgCycle.rounded())) jours").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Entrées récentes") {
                    if entries.isEmpty {
                        Text("Aucune donnée.").foregroundStyle(.secondary)
                    } else {
                        ForEach(entries.prefix(30)) { e in
                            HStack(spacing: 12) {
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(Color(hex: 0xE85D9A).opacity(0.5 + Double(e.flow) * 0.15))
                                    .font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.date, style: .date).font(.subheadline)
                                    if !e.symptoms.isEmpty {
                                        Text(e.symptoms.joined(separator: ", "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
