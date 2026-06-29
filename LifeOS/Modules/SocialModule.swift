import SwiftUI
import SwiftData
import Contacts

extension ShapeStyle where Self == Color { static var socialTint: Color { AppCategory.social.tint } }

// MARK: - Hub Social

struct SocialHubView: View {
    var body: some View {
        HubScaffold(category: .social) {
            ToolRow(icon: "person.crop.circle.badge.clock", title: "CRM personnel",
                    subtitle: "Qui relancer", tint: .socialTint) { CRMView() }
            ToolRow(icon: "gift.fill", title: "Anniversaires & cadeaux",
                    subtitle: "Rappels + idées", tint: .socialTint) { BirthdaysView() }
            ToolRow(icon: "calendar.badge.plus", title: "Sorties & events",
                    subtitle: "Organise tes événements", tint: .socialTint) { EventsView() }
        }
    }
}

// MARK: - CRM

struct CRMView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var showAdd = false
    @State private var showImport = false
    private var overdue: [Contact] { contacts.filter { $0.isOverdue } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if !overdue.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "À recontacter", subtitle: "Tu n'as pas donné de nouvelles")
                            ForEach(overdue) { c in contactRow(c, highlight: true) }
                        }.card()
                    }
                    if contacts.isEmpty {
                        EmptyState(icon: "person.2", title: "Aucun contact", message: "Ajoute les gens qui comptent et la fréquence à laquelle tu veux garder le lien.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Tous mes contacts")
                            ForEach(contacts) { c in contactRow(c, highlight: false) }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("CRM personnel").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAdd = true } label: { Label("Nouveau contact", systemImage: "plus") }
                    Button { showImport = true } label: { Label("Importer depuis Contacts", systemImage: "person.crop.circle.badge.plus") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ContactEditor() }
        .sheet(isPresented: $showImport) { ContactImportSheet(existingNames: Set(contacts.map(\.name))) { imported in
            for c in imported { ctx.insert(c) }
        }}
    }
    private func contactRow(_ c: Contact, highlight: Bool) -> some View {
        HStack {
            Circle().fill(Color.socialTint.opacity(0.2)).frame(width: 40, height: 40)
                .overlay(Text(String(c.name.prefix(1)).uppercased()).bold().foregroundStyle(.socialTint))
            VStack(alignment: .leading) {
                Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                if let last = c.lastSeen { Text("Vu \(last, style: .relative)").font(.caption).foregroundStyle(highlight ? .orange : Theme.textSecondary) }
                else { Text("Jamais marqué").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Button { c.lastSeen = Date(); Haptics.tap() } label: { Image(systemName: "checkmark.message.fill").foregroundStyle(.socialTint) }
        }
        .card(padding: 12)
        .contextMenu { Button(role: .destructive) { ctx.delete(c) } label: { Label("Supprimer", systemImage: "trash") } }
    }
}

struct ContactEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var cadence = 30
    @State private var hasBirthday = false; @State private var birthday = Date()
    @State private var gifts = ""; @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                Stepper("Garder contact tous les \(cadence) j", value: $cadence, in: 7...365, step: 7)
                Toggle("Anniversaire", isOn: $hasBirthday)
                if hasBirthday { DatePicker("Date", selection: $birthday, displayedComponents: .date) }
                TextField("Idées cadeaux", text: $gifts, axis: .vertical).lineLimit(1...3)
                TextField("Notes (enfants, taf, hobbies…)", text: $notes, axis: .vertical).lineLimit(2...5)
            }
            .navigationTitle("Nouveau contact").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Contact(name: name, cadenceDays: cadence, birthday: hasBirthday ? birthday : nil, giftIdeas: gifts, notes: notes)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Anniversaires

struct BirthdaysView: View {
    @Query private var contacts: [Contact]
    private var withBirthday: [Contact] {
        contacts.filter { $0.birthday != nil }.sorted { daysUntil($0.birthday!) < daysUntil($1.birthday!) }
    }
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if withBirthday.isEmpty {
                        EmptyState(icon: "gift", title: "Aucun anniversaire", message: "Ajoute les dates de naissance dans le CRM.")
                    } else {
                        ForEach(withBirthday) { c in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "gift.fill").foregroundStyle(.socialTint)
                                    Text(c.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    let d = daysUntil(c.birthday!)
                                    Text(d == 0 ? "Aujourd'hui 🎉" : "Dans \(d) j").font(.subheadline.bold()).foregroundStyle(d <= 7 ? .orange : .socialTint)
                                }
                                Text(c.birthday!, format: .dateTime.day().month(.wide)).font(.caption).foregroundStyle(Theme.textSecondary)
                                if !c.giftIdeas.isEmpty { Label(c.giftIdeas, systemImage: "lightbulb.fill").font(.caption).foregroundStyle(.socialTint) }
                            }.frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Anniversaires").navigationBarTitleDisplayMode(.inline)
    }
    private func daysUntil(_ birthday: Date) -> Int {
        let cal = Calendar.current
        let now = cal.startOfDay(for: .now)
        var comps = cal.dateComponents([.month, .day], from: birthday)
        comps.year = cal.component(.year, from: now)
        var next = cal.date(from: comps) ?? now
        if next < now { comps.year! += 1; next = cal.date(from: comps) ?? now }
        return cal.dateComponents([.day], from: now, to: next).day ?? 0
    }
}

// MARK: - Events

struct EventsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SocialEvent.date) private var events: [SocialEvent]
    @State private var showAdd = false
    private var upcoming: [SocialEvent] { events.filter { $0.date >= Calendar.current.startOfDay(for: .now) } }
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if upcoming.isEmpty {
                        EmptyState(icon: "calendar.badge.plus", title: "Aucun event", message: "Organise une sortie, un dîner, un week-end.")
                    } else {
                        ForEach(upcoming) { e in
                            HStack {
                                VStack {
                                    Text(e.date, format: .dateTime.day()).font(.title2.bold()).foregroundStyle(.socialTint)
                                    Text(e.date, format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(Theme.textSecondary)
                                }.frame(width: 50)
                                VStack(alignment: .leading) {
                                    Text(e.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    if !e.location.isEmpty { Label(e.location, systemImage: "mappin").font(.caption).foregroundStyle(Theme.textSecondary) }
                                    Text(e.date, style: .time).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                            }.card(padding: 12)
                                .contextMenu { Button(role: .destructive) { ctx.delete(e) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Sorties & events").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { EventEditor() }
    }
}

struct EventEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var date = Date(); @State private var location = ""; @State private var remind = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $title)
                DatePicker("Quand", selection: $date)
                TextField("Lieu", text: $location)
                Toggle("Me rappeler la veille", isOn: $remind)
            }
            .navigationTitle("Nouvel event").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(SocialEvent(title: title, date: date, location: location))
                    if remind { NotificationManager.shared.schedule(id: "event-\(title)-\(Int(date.timeIntervalSince1970))", title: "Demain : \(title)", body: location.isEmpty ? "" : "📍 \(location)", at: Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date) }
                    dismiss()
                }.disabled(title.isEmpty) }
            }
        }
    }
}
