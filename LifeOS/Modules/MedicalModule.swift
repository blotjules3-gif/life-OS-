import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var medicalTint: Color { AppCategory.medical.tint } }

// MARK: - Médicaments

struct MedicationView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medication.name) private var meds: [Medication]
    @State private var showAdd = false

    private var active: [Medication] { meds.filter { $0.active } }
    private var inactive: [Medication] { meds.filter { !$0.active } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if meds.isEmpty {
                        EmptyState(icon: "pills", title: "Aucun médicament", message: "Ajoute tes traitements en cours pour recevoir des rappels de prise.")
                    } else {
                        if !active.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "En cours")
                                ForEach(active) { med in medRow(med) }
                            }.card()
                        }
                        if !inactive.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Terminés")
                                ForEach(inactive) { med in medRow(med) }
                            }.card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Médicaments").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { MedicationEditor() }
        // Remise a plat a chaque ouverture. C'est ce qui rattrape les
        // traitements enregistres avant que les rappels existent, ceux dont
        // la date de fin est passee, et une reinstallation de l'app.
        .onAppear { meds.forEach { MedicationReminders.reschedule($0, ctx: ctx) } }
    }

    private func medRow(_ med: Medication) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(med.active ? Color.medicalTint : Color.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(med.name).font(.subheadline.weight(.semibold))
                    Text(med.dosage).font(.caption).foregroundStyle(.secondary)
                }
                Text(med.frequency).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { med.active }, set: { setActive(med, $0) }))
                .labelsHidden()
        }
        .contextMenu {
            Button(role: .destructive) { remove(med) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func setActive(_ med: Medication, _ on: Bool) {
        med.active = on
        Haptics.tap()
        MedicationReminders.reschedule(med, ctx: ctx)
    }

    /// Annuler AVANT de supprimer: une fois la ligne partie, son identifiant
    /// stable n'est plus lisible et le rappel sonnerait pour un traitement
    /// qui n'existe plus.
    private func remove(_ med: Medication) {
        MedicationReminders.cancel(med)
        ctx.delete(med)
    }
}

struct MedicationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency = "1x/jour"
    @State private var hourMorning = MedicationSchedule.defaultMorning
    @State private var hourEvening = MedicationSchedule.defaultEvening
    @State private var notes = ""
    @State private var hasEndDate = false
    @State private var endDate = Date()

    private let frequencies = ["1x/jour", "2x/jour", "3x/jour", "Au besoin", "1x/semaine"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Médicament") {
                    TextField("Nom (ex: Doliprane)", text: $name)
                    TextField("Dosage (ex: 500mg)", text: $dosage)
                }
                Section {
                    Picker("Fréquence", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0).tag($0) }
                    }
                    if !MedicationSchedule.isOnDemand(frequency) {
                        Stepper("Heure matin : \(String(format: "%02d:00", hourMorning))", value: $hourMorning, in: 0...23)
                        if doses.count > 1 {
                            Stepper("Heure soir : \(String(format: "%02d:00", hourEvening))", value: $hourEvening, in: 0...23)
                        }
                    }
                } header: {
                    Text("Prise")
                } footer: {
                    // On annonce exactement ce qui va sonner: un ecran qui
                    // promet "des rappels" sans dire lesquels ne se verifie pas.
                    Text(reminderSummary)
                }
                Section("Durée") {
                    Toggle("Date de fin", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("Fin le", selection: $endDate, displayedComponents: .date) }
                }
                Section("Notes") {
                    TextField("Effets secondaires, instructions…", text: $notes, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("Nouveau médicament").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { add() }.disabled(name.isEmpty)
                }
            }
        }
    }

    private var doses: [MedicationSchedule.Dose] {
        MedicationSchedule.doses(frequency: frequency,
                                 hourMorning: hourMorning,
                                 hourEvening: hourEvening)
    }

    private var reminderSummary: String {
        if MedicationSchedule.isOnDemand(frequency) {
            return "Aucun rappel : un traitement à prendre au besoin ne se rappelle pas à heure fixe."
        }
        let hours = doses.map { String(format: "%02d:00", $0.hour) }.joined(separator: ", ")
        return MedicationSchedule.isWeekly(frequency)
            ? "Rappel chaque semaine à \(hours), le même jour qu'aujourd'hui."
            : "Rappel chaque jour à \(hours)."
    }

    private func add() {
        let med = Medication(name: name, dosage: dosage, frequency: frequency,
                             hourMorning: hourMorning, hourEvening: hourEvening,
                             notes: notes, endDate: hasEndDate ? endDate : nil)
        ctx.insert(med)
        MedicationReminders.reschedule(med, ctx: ctx)
        dismiss()
    }
}

