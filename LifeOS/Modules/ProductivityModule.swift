import SwiftUI
import SwiftData
import EventKit

extension ShapeStyle where Self == Color { static var prodTint: Color { AppCategory.productivity.tint } }

// MARK: - Hub Productivité

struct ProductivityHubView: View {
    var body: some View {
        HubScaffold(category: .productivity) {
            ToolRow(icon: "checklist", title: "To-do intelligente",
                    subtitle: "Priorités, projets, échéances", tint: .prodTint) { TodoView() }
            ToolRow(icon: "calendar.day.timeline.left", title: "Time-blocking auto",
                    subtitle: "L'app remplit ta journée", tint: .prodTint) { TimeBlockView() }
            ToolRow(icon: "square.grid.3x3.fill", title: "Habit tracker",
                    subtitle: "Streaks & régularité", tint: .prodTint) { HabitTrackerView() }
            ToolRow(icon: "timer", title: "Focus / Pomodoro",
                    subtitle: "25 min concentration", tint: .prodTint) { FocusTimerView() }
            ToolRow(icon: "note.text", title: "Notes & second cerveau",
                    subtitle: "Capture rapide + tags", tint: .prodTint) { NotesView() }
        }
    }
}

// MARK: - To-do

struct TodoView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TodoItem.due) private var todos: [TodoItem]
    @State private var showAdd = false
    @State private var filter = 0   // 0 actives, 1 toutes
    @State private var calendarAlert: String? = nil

    private var visible: [TodoItem] {
        let base = filter == 0 ? todos.filter { !$0.done } : todos
        return base.sorted { ($0.priority, $0.due ?? .distantFuture) > ($1.priority, $1.due ?? .distantFuture) }
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                Picker("", selection: $filter) { Text("À faire").tag(0); Text("Toutes").tag(1) }
                    .pickerStyle(.segmented).padding()
                if visible.isEmpty {
                    EmptyState(icon: "checklist", title: "Rien à faire 🎉", message: "Ajoute une tâche avec le +.")
                    Spacer()
                } else {
                    List {
                        ForEach(visible) { t in
                            HStack(spacing: 12) {
                                Button { withAnimation { t.done.toggle() } } label: {
                                    Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(t.done ? .green : priorityColor(t.priority))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).strikethrough(t.done).foregroundStyle(t.done ? Theme.textSecondary : Theme.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(t.project).font(.caption2).padding(.horizontal,6).padding(.vertical,2)
                                            .background(Theme.bg2, in: Capsule()).foregroundStyle(Theme.textSecondary)
                                        if let d = t.due { Text(d, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(d < .now && !t.done ? .red : Theme.textSecondary) }
                                    }
                                }
                                Spacer()
                            }
                            .listRowBackground(Theme.card)
                            .contextMenu {
                                Button {
                                    addToCalendar(t)
                                } label: {
                                    Label("Ajouter au calendrier", systemImage: "calendar.badge.plus")
                                }
                                Button(role: .destructive) {
                                    ctx.delete(t)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { idx in idx.map { visible[$0] }.forEach(ctx.delete) }
                    }
                    .scrollContentBackground(.hidden)
                    .alert("Calendrier", isPresented: .init(
                        get: { calendarAlert != nil },
                        set: { if !$0 { calendarAlert = nil } }
                    )) {
                        Button("OK") { calendarAlert = nil }
                    } message: {
                        Text(calendarAlert ?? "")
                    }
                }
            }
        }
        .navigationTitle("To-do").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { TodoEditor() }
    }
    private func priorityColor(_ p: Int) -> Color { p >= 2 ? .red : p == 1 ? .orange : Theme.textSecondary }

    private func addToCalendar(_ todo: TodoItem) {
        let store = EKEventStore()
        let requestAccess = {
            let event = EKEvent(eventStore: store)
            event.title = todo.title
            event.notes = todo.project.isEmpty ? nil : todo.project
            let start = todo.due ?? Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
            event.startDate = start
            event.endDate   = Calendar.current.date(byAdding: .hour, value: 1, to: start)!
            event.calendar  = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
                calendarAlert = "Ajouté au calendrier pour \(start.formatted(.dateTime.day().month().hour().minute()))."
            } catch {
                calendarAlert = "Impossible d'accéder au calendrier. Vérifie les autorisations dans Réglages."
            }
        }
        if #available(iOS 17, *) {
            store.requestWriteOnlyAccessToEvents { granted, _ in
                DispatchQueue.main.async { if granted { requestAccess() } else { calendarAlert = "Accès calendrier refusé." } }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { if granted { requestAccess() } else { calendarAlert = "Accès calendrier refusé." } }
            }
        }
    }
}

