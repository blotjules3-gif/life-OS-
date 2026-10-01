import UserNotifications
import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var medicalTint: Color { AppCategory.medical.tint } }

// MARK: - Médicaments

struct MedicationView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medication.name) private var meds: [Medication]
    @State private var showAdd = false
    @State private var editing: Medication?

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
        .sheet(item: $editing) { med in MedicationEditor(editing: med) }
        // Remise a plat a chaque ouverture. C'est ce qui rattrape les
        // traitements enregistres avant que les rappels existent, ceux dont
        // la date de fin est passee, et une reinstallation de l'app.
        .onAppear { MedicationReminders.reconcileAll(ctx: ctx) }
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
                // Les notes (effets secondaires, consignes) etaient
                // enregistrees puis jamais affichees nulle part.
                if !med.notes.isEmpty {
                    Text(med.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if let coverage = MedicationReminders.coverageText(for: med) {
                    Text(coverage).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { med.active }, set: { setActive(med, $0) }))
                .labelsHidden()
        }
        .contextMenu {
            Button { editing = med } label: { Label("Modifier", systemImage: "pencil") }
            Button(role: .destructive) { remove(med) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func setActive(_ med: Medication, _ on: Bool) {
        med.active = on
        Haptics.tap()
        MedicationReminders.reschedule(med, ctx: ctx)
    }

    private func remove(_ med: Medication) {
        ctx.delete(med)
        LifeOSTry(try ctx.save(), context: "suppression medicament", category: AppLog.data)
        // La reconciliation relit la base: le medicament supprime n'y est plus,
        // donc tous ses rappels partent.
        MedicationReminders.reconcileAll(ctx: ctx)
    }
}

struct MedicationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    /// Medicament a modifier; nil pour un ajout.
    var editing: Medication? = nil
    @State private var loaded = false
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
            .navigationTitle(editing == nil ? "Nouveau médicament" : "Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { add() }.disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let med = editing else { return }
        loaded = true
        name = med.name; dosage = med.dosage; notes = med.notes
        // Valeur gardee telle quelle meme hors liste: l'ecraser par
        // "1x/jour" changerait les rappels sans qu'on l'ait demande.
        frequency = med.frequency
        hourMorning = med.hourMorning ?? MedicationSchedule.defaultMorning
        hourEvening = med.hourEvening ?? MedicationSchedule.defaultEvening
        hasEndDate = med.endDate != nil
        endDate = med.endDate ?? Date()
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
        if let med = editing {
            med.name = name; med.dosage = dosage; med.frequency = frequency
            med.hourMorning = hourMorning; med.hourEvening = hourEvening
            med.notes = notes; med.endDate = hasEndDate ? endDate : nil
            LifeOSTry(try ctx.save(), context: "modification medicament", category: AppLog.data)
            MedicationReminders.reschedule(med, ctx: ctx)
            dismiss()
            return
        }
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

    static let identifierPrefix = "med."

    /// Prefixe stable. Tous les identifiants d'un medicament en derivent.
    private static func prefix(_ med: Medication, ctx: ModelContext) -> String {
        if med.stableID.isEmpty {
            med.stableID = UUID().uuidString
            LifeOSTry(try ctx.save(), context: "stableID medicament", category: AppLog.data)
        }
        return "\(identifierPrefix)\(med.stableID)"
    }

    /// Horizon demande au planificateur: le budget commun tranche ensuite.
    static let planningHorizonDays = 90

    // Anciennes entrees: tout passe par la reconciliation globale.
    @MainActor static func reschedule(_ med: Medication, ctx: ModelContext) { reconcileAll(ctx: ctx) }
    @MainActor static func renewAll(ctx: ModelContext) { reconcileAll(ctx: ctx) }

    /// Attend la fin du passage en cours (tache de fond qui doit finir avant d'etre coupee).
    @MainActor static func waitForIdle() async { await chain?.value }

    /// Dernier passage en cours: chaque reconciliation attend la precedente.
    /// Avant, deux remplacements lances de suite pouvaient s'entrelacer (A retire,
    /// B retire, A remet l'ANCIEN plan, B remet le nouveau): un rappel supprime
    /// ressuscitait. Ici l'etat est photographie au moment de l'appel et les
    /// passages s'executent l'un apres l'autre: le dernier gagne toujours.
    @MainActor private static var chain: Task<Void, Never>?

    /// Recalcule TOUS les rappels de medicaments d'un coup, dans le budget commun.
    @MainActor
    static func reconcileAll(ctx: ModelContext, now: Date = .now) {
        let meds = (try? ctx.fetch(FetchDescriptor<Medication>())) ?? []
        var items: [MedicationBudget.Item] = []
        var requests: [String: UNNotificationRequest] = [:]
        for med in meds {
            let base = prefix(med, ctx: ctx)
            for r in Self.requests(for: med, base: base, now: now) {
                let date = (r.trigger as? UNCalendarNotificationTrigger).flatMap { $0.repeats ? nil : $0.nextTriggerDate() }
                items.append(.init(medID: med.stableID, identifier: r.identifier, fireDate: date))
                requests[r.identifier] = r
            }
        }
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await apply(items: items, requests: requests)
        }
    }

    @MainActor
    private static func apply(items: [MedicationBudget.Item], requests: [String: UNNotificationRequest]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        let others = pending.count - ours.count
        let budget = MedicationBudget.systemLimit - MedicationBudget.reserve - others
        let (chosen, coverage) = MedicationBudget.select(items, budget: budget)

        center.removePendingNotificationRequests(withIdentifiers: ours)
        var failed = Set<String>()
        for item in chosen {
            guard let r = requests[item.identifier] else { continue }
            do { try await center.add(r) }
            catch {
                failed.insert(item.medID)
                AppLog.general.error("rappel non posé \(r.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        let denied = settings.authorizationStatus == .denied
        storeCoverage(coverage, denied: denied, failed: failed)
    }

    // MARK: Couverture affichee

    private static func key(_ id: String) -> String { "med.coverage.\(id)" }

    private static func storeCoverage(_ coverage: [String: MedicationBudget.Coverage], denied: Bool, failed: Set<String>) {
        let ud = UserDefaults.standard
        for (id, c) in coverage {
            let value: String
            if denied { value = "denied" }
            else if failed.contains(id) { value = "failed" }
            else {
                switch c {
                case .unlimited: value = "unlimited"
                case .until(let d): value = "until:\(d.timeIntervalSince1970)"
                case .none: value = "none"
                }
            }
            ud.set(value, forKey: key(id))
        }
    }

    /// Phrase montree sous le medicament: jusqu'ou les rappels sont vraiment programmes.
    static func coverageText(for med: Medication) -> String? {
        guard med.active, !med.stableID.isEmpty, let raw = UserDefaults.standard.string(forKey: key(med.stableID)) else { return nil }
        switch raw {
        case "denied": return "Notifications refusées dans Réglages : aucun rappel ne sonnera."
        case "failed": return "Des rappels n'ont pas pu être programmés. Rouvre l'app pour réessayer."
        case "unlimited": return "Rappels programmés sans date de fin."
        case "none": return "Aucun rappel programmé (plus de place ou traitement terminé)."
        default:
            guard raw.hasPrefix("until:"), let t = Double(raw.dropFirst(6)) else { return nil }
            let d = Date(timeIntervalSince1970: t)
            return "Rappels programmés jusqu'au \(d.formatted(date: .abbreviated, time: .shortened)). Ouvre LifeOS avant pour prolonger."
        }
    }

    static func requests(for med: Medication, base: String, now: Date = .now) -> [UNNotificationRequest] {
        let plan = MedicationSchedule.plan(frequency: med.frequency, hourMorning: med.hourMorning,
                                           hourEvening: med.hourEvening, active: med.active,
                                           startDate: med.startDate, endDate: med.endDate, now: now,
                                           horizonDays: planningHorizonDays, maxDates: MedicationBudget.systemLimit)
        let title = "Prendre \(med.name)"
        let detail = med.dosage.isEmpty ? med.frequency : "\(med.dosage) · \(med.frequency)"
        func content(_ body: String) -> UNMutableNotificationContent {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            return c
        }
        func repeating(_ i: Int, _ d: MedicationSchedule.Dose, weekday: Int?) -> UNNotificationRequest {
            var comps = DateComponents(); comps.hour = d.hour; comps.minute = d.minute
            if let weekday { comps.weekday = weekday }
            return UNNotificationRequest(identifier: "\(base).\(i)", content: content("\(detail) — \(d.label)"),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        }
        switch plan {
        case .none:
            return []
        case .repeatingDaily(let doses):
            return doses.enumerated().map { repeating($0.offset, $0.element, weekday: nil) }
        case .repeatingWeekly(let weekday, let doses):
            return doses.enumerated().map { repeating($0.offset, $0.element, weekday: weekday) }
        case .dates(let dates):
            // Composantes SANS fuseau: 8 h reste 8 h a l'heure locale apres un
            // voyage ou un changement d'heure.
            let cal = Calendar.current
            return dates.enumerated().map { i, at in
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                return UNNotificationRequest(identifier: "\(base).d\(i)", content: content(detail),
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            }
        }
    }
}

// MARK: - Rendez-vous médicaux

struct AppointmentsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MedicalAppointment.date) private var appointments: [MedicalAppointment]
    @State private var showAdd = false
    @State private var editing: MedicalAppointment?

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
        .sheet(item: $editing) { apt in AppointmentEditor(editing: apt) }
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
                // Motif, resultats, ordonnances: saisis puis jamais montres.
                if !apt.notes.isEmpty { Text(apt.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            }
            Spacer()
            if let next = apt.nextDate, next > .now {
                VStack(spacing: 0) {
                    Text("Prochain").font(.caption2).foregroundStyle(.secondary)
                    Text(next, format: .dateTime.day().month(.abbreviated)).font(.caption.bold()).foregroundStyle(.medicalTint)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = apt }
        .contextMenu {
            Button { editing = apt } label: { Label("Modifier", systemImage: "pencil") }
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
    /// Rendez-vous a modifier; nil pour un ajout.
    var editing: MedicalAppointment? = nil
    @State private var loaded = false
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
                } footer: {
                    // Un rendez-vous a moins de 24 h n'avait aucun rappel, en
                    // silence. On dit ce qui va sonner, ou que rien ne sonnera.
                    Text(reminderLine)
                }
                Section("Notes") {
                    TextField("Motif, résultats, ordonnances…", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section("Suivi") {
                    Toggle("Planifier prochain RDV", isOn: $hasNext)
                    if hasNext { DatePicker("Prochain RDV", selection: $nextDate, displayedComponents: .date) }
                }
            }
            .navigationTitle(editing == nil ? "Nouveau RDV" : "Modifier le RDV").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var reminderLine: String {
        guard let r = MedicalReminderTiming.appointment(date) else {
            return "Pas de rappel : le rendez-vous est passé ou dans moins de 2 h."
        }
        return r.dayBefore
            ? "Rappel la veille, le \(r.at.formatted(date: .abbreviated, time: .shortened))."
            : "Rappel 2 h avant, à \(r.at.formatted(date: .omitted, time: .shortened))."
    }

    private func load() {
        guard !loaded, let apt = editing else { return }
        loaded = true
        date = apt.date; specialty = apt.specialty; doctorName = apt.doctorName
        location = apt.location; notes = apt.notes
        hasNext = apt.nextDate != nil
        nextDate = apt.nextDate ?? Date()
    }

    private func save() {
        let s = specialty.isEmpty ? "Généraliste" : specialty
        if let apt = editing {
            // L'ancien rappel porte l'ancienne date dans son identifiant.
            NotificationManager.shared.cancel(id: ReminderIDs.appointment(apt.date))
            apt.date = date; apt.specialty = s; apt.doctorName = doctorName
            apt.location = location; apt.notes = notes; apt.nextDate = hasNext ? nextDate : nil
        } else {
            ctx.insert(MedicalAppointment(date: date, specialty: s, doctorName: doctorName,
                                          location: location, notes: notes,
                                          nextDate: hasNext ? nextDate : nil))
        }
        if let r = MedicalReminderTiming.appointment(date) {
            NotificationManager.shared.schedule(
                id: ReminderIDs.appointment(date),
                title: r.dayBefore ? "RDV \(s) demain" : "RDV \(s) dans 2 h",
                body: doctorName.isEmpty ? location : "\(doctorName) · \(location)",
                at: r.at
            )
        }
        dismiss()
    }
}

/// Quand faire sonner un rappel medical. Avant, le delai etait fixe (veille
/// pour un RDV, 30 jours pour un vaccin): si ce moment etait deja passe,
/// NotificationManager.schedule l'ignorait sans rien dire.
enum MedicalReminderTiming {

    /// La veille a la meme heure; sinon 2 h avant; sinon rien.
    static func appointment(_ date: Date, now: Date = .now,
                            calendar: Calendar = .current) -> (at: Date, dayBefore: Bool)? {
        if let d = calendar.date(byAdding: .day, value: -1, to: date), d > now { return (d, true) }
        if let h = calendar.date(byAdding: .hour, value: -2, to: date), h > now { return (h, false) }
        return nil
    }

    /// 30 jours avant a 9 h; si c'est passe, 7 jours, la veille, puis le jour
    /// meme. Rien si la date de rappel est deja passee.
    static func vaccine(due: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let dueDay = calendar.startOfDay(for: due)
        for lead in [30, 7, 1, 0] {
            guard let day = calendar.date(byAdding: .day, value: -lead, to: dueDay),
                  let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            if at > now { return at }
        }
        return nil
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

    private var isTension: Bool { selectedType == "tension" }

    private var trendCard: some View {
        let data = chartData
        let sys = data.map(\.value)
        // La diastolique (value2) etait ignoree: graphe et ecart ne
        // montraient que la systolique.
        let dia = isTension ? data.compactMap(\.value2) : []
        let all = sys + dia
        let minV = all.min() ?? 0
        let maxV = all.max() ?? 1
        let pad = Swift.max((maxV - minV) * 0.15, 0.5)
        let delta = (data.last?.value ?? 0) - (data.first?.value ?? 0)
        let diaPairs = data.filter { $0.value2 != nil }
        let deltaDia: Double? = isTension && diaPairs.count >= 2
            ? (diaPairs.last?.value2 ?? 0) - (diaPairs.first?.value2 ?? 0) : nil
        let unit = data.last?.unit ?? ""
        let tone = VitalTrend.tone(type: selectedType, deltas: [delta] + (deltaDia.map { [$0] } ?? []))
        let deltaText = deltaDia.map { String(format: "%+.0f / %+.0f %@", delta, $0, unit) }
            ?? String(format: "%+.1f %@", delta, unit)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TENDANCE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Text(deltaText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone == .better ? Color(hex: 0x4CC38A)
                                     : tone == .worse ? Color(hex: 0xF1746C) : Color.secondary)
            }
            Chart(data) { r in
                if isTension {
                    LineMark(
                        x: .value("Date", r.date),
                        y: .value("Valeur", r.value),
                        series: .value("Mesure", "Systolique")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    if let d = r.value2 {
                        LineMark(
                            x: .value("Date", r.date),
                            y: .value("Valeur", d),
                            series: .value("Mesure", "Diastolique")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                    }
                } else {
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
                if isTension {
                    Text(String(format: "Sys %.0f–%.0f", sys.min() ?? 0, sys.max() ?? 0))
                    Spacer()
                    Text("\(data.count) mesures")
                    Spacer()
                    if let lo = dia.min(), let hi = dia.max() {
                        Text(String(format: "Dia %.0f–%.0f", lo, hi))
                    }
                } else {
                    Text(String(format: "Min %.1f", minV))
                    Spacer()
                    Text("\(data.count) mesures")
                    Spacer()
                    Text(String(format: "Max %.1f", maxV))
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
        .card()
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

/// Couleur de l'ecart d'une mesure. Avant, toute HAUSSE de tension, de
/// glycemie ou de frequence cardiaque etait verte, comme une bonne nouvelle.
enum VitalTrend {
    enum Tone: Equatable { case better, worse, neutral }

    static func tone(type: String, deltas: [Double]) -> Tone {
        let moved = deltas.filter { $0 != 0 }
        guard !moved.isEmpty else { return .neutral }
        if type == "poids" {
            return moved.allSatisfy { $0 < 0 } ? .better : .worse
        }
        // Tension, glycemie, cœur: une hausse est un signal a surveiller. Une
        // baisse n'est pas forcement bonne (hypotension, hypoglycemie): neutre.
        return moved.contains { $0 > 0 } ? .worse : .neutral
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
                .background(highlight ? Theme.warning : Color.medicalTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(.subheadline.weight(.semibold))
                Text("Fait le \(v.date.formatted(.dateTime.day().month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
                // Le lot n'apparaissait que dans l'export JSON.
                if !v.lot.isEmpty { Text("Lot \(v.lot)").font(.caption).foregroundStyle(.secondary) }
                if !v.notes.isEmpty { Text(v.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if let next = v.nextDueDate {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Rappel").font(.caption2).foregroundStyle(.secondary)
                    Text(next, format: .dateTime.day().month(.abbreviated).year()).font(.caption.bold()).foregroundStyle(highlight ? Theme.warning : .medicalTint)
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
                Section {
                    Toggle("Date de rappel", isOn: $hasNext)
                    if hasNext { DatePicker("Prochain rappel", selection: $nextDate, displayedComponents: .date) }
                } header: {
                    Text("Rappel")
                } footer: {
                    if hasNext {
                        if let at = MedicalReminderTiming.vaccine(due: nextDate) {
                            Text("Notification le \(at.formatted(date: .abbreviated, time: .shortened)).")
                        } else {
                            Text("Pas de notification : cette date est déjà passée.")
                        }
                    }
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
                        if hasNext, let at = MedicalReminderTiming.vaccine(due: nextDate) {
                            NotificationManager.shared.schedule(
                                id: ReminderIDs.vaccination(name: name, nextDate: nextDate),
                                title: "Rappel vaccin \(name)",
                                body: "Le rappel est prévu pour le \(nextDate.formatted(.dateTime.day().month(.wide)))",
                                at: at
                            )
                        }
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