// MARK: - Rappels de prise

/// Pose et retire les rappels d'un medicament.
///
/// Sorti de la vue parce que trois endroits en ont besoin: l'ajout, le
/// basculement actif/termine, et la remise a plat a l'ouverture de l'ecran.
/// Trois copies auraient derive.
enum MedicationReminders {

    /// Prefixe stable. Tous les identifiants d'un medicament en derivent,
    /// ce qui permet de tous les annuler sans savoir combien il y en avait
    /// quand ils ont ete poses.
    private static func prefix(_ med: Medication, ctx: ModelContext) -> String {
        if med.stableID.isEmpty {
            med.stableID = UUID().uuidString
            LifeOSTry(try ctx.save(), context: "stableID medicament", category: AppLog.data)
        }
        return "med.\(med.stableID)"
    }

    /// Jusqu'a trois prises par jour, plus une marge si la frequence baisse.
    private static let maxDoses = 4

    static func cancel(_ med: Medication) {
        guard !med.stableID.isEmpty else { return }
        let base = "med.\(med.stableID)"
        for i in 0..<maxDoses { NotificationManager.shared.cancel(id: "\(base).\(i)") }
    }

    static func reschedule(_ med: Medication, ctx: ModelContext) {
        let base = prefix(med, ctx: ctx)
        // Toujours tout annuler d'abord: passer de 3x/jour a 1x/jour doit
        // retirer les deux prises en trop, pas seulement replacer la premiere.
        for i in 0..<maxDoses { NotificationManager.shared.cancel(id: "\(base).\(i)") }

        guard MedicationSchedule.isRunning(active: med.active, endDate: med.endDate) else { return }
        let doses = MedicationSchedule.doses(frequency: med.frequency,
                                             hourMorning: med.hourMorning,
                                             hourEvening: med.hourEvening)
        guard !doses.isEmpty else { return }

        let title = "Prendre \(med.name)"
        let detail = med.dosage.isEmpty ? med.frequency : "\(med.dosage) · \(med.frequency)"

        for (i, dose) in doses.enumerated() {
            let id = "\(base).\(i)"
            let body = "\(detail) — \(dose.label)"
            if MedicationSchedule.isWeekly(med.frequency) {
                let weekday = Calendar.current.component(.weekday, from: med.startDate)
                NotificationManager.shared.scheduleWeekly(
                    id: id, title: title, body: body,
                    weekday: weekday, hour: dose.hour, minute: dose.minute)
            } else {
                NotificationManager.shared.scheduleDaily(
                    id: id, title: title, body: body,
                    hour: dose.hour, minute: dose.minute)
            }
        }
    }
}

// MARK: - Rendez-vous médicaux

