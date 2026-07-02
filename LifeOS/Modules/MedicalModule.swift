import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var medicalTint: Color { AppCategory.medical.tint } }

// MARK: - Hub

struct MedicalHubView: View {
    var body: some View {
        HubScaffold(category: .medical) {
            ToolRow(icon: "pills.fill",           title: "Médicaments",        subtitle: "Traitements en cours et rappels",   tint: .medicalTint) { MedicationView() }
            ToolRow(icon: "stethoscope",          title: "Rendez-vous",        subtitle: "Agenda médical et suivi",            tint: .medicalTint) { AppointmentsView() }
            ToolRow(icon: "waveform.path.ecg",    title: "Carnet de santé",    subtitle: "Poids, tension, glycémie…",          tint: .medicalTint) { VitalsView() }
            ToolRow(icon: "syringe.fill",         title: "Vaccinations",       subtitle: "Historique et rappels",              tint: .medicalTint) { VaccinationView() }
        }
    }
}

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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { MedicationEditor() }
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
            Toggle("", isOn: Binding(get: { med.active }, set: { med.active = $0; Haptics.tap() }))
                .labelsHidden()
        }
        .contextMenu { Button(role: .destructive) { ctx.delete(med) } label: { Label("Supprimer", systemImage: "trash") } }
    }
}

struct MedicationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency = "1x/jour"
    @State private var hourMorning = 8
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
                Section("Prise") {
                    Picker("Fréquence", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("Heure matin : \(String(format: "%02d:00", hourMorning))", value: $hourMorning, in: 0...23)
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
                    Button("Ajouter") {
                        ctx.insert(Medication(name: name, dosage: dosage, frequency: frequency,
                                              hourMorning: hourMorning, notes: notes,
                                              endDate: hasEndDate ? endDate : nil))
                        if !name.isEmpty {
                            NotificationManager.shared.schedule(
                                id: "med-\(name)-morning",
                                title: "Prendre \(name)",
                                body: dosage.isEmpty ? frequency : "\(dosage) · \(frequency)",
                                at: Calendar.current.nextDate(after: .now, matching: DateComponents(hour: hourMorning, minute: 0), matchingPolicy: .nextTime) ?? .now
                            )
                        }
                        dismiss()
                    }.disabled(name.isEmpty)
                }
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
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
        .contextMenu { Button(role: .destructive) { ctx.delete(apt) } label: { Label("Supprimer", systemImage: "trash") } }
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
                            id: "appt-\(Int(date.timeIntervalSince1970))",
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
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
        .contextMenu { Button(role: .destructive) { ctx.delete(v) } label: { Label("Supprimer", systemImage: "trash") } }
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
                                id: "vacc-\(name)-\(Int(nextDate.timeIntervalSince1970))",
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
