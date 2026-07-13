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
            NotificationManager.shared.cancel(id: "gym.day.\(w).protein")
        }
        guard on else { return }
        // Heure d'entraînement (par défaut 18h) pour caler la collation post-séance.
        let trainHour = UserDefaults.standard.integer(forKey: "sportHour")
        let trainStart = (trainHour > 0 ? trainHour : 18) * 60
        for w in 1...7 {
            guard let d = day(w), !d.isRest,
                  !d.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let extra = d.focus.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\n\(d.focus)"
            NotificationManager.shared.scheduleWeekly(
                id: "gym.day.\(w)",
                title: "SALLE DE SPORT",
                body: "Allez, lève-toi! Aujourd'hui : \(d.title)" + extra,
                weekday: w, hour: hour, minute: minute)

            // Post-séance (~10 min après une séance d'~1 h) : protéines + créatine.
            var pw = w
            var pwTotal = trainStart + 70
            if pwTotal >= 1440 { pwTotal -= 1440; pw = w % 7 + 1 }
            NotificationManager.shared.scheduleWeekly(
                id: "gym.day.\(w).protein",
                title: "Fin de séance",
                body: "Dans la foulée : ~30 g de protéines + ta créatine pour bien récupérer.",
                weekday: pw, hour: pwTotal / 60, minute: pwTotal % 60)
            if confirm {
                var cw = w
                var total = hour * 60 + minute + 90
                if total >= 1440 { total -= 1440; cw = w % 7 + 1 }   // dépasse minuit → jour suivant
                NotificationManager.shared.scheduleWeekly(
                    id: "gym.day.\(w).confirm",
                    title: "Séance faite?",
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
    @State private var showAI = false

    private var exercises: [String] {
        day.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func writeExercises(_ list: [String]) { day.focus = list.joined(separator: " · ") }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Jour de repos", isOn: $day.isRest).tint(.fitTint)
                if !day.isRest {
                    Section("Séance") {
                        TextField("Nom (ex: Dos + Biceps)", text: $day.title)
                    }
                    Section {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { i, ex in
                            HStack(spacing: 10) {
                                Image(systemName: "\(min(i + 1, 50)).circle.fill").foregroundStyle(.fitTint)
                                Text(ex).font(.subheadline)
                                Spacer()
                                Button { swap(at: i) } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.fitTint)
                                }.buttonStyle(.plain)
                            }
                            .swipeActions { Button(role: .destructive) { remove(at: i) } label: { Label("Suppr", systemImage: "trash") } }
                        }
                        Menu {
                            ForEach(GymExercises.catalog.keys.sorted(), id: \.self) { group in
                                Button(group) { addExercise(from: group) }
                            }
                        } label: {
                            Label("Ajouter un exercice", systemImage: "plus.circle.fill").foregroundStyle(.fitTint)
                        }
                    } header: {
                        Text("Exercices — touche ↻ pour remplacer une machine indisponible")
                    }
                }
            }
            .navigationTitle(gymWeekdayName(day.weekday)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !day.isRest {
                        Button { showAI = true } label: { Image(systemName: "sparkles") }.tint(.fitTint)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { onDone(); dismiss() }
                }
            }
            .sheet(isPresented: $showAI) {
                ToolAISheet(title: "Modifier la séance",
                            placeholder: "Ex : le développé couché, la machine n'est pas dispo, remplace-le") { request in
                    applyAI(request)
                }
            }
        }
    }

    private func swap(at i: Int) {
        var list = exercises
        guard list.indices.contains(i), let alt = GymExercises.alternative(for: list[i], avoiding: list) else { return }
        list[i] = alt; writeExercises(list); Haptics.tap()
    }
    private func remove(at i: Int) {
        var list = exercises; guard list.indices.contains(i) else { return }
        list.remove(at: i); writeExercises(list); Haptics.tap()
    }
    private func addExercise(from group: String) {
        guard let pool = GymExercises.catalog[group] else { return }
        var list = exercises
        let present = Set(list.map { GymExercises.baseName($0) })
        let pick = pool.first { !present.contains($0) } ?? pool.first
        if let p = pick { list.append(p); writeExercises(list); Haptics.tap() }
    }

    /// Édition en langage naturel : repère un exercice cité et le remplace.
    private func applyAI(_ request: String) -> String {
        let text = request.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        var list = exercises
        for (i, ex) in list.enumerated() {
            let base = GymExercises.baseName(ex).lowercased().folding(options: .diacriticInsensitive, locale: .current)
            // mot-clé principal de l'exercice (premier mot significatif)
            let key = base.split(separator: " ").first.map(String.init) ?? base
            if text.contains(base) || (key.count > 3 && text.contains(key)) {
                if let alt = GymExercises.alternative(for: ex, avoiding: list) {
                    list[i] = alt; writeExercises(list); Haptics.success()
                    return "Remplacé par : \(GymExercises.baseName(alt))"
                }
            }
        }
        return "Dis-moi quel exercice remplacer (ex : « remplace le squat »), ou touche ↻ à côté de l'exercice."
    }
}