struct AppointmentsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MedicalAppointment.date) private var appointments: [MedicalAppointment]
    @State private var showAdd = false

    private var upcoming: [MedicalAppointment] { appointments.filter { $0.date >= Calendar.current.startOfDay(for: .now) } }
    private var past: [MedicalAppointment] { appointments.filter { $0.date < Calendar.current.startOfDay(for: .now) }.reversed() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if appointments.isEmpty {
                        EmptyState(icon: "stethoscope", title: "Aucun RDV", message: "Note tes rendez-vous médicaux pour ne rien oublier.")
                    } else {
                        if !upcoming.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "À venir")
                                ForEach(upcoming) { apt in apptRow(apt) }
                            }.card()
                        }
                        if !past.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Passés")
                                ForEach(past) { apt in apptRow(apt) }
                            }.card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Rendez-vous").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { AppointmentEditor() }
    }

    private func apptRow(_ apt: MedicalAppointment) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(apt.date, format: .dateTime.day()).font(.title3.bold()).foregroundStyle(.medicalTint)
                Text(apt.date, format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(apt.specialty).font(.subheadline.weight(.semibold))
                if !apt.doctorName.isEmpty { Text(apt.doctorName).font(.caption).foregroundStyle(.secondary) }
                if !apt.location.isEmpty { Label(apt.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let next = apt.nextDate, next > .now {
                VStack(spacing: 0) {
                    Text("Prochain").font(.caption2).foregroundStyle(.secondary)
                    Text(next, format: .dateTime.day().month(.abbreviated)).font(.caption.bold()).foregroundStyle(.medicalTint)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                // Sans ca, le rappel de la veille sonnait pour un rendez
                // vous annule, et rien ne permettait de le faire taire.
                NotificationManager.shared.cancel(id: ReminderIDs.appointment(apt.date))
                ctx.delete(apt)
            } label: { Label("Supprimer", systemImage: "trash") }
        }
    }
}

struct AppointmentEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var specialty = ""
    @State private var doctorName = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var hasNext = false
    @State private var nextDate = Date()

    private let specialties = ["Généraliste", "Dentiste", "Ophtalmologue", "Dermatologue",
                                "Cardiologue", "ORL", "Kinésithérapeute", "Psychiatre", "Autre"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date)
                    Picker("Spécialité", selection: $specialty) {
                        ForEach(specialties, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Médecin (optionnel)", text: $doctorName)
                    TextField("Lieu / Adresse", text: $location)
                }
                Section("Notes") {
                    TextField("Motif, résultats, ordonnances…", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section("Suivi") {
                    Toggle("Planifier prochain RDV", isOn: $hasNext)
                    if hasNext { DatePicker("Prochain RDV", selection: $nextDate, displayedComponents: .date) }
                }
            }
            .navigationTitle("Nouveau RDV").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let s = specialty.isEmpty ? "Généraliste" : specialty
                        ctx.insert(MedicalAppointment(date: date, specialty: s, doctorName: doctorName,
                                                       location: location, notes: notes,
                                                       nextDate: hasNext ? nextDate : nil))
                        NotificationManager.shared.schedule(
                            id: ReminderIDs.appointment(date),
                            title: "RDV \(s) demain",
                            body: doctorName.isEmpty ? location : "\(doctorName) · \(location)",
                            at: Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Carnet de santé (constantes vitales)

struct VitalsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \VitalRecord.date, order: .reverse) private var records: [VitalRecord]
    @State private var showAdd = false
    @State private var selectedType = "poids"

    private let types = ["poids", "tension", "glycémie", "fréquence cardiaque"]
    private var filtered: [VitalRecord] { records.filter { $0.type == selectedType } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Type", selection: $selectedType) {
                        ForEach(types, id: \.self) { Text(typeLabel($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.pad)

                    if filtered.isEmpty {
                        EmptyState(icon: "waveform.path.ecg", title: "Aucune mesure", message: "Enregistre ta première mesure de \(typeLabel(selectedType).lowercased()).")
                    } else {
                        if chartData.count >= 2 {
                            trendCard
                        }
                        VStack(spacing: 8) {
                            ForEach(filtered) { r in vitalRow(r) }
                        }.card()
                    }
                }.padding(.vertical, Theme.pad)
            }
        }
        .navigationTitle("Carnet de santé").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { VitalEditor(defaultType: selectedType) }
    }

    private func typeLabel(_ t: String) -> String {
        switch t {
        case "poids": return "Poids"
        case "tension": return "Tension"
        case "glycémie": return "Glycémie"
        case "fréquence cardiaque": return "Cœur"
        default: return t.capitalized
        }
    }

    // Dernières 30 mesures, chronologiques, pour le graphe.
    private var chartData: [VitalRecord] {
        Array(filtered.sorted { $0.date < $1.date }.suffix(30))
    }

    private var trendCard: some View {
        let data = chartData
        let values = data.map(\.value)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let pad = Swift.max((maxV - minV) * 0.15, 0.5)
        let delta = (data.last?.value ?? 0) - (data.first?.value ?? 0)
        let unit = data.last?.unit ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TENDANCE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Text(String(format: "%+.1f %@", delta, unit))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(delta == 0 ? Color.secondary
                                     : trendIsPositive(delta) ? Color(hex: 0x4CC38A) : Color(hex: 0xF1746C))
            }
            Chart(data) { r in
                AreaMark(
                    x: .value("Date", r.date),
                    yStart: .value("Base", minV - pad),
                    yEnd: .value("Valeur", r.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value("Date", r.date),
                    y: .value("Valeur", r.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartYScale(domain: (minV - pad)...(maxV + pad))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel().font(.system(size: 10))
                }
            }
            .frame(height: 150)
            HStack {
                Text(String(format: "Min %.1f", minV))
                Spacer()
                Text("\(data.count) mesures")
                Spacer()
                Text(String(format: "Max %.1f", maxV))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
        .card()
    }

    /// Pour le poids, une baisse est affichée en vert ; pour le reste, la couleur reste neutre-positive à la hausse.
    private func trendIsPositive(_ delta: Double) -> Bool {
        selectedType == "poids" ? delta < 0 : delta > 0
    }

    private func vitalRow(_ r: VitalRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if r.type == "tension", let d = r.value2 {
                    Text("\(Int(r.value)) / \(Int(d)) \(r.unit)").font(.subheadline.weight(.semibold))
                } else {
                    Text(String(format: "%.1f \(r.unit)", r.value)).font(.subheadline.weight(.semibold))
                }
                if !r.notes.isEmpty { Text(r.notes).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(r.date, style: .date).font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu { Button(role: .destructive) { ctx.delete(r) } label: { Label("Supprimer", systemImage: "trash") } }
    }
}

struct VitalEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var defaultType: String
    @State private var type = "poids"
    @State private var value = ""
    @State private var value2 = ""
    @State private var notes = ""
    @State private var date = Date()

    private var unit: String {
        switch type {
        case "poids": return "kg"
        case "tension": return "mmHg"
        case "glycémie": return "g/L"
        case "fréquence cardiaque": return "bpm"
        default: return ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        Text("Poids").tag("poids")
                        Text("Tension").tag("tension")
                        Text("Glycémie").tag("glycémie")
                        Text("Fréquence cardiaque").tag("fréquence cardiaque")
                    }
                    DatePicker("Date", selection: $date)
                }
                Section("Valeur (\(unit))") {
                    TextField(type == "tension" ? "Systolique (ex: 120)" : "Valeur (ex: 70)", text: $value)
                        .keyboardType(.decimalPad)
                    if type == "tension" {
                        TextField("Diastolique (ex: 80)", text: $value2).keyboardType(.decimalPad)
                    }
                }
                Section {
                    TextField("Notes (optionnel)", text: $notes)
                }
            }
            .navigationTitle("Nouvelle mesure").navigationBarTitleDisplayMode(.inline)
            .onAppear { type = defaultType }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        guard let v = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
                        let v2 = Double(value2.replacingOccurrences(of: ",", with: "."))
                        ctx.insert(VitalRecord(date: date, type: type, value: v, value2: v2, unit: unit, notes: notes))
                        dismiss()
                    }.disabled(value.isEmpty)
                }
            }
        }
    }
}

