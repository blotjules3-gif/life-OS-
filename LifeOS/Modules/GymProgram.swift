import SwiftUI
import SwiftData

// Lundi → Dimanche (la convention Calendar met Dimanche = 1).
let gymWeekOrder = [2, 3, 4, 5, 6, 7, 1]
func gymWeekdayName(_ w: Int) -> String {
    ["", "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"][w]
}

// MARK: - Programme de sport

struct GymProgramView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var days: [GymDay]

    @AppStorage("gymReminderOn")     private var on = true
    @AppStorage("gymReminderHour")   private var hour = 7
    @AppStorage("gymReminderMinute") private var minute = 0
    @AppStorage("gymConfirm")        private var confirm = true

    @State private var editing: GymDay?

    private func day(_ w: Int) -> GymDay? { days.first { $0.weekday == w } }

    var body: some View {
        Form {
            Section {
                Toggle("Rappel chaque jour d'entraînement", isOn: $on)
                    .onChange(of: on) { _, _ in reschedule() }
                if on {
                    DatePicker("Heure", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Toggle("Vérif « bien été ? » +1h30", isOn: $confirm)
                        .onChange(of: confirm) { _, _ in reschedule() }
                }
            } header: {
                Text("Rappel salle")
            } footer: {
                Text("Chaque jour d'entraînement, une notif motivante avec la séance du jour. Les jours de repos, rien.")
            }

            Section("Ma semaine") {
                ForEach(gymWeekOrder, id: \.self) { w in
                    let d = day(w)
                    Button { editing = d } label: {
                        HStack(spacing: 12) {
                            Text(gymWeekdayName(w)).foregroundStyle(.primary)
                            Spacer()
                            Text(label(for: d))
                                .font(.subheadline)
                                .foregroundStyle(color(for: d))
                                .lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Programme de sport").navigationBarTitleDisplayMode(.inline)
        .task {
            seedIfNeeded()
            _ = await NotificationManager.shared.requestAuthorization()
        }
        .sheet(item: $editing) { d in
            GymDayEditor(day: d) { reschedule() }
        }
    }

    private func label(for d: GymDay?) -> String {
        guard let d else { return "—" }
        if d.isRest { return "Repos" }
        return d.title.trimmingCharacters(in: .whitespaces).isEmpty ? "À définir" : d.title
    }
    private func color(for d: GymDay?) -> Color {
        guard let d, !d.isRest, !d.title.trimmingCharacters(in: .whitespaces).isEmpty else { return .secondary }
        return .fitTint
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = hour; c.minute = minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { v in
                let c = Calendar.current.dateComponents([.hour, .minute], from: v)
                hour = c.hour ?? 7; minute = c.minute ?? 0
                reschedule()
            }
        )
    }

    private func seedIfNeeded() {
        guard days.isEmpty else { return }
        for w in 1...7 { ctx.insert(GymDay(weekday: w)) }
    }

    private func reschedule() {
        for w in 1...7 {
            NotificationManager.shared.cancel(id: "gym.day.\(w)")
            NotificationManager.shared.cancel(id: "gym.day.\(w).confirm")
        }
        guard on else { return }
        for w in 1...7 {
            guard let d = day(w), !d.isRest,
                  !d.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let extra = d.focus.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\n\(d.focus)"
            NotificationManager.shared.scheduleWeekly(
                id: "gym.day.\(w)",
                title: "💪 SALLE DE SPORT",
                body: "Allez, lève-toi ! Aujourd'hui : \(d.title) 🔥" + extra,
                weekday: w, hour: hour, minute: minute)
            if confirm {
                var cw = w
                var total = hour * 60 + minute + 90
                if total >= 1440 { total -= 1440; cw = w % 7 + 1 }   // dépasse minuit → jour suivant
                NotificationManager.shared.scheduleWeekly(
                    id: "gym.day.\(w).confirm",
                    title: "Séance faite ? 💪",
                    body: "Tu as bien été à la salle (\(d.title)) ?",
                    weekday: cw, hour: total / 60, minute: total % 60,
                    categoryId: "LIFEOS_CONFIRM",
                    userInfo: ["confirmKey": "gym", "confirmLabel": "ta séance"])
            }
        }
    }
}

// MARK: - Éditeur d'un jour

struct GymDayEditor: View {
    @Bindable var day: GymDay
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Jour de repos", isOn: $day.isRest).tint(.fitTint)
                if !day.isRest {
                    Section("Séance") {
                        TextField("Nom (ex: Dos + Biceps)", text: $day.title)
                        TextField("Exercices / notes (optionnel)", text: $day.focus, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle(gymWeekdayName(day.weekday)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { onDone(); dismiss() }
                }
            }
        }
    }
}