struct TodoEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var project = "Perso"; @State private var priority = 0
    @State private var hasDue = false; @State private var due = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("Tâche", text: $title)
                TextField("Projet", text: $project)
                Picker("Priorité", selection: $priority) { Text("Normale").tag(0); Text("Importante").tag(1); Text("Urgente").tag(2) }
                Toggle("Échéance", isOn: $hasDue)
                if hasDue { DatePicker("Pour le", selection: $due) }
            }
            .navigationTitle("Nouvelle tâche").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(TodoItem(title: title, due: hasDue ? due : nil, priority: priority, project: project)); dismiss()
                }.disabled(title.isEmpty) }
            }
        }
    }
}

// MARK: - Time-blocking auto

struct TimeBlockView: View {
    @Query private var todos: [TodoItem]
    @AppStorage("dayStart") private var dayStart = 9
    @AppStorage("dayEnd") private var dayEnd = 18
    @State private var blocks: [(Date, Date, TodoItem)] = []

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Stepper("Début \(dayStart)h", value: $dayStart, in: 5...12)
                        Divider().frame(height: 24)
                        Stepper("Fin \(dayEnd)h", value: $dayEnd, in: 13...23)
                    }.font(.footnote).card()

                    PrimaryButton(title: "Générer ma journée", icon: "wand.and.stars", tint: .prodTint) { generate() }

                    if blocks.isEmpty {
                        IntegrationNotice(text: "Le time-blocking remplit automatiquement des créneaux d'1h avec tes tâches non terminées (les plus prioritaires d'abord), entre ton heure de début et de fin, en sautant la pause déjeuner. Ajoute des tâches dans la To-do puis génère.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack { Text(b.0, style: .time).font(.caption.bold()).foregroundStyle(.prodTint) }.frame(width: 56)
                                    RoundedRectangle(cornerRadius: 3).fill(priorityColor(b.2.priority)).frame(width: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.2.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(b.2.project).font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }.padding(.vertical, 10)
                                Divider().overlay(Theme.stroke)
                            }
                        }.card()
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Time-blocking").navigationBarTitleDisplayMode(.inline)
    }
    private func generate() {
        let pending = todos.filter { !$0.done }.sorted { $0.priority > $1.priority }
        var result: [(Date, Date, TodoItem)] = []
        let cal = Calendar.current
        var hour = max(dayStart, cal.component(.hour, from: .now) + 1)
        for t in pending {
            while hour == 13 { hour += 1 }            // saute la pause déj
            guard hour + 1 <= dayEnd else { break }
            let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
            let end = cal.date(byAdding: .hour, value: 1, to: start)!
            result.append((start, end, t))
            hour += 1
        }
        withAnimation { blocks = result }
    }
    private func priorityColor(_ p: Int) -> Color { p >= 2 ? .red : p == 1 ? .orange : .prodTint }
}

// MARK: - Habit tracker