// MARK: - Vaccinations

struct VaccinationView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Vaccination.date, order: .reverse) private var vaccinations: [Vaccination]
    @State private var showAdd = false

    private var due: [Vaccination] { vaccinations.filter { $0.isDue } }
    private var upToDate: [Vaccination] { vaccinations.filter { !$0.isDue } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if vaccinations.isEmpty {
                        EmptyState(icon: "syringe", title: "Aucune vaccination", message: "Ajoute tes vaccins pour suivre les rappels.")
                    } else {
                        if !due.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Rappels à prévoir", subtitle: "Dans les 30 prochains jours")
                                ForEach(due) { v in vaccRow(v, highlight: true) }
                            }.card()
                        }
                        if !upToDate.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "À jour")
                                ForEach(upToDate) { v in vaccRow(v, highlight: false) }
                            }.card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Vaccinations").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { VaccinationEditor() }
    }

    private func vaccRow(_ v: Vaccination, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "syringe.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(highlight ? Color.orange : Color.medicalTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(.subheadline.weight(.semibold))
                Text("Fait le \(v.date.formatted(.dateTime.day().month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let next = v.nextDueDate {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Rappel").font(.caption2).foregroundStyle(.secondary)
                    Text(next, format: .dateTime.day().month(.abbreviated).year()).font(.caption.bold()).foregroundStyle(highlight ? .orange : .medicalTint)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                if let next = v.nextDueDate {
                    NotificationManager.shared.cancel(id: ReminderIDs.vaccination(name: v.name, nextDate: next))
                }
                ctx.delete(v)
            } label: { Label("Supprimer", systemImage: "trash") }
        }
    }
}

struct VaccinationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var date = Date()
    @State private var lot = ""
    @State private var hasNext = false
    @State private var nextDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var notes = ""

    private let common = ["Grippe", "COVID-19", "Tétanos-Diphtérie-Polio", "Hépatite B", "ROR", "Pneumocoque"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du vaccin", text: $name)
                    Picker("Vaccin courant", selection: $name) {
                        Text("Choisir…").tag("")
                        ForEach(common, id: \.self) { Text($0).tag($0) }
                    }
                    DatePicker("Date d'injection", selection: $date, displayedComponents: .date)
                    TextField("N° de lot (optionnel)", text: $lot)
                }
                Section("Rappel") {
                    Toggle("Date de rappel", isOn: $hasNext)
                    if hasNext { DatePicker("Prochain rappel", selection: $nextDate, displayedComponents: .date) }
                }
                Section {
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Nouveau vaccin").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        ctx.insert(Vaccination(name: name, date: date, nextDueDate: hasNext ? nextDate : nil, lot: lot, notes: notes))
                        if hasNext {
                            NotificationManager.shared.schedule(
                                id: ReminderIDs.vaccination(name: name, nextDate: nextDate),
                                title: "Rappel vaccin \(name)",
                                body: "Le rappel est prévu pour le \(nextDate.formatted(.dateTime.day().month(.wide)))",
                                at: Calendar.current.date(byAdding: .day, value: -30, to: nextDate) ?? nextDate
                            )
                        }
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
