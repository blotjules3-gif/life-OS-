import UserNotifications
import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

extension ShapeStyle where Self == Color { static var medicalTint: Color { AppCategory.medical.tint } }

// MARK: - Commun: personnes, pieces jointes, export

/// Filtre de personne partage par les quatre outils: choisir "Léa" dans les
/// médicaments la garde dans les vaccins.
private let personFilterKey = "medical.personFilter"

/// Menu de barre d'outils: tout le monde, moi, un proche, gerer les proches.
struct MedicalPersonFilterMenu: View {
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    @AppStorage(personFilterKey) private var filter = MedicalPeople.everyone
    @State private var showPeople = false

    var body: some View {
        Menu {
            Picker("Afficher", selection: $filter) {
                Text("Tout le monde").tag(MedicalPeople.everyone)
                Text("Moi").tag("")
                ForEach(people) { p in Text(p.name).tag(p.stableID) }
            }
            Divider()
            Button { showPeople = true } label: { Label("Gérer les proches", systemImage: "person.2") }
        } label: {
            Image(systemName: filter == MedicalPeople.everyone ? "person.2" : "person.crop.circle.fill")
        }
        .accessibilityLabel("Personne affichée")
        .sheet(isPresented: $showPeople) { MedicalPeopleView() }
    }
}

/// Liste des proches. "Moi" n'y figure pas: c'est la personne par defaut.
struct MedicalPeopleView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    @AppStorage(personFilterKey) private var filter = MedicalPeople.everyone
    @State private var newName = ""
    @State private var newRelation = ""
    @State private var blocked: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Prénom", text: $newName)
                    TextField("Lien (enfant, parent…)", text: $newRelation)
                    Button("Ajouter") { add() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("Nouveau proche") } footer: {
                    Text("Chaque traitement, rendez-vous et vaccin peut être rattaché à toi ou à un proche.")
                }
                if !people.isEmpty {
                    Section("Proches") {
                        ForEach(people) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Prénom", text: Binding(get: { p.name }, set: { p.name = $0 }))
                                    .font(.subheadline.weight(.semibold))
                                if !p.relation.isEmpty { Text(p.relation).font(.caption).foregroundStyle(.secondary) }
                            }
                            .swipeActions { Button(role: .destructive) { remove(p) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }
            }
            .navigationTitle("Proches").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { save(); dismiss() } } }
            .alert("Suppression impossible", isPresented: Binding(get: { blocked != nil }, set: { if !$0 { blocked = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(blocked ?? "") }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ctx.insert(MedicalPerson(name: name, relation: newRelation.trimmingCharacters(in: .whitespaces)))
        newName = ""; newRelation = ""
        save()
    }

    /// On ne supprime pas un proche qui a encore des fiches: les rattacher en
    /// douce a "moi" melangerait deux dossiers medicaux.
    private func remove(_ p: MedicalPerson) {
        let n = MedicalData.linkedCount(personID: p.stableID, ctx: ctx)
        guard n == 0 else {
            blocked = "\(p.name) a encore \(n) fiche\(n > 1 ? "s" : "") (traitement, rendez-vous ou vaccin). Supprime-les ou rattache-les à quelqu'un d'autre d'abord."
            return
        }
        if filter == p.stableID { filter = MedicalPeople.everyone }
        ctx.delete(p)
        save()
    }

    private func save() { LifeOSTry(try ctx.save(), context: "proches medicaux", category: AppLog.data) }
}

/// Choix de la personne dans un formulaire.
struct MedicalPersonPicker: View {
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    @Binding var personID: String

    var body: some View {
        if !people.isEmpty {
            Picker("Pour", selection: $personID) {
                Text("Moi").tag("")
                ForEach(people) { p in Text(p.name).tag(p.stableID) }
            }
        }
    }
}

/// Petite etiquette du proche concerne, absente pour "moi".
struct MedicalPersonTag: View {
    let personID: String
    let people: [MedicalPerson]
    var body: some View {
        if !personID.isEmpty {
            Text(MedicalPeople.name(for: personID, in: people.map { ($0.stableID, $0.name) }))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.medicalTint.opacity(0.15), in: Capsule())
                .foregroundStyle(.medicalTint)
        }
    }
}

struct MedicalAttachmentRef: Identifiable { let id: String }

/// Section de formulaire: photos d'ordonnance, comptes rendus, certificats.
struct MedicalAttachmentsSection: View {
    let title: String
    let prefix: String
    @Binding var draft: MedicalFiles.Draft
    @State private var viewing: MedicalAttachmentRef?

    var body: some View {
        Section {
            if !draft.current.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(draft.current, id: \.self) { f in
                            StoredImage(filename: f, placeholder: "doc.text")
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { draft.remove(f) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain).padding(3)
                                    .accessibilityLabel("Retirer la photo")
                                }
                                .onTapGesture { viewing = MedicalAttachmentRef(id: f) }
                        }
                    }.padding(.vertical, 4)
                }
            }
            PhotoPickerButton(label: "Ajouter une photo", prefix: prefix) { draft.add($0) }
        } header: { Text(title) } footer: {
            Text("Les photos restent sur cet appareil et partent avec la fiche si tu la supprimes.")
        }
        .sheet(item: $viewing) { ref in MedicalAttachmentViewer(filename: ref.id) }
    }
}

/// Vignettes en lecture seule (fiche detaillee, lignes de liste).
struct MedicalAttachmentStrip: View {
    let files: [String]
    @State private var viewing: MedicalAttachmentRef?
    var body: some View {
        if !files.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(files, id: \.self) { f in
                        StoredImage(filename: f, placeholder: "doc.text")
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onTapGesture { viewing = MedicalAttachmentRef(id: f) }
                            .accessibilityLabel("Voir la photo")
                    }
                }
            }
            .sheet(item: $viewing) { ref in MedicalAttachmentViewer(filename: ref.id) }
        }
    }
}

struct MedicalAttachmentViewer: View {
    let filename: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let img = ImageStore.load(filename) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity)
                    }
                } else {
                    EmptyState(icon: "doc.questionmark", title: "Photo introuvable",
                               message: "Le fichier n'est plus sur cet appareil. Retire-le de la fiche et ajoute-le à nouveau.")
                }
            }
            .navigationTitle("Document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                if let url = ImageStore.url(for: filename) {
                    ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
                }
            }
        }
    }
}

/// Fichier CSV partageable (Fichiers, Mail, AirDrop). La marque d'ordre des
/// octets fait lire les accents correctement a Excel.
struct MedicalCSVFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in Data(("\u{FEFF}" + file.text).utf8) }
            .suggestedFileName("observance-lifeos.csv")
    }
}

/// Acces a la base partages par les ecrans medicaux.
enum MedicalData {

    /// Enregistrement depuis une fermeture de bouton (un `try` y rendrait la fermeture "throws").
    @MainActor static func save(_ ctx: ModelContext, _ what: String) {
        LifeOSTry(try ctx.save(), context: what, category: AppLog.data)
    }

    /// Identifiant stable d'un traitement, cree a la premiere demande.
    @MainActor static func ensureID(_ med: Medication, ctx: ModelContext) -> String {
        if med.stableID.isEmpty {
            med.stableID = UUID().uuidString
            LifeOSTry(try ctx.save(), context: "stableID medicament", category: AppLog.data)
        }
        return med.stableID
    }

    static func snapshot(_ e: DoseEvent) -> DoseLog.Event {
        DoseLog.Event(scheduledAt: e.scheduledAt, loggedAt: e.loggedAt, status: e.status,
                      snoozedUntil: e.snoozedUntil, quantity: e.quantity)
    }

    static func events(of med: Medication, in all: [DoseEvent]) -> [DoseLog.Event] {
        guard !med.stableID.isEmpty else { return [] }
        return all.filter { $0.medID == med.stableID }.map(snapshot)
    }

    static func stock(of med: Medication, events: [DoseLog.Event]) -> Double {
        DoseLog.stock(initial: med.stockCount, setAt: med.stockSetAt, events: events)
    }

    @MainActor static func log(_ med: Medication, at: Date?, status: String, snoozeMinutes: Int = 0,
                               ctx: ModelContext, now: Date = .now) {
        let id = ensureID(med, ctx: ctx)
        let until: Date? = status == "snoozed" ? max(now, at ?? now).addingTimeInterval(Double(snoozeMinutes) * 60) : nil
        ctx.insert(DoseEvent(medID: id, scheduledAt: at, status: status, loggedAt: now,
                             snoozedUntil: until, quantity: status == "taken" ? med.dosePerIntake : 0))
        LifeOSTry(try ctx.save(), context: "prise medicament", category: AppLog.data)
        Haptics.tap()
        MedicationReminders.reconcileAll(ctx: ctx)
    }

    /// Annule la DERNIERE ligne d'une prise prevue: la precedente reprend la main.
    @MainActor static func undo(_ med: Medication, at: Date, all: [DoseEvent], ctx: ModelContext) {
        let k = DoseLog.key(at)
        guard let last = all.filter({ $0.medID == med.stableID && $0.scheduledAt.map(DoseLog.key) == k })
            .max(by: { $0.loggedAt < $1.loggedAt }) else { return }
        undo(event: last, ctx: ctx)
    }

    @MainActor static func undo(event: DoseEvent, ctx: ModelContext) {
        ctx.delete(event)
        LifeOSTry(try ctx.save(), context: "annulation prise", category: AppLog.data)
        MedicationReminders.reconcileAll(ctx: ctx)
    }