struct HabitTrackerView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]
    @State private var showAdd = false
    @AppStorage("habitModulesRaw") private var habitModulesRaw = ""

    private var pendingHabits: [Habit] { allHabits.filter { $0.isPending } }
    private var activeHabits: [Habit] { allHabits.filter { !$0.isPending } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if !pendingHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                Text("PROPOSEES PAR LIFEOS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .kerning(1.2)
                            }
                            ForEach(pendingHabits) { h in
                                PendingHabitRow(habit: h)
                            }
                        }
                        Divider().opacity(0.4)
                    }

                    if activeHabits.isEmpty && pendingHabits.isEmpty {
                        EmptyState(icon: "square.grid.3x3", title: "Aucune habitude", message: "Crée ta première habitude à suivre.")
                    } else if !activeHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if !pendingHabits.isEmpty {
                                Text("MES HABITUDES")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .kerning(1.2)
                            }
                            ForEach(activeHabits) { h in HabitRow(habit: h) }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Habit tracker").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { HabitEditor() }
        .task { NotificationManager.shared.schedulePendingHabitNotification(pendingCount: pendingHabits.count) }
        .onChange(of: pendingHabits.count) { _, new in
            NotificationManager.shared.schedulePendingHabitNotification(pendingCount: new)
        }
    }
}

struct PendingHabitRow: View {
    @Environment(\.modelContext) private var ctx
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: UInt(habit.colorHex)))
                .frame(width: 36, height: 36)
                .background(Color(hex: UInt(habit.colorHex)).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(habit.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.25)) {
                    habit.isPending = false
                    try? ctx.save()
                }
                Haptics.tap()
            } label: {
                Text("Activer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: UInt(habit.colorHex)), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                ctx.delete(habit)
                try? ctx.save()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.orange.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var ctx
    let habit: Habit
    private var last7: [Date] { (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now))! }.reversed() }
    private func done(_ day: Date) -> Bool { habit.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: day) } }
    private var streak: Int {
        var c = 0; var day = Calendar.current.startOfDay(for: .now)
        if !done(day) { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        while done(day) { c += 1; day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        return c
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: habit.icon).foregroundStyle(Color(hex: UInt(habit.colorHex)))
                Text(habit.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Label("\(streak)", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.orange)
                Button(role: .destructive) { ctx.delete(habit) } label: { Image(systemName: "trash").font(.caption) }.foregroundStyle(.red.opacity(0.6))
            }
            HStack(spacing: 8) {
                ForEach(last7, id: \.self) { day in
                    let isDone = done(day)
                    Button { toggle(day) } label: {
                        VStack(spacing: 4) {
                            Text(shortDay(day)).font(.caption2).foregroundStyle(Theme.textSecondary)
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isDone ? Color(hex: UInt(habit.colorHex)) : Theme.bg2)
                                .frame(height: 34)
                                .overlay(isDone ? Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) : nil)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }.card()
    }
    private func toggle(_ day: Date) {
        if let c = habit.completions.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            habit.completions.removeAll { $0 === c }; ctx.delete(c)
        } else { habit.completions.append(HabitCompletion(date: day)) }
        Haptics.tap()
    }
    private func shortDay(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier:"fr_FR"); f.dateFormat = "EE"; return String(f.string(from: d).prefix(1)).uppercased() }
}

struct HabitEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var icon = "drop.fill"; @State private var color = 0x4CC38A
    private let icons = ["drop.fill","book.fill","dumbbell.fill","leaf.fill","sun.max.fill","moon.fill","pencil","heart.fill","cup.and.saucer.fill","bed.double.fill"]
    private let colors = [0x4CC38A, 0x618EF1, 0xF1746C, 0xE0A23C, 0x9B6CF1, 0x3CD0C8]
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom de l'habitude", text: $name)
                Section("Icône") {
                    LazyVGrid(columns: Array(repeating: GridItem(), count: 5)) {
                        ForEach(icons, id: \.self) { i in
                            Image(systemName: i).font(.title3).frame(width: 40, height: 40)
                                .background(icon == i ? Color.prodTint.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { icon = i }
                        }
                    }
                }
                Section("Couleur") {
                    HStack { ForEach(colors, id: \.self) { c in
                        Circle().fill(Color(hex: UInt(c))).frame(width: 30, height: 30)
                            .overlay(color == c ? Circle().stroke(.white, lineWidth: 2) : nil)
                            .onTapGesture { color = c }
                    } }
                }
            }
            .navigationTitle("Nouvelle habitude").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer") {
                    ctx.insert(Habit(name: name, icon: icon, colorHex: color)); dismiss()
                }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Focus / Pomodoro

