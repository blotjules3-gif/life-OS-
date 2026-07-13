import SwiftUI
import SwiftData

// MARK: - Centre de notifications

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CustomReminder.hour) private var reminders: [CustomReminder]

    @AppStorage("morningReminderOn")   private var morningOn = true
    @AppStorage("morningReminderText") private var morningText = MorningReminder.defaultText
    @AppStorage("notifMasterMute")     private var muted = false

    @State private var showAdd = false

    var body: some View {
        Form {
            // ---- Réveil ----
            Section {
                Toggle("Rappel 5 min après le réveil", isOn: $morningOn).tint(.accentColor)
                if morningOn {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Message").font(.caption).foregroundStyle(.secondary)
                        TextField("Message", text: $morningText, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }
            } header: {
                Text("Au réveil")
            } footer: {
                Text("Envoyé automatiquement 5 min après ta première ouverture de l'app le matin (entre 4h et 12h).")
            }

            // ---- Rappels perso ----
            Section {
                if reminders.isEmpty {
                    Text("Aucun rappel. Ajoute ceux qui te sont utiles")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                ForEach(reminders) { r in reminderRow(r) }
                    .onDelete(perform: deleteReminders)
                Button { showAdd = true } label: {
                    Label("Ajouter un rappel", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Mes rappels")
            } footer: {
                Text("Chaque rappel se déclenche tous les jours à l'heure choisie. Tu peux activer une vérification « bien fait ? » ~1h30 après.")
            }

            // ---- Pause générale ----
            Section {
                Toggle("Tout mettre en pause", isOn: $muted)
                    .tint(.red)
                    .onChange(of: muted) { _, v in
                        if v { NotificationManager.shared.cancelAll() }
                        else { reminders.forEach { reschedule($0) } }
                    }
            } footer: {
                Text("Coupe temporairement toutes les notifications de l'app.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { _ = await NotificationManager.shared.requestAuthorization() }
        .sheet(isPresented: $showAdd) {
            ReminderEditor { title, message, hour, minute, confirm in
                let r = CustomReminder(title: title, message: message, hour: hour, minute: minute, confirm: confirm)
                ctx.insert(r)
                reschedule(r)
            }
        }
    }

    private func reminderRow(_ r: CustomReminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title.isEmpty ? "Rappel" : r.title).font(.body.weight(.medium))
                Text(String(format: "%02d:%02d", r.hour, r.minute) + (r.confirm ? " · vérif +1h30" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { r.enabled }, set: { r.enabled = $0; reschedule(r) }))
                .labelsHidden()
        }
    }

    private func deleteReminders(_ idx: IndexSet) {
        for i in idx {
            let r = reminders[i]
            let id = "custom.\(r.persistentModelID.hashValue)"
            NotificationManager.shared.cancel(id: id)
            NotificationManager.shared.cancel(id: id + ".confirm")
            ctx.delete(r)
        }
    }

    private func reschedule(_ r: CustomReminder) {
        let id = "custom.\(r.persistentModelID.hashValue)"
        NotificationManager.shared.cancel(id: id)
        NotificationManager.shared.cancel(id: id + ".confirm")
        guard r.enabled && !muted else { return }
        NotificationManager.shared.scheduleDaily(
            id: id,
            title: r.title.isEmpty ? "Rappel" : r.title,
            body: r.message.isEmpty ? "C'est l'heure !" : r.message,
            hour: r.hour, minute: r.minute)
        if r.confirm {
            let total = r.hour * 60 + r.minute + 90
            NotificationManager.shared.scheduleDailyAction(
                id: id + ".confirm",
                title: "Petite vérif",
                body: "Tu as bien fait : \(r.title.isEmpty ? "ton rappel" : r.title) ?",
                hour: (total / 60) % 24, minute: total % 60,
                categoryId: "LIFEOS_CONFIRM",
                userInfo: ["confirmKey": id, "confirmLabel": r.title])
        }
    }
}

// MARK: - Éditeur d'un rappel

struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (_ title: String, _ message: String, _ hour: Int, _ minute: Int, _ confirm: Bool) -> Void

    @State private var title = ""
    @State private var message = ""
    @State private var time = Date()
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rappel") {
                    TextField("Titre (ex: Étirements, Lecture…)", text: $title)
                    TextField("Message", text: $message, axis: .vertical).lineLimit(1...3)
                    DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section {
                    Toggle("Vérification « bien fait ? » ~1h30 après", isOn: $confirm)
                } footer: {
                    Text("Une 2e notif avec « Oui / Pas encore » pour construire ta série.")
                }
            }
            .navigationTitle("Nouveau rappel").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onSave(title.trimmingCharacters(in: .whitespaces), message,
                               c.hour ?? 9, c.minute ?? 0, confirm)
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