    /// Supprime un traitement ET ce qui lui appartient: prises, photos,
    /// rappels. Rend les fichiers effaces (verifie par les tests).
    @MainActor @discardableResult
    static func deleteMedication(_ med: Medication, ctx: ModelContext) -> [String] {
        let id = med.stableID
        if !id.isEmpty {
            let mine = (try? ctx.fetch(FetchDescriptor<DoseEvent>(predicate: #Predicate { $0.medID == id }))) ?? []
            mine.forEach { ctx.delete($0) }
        }
        let files = MedicalFiles.list(med.attachmentFiles)
        files.forEach { ImageStore.delete($0) }
        ctx.delete(med)
        LifeOSTry(try ctx.save(), context: "suppression medicament", category: AppLog.data)
        // La reconciliation relit la base: le medicament supprime n'y est plus,
        // donc tous ses rappels partent.
        MedicationReminders.reconcileAll(ctx: ctx)
        return files
    }

    @MainActor static func linkedCount(personID: String, ctx: ModelContext) -> Int {
        let m = (try? ctx.fetchCount(FetchDescriptor<Medication>(predicate: #Predicate { $0.personID == personID }))) ?? 0
        let a = (try? ctx.fetchCount(FetchDescriptor<MedicalAppointment>(predicate: #Predicate { $0.personID == personID }))) ?? 0
        let v = (try? ctx.fetchCount(FetchDescriptor<Vaccination>(predicate: #Predicate { $0.personID == personID }))) ?? 0
        return m + a + v
    }

    // MARK: Historique

    struct HistoryItem: Identifiable {
        let id: String
        let scheduledAt: Date?
        let status: DoseLog.Status
        let loggedAt: Date?
        let isPRN: Bool
    }

    /// Prises passees (prevues et notees) d'un traitement depuis `from`, la plus recente d'abord.
    static func history(_ med: Medication, events: [DoseLog.Event], from: Date?, now: Date,
                        calendar: Calendar = .current) -> [HistoryItem] {
        let rule = MedSchedule.rule(for: med, calendar: calendar)
        let lower = from ?? .distantPast
        let occ = MedSchedule.occurrences(rule, from: max(lower, rule.effectiveStart), to: now, calendar: calendar)
        let byKey = Dictionary(grouping: events.compactMap { e in e.scheduledAt.map { (DoseLog.key($0), e) } }, by: { $0.0 })
        var items: [HistoryItem] = DoseLog.slots(occurrences: occ, events: events, now: now)
            .filter { $0.status != .upcoming }
            .map { s in
                let logged = byKey[DoseLog.key(s.scheduledAt)]?.map(\.1).max(by: { $0.loggedAt < $1.loggedAt })?.loggedAt
                return HistoryItem(id: "s\(DoseLog.key(s.scheduledAt))", scheduledAt: s.scheduledAt, status: s.status,
                                   loggedAt: logged, isPRN: false)
            }
        let orphans = DoseLog.orphans(occurrences: occ, events: events).filter { ($0.scheduledAt ?? $0.loggedAt) >= lower }
        // Une seule ligne par prise prevue orpheline (la derniere), toutes les prises au besoin.
        let scheduledOrphans = Dictionary(grouping: orphans.filter { $0.scheduledAt != nil }, by: { DoseLog.key($0.scheduledAt!) })
            .compactMap { $0.value.max(by: { $0.loggedAt < $1.loggedAt }) }
        for e in scheduledOrphans {
            let st = DoseLog.status(at: e.scheduledAt!, events: [e], now: now)
            items.append(HistoryItem(id: "o\(DoseLog.key(e.scheduledAt!))", scheduledAt: e.scheduledAt, status: st,
                                     loggedAt: e.loggedAt, isPRN: false))
        }
        for e in orphans where e.scheduledAt == nil && e.status == "taken" {
            items.append(HistoryItem(id: "p\(e.loggedAt.timeIntervalSince1970)", scheduledAt: nil, status: .taken,
                                     loggedAt: e.loggedAt, isPRN: true))
        }
        return items.sorted { ($0.scheduledAt ?? $0.loggedAt ?? .distantPast) > ($1.scheduledAt ?? $1.loggedAt ?? .distantPast) }
    }

    static func adherence(_ med: Medication, events: [DoseLog.Event], from: Date?, now: Date,
                          calendar: Calendar = .current) -> DoseLog.Adherence {
        let rule = MedSchedule.rule(for: med, calendar: calendar)
        let lower = from ?? .distantPast
        let occ = MedSchedule.occurrences(rule, from: max(lower, rule.effectiveStart), to: now, calendar: calendar)
        let orphans = DoseLog.orphans(occurrences: occ, events: events).filter { ($0.scheduledAt ?? .distantPast) >= lower }
        return DoseLog.adherence(slots: DoseLog.slots(occurrences: occ, events: events, now: now), orphans: orphans)
    }

    static func csvRows(_ med: Medication, events: [DoseLog.Event], person: String, now: Date) -> [MedicalCSV.Row] {
        history(med, events: events, from: nil, now: now).map { h in
            let status: String
            switch h.status {
            case .taken: status = h.isPRN ? "Pris (au besoin)" : "Pris"
            case .skipped: status = "Sauté"
            case .snoozed: status = "Reporté"
            case .missed: status = "Manqué"
            case .due: status = "À prendre"
            case .upcoming: status = "À venir"
            }
            return MedicalCSV.Row(person: person, medication: med.name, dosage: med.dosage,
                                  scheduled: h.scheduledAt, status: status, logged: h.status.isLogged ? h.loggedAt : nil)
        }
    }
}

// MARK: - Médicaments

struct MedicationView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query(sort: \DoseEvent.loggedAt) private var events: [DoseEvent]
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    @AppStorage(personFilterKey) private var filter = MedicalPeople.everyone
    @State private var showAdd = false
    @State private var editing: Medication?
    @State private var detail: Medication?
    @State private var pendingDelete: Medication?
    @State private var period: VitalPeriod = .week

    private var visible: [Medication] { meds.filter { MedicalPeople.matches(filter: filter, personID: $0.personID) } }
    private var active: [Medication] { visible.filter { $0.active } }
    private var inactive: [Medication] { visible.filter { !$0.active } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if visible.isEmpty {
                        EmptyState(icon: "pills", title: "Aucun médicament",
                                   message: meds.isEmpty ? "Ajoute tes traitements en cours pour recevoir des rappels de prise."
                                                         : "Aucun traitement pour cette personne.")
                    } else {
                        refillCard
                        todayCard
                        adherenceCard
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { MedicalPersonFilterMenu() }
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") }
        }
        .sheet(isPresented: $showAdd) { MedicationEditor() }
        .sheet(item: $editing) { med in MedicationEditor(editing: med) }
        .sheet(item: $detail, onDismiss: {
            // Suppression APRES la fermeture: la fiche ouverte ne lit jamais un objet efface.
            if let m = pendingDelete { pendingDelete = nil; MedicalData.deleteMedication(m, ctx: ctx) }
        }) { med in
            MedicationDetailView(med: med) { pendingDelete = med; detail = nil }
        }
        // Remise a plat a chaque ouverture. C'est ce qui rattrape les
        // traitements enregistres avant que les rappels existent, ceux dont
        // la date de fin est passee, et une reinstallation de l'app.
        .onAppear { MedicationReminders.reconcileAll(ctx: ctx) }
    }

    // MARK: Aujourd'hui

    private struct TodayDose: Identifiable {
        let med: Medication
        let at: Date
        let status: DoseLog.Status
        var id: String { "\(ObjectIdentifier(med).hashValue)-\(DoseLog.key(at))" }
    }

    private var todayDoses: [TodayDose] {
        let now = Date.now
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
        return active.flatMap { med -> [TodayDose] in
            let rule = MedSchedule.rule(for: med)
            let occ = MedSchedule.occurrences(rule, from: start, to: end)
            return DoseLog.slots(occurrences: occ, events: MedicalData.events(of: med, in: events), now: now)
                .map { TodayDose(med: med, at: $0.scheduledAt, status: $0.status) }
        }
        .sorted { $0.at < $1.at }
    }

    private var prnMeds: [Medication] { active.filter { MedSchedule.rule(for: $0).kind == .prn } }

    @ViewBuilder private var todayCard: some View {
        let doses = todayDoses
        if !doses.isEmpty || !prnMeds.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Aujourd'hui", subtitle: "Note chaque prise : l'historique et le stock en dépendent.")
                ForEach(doses) { d in doseRow(d) }
                ForEach(prnMeds) { med in prnRow(med) }
            }.card()
        }
    }

    private func doseRow(_ d: TodayDose) -> some View {
        HStack(spacing: 10) {
            Text(d.at, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.med.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    MedicalPersonTag(personID: d.med.personID, people: people)
                }
                Text(d.status.label).font(.caption)
                    .foregroundStyle(d.status == .missed ? Theme.danger : d.status == .taken ? Theme.success : .secondary)
            }
            Spacer(minLength: 4)
            if d.status.isLogged {
                Button("Annuler") { MedicalData.undo(d.med, at: d.at, all: events, ctx: ctx) }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered)
            } else {
                Button { MedicalData.log(d.med, at: d.at, status: "taken", ctx: ctx) } label: {
                    Label("Pris", systemImage: "checkmark")
                }
                .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).tint(.medicalTint)
                Menu {
                    Button { MedicalData.log(d.med, at: d.at, status: "skipped", ctx: ctx) } label: { Label("Sauter cette prise", systemImage: "forward") }
                    ForEach([15, 30, 60], id: \.self) { m in
                        Button { MedicalData.log(d.med, at: d.at, status: "snoozed", snoozeMinutes: m, ctx: ctx) } label: {
                            Label(m == 60 ? "Reporter d'1 h" : "Reporter de \(m) min", systemImage: "clock.arrow.circlepath")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }
                .accessibilityLabel("Autres choix")
            }
        }
    }

    private func prnRow(_ med: Medication) -> some View {
        let start = Calendar.current.startOfDay(for: .now)
        let todayCount = events.filter { $0.medID == med.stableID && !med.stableID.isEmpty && $0.scheduledAt == nil
            && $0.status == "taken" && $0.loggedAt >= start }.count
        return HStack(spacing: 10) {
            Image(systemName: "hand.raised").frame(minWidth: 48, alignment: .leading).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(med.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    MedicalPersonTag(personID: med.personID, people: people)
                }
                Text(todayCount == 0 ? "Au besoin, rien noté aujourd'hui" : "Au besoin, \(todayCount) prise\(todayCount > 1 ? "s" : "") aujourd'hui")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { MedicalData.log(med, at: nil, status: "taken", ctx: ctx) } label: { Label("J'en prends", systemImage: "plus") }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered)
        }
    }

    // MARK: Stock et observance

    @ViewBuilder private var refillCard: some View {
        let low = active.filter { med in
            med.trackStock && MedicalData.stock(of: med, events: MedicalData.events(of: med, in: events)) <= med.refillThreshold
        }
        if !low.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Renouvellement à prévoir", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warning)
                ForEach(low) { med in
                    let s = MedicalData.stock(of: med, events: MedicalData.events(of: med, in: events))
                    Text("\(med.name) : \(Self.units(max(0, s))) restante\(s > 1 ? "s" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var adherenceCard: some View {
        let now = Date.now
        let from = period.start(now: now)
        var total = DoseLog.Adherence()
        var rows: [MedicalCSV.Row] = []
        let peopleList = people.map { ($0.stableID, $0.name) }
        for med in visible {
            let ev = MedicalData.events(of: med, in: events)
            let a = MedicalData.adherence(med, events: ev, from: from, now: now)
            total.taken += a.taken; total.skipped += a.skipped; total.missed += a.missed
            rows += MedicalData.csvRows(med, events: ev, person: MedicalPeople.name(for: med.personID, in: peopleList), now: now)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Observance")
                Spacer()
                ShareLink(item: MedicalCSVFile(text: MedicalCSV.adherence(rows)),
                          preview: SharePreview("Observance LifeOS")) {
                    Label("CSV", systemImage: "square.and.arrow.up")
                }
                .font(.caption.weight(.semibold))
                .disabled(rows.isEmpty)
            }
            Picker("Période", selection: $period) {
                ForEach(VitalPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            AdherenceSummary(adherence: total)
        }.card()
    }

    static func units(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v)) unité\(abs(v) > 1 ? "s" : "")" : String(format: "%.1f unités", v)
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
                    MedicalPersonTag(personID: med.personID, people: people)
                }
                Text(MedSchedule.summary(MedSchedule.rule(for: med))).font(.caption).foregroundStyle(.secondary)
                // Les notes (effets secondaires, consignes) etaient
                // enregistrees puis jamais affichees nulle part.
                if !med.notes.isEmpty {
                    Text(med.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if med.trackStock {
                    let s = MedicalData.stock(of: med, events: MedicalData.events(of: med, in: events))
                    Text("Stock : \(Self.units(max(0, s)))").font(.caption2).foregroundStyle(s <= med.refillThreshold ? Theme.warning : .secondary)
                }
                if let coverage = MedicationReminders.coverageText(for: med) {
                    Text(coverage).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { detail = med }
        .contextMenu {
            Button { editing = med } label: { Label("Modifier", systemImage: "pencil") }
            Button { MedicationActions.setActive(med, !med.active, ctx: ctx) } label: {
                Label(med.active ? "Terminer" : "Reprendre", systemImage: med.active ? "stop.circle" : "play.circle")
            }
            Button(role: .destructive) { MedicalData.deleteMedication(med, ctx: ctx) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }
}

enum MedicationActions {
    /// Terminer garde la trace du moment: aucune prise n'est attendue apres.
    /// Reprendre repart de maintenant: la pause n'est pas comptee en oublis.
    @MainActor static func setActive(_ med: Medication, _ on: Bool, ctx: ModelContext, now: Date = .now) {
        med.active = on
        if on { med.inactiveSince = nil; med.scheduleSince = now } else { med.inactiveSince = now }
        LifeOSTry(try ctx.save(), context: "bascule medicament", category: AppLog.data)
        Haptics.tap()
        MedicationReminders.reconcileAll(ctx: ctx)
    }
}

struct AdherenceSummary: View {
    let adherence: DoseLog.Adherence
    var body: some View {
        HStack(spacing: 0) {
            stat(adherence.rate.map { "\(Int(($0 * 100).rounded())) %" } ?? "n/d", "observance")
            stat("\(adherence.taken)", "prises")
            stat("\(adherence.skipped)", "sautées")
            stat("\(adherence.missed)", "manquées")
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

/// Fiche d'un traitement: horaires, stock, observance, historique, ordonnances.
struct MedicationDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DoseEvent.loggedAt) private var allEvents: [DoseEvent]
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    let med: Medication
    let onDelete: () -> Void
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var refill = false
    @State private var refillText = ""
    @State private var period: VitalPeriod = .month

    private var events: [DoseLog.Event] { MedicalData.events(of: med, in: allEvents) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if med.trackStock { stockCard }
                    statsCard
                    historyCard
                    if !MedicalFiles.list(med.attachmentFiles).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Ordonnances")
                            MedicalAttachmentStrip(files: MedicalFiles.list(med.attachmentFiles))
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Supprimer le traitement", systemImage: "trash").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
                .padding(Theme.pad)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle(med.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Modifier") { editing = true } }
            }
            .sheet(isPresented: $editing) { MedicationEditor(editing: med) }
            .confirmationDialog("Supprimer \(med.name) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { onDelete() }
            } message: { Text("Les prises notées, les photos d'ordonnance et les rappels partent avec.") }
            .alert("Renouvellement", isPresented: $refill) {
                TextField("Unités ajoutées", text: $refillText).keyboardType(.decimalPad)
                Button("Ajouter") { addRefill() }
                Button("Annuler", role: .cancel) {}
            } message: { Text("Combien d'unités viens-tu d'ajouter ?") }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(med.dosage.isEmpty ? med.name : "\(med.name) · \(med.dosage)").font(.headline)
                MedicalPersonTag(personID: med.personID, people: people)
            }
            Text(MedSchedule.summary(MedSchedule.rule(for: med))).font(.subheadline).foregroundStyle(.secondary)
            if let end = med.endDate {
                Text("Jusqu'au \(end.formatted(date: .abbreviated, time: .omitted)) inclus").font(.caption).foregroundStyle(.secondary)
            }
            if !med.notes.isEmpty { Text(med.notes).font(.caption).foregroundStyle(.secondary) }
            if let coverage = MedicationReminders.coverageText(for: med) {
                Text(coverage).font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Traitement en cours", isOn: Binding(get: { med.active }, set: { MedicationActions.setActive(med, $0, ctx: ctx) }))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var stockCard: some View {
        let s = MedicalData.stock(of: med, events: events)
        let rule = MedSchedule.rule(for: med)
        let days = DoseLog.daysLeft(stock: max(0, s), perDose: med.dosePerIntake, dosesPerDay: DoseLog.dosesPerDay(rule))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Stock")
            HStack(alignment: .firstTextBaseline) {
                Text(MedicationView.units(max(0, s))).font(.title3.weight(.semibold))
                Spacer()
                if let days { Text("≈ \(days) jour\(days > 1 ? "s" : "") au rythme prévu").font(.caption).foregroundStyle(.secondary) }
            }
            if s <= med.refillThreshold {
                Text("Sous ton seuil d'alerte (\(MedicationView.units(med.refillThreshold))) : pense à l'ordonnance.")
                    .font(.caption).foregroundStyle(Theme.warning)
            }
            Text("Calculé à partir des prises notées. Une prise annulée revient dans la boîte.")
                .font(.caption2).foregroundStyle(.tertiary)
            Button { refillText = ""; refill = true } label: { Label("J'ai renouvelé", systemImage: "plus.circle") }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statsCard: some View {
        let now = Date.now
        let a = MedicalData.adherence(med, events: events, from: period.start(now: now), now: now)
        let person = MedicalPeople.name(for: med.personID, in: people.map { ($0.stableID, $0.name) })
        let rows = MedicalData.csvRows(med, events: events, person: person, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Observance")
                Spacer()
                ShareLink(item: MedicalCSVFile(text: MedicalCSV.adherence(rows)), preview: SharePreview("Observance \(med.name)")) {
                    Label("CSV", systemImage: "square.and.arrow.up")
                }.font(.caption.weight(.semibold)).disabled(rows.isEmpty)
            }
            Picker("Période", selection: $period) {
                ForEach(VitalPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            AdherenceSummary(adherence: a)
        }.card()
    }

    private var historyCard: some View {
        let items = Array(MedicalData.history(med, events: events, from: nil, now: .now).prefix(60))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Historique", subtitle: items.isEmpty ? "Aucune prise passée pour l'instant." : nil)
            ForEach(items) { h in historyRow(h) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func historyRow(_ h: MedicalData.HistoryItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(h.isPRN ? "Au besoin" : (h.scheduledAt?.formatted(date: .abbreviated, time: .shortened) ?? ""))
                    .font(.subheadline.weight(.medium))
                Group {
                    if h.status.isLogged, let l = h.loggedAt {
                        Text("\(h.status.label), notée le \(l.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text(h.status.label)
                    }
                }
                .font(.caption)
                .foregroundStyle(h.status == .missed ? Theme.danger : .secondary)
            }
            Spacer(minLength: 4)
            if h.status.isLogged {
                Button("Annuler") { undo(h) }.font(.caption.weight(.semibold)).buttonStyle(.bordered)
            } else if let at = h.scheduledAt {
                Button("Pris en retard") { MedicalData.log(med, at: at, status: "taken", ctx: ctx) }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered)
            }
        }
    }

    private func undo(_ h: MedicalData.HistoryItem) {
        if let at = h.scheduledAt {
            MedicalData.undo(med, at: at, all: allEvents, ctx: ctx)
        } else if let l = h.loggedAt,
                  let e = allEvents.first(where: { $0.medID == med.stableID && $0.scheduledAt == nil && $0.loggedAt == l }) {
            MedicalData.undo(event: e, ctx: ctx)
        }
    }

    /// Le renouvellement repart d'un compte neuf: stock courant + ajout, date de maintenant.
    private func addRefill() {
        guard let add = Double(refillText.replacingOccurrences(of: ",", with: ".")), add > 0 else { return }
        let now = Date.now
        med.stockCount = max(0, MedicalData.stock(of: med, events: events)) + add
        med.stockSetAt = now
        LifeOSTry(try ctx.save(), context: "renouvellement medicament", category: AppLog.data)
        MedicationReminders.reconcileAll(ctx: ctx)
    }
}

struct MedicationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DoseEvent.loggedAt) private var allEvents: [DoseEvent]
    /// Medicament a modifier; nil pour un ajout.
    var editing: Medication? = nil
    @State private var loaded = false
    @State private var name = ""
    @State private var dosage = ""
    @State private var notes = ""
    @State private var personID = ""
    @State private var kind: MedSchedule.Kind = .daily
    @State private var times: [Int] = [MedicationSchedule.defaultMorning * 60]
    @State private var weekdays: Set<Int> = []
    @State private var intervalDays = 2
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var dosePerIntake = 1.0
    @State private var trackStock = false
    @State private var stockText = ""
    @State private var initialStockText = ""
    @State private var threshold = 7.0
    @State private var files = MedicalFiles.Draft(raw: "")

    var body: some View {
        NavigationStack {
            Form {
                Section("Médicament") {
                    TextField("Nom (ex: Doliprane)", text: $name)
                    TextField("Dosage (ex: 500mg)", text: $dosage)
                    MedicalPersonPicker(personID: $personID)
                }
                scheduleSection
                Section("Durée") {
                    DatePicker("Début le", selection: $startDate, displayedComponents: .date)
                    Toggle("Date de fin", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("Fin le", selection: $endDate, in: startDate..., displayedComponents: .date) }
                }
                stockSection
                Section("Notes") {
                    TextField("Effets secondaires, instructions…", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                MedicalAttachmentsSection(title: "Ordonnance", prefix: "rx", draft: $files)
            }
            .navigationTitle(editing == nil ? "Nouveau médicament" : "Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { save() }.disabled(invalidReason != nil)
                }
            }
            .interactiveDismissDisabled(!files.deletedOnCancel.isEmpty)
            .onAppear(perform: load)
        }
    }

    // MARK: Horaires

    private var scheduleSection: some View {
        Section {
            Picker("Rythme", selection: $kind) {
                ForEach(MedSchedule.Kind.allCases) { Text($0.label).tag($0) }
            }
            if kind == .weekdays { weekdayChips }
            if kind == .interval {
                Stepper("Tous les \(intervalDays) jours", value: $intervalDays, in: 2...60)
            }
            if kind != .prn {
                ForEach(times.indices, id: \.self) { i in
                    HStack {
                        DatePicker("Prise \(i + 1)", selection: timeBinding(i), displayedComponents: .hourAndMinute)
                        if times.count > 1 {
                            Button { times.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger) }
                                .buttonStyle(.plain).accessibilityLabel("Retirer cette heure")
                        }
                    }
                }
                if times.count < MedSchedule.maxTimes {
                    Button { addTime() } label: { Label("Ajouter une heure", systemImage: "plus.circle") }
                }
            }
            Stepper("Unités par prise : \(Self.format(dosePerIntake))", value: $dosePerIntake, in: 0.5...20, step: 0.5)
        } header: {
            Text("Prise")
        } footer: {
            // On annonce exactement ce qui va sonner: un ecran qui
            // promet "des rappels" sans dire lesquels ne se verifie pas.
            Text(invalidReason ?? reminderSummary)
        }
    }

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(MedSchedule.weekdayOrder, id: \.self) { wd in
                let on = weekdays.contains(wd)
                Button {
                    if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                } label: {
                    Text(String(MedSchedule.weekdayShort[wd]?.prefix(2) ?? ""))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(on ? Color.medicalTint : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MedSchedule.weekdayShort[wd] ?? "")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func timeBinding(_ i: Int) -> Binding<Date> {
        Binding(get: {
            let m = i < times.count ? times[i] : 0
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
        }, set: { d in
            guard i < times.count else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            times[i] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    private func addTime() {
        let next = min(1439, (times.max() ?? 420) + 240)
        times.append(times.contains(next) ? 1200 : next)
    }

    private var draftRule: MedSchedule.Rule {
        MedSchedule.Rule(kind: kind, minutes: kind == .prn ? [] : MedSchedule.normalize(times), weekdays: weekdays,
                         intervalDays: kind == .interval ? intervalDays : 1, anchor: startDate,
                         effectiveStart: startDate, end: hasEndDate ? endDate : nil, stop: nil)
    }

    private var invalidReason: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Donne un nom au médicament." }
        if kind != .prn && MedSchedule.normalize(times).isEmpty { return "Ajoute au moins une heure de prise." }
        if kind == .weekdays && weekdays.isEmpty { return "Choisis au moins un jour." }
        if trackStock && Double(stockText.replacingOccurrences(of: ",", with: ".")) == nil {
            return "Indique combien d'unités il te reste pour suivre le stock."
        }
        return nil
    }

    private var reminderSummary: String {
        if kind == .prn {
            return "Aucun rappel : un traitement à prendre au besoin ne se rappelle pas à heure fixe. Note chaque prise dans « Aujourd'hui »."
        }
        return "Rappel : \(MedSchedule.summary(draftRule).lowercased())."
    }

    // MARK: Stock

    private var stockSection: some View {
        Section {
            Toggle("Suivre le stock", isOn: $trackStock)
            if trackStock {
                TextField("Unités restantes (ex: 30)", text: $stockText).keyboardType(.decimalPad)
                Stepper("Alerte sous \(Self.format(threshold)) unités", value: $threshold, in: 0...200, step: 1)
            }
        } header: { Text("Stock") } footer: {
            if trackStock {
                Text("Chaque prise notée retire \(Self.format(dosePerIntake)) unité\(dosePerIntake > 1 ? "s" : "") du stock. Une notification part quand le stock passera sous le seuil.")
            }
        }
    }

    static func format(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }

    // MARK: Chargement et enregistrement

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let med = editing else {
            weekdays = [Calendar.current.component(.weekday, from: .now)]
            return
        }
        name = med.name; dosage = med.dosage; notes = med.notes; personID = med.personID
        // Une ancienne fiche ("2x/jour", heures matin/soir) est convertie ici:
        // les memes heures, au meme rythme, sans rien changer aux rappels.
        let rule = MedSchedule.rule(for: med)
        kind = rule.kind
        times = rule.minutes.isEmpty ? [MedicationSchedule.defaultMorning * 60] : rule.minutes
        weekdays = rule.weekdays.isEmpty ? [Calendar.current.component(.weekday, from: med.startDate)] : rule.weekdays
        intervalDays = max(2, rule.intervalDays)
        startDate = med.startDate
        hasEndDate = med.endDate != nil
        endDate = med.endDate ?? Date()
        dosePerIntake = med.dosePerIntake
        trackStock = med.trackStock
        let current = max(0, MedicalData.stock(of: med, events: MedicalData.events(of: med, in: allEvents)))
        stockText = med.trackStock ? Self.format(current) : ""
        initialStockText = stockText
        threshold = med.refillThreshold
        files = MedicalFiles.Draft(raw: med.attachmentFiles)
    }

    private func cancel() {
        files.deletedOnCancel.forEach { ImageStore.delete($0) }
        dismiss()
    }

    private func save() {
        guard invalidReason == nil else { return }
        let now = Date.now
        let med: Medication
        let isNew = editing == nil
        if let e = editing { med = e } else {
            med = Medication(name: name, startDate: startDate)
            med.stableID = UUID().uuidString
            ctx.insert(med)
        }
        let before = isNew ? nil : MedSchedule.rule(for: med)
        med.name = name.trimmingCharacters(in: .whitespaces); med.dosage = dosage; med.notes = notes
        med.personID = personID
        med.scheduleKind = kind.rawValue
        med.doseMinutes = kind == .prn ? "" : MedSchedule.encodeMinutes(times)
        med.weekdays = kind == .weekdays ? MedSchedule.encodeWeekdays(weekdays) : ""
        med.intervalDays = kind == .interval ? intervalDays : 1
        med.startDate = startDate
        med.endDate = hasEndDate ? endDate : nil
        let rule = MedSchedule.rule(for: med)
        // Texte lisible garde dans `frequency` (export, autres ecrans).
        med.frequency = MedSchedule.summary(rule)
        med.hourMorning = rule.minutes.first.map { $0 / 60 }
        med.hourEvening = rule.minutes.count > 1 ? rule.minutes.last.map { $0 / 60 } : nil
        // L'ancien horaire n'est pas garde: les prises "manquees" ne se
        // deduisent qu'a partir du nouveau, jamais retroactivement.
        if isNew || before.map({ $0.kind != rule.kind || $0.minutes != rule.minutes || $0.weekdays != rule.weekdays
            || $0.intervalDays != rule.intervalDays || $0.anchor != rule.anchor }) == true {
            med.scheduleSince = now
        }
        med.dosePerIntake = dosePerIntake
        let wasTracking = med.trackStock
        med.trackStock = trackStock
        med.refillThreshold = threshold
        if trackStock, let v = Double(stockText.replacingOccurrences(of: ",", with: ".")),
           !wasTracking || stockText != initialStockText {
            med.stockCount = max(0, v)
            med.stockSetAt = now
        }
        files.deletedOnSave.forEach { ImageStore.delete($0) }
        med.attachmentFiles = files.raw
        LifeOSTry(try ctx.save(), context: isNew ? "ajout medicament" : "modification medicament", category: AppLog.data)
        MedicationReminders.reconcileAll(ctx: ctx)
        dismiss()
    }
}

// MARK: - Rappels de prise

/// Pose et retire les rappels d'un medicament.
///
/// Sorti de la vue parce que plusieurs endroits en ont besoin: l'ajout, le
/// basculement actif/termine, chaque prise notee, et la remise a plat a
/// l'ouverture de l'ecran. Plusieurs copies auraient derive.
enum MedicationReminders {

    static let identifierPrefix = "med."

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
    /// Les prises notees, les reports et le stock viennent des DoseEvent.
    @MainActor
    static func reconcileAll(ctx: ModelContext, now: Date = .now) {
        let meds = (try? ctx.fetch(FetchDescriptor<Medication>())) ?? []
        let allEvents = (try? ctx.fetch(FetchDescriptor<DoseEvent>())) ?? []
        let people = ((try? ctx.fetch(FetchDescriptor<MedicalPerson>())) ?? []).map { ($0.stableID, $0.name) }
        var items: [MedicationBudget.Item] = []
        var requests: [String: UNNotificationRequest] = [:]
        for med in meds {
            let id = MedicalData.ensureID(med, ctx: ctx)
            let base = "\(identifierPrefix)\(id)"
            let events = allEvents.filter { $0.medID == id }.map(MedicalData.snapshot)
            let person = med.personID.isEmpty ? "" : MedicalPeople.name(for: med.personID, in: people)
            for r in Self.requests(for: med, base: base, now: now, events: events, personName: person) {
                let date = (r.trigger as? UNCalendarNotificationTrigger).flatMap { $0.repeats ? nil : $0.nextTriggerDate() }
                items.append(.init(medID: id, identifier: r.identifier, fireDate: date))
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
        case "none":
            return MedSchedule.rule(for: med).kind == .prn ? nil : "Aucun rappel programmé (plus de place ou traitement terminé)."
        default:
            guard raw.hasPrefix("until:"), let t = Double(raw.dropFirst(6)) else { return nil }
            let d = Date(timeIntervalSince1970: t)
            return "Rappels programmés jusqu'au \(d.formatted(date: .abbreviated, time: .shortened)). Ouvre LifeOS avant pour prolonger."
        }
    }

    /// Notifications d'un traitement: prises, reports en cours, alerte de stock.
    static func requests(for med: Medication, base: String, now: Date = .now,
                         events: [DoseLog.Event] = [], personName: String = "",
                         calendar cal: Calendar = .current) -> [UNNotificationRequest] {
        let rule = MedSchedule.rule(for: med, calendar: cal)
        // Prises deja notees (prises, sautees, reportees): on ne les rappelle plus.
        let handled = Set(events.compactMap(\.scheduledAt))
        let plan = MedSchedule.reminderPlan(rule, active: med.active, now: now, horizonDays: planningHorizonDays,
                                            maxDates: MedicationBudget.systemLimit, handled: handled, calendar: cal)
        let title = personName.isEmpty ? "Prendre \(med.name)" : "\(personName) : \(med.name)"
        let detail = med.dosage.isEmpty ? MedSchedule.summary(rule) : med.dosage
        func content(_ body: String, title t: String) -> UNMutableNotificationContent {
            let c = UNMutableNotificationContent()
            c.title = t; c.body = body; c.sound = .default
            return c
        }
        func dated(_ id: String, _ at: Date, _ c: UNMutableNotificationContent) -> UNNotificationRequest {
            // Composantes SANS fuseau: 8 h reste 8 h a l'heure locale apres un
            // voyage ou un changement d'heure.
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            return UNNotificationRequest(identifier: id, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
        var out: [UNNotificationRequest] = []
        switch plan {
        case .none:
            break
        case .repeating(let slots):
            out = slots.enumerated().map { i, s in
                var comps = DateComponents(); comps.hour = s.hour; comps.minute = s.minute
                if let wd = s.weekday { comps.weekday = wd }
                let label = MedSchedule.label(minute: s.hour * 60 + s.minute)
                return UNNotificationRequest(identifier: "\(base).\(i)", content: content("\(detail), \(label)", title: title),
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
            }
        case .dates(let dates):
            out = dates.enumerated().map { i, at in dated("\(base).d\(i)", at, content(detail, title: title)) }
        }
        guard med.active else { return out }
        // Reports en cours: seul le DERNIER etat de la prise compte.
        let scheduled = events.filter { $0.scheduledAt != nil }
        for (k, group) in Dictionary(grouping: scheduled, by: { DoseLog.key($0.scheduledAt!) }) {
            guard let last = group.max(by: { $0.loggedAt < $1.loggedAt }), last.status == "snoozed",
                  let until = last.snoozedUntil, until > now else { continue }
            out.append(dated("\(base).s\(k)", until, content("Prise reportée. \(detail)", title: title)))
        }
        // Alerte de stock: au moment ou la prise prevue fera passer sous le seuil.
        if med.trackStock {
            let stock = DoseLog.stock(initial: med.stockCount, setAt: med.stockSetAt, events: events)
            let horizon = cal.date(byAdding: .day, value: planningHorizonDays, to: now) ?? now
            let upcoming = MedSchedule.occurrences(rule, from: now, to: horizon, calendar: cal).filter { $0 > now }
            if let at = DoseLog.refillDate(stock: stock, threshold: med.refillThreshold, perDose: med.dosePerIntake, upcoming: upcoming) {
                out.append(dated("\(base).refill", at,
                                 content("Le stock passe sous ton seuil d'alerte. Pense à renouveler l'ordonnance.",
                                         title: "Renouvellement \(med.name)")))
            }
        }
        return out
    }
}

// MARK: - Rendez-vous médicaux

enum AppointmentReminder {
    @MainActor static func schedule(_ apt: MedicalAppointment, personName: String) {
        guard AppointmentStatus(rawValue: apt.status) != .cancelled,
              let r = MedicalReminderTiming.appointment(apt.date) else { return }
        let who = personName.isEmpty ? "" : "\(personName) : "
        NotificationManager.shared.schedule(
            id: ReminderIDs.appointment(apt.date),
            title: r.dayBefore ? "\(who)RDV \(apt.specialty) demain" : "\(who)RDV \(apt.specialty) dans 2 h",
            body: apt.doctorName.isEmpty ? apt.location : "\(apt.doctorName) · \(apt.location)",
            at: r.at
        )
    }

    static func cancel(_ apt: MedicalAppointment) {
        NotificationManager.shared.cancel(id: ReminderIDs.appointment(apt.date))
    }
}

struct AppointmentsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MedicalAppointment.date) private var appointments: [MedicalAppointment]
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    @AppStorage(personFilterKey) private var filter = MedicalPeople.everyone
    @State private var showAdd = false
    @State private var editing: MedicalAppointment?
    @State private var byPractitioner = false

    private var visible: [MedicalAppointment] { appointments.filter { MedicalPeople.matches(filter: filter, personID: $0.personID) } }
    private func status(_ a: MedicalAppointment) -> AppointmentStatus { AppointmentStatus.effective(stored: a.status, date: a.date, now: .now) }
    private var upcoming: [MedicalAppointment] { visible.filter { status($0) == .planned || status($0) == .confirmed } }
    private var past: [MedicalAppointment] { visible.filter { status($0) == .done }.reversed() }
    private var cancelled: [MedicalAppointment] { visible.filter { status($0) == .cancelled }.reversed() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if visible.isEmpty {
                        EmptyState(icon: "stethoscope", title: "Aucun RDV",
                                   message: appointments.isEmpty ? "Note tes rendez-vous médicaux pour ne rien oublier."
                                                                 : "Aucun rendez-vous pour cette personne.")
                    } else {
                        Picker("Vue", selection: $byPractitioner) {
                            Text("Agenda").tag(false)
                            Text("Par praticien").tag(true)
                        }.pickerStyle(.segmented)
                        if byPractitioner { practitionerList } else { agenda }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Rendez-vous").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { MedicalPersonFilterMenu() }
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") }
        }
        .sheet(isPresented: $showAdd) { AppointmentEditor() }
        .sheet(item: $editing) { apt in AppointmentEditor(editing: apt) }
    }

    @ViewBuilder private var agenda: some View {
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
        if !cancelled.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Annulés")
                ForEach(cancelled) { apt in apptRow(apt) }
            }.card()
        }
    }

    private var practitionerList: some View {
        let groups = AppointmentHistory.byPractitioner(visible.map {
            AppointmentHistory.Entry(date: $0.date, doctor: $0.doctorName, specialty: $0.specialty, notes: $0.notes,
                                     cancelled: AppointmentStatus(rawValue: $0.status) == .cancelled,
                                     files: MedicalFiles.list($0.attachmentFiles).count)
        }, now: .now)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Historique des consultations", subtitle: groups.isEmpty ? "Aucune consultation passée." : nil)
            ForEach(groups, id: \.key) { g in
                DisclosureGroup {
                    ForEach(Array(g.visits.enumerated()), id: \.offset) { _, v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(v.date.formatted(date: .abbreviated, time: .shortened)) · \(v.specialty)")
                                .font(.caption.weight(.semibold))
                            if !v.notes.isEmpty { Text(v.notes).font(.caption).foregroundStyle(.secondary) }
                            if v.files > 0 { Label("\(v.files) document\(v.files > 1 ? "s" : "")", systemImage: "paperclip").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).font(.subheadline.weight(.semibold))
                        Text("\(g.subtitle) · \(g.visits.count) consultation\(g.visits.count > 1 ? "s" : ""), dernière le \(g.visits[0].date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.card()
    }

    private func personName(_ id: String) -> String {
        id.isEmpty ? "" : MedicalPeople.name(for: id, in: people.map { ($0.stableID, $0.name) })
    }

    private func apptRow(_ apt: MedicalAppointment) -> some View {
        let st = status(apt)
        let files = MedicalFiles.list(apt.attachmentFiles)
        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(apt.date, format: .dateTime.day()).font(.title3.bold()).foregroundStyle(.medicalTint)
                Text(apt.date, format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(apt.specialty).font(.subheadline.weight(.semibold)).strikethrough(st == .cancelled)
                    MedicalPersonTag(personID: apt.personID, people: people)
                }
                Text("\(apt.date.formatted(date: .omitted, time: .shortened)) · \(st.label)").font(.caption)
                    .foregroundStyle(st == .confirmed ? Theme.success : st == .cancelled ? Theme.danger : .secondary)
                if !apt.doctorName.isEmpty { Text(apt.doctorName).font(.caption).foregroundStyle(.secondary) }
                if !apt.location.isEmpty { Label(apt.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                // Motif, resultats, ordonnances: saisis puis jamais montres.
                if !apt.notes.isEmpty { Text(apt.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                if !files.isEmpty { Label("\(files.count) document\(files.count > 1 ? "s" : "")", systemImage: "paperclip").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if let next = apt.nextDate, next > .now {
                VStack(spacing: 0) {
                    Text("Prochain").font(.caption2).foregroundStyle(.secondary)
                    Text(next, format: .dateTime.day().month(.abbreviated)).font(.caption.bold()).foregroundStyle(.medicalTint)
                }
            }
        }
        .opacity(st == .cancelled ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editing = apt }
        .contextMenu {
            Button { editing = apt } label: { Label("Modifier", systemImage: "pencil") }
            if st == .planned {
                Button { setStatus(apt, .confirmed) } label: { Label("Confirmé par le cabinet", systemImage: "checkmark.seal") }
            }
            if st == .confirmed {
                Button { setStatus(apt, .planned) } label: { Label("Remettre en prévu", systemImage: "calendar") }
            }
            if st == .planned || st == .confirmed {
                Button { setStatus(apt, .cancelled) } label: { Label("Annuler le RDV", systemImage: "xmark.circle") }
            }
            if st == .cancelled && apt.date > .now {
                Button { setStatus(apt, .planned) } label: { Label("Rétablir", systemImage: "arrow.uturn.backward") }
            }
            Button(role: .destructive) {
                // Sans ca, le rappel de la veille sonnait pour un rendez
                // vous annule, et rien ne permettait de le faire taire.
                AppointmentReminder.cancel(apt)
                MedicalFiles.list(apt.attachmentFiles).forEach { ImageStore.delete($0) }
                ctx.delete(apt)
                MedicalData.save(ctx, "suppression rdv")
            } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func setStatus(_ apt: MedicalAppointment, _ s: AppointmentStatus) {
        apt.status = s.rawValue
        AppointmentReminder.cancel(apt)
        if s != .cancelled { AppointmentReminder.schedule(apt, personName: personName(apt.personID)) }
        LifeOSTry(try ctx.save(), context: "statut rdv", category: AppLog.data)
        Haptics.tap()
    }
}

struct AppointmentEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
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
    @State private var personID = ""
    @State private var status: AppointmentStatus = .planned
    @State private var files = MedicalFiles.Draft(raw: "")

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
                    MedicalPersonPicker(personID: $personID)
                } footer: {
                    // Un rendez-vous a moins de 24 h n'avait aucun rappel, en
                    // silence. On dit ce qui va sonner, ou que rien ne sonnera.
                    Text(reminderLine)
                }
                Section {
                    Picker("Statut", selection: $status) {
                        Text(AppointmentStatus.planned.label).tag(AppointmentStatus.planned)
                        Text(AppointmentStatus.confirmed.label).tag(AppointmentStatus.confirmed)
                        Text(AppointmentStatus.cancelled.label).tag(AppointmentStatus.cancelled)
                    }
                } footer: {
                    Text("LifeOS ne réserve rien chez le praticien : ce statut est celui que tu indiques. Un RDV passé devient « Passé » tout seul.")
                }
                Section("Notes") {
                    TextField("Motif, résultats, ordonnances…", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                MedicalAttachmentsSection(title: "Documents", prefix: "rdv", draft: $files)
                Section("Suivi") {
                    Toggle("Planifier prochain RDV", isOn: $hasNext)
                    if hasNext { DatePicker("Prochain RDV", selection: $nextDate, displayedComponents: .date) }
                }
            }
            .navigationTitle(editing == nil ? "Nouveau RDV" : "Modifier le RDV").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { save() }
                }
            }
            .interactiveDismissDisabled(!files.deletedOnCancel.isEmpty)
            .onAppear(perform: load)
        }
    }

    private var reminderLine: String {
        if status == .cancelled { return "Pas de rappel : le rendez-vous est annulé." }
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
        location = apt.location; notes = apt.notes; personID = apt.personID
        hasNext = apt.nextDate != nil
        nextDate = apt.nextDate ?? Date()
        let s = AppointmentStatus(rawValue: apt.status) ?? .planned
        status = s == .done ? .planned : s
        files = MedicalFiles.Draft(raw: apt.attachmentFiles)
    }

    private func cancel() {
        files.deletedOnCancel.forEach { ImageStore.delete($0) }
        dismiss()
    }

    private func save() {
        let s = specialty.isEmpty ? "Généraliste" : specialty
        let apt: MedicalAppointment
        if let e = editing {
            // L'ancien rappel porte l'ancienne date dans son identifiant.
            AppointmentReminder.cancel(e)
            apt = e
        } else {
            apt = MedicalAppointment()
            ctx.insert(apt)
        }
        apt.date = date; apt.specialty = s; apt.doctorName = doctorName
        apt.location = location; apt.notes = notes; apt.nextDate = hasNext ? nextDate : nil
        apt.personID = personID
        apt.status = status.rawValue
        files.deletedOnSave.forEach { ImageStore.delete($0) }
        apt.attachmentFiles = files.raw
        LifeOSTry(try ctx.save(), context: "enregistrement rdv", category: AppLog.data)
        let who = personID.isEmpty ? "" : MedicalPeople.name(for: personID, in: people.map { ($0.stableID, $0.name) })
        AppointmentReminder.schedule(apt, personName: who)
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

enum VitalTypes {
    static let all = ["poids", "tension", "glycémie", "fréquence cardiaque", "température", "SpO2", "sommeil"]

    static func label(_ t: String) -> String {
        switch t {
        case "poids": return "Poids"
        case "tension": return "Tension"
        case "glycémie": return "Glycémie"
        case "fréquence cardiaque": return "Cœur"
        case "température": return "Température"
        case "SpO2": return "SpO2"
        case "sommeil": return "Sommeil"
        default: return t.capitalized
        }
    }

    static func longLabel(_ t: String) -> String {
        switch t {
        case "fréquence cardiaque": return "Fréquence cardiaque"
        case "SpO2": return "Saturation en oxygène (SpO2)"
        case "sommeil": return "Sommeil (durée)"
        default: return label(t)
        }
    }
}

/// Import des mesures qu'Apple Santé expose deja a l'app (poids, FC au repos,
/// sommeil de la nuit). Rien n'est invente: une absence de donnee reste une
/// absence, jamais un zero.
enum VitalHealthImport {
    @MainActor static func run(ctx: ModelContext, existing: [VitalRecord]) async -> String {
        let hs = HealthService.shared
        guard hs.isAvailable else {
            return "Apple Santé n'est pas disponible sur cet appareil. La saisie manuelle reste possible."
        }
        _ = await hs.requestAuthorization()
        var keys = existing.map { (type: $0.type, date: $0.date) }
        var added = 0
        func insert(_ type: String, _ date: Date, _ value: Double, sameDay: Bool, notes: String = "") {
            guard !VitalSource.isDuplicate(type: type, date: date, existing: keys, sameDay: sameDay) else { return }
            let rec = VitalRecord(date: date, type: type, value: value, unit: VitalUnits.canonicalUnit(type), notes: notes)
            rec.source = VitalSource.health
            ctx.insert(rec)
            keys.append((type, date))
            added += 1
        }
        if let w = await hs.latestBodyMass() { insert("poids", w.date, (w.kg * 10).rounded() / 10, sameDay: false) }
        if let hr = await hs.restingHeartRateSample() { insert("fréquence cardiaque", hr.date, hr.value.rounded(), sameDay: false, notes: "FC au repos") }
        if let h = await hs.sleepHoursLastNight(), h > 0 {
            insert("sommeil", Calendar.current.startOfDay(for: .now), (h * 10).rounded() / 10, sameDay: true)
        }
        LifeOSTry(try ctx.save(), context: "import sante", category: AppLog.data)
        if added == 0 {
            return "Rien de nouveau à importer. Si tu attendais des données, vérifie l'accès dans Réglages > Santé > Accès aux données > LifeOS."
        }
        return "\(added) mesure\(added > 1 ? "s" : "") importée\(added > 1 ? "s" : "") depuis Apple Santé."
    }
}

struct VitalsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \VitalRecord.date, order: .reverse) private var records: [VitalRecord]
    @AppStorage("vitals.glucoseUnit") private var glucoseUnit = "g/L"
    @AppStorage("vitals.weightUnit") private var weightUnit = "kg"
    @State private var showAdd = false
    @State private var editing: VitalRecord?
    @State private var selectedType = "poids"
    @State private var period: VitalPeriod = .month
    @State private var importing = false
    @State private var importMessage: String?

    private var ofType: [VitalRecord] { records.filter { $0.type == selectedType } }
    private var filtered: [VitalRecord] { ofType.filter { period.contains($0.date, now: .now) } }
    private var displayUnit: String { VitalUnits.displayUnit(selectedType, glucose: glucoseUnit, weight: weightUnit) }
    private func shown(_ v: Double) -> Double { VitalUnits.toDisplay(v, type: selectedType, glucose: glucoseUnit, weight: weightUnit) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    typeChips
                    Picker("Période", selection: $period) {
                        ForEach(VitalPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.pad)

                    if let importMessage {
                        Text(importMessage).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card().padding(.horizontal, Theme.pad)
                    }
                    referenceCard.padding(.horizontal, Theme.pad)

                    if filtered.isEmpty {
                        EmptyState(icon: "waveform.path.ecg", title: "Aucune mesure",
                                   message: ofType.isEmpty ? "Enregistre ta première mesure de \(VitalTypes.label(selectedType).lowercased())."
                                                           : "Aucune mesure sur cette période. Essaie « Tout ».")
                    } else {
                        if filtered.count >= 2 {
                            trendCard.padding(.horizontal, Theme.pad)
                        }
                        VStack(spacing: 8) {
                            ForEach(filtered) { r in vitalRow(r) }
                        }.card().padding(.horizontal, Theme.pad)
                    }
                }.padding(.vertical, Theme.pad)
            }
        }
        .navigationTitle("Carnet de santé").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") }
        }
        .sheet(isPresented: $showAdd) { VitalEditor(defaultType: selectedType) }
        .sheet(item: $editing) { r in VitalEditor(defaultType: r.type, editing: r) }
    }

    private var optionsMenu: some View {
        Menu {
            Button { runImport() } label: { Label("Importer depuis Santé", systemImage: "heart.text.square") }
                .disabled(importing)
            Picker("Glycémie", selection: $glucoseUnit) {
                Text("Glycémie en g/L").tag("g/L")
                Text("Glycémie en mmol/L").tag("mmol/L")
            }
            Picker("Poids", selection: $weightUnit) {
                Text("Poids en kg").tag("kg")
                Text("Poids en lb").tag("lb")
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("Options")
    }

    private func runImport() {
        importing = true
        importMessage = "Import en cours…"
        Task { @MainActor in
            importMessage = await VitalHealthImport.run(ctx: ctx, existing: records)
            importing = false
        }
    }

    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VitalTypes.all, id: \.self) { t in
                    let on = t == selectedType
                    Button { selectedType = t } label: {
                        Text(VitalTypes.label(t)).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? Color.medicalTint : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }.padding(.horizontal, Theme.pad)
        }
    }

    @ViewBuilder private var referenceCard: some View {
        if let r = VitalReference.range(selectedType) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Repère général", systemImage: "info.circle").font(.caption.weight(.semibold))
                Text(referenceText(r)).font(.caption)
                Text("Source : \(r.source). Ce n'est pas un diagnostic : ton médecin reste la référence.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else if selectedType == "poids" {
            Text("Pas de repère pour le poids seul : il dépend de la taille.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    /// Le texte du repere est ecrit en g/L: en mmol/L on donne les bornes converties.
    private func referenceText(_ r: VitalReference.Range) -> String {
        guard selectedType == "glycémie", glucoseUnit == "mmol/L" else { return r.text }
        let lo = r.low.map { VitalUnits.format(shown($0), type: selectedType, displayUnit: displayUnit) } ?? ""
        let hi = r.high.map { VitalUnits.format(shown($0), type: selectedType, displayUnit: displayUnit) } ?? ""
        let dia = VitalUnits.format(shown(1.26), type: selectedType, displayUnit: displayUnit)
        return "À jeun : \(lo) à \(hi) mmol/L. Diabète à partir de \(dia) mmol/L à jeun, contrôlé deux fois."
    }

    private var isTension: Bool { selectedType == "tension" }

    private var trendCard: some View {
        let data = filtered.sorted { $0.date < $1.date }
        let sys = data.map { shown($0.value) }
        // La diastolique (value2) etait ignoree: graphe et ecart ne
        // montraient que la systolique.
        let dia = isTension ? data.compactMap(\.value2) : []
        let all = sys + dia
        let minV = all.min() ?? 0
        let maxV = all.max() ?? 1
        let pad = Swift.max((maxV - minV) * 0.15, 0.5)
        let delta = (sys.last ?? 0) - (sys.first ?? 0)
        let diaPairs = data.filter { $0.value2 != nil }
        let deltaDia: Double? = isTension && diaPairs.count >= 2
            ? (diaPairs.last?.value2 ?? 0) - (diaPairs.first?.value2 ?? 0) : nil
        let unit = displayUnit
        let tone = VitalTrend.tone(type: selectedType, deltas: [delta] + (deltaDia.map { [$0] } ?? []))
        let deltaText = deltaDia.map { String(format: "%+.0f / %+.0f %@", delta, $0, unit) }
            ?? String(format: "%+.\(VitalUnits.decimals(selectedType, displayUnit: unit))f %@", delta, unit)

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
                        yEnd: .value("Valeur", shown(r.value))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("Date", r.date),
                        y: .value("Valeur", shown(r.value))
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
                    Text(String(format: "Sys %.0f à %.0f", sys.min() ?? 0, sys.max() ?? 0))
                    Spacer()
                    Text("\(data.count) mesures")
                    Spacer()
                    if let lo = dia.min(), let hi = dia.max() {
                        Text(String(format: "Dia %.0f à %.0f", lo, hi))
                    }
                } else {
                    Text("Min \(VitalUnits.format(minV, type: selectedType, displayUnit: unit))")
                    Spacer()
                    Text("\(data.count) mesures")
                    Spacer()
                    Text("Max \(VitalUnits.format(maxV, type: selectedType, displayUnit: unit))")
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
        .card()
    }

    private func vitalRow(_ r: VitalRecord) -> some View {
        let pos = VitalReference.position(value: r.value, value2: r.value2, type: r.type)
        let source = VitalSource.label(source: r.source, notes: r.notes)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if r.type == "tension", let d = r.value2 {
                    Text("\(Int(r.value)) / \(Int(d)) \(r.unit)").font(.subheadline.weight(.semibold))
                } else {
                    Text("\(VitalUnits.format(shown(r.value), type: r.type, displayUnit: displayUnit)) \(displayUnit)")
                        .font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 6) {
                    Text(source).font(.caption2).foregroundStyle(.secondary)
                    if pos == .above { Text("Au-dessus du repère").font(.caption2).foregroundStyle(Theme.warning) }
                    if pos == .below { Text("Sous le repère").font(.caption2).foregroundStyle(Theme.warning) }
                }
                if !r.notes.isEmpty && r.notes != VitalSource.health { Text(r.notes).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(r.date, style: .date).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = r }
        .contextMenu {
            Button { editing = r } label: { Label("Modifier", systemImage: "pencil") }
            Button(role: .destructive) {
                ctx.delete(r)
                MedicalData.save(ctx, "suppression mesure")
            } label: { Label("Supprimer", systemImage: "trash") }
        }
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
        // Saturation et sommeil: c'est la BAISSE qui est un signal a surveiller.
        if type == "SpO2" || type == "sommeil" {
            return moved.contains { $0 < 0 } ? .worse : .neutral
        }
        // Tension, glycemie, cœur, temperature: une hausse est un signal a
        // surveiller. Une baisse n'est pas forcement bonne (hypotension,
        // hypoglycemie): neutre.
        return moved.contains { $0 > 0 } ? .worse : .neutral
    }
}

struct VitalEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vitals.glucoseUnit") private var glucoseUnit = "g/L"
    @AppStorage("vitals.weightUnit") private var weightUnit = "kg"
    var defaultType: String
    /// Mesure a corriger; nil pour un ajout.
    var editing: VitalRecord? = nil
    @State private var loaded = false
    @State private var type = "poids"
    @State private var value = ""
    @State private var value2 = ""
    @State private var notes = ""
    @State private var date = Date()

    private var unit: String { VitalUnits.displayUnit(type, glucose: glucoseUnit, weight: weightUnit) }

    private var placeholder: String {
        switch type {
        case "tension": return "Systolique (ex: 120)"
        case "température": return "Valeur (ex: 37,2)"
        case "SpO2": return "Valeur (ex: 98)"
        case "sommeil": return "Heures (ex: 7,5)"
        case "glycémie": return glucoseUnit == "mmol/L" ? "Valeur (ex: 5,4)" : "Valeur (ex: 0,95)"
        default: return "Valeur (ex: 70)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(VitalTypes.all, id: \.self) { Text(VitalTypes.longLabel($0)).tag($0) }
                    }
                    .disabled(editing != nil)
                    DatePicker("Date", selection: $date)
                }
                Section("Valeur (\(unit))") {
                    TextField(placeholder, text: $value).keyboardType(.decimalPad)
                    if type == "tension" {
                        TextField("Diastolique (ex: 80)", text: $value2).keyboardType(.decimalPad)
                    }
                }
                Section {
                    TextField("Notes (optionnel)", text: $notes)
                } footer: {
                    if let e = editing, VitalSource.label(source: e.source, notes: e.notes) != "Saisie manuelle" {
                        Text("Mesure venue d'Apple Santé : une correction est marquée comme telle.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nouvelle mesure" : "Modifier la mesure").navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { save() }.disabled(parsed(value) == nil)
                }
            }
        }
    }

    private func parsed(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let r = editing else { type = defaultType; return }
        type = r.type; date = r.date
        notes = r.notes == VitalSource.health ? "" : r.notes
        let v = VitalUnits.toDisplay(r.value, type: r.type, glucose: glucoseUnit, weight: weightUnit)
        value = VitalUnits.format(v, type: r.type, displayUnit: unit).replacingOccurrences(of: ".", with: ",")
        value2 = r.value2.map { String(Int($0)) } ?? ""
    }

    private func save() {
        guard let shownValue = parsed(value) else { return }
        // On stocke toujours l'unite canonique (kg, g/L): changer de preference
        // d'affichage ne touche jamais une mesure enregistree.
        let v = VitalUnits.toCanonical(shownValue, type: type, glucose: glucoseUnit, weight: weightUnit)
        let v2 = type == "tension" ? parsed(value2) : nil
        if let r = editing {
            let fromHealth = VitalSource.label(source: r.source, notes: r.notes) == VitalSource.health
            let changed = abs(r.value - v) > 0.0001 || r.value2 != v2 || r.date != date
            r.value = v; r.value2 = v2; r.date = date; r.unit = VitalUnits.canonicalUnit(type)
            r.notes = notes
            if fromHealth && changed { r.source = "Apple Santé, corrigée" }
        } else {
            ctx.insert(VitalRecord(date: date, type: type, value: v, value2: v2, unit: VitalUnits.canonicalUnit(type), notes: notes))
        }
        LifeOSTry(try ctx.save(), context: "enregistrement mesure", category: AppLog.data)
        dismiss()
    }
}

// MARK: - Vaccinations

enum VaccineReminder {
    /// Le proche entre dans l'identifiant: deux enfants vaccines le meme jour
    /// ne partagent plus un seul rappel. "Moi" garde l'ancienne forme, donc les
    /// rappels deja poses restent annulables.
    static func id(name: String, personID: String, next: Date) -> String {
        ReminderIDs.vaccination(name: personID.isEmpty ? name : "\(name)-\(personID)", nextDate: next)
    }

    static func cancel(_ v: Vaccination) {
        guard let next = v.nextDueDate else { return }
        NotificationManager.shared.cancel(id: id(name: v.name, personID: v.personID, next: next))
    }

    static func schedule(_ v: Vaccination, personName: String) {
        guard let next = v.nextDueDate, let at = MedicalReminderTiming.vaccine(due: next) else { return }
        let who = personName.isEmpty ? "" : "\(personName) : "
        NotificationManager.shared.schedule(
            id: id(name: v.name, personID: v.personID, next: next),
            title: "\(who)Rappel vaccin \(v.name)",
            body: "Le rappel est prévu pour le \(next.formatted(.dateTime.day().month(.wide)))",
            at: at
        )
    }
}

struct VaccinationView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Vaccination.date, order: .reverse) private var vaccinations: [Vaccination]
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    @AppStorage(personFilterKey) private var filter = MedicalPeople.everyone
    @State private var showAdd = false
    @State private var editing: Vaccination?

    private var visible: [Vaccination] { vaccinations.filter { MedicalPeople.matches(filter: filter, personID: $0.personID) } }
    private var due: [Vaccination] { visible.filter { $0.isDue } }
    private var upToDate: [Vaccination] { visible.filter { !$0.isDue } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if visible.isEmpty {
                        EmptyState(icon: "syringe", title: "Aucune vaccination",
                                   message: vaccinations.isEmpty ? "Ajoute tes vaccins pour suivre les rappels."
                                                                 : "Aucun vaccin pour cette personne.")
                    } else {
                        if !due.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Rappels à prévoir", subtitle: "Dans les 30 prochains jours")
                                ForEach(due) { v in vaccRow(v, highlight: true) }
                            }.card()
                        }
                        if !upToDate.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Historique")
                                ForEach(upToDate) { v in vaccRow(v, highlight: false) }
                            }.card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Vaccinations").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { MedicalPersonFilterMenu() }
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") }
        }
        .sheet(isPresented: $showAdd) { VaccinationEditor() }
        .sheet(item: $editing) { v in VaccinationEditor(editing: v) }
    }

    private func vaccRow(_ v: Vaccination, highlight: Bool) -> some View {
        let files = MedicalFiles.list(v.attachmentFiles)
        return HStack(spacing: 12) {
            Image(systemName: "syringe.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(highlight ? Theme.warning : Color.medicalTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(v.doseNumber > 0 ? "\(v.name), dose \(v.doseNumber)" : v.name).font(.subheadline.weight(.semibold))
                    MedicalPersonTag(personID: v.personID, people: people)
                }
                Text("Fait le \(v.date.formatted(.dateTime.day().month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
                if !v.practitioner.isEmpty { Text(v.practitioner).font(.caption).foregroundStyle(.secondary) }
                // Le lot n'apparaissait que dans l'export JSON.
                if !v.lot.isEmpty { Text("Lot \(v.lot)").font(.caption).foregroundStyle(.secondary) }
                if !v.notes.isEmpty { Text(v.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if !files.isEmpty { Label("\(files.count) document\(files.count > 1 ? "s" : "")", systemImage: "paperclip").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if let next = v.nextDueDate {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Rappel").font(.caption2).foregroundStyle(.secondary)
                    Text(next, format: .dateTime.day().month(.abbreviated).year()).font(.caption.bold()).foregroundStyle(highlight ? Theme.warning : .medicalTint)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = v }
        .contextMenu {
            Button { editing = v } label: { Label("Modifier", systemImage: "pencil") }
            Button(role: .destructive) {
                VaccineReminder.cancel(v)
                files.forEach { ImageStore.delete($0) }
                ctx.delete(v)
                MedicalData.save(ctx, "suppression vaccin")
            } label: { Label("Supprimer", systemImage: "trash") }
        }
    }
}

struct VaccinationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MedicalPerson.name) private var people: [MedicalPerson]
    /// Vaccin a modifier; nil pour un ajout.
    var editing: Vaccination? = nil
    @State private var loaded = false
    @State private var name = ""
    @State private var date = Date()
    @State private var lot = ""
    @State private var hasNext = false
    @State private var nextDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var notes = ""
    @State private var personID = ""
    @State private var doseNumber = 0
    @State private var practitioner = ""
    @State private var files = MedicalFiles.Draft(raw: "")

    private let common = ["Grippe", "COVID-19", "Tétanos-Diphtérie-Polio", "Hépatite B", "ROR", "Pneumocoque"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du vaccin", text: $name)
                    Picker("Vaccin courant", selection: $name) {
                        Text("Choisir…").tag("")
                        ForEach(common, id: \.self) { Text($0).tag($0) }
                        if !name.isEmpty && !common.contains(name) { Text(name).tag(name) }
                    }
                    MedicalPersonPicker(personID: $personID)
                    DatePicker("Date d'injection", selection: $date, displayedComponents: .date)
                    Stepper(doseNumber == 0 ? "Dose n° : non précisée" : "Dose n° \(doseNumber)", value: $doseNumber, in: 0...10)
                }
                Section("Provenance") {
                    TextField("Praticien ou centre (optionnel)", text: $practitioner)
                    TextField("N° de lot (optionnel)", text: $lot)
                }
                Section {
                    Toggle("Date de rappel", isOn: $hasNext)
                    if hasNext { DatePicker("Prochain rappel", selection: $nextDate, displayedComponents: .date) }
                } header: {
                    Text("Rappel")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if hasNext {
                            if let at = MedicalReminderTiming.vaccine(due: nextDate) {
                                Text("Notification le \(at.formatted(date: .abbreviated, time: .shortened)).")
                            } else {
                                Text("Pas de notification : cette date est déjà passée.")
                            }
                        }
                        Text("Le calendrier vaccinal officiel n'est pas intégré : la date de rappel est celle que tu indiques.")
                    }
                }
                Section {
                    TextField("Notes", text: $notes)
                }
                MedicalAttachmentsSection(title: "Certificat ou carnet", prefix: "vacc", draft: $files)
            }
            .navigationTitle(editing == nil ? "Nouveau vaccin" : "Modifier le vaccin").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .interactiveDismissDisabled(!files.deletedOnCancel.isEmpty)
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let v = editing else { return }
        loaded = true
        name = v.name; date = v.date; lot = v.lot; notes = v.notes
        hasNext = v.nextDueDate != nil
        nextDate = v.nextDueDate ?? nextDate
        personID = v.personID; doseNumber = v.doseNumber; practitioner = v.practitioner
        files = MedicalFiles.Draft(raw: v.attachmentFiles)
    }

    private func cancel() {
        files.deletedOnCancel.forEach { ImageStore.delete($0) }
        dismiss()
    }

    private func save() {
        let v: Vaccination
        if let e = editing {
            // L'ancien rappel porte l'ancien nom et l'ancienne date: on l'annule avant.
            VaccineReminder.cancel(e)
            v = e
        } else {
            v = Vaccination()
            ctx.insert(v)
        }
        v.name = name.trimmingCharacters(in: .whitespaces); v.date = date; v.lot = lot; v.notes = notes
        v.nextDueDate = hasNext ? nextDate : nil
        v.personID = personID; v.doseNumber = doseNumber; v.practitioner = practitioner
        files.deletedOnSave.forEach { ImageStore.delete($0) }
        v.attachmentFiles = files.raw
        LifeOSTry(try ctx.save(), context: "enregistrement vaccin", category: AppLog.data)
        let who = personID.isEmpty ? "" : MedicalPeople.name(for: personID, in: people.map { ($0.stableID, $0.name) })
        VaccineReminder.schedule(v, personName: who)
        dismiss()
    }
}