struct FocusTimerView: View {
    @State private var engine = CountdownEngine()
    @State private var isFocus = true
    @State private var sessions = 0
    @State private var running = false
    @AppStorage("focusLen") private var focusLen = 25
    @AppStorage("breakLen") private var breakLen = 5

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 24) {
                if !running {
                    HStack {
                        Stepper("Focus \(focusLen)min", value: $focusLen, in: 10...60, step: 5)
                    }.font(.footnote).card()
                }
                Text(isFocus ? "CONCENTRATION" : "PAUSE").font(.caption.bold()).foregroundStyle(isFocus ? .prodTint : .green)
                TimerDial(engine: engine, tint: isFocus ? .prodTint : .green, caption: "Session \(sessions+1)")
                Label("\(sessions) sessions terminées", systemImage: "checkmark.seal").font(.footnote).foregroundStyle(Theme.textSecondary)
                if !running {
                    PrimaryButton(title: "Démarrer le focus", icon: "play.fill", tint: .prodTint) { startFocus() }
                } else {
                    HStack {
                        PrimaryButton(title: engine.isRunning ? "Pause" : "Reprendre", icon: engine.isRunning ? "pause.fill" : "play.fill", tint: .prodTint) { engine.isRunning ? engine.pause() : engine.resume() }
                        PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) { engine.stop(); running = false }
                    }
                }
                IntegrationNotice(text: "Le « bloqueur d'apps » façon Forest nécessite la Screen Time API (DeviceActivity + FamilyControls) qui requiert une autorisation spéciale Apple. Ici le minuteur de focus est pleinement fonctionnel ; le blocage dur des apps est l'étape à activer ensuite.")
            }.padding()
        }
        .navigationTitle("Focus").navigationBarTitleDisplayMode(.inline)
    }
    private func startFocus() {
        running = true; isFocus = true
        engine.onFinish = finishPhase
        engine.start(seconds: focusLen*60)
    }
    private func finishPhase() {
        if isFocus { sessions += 1; isFocus = false; engine.onFinish = finishPhase; engine.start(seconds: breakLen*60) }
        else { isFocus = true; engine.onFinish = finishPhase; engine.start(seconds: focusLen*60) }
    }
}

// MARK: - Notes

struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.created, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var showAdd = false
    private var filtered: [Note] {
        guard !search.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) || $0.tags.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if filtered.isEmpty {
                        EmptyState(icon: "note.text", title: "Aucune note", message: "Capture une idée, un lien, une réflexion.")
                    } else {
                        ForEach(filtered) { n in
                            NavigationLink { NoteEditor(note: n) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.title.isEmpty ? "Sans titre" : n.title).font(.headline).foregroundStyle(Theme.textPrimary)
                                    if !n.body.isEmpty { Text(n.body).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2) }
                                    if !n.tags.isEmpty {
                                        HStack { ForEach(n.tags.split(separator: ",").map(String.init), id: \.self) { tag in
                                            Text("#\(tag.trimmingCharacters(in: .whitespaces))").font(.caption2).foregroundStyle(.prodTint)
                                        } }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).card()
                            }.buttonStyle(.plain)
                            .contextMenu { Button(role: .destructive) { ctx.delete(n) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .searchable(text: $search, prompt: "Rechercher dans tes notes")
        .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) {
            NavigationStack { NoteEditor(note: nil) }
        }
    }
}

struct NoteEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let note: Note?
    @State private var title = ""; @State private var body_ = ""; @State private var tags = ""
    var body: some View {
        Form {
            TextField("Titre", text: $title)
            TextField("Contenu…", text: $body_, axis: .vertical).lineLimit(6...20)
            TextField("Tags (séparés par virgule)", text: $tags)
        }
        .navigationTitle(note == nil ? "Nouvelle note" : "Note").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("OK") { save(); dismiss() } }
        }
        .onAppear { if let note { title = note.title; body_ = note.body; tags = note.tags } }
    }
    private func save() {
        if let note { note.title = title; note.body = body_; note.tags = tags }
        else { ctx.insert(Note(title: title, body: body_, tags: tags)) }
    }
}
