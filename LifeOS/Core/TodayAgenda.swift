import SwiftUI
import SwiftData

/// Un élément « à faire / prévu aujourd'hui » agrégé depuis n'importe quelle catégorie.
struct AgendaItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let category: AppCategory?   // pour rediriger vers le bon pôle au tap
    let sortKey: Int             // minutes depuis minuit ; 24*60 = toute la journée (fin de liste)
}

/// Section « AUJOURD'HUI » de l'accueil : rassemble TOUT ce qui a été enregistré dans
/// les catégories et qui tombe aujourd'hui (séance de sport, compléments, rappels type
/// shampoing, livraisons/échéances, ménage, renouvellements, événements, voyages…).
struct TodayAgendaSection: View {
    @Query private var gymDays: [GymDay]
    @Query private var supplements: [Supplement]
    @Query private var reminders: [CustomReminder]
    @Query private var subscriptions: [Subscription]
    @Query private var deadlines: [Deadline]
    @Query private var chores: [Chore]
    @Query private var petCares: [PetCare]
    @Query private var maintenances: [Maintenance]
    @Query private var vehicles: [Vehicle]
    @Query private var events: [SocialEvent]
    @Query private var trips: [Trip]
    @Query private var contacts: [Contact]

    private var items: [AgendaItem] { buildItems() }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Aujourd'hui")
                        .font(.system(size: 20, weight: .black)).textCase(.uppercase).kerning(-0.3)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(Date(), format: .dateTime.weekday(.wide).day().month())
                        .monoLabel(10).foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        agendaRow(item)
                        if idx < items.count - 1 {
                            Divider().overlay(Theme.hairline).padding(.leading, 58)
                        }
                    }
                }
                .card(padding: 6, elevated: true)
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func agendaRow(_ item: AgendaItem) -> some View {
        if let cat = item.category {
            NavigationLink { cat.destination } label: { rowContent(item) }
                .buttonStyle(.plain)
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: AgendaItem) -> some View {
        HStack(spacing: 12) {
            IconBadge(icon: item.icon, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.category != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Agrégation

    private func buildItems() -> [AgendaItem] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: now)
        var out: [AgendaItem] = []

        func hm(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }
        func isToday(_ d: Date) -> Bool { cal.isDateInToday(d) }
        func isDueBy(_ d: Date?) -> Bool { guard let d else { return false }; return cal.startOfDay(for: d) <= today }

        // 🏋️ Séance de sport du jour
        if let gym = gymDays.first(where: { $0.weekday == weekday && !$0.isRest && !$0.title.isEmpty }) {
            out.append(.init(icon: "figure.strengthtraining.traditional",
                             title: "Séance : \(gym.title)",
                             detail: gym.focus.isEmpty ? "Jour de sport" : gym.focus,
                             category: .fitness, sortKey: 7 * 60))
        }

        // 💊 Compléments du jour — REGROUPÉS par heure (Whey + Créatine à 08:00 = 1 seule ligne)
        let activeSupps = supplements.filter { $0.active }
        let byTime = Dictionary(grouping: activeSupps) { $0.hour * 60 + $0.minute }
        for (key, group) in byTime.sorted(by: { $0.key < $1.key }) {
            let names = group.map { $0.name }.filter { !$0.isEmpty }
            guard !names.isEmpty else { continue }
            let title = names.count == 1 ? "Complément : \(names[0])"
                                         : "Compléments : \(names.joined(separator: ", "))"
            out.append(.init(icon: "pills.fill", title: title,
                             detail: hm(key / 60, key % 60),
                             category: .nutrition, sortKey: key))
        }

        // 🔔 Rappels perso (shampoing, soins, routines…)
        for r in reminders.filter({ $0.enabled }) {
            out.append(.init(icon: "bell.fill",
                             title: r.title,
                             detail: r.message.isEmpty ? hm(r.hour, r.minute) : r.message,
                             category: nil, sortKey: r.hour * 60 + r.minute))
        }

        // 🔁 Abonnements à renouveler
        for sub in subscriptions.filter({ isToday($0.nextDate) }) {
            out.append(.init(icon: "arrow.triangle.2.circlepath",
                             title: "Renouvellement : \(sub.name)",
                             detail: "Abonnement", category: .finance, sortKey: 24 * 60))
        }

        // 📦 Échéances / livraisons (aujourd'hui ou en retard)
        for d in deadlines.filter({ isDueBy($0.date) }) {
            let overdue = cal.startOfDay(for: d.date) < today
            out.append(.init(icon: "shippingbox.fill",
                             title: d.title,
                             detail: overdue ? "En retard" : "Échéance aujourd'hui",
                             category: .admin, sortKey: 24 * 60))
        }

        // 🧹 Tâches ménagères dues
        for c in chores.filter({ $0.lastDone == nil || isDueBy($0.nextDue) }) {
            out.append(.init(icon: "spray.and.wipe.fill",
                             title: c.name, detail: "À faire (\(c.assigneeShort))",
                             category: .home, sortKey: 24 * 60))
        }

        // 🐾 Soins animaux
        for p in petCares.filter({ isToday($0.date) }) {
            out.append(.init(icon: "pawprint.fill", title: p.type,
                             detail: p.note.isEmpty ? "Soin animal" : p.note,
                             category: .home, sortKey: 24 * 60))
        }

        // 🔧 Entretien maison
        for m in maintenances.filter({ isDueBy($0.nextDue) }) {
            out.append(.init(icon: "wrench.and.screwdriver.fill", title: m.name, detail: "Entretien",
                             category: .home, sortKey: 24 * 60))
        }

        // 🚗 Révision véhicule
        for v in vehicles.filter({ isDueBy($0.nextService) }) {
            out.append(.init(icon: "car.fill", title: "Révision : \(v.name)", detail: "Véhicule",
                             category: .mobility, sortKey: 24 * 60))
        }

        // 🎉 Événements sociaux
        for e in events.filter({ isToday($0.date) }) {
            out.append(.init(icon: "party.popper.fill", title: e.title, detail: "Événement",
                             category: .social, sortKey: cal.component(.hour, from: e.date) * 60 + cal.component(.minute, from: e.date)))
        }

        // ✈️ Voyage : départ ou en cours
        for t in trips {
            if isToday(t.start) {
                out.append(.init(icon: "airplane.departure", title: "Départ : \(t.name)",
                                 detail: t.destination.isEmpty ? "Voyage" : t.destination,
                                 category: .travel, sortKey: 24 * 60))
            } else if cal.startOfDay(for: t.start) < today && today <= cal.startOfDay(for: t.end) {
                out.append(.init(icon: "airplane", title: "En voyage : \(t.name)",
                                 detail: t.destination.isEmpty ? "En cours" : t.destination,
                                 category: .travel, sortKey: 24 * 60))
            }
        }

        // 🎁 Anniversaires + prises de nouvelles
        for c in contacts {
            if let b = c.birthday, cal.component(.month, from: b) == cal.component(.month, from: now),
               cal.component(.day, from: b) == cal.component(.day, from: now) {
                out.append(.init(icon: "gift.fill", title: "Anniversaire : \(c.name)",
                                 detail: "Pense à souhaiter 🎂", category: .social, sortKey: 24 * 60))
            } else if let last = c.lastSeen, c.cadenceDays > 0,
                      let due = cal.date(byAdding: .day, value: c.cadenceDays, to: last), isDueBy(due) {
                out.append(.init(icon: "phone.fill", title: "Prendre des nouvelles : \(c.name)",
                                 detail: "Ça fait un moment", category: .social, sortKey: 24 * 60))
            }
        }

        return out.sorted { $0.sortKey < $1.sortKey }
    }
}

private extension Chore {
    var assigneeShort: String { assignee.isEmpty ? "Moi" : assignee }
}
