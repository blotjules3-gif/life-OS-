import SwiftUI
import SwiftData

// MARK: - Centre de notifications

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CustomReminder.created, order: .reverse) private var reminders: [CustomReminder]

    @AppStorage(AppStorageKeys.morningReminderOn)   private var morningOn = true
    @AppStorage(AppStorageKeys.morningReminderText) private var morningText = MorningReminder.defaultText
    @AppStorage(AppStorageKeys.notifMasterMute)     private var muted = false
    @AppStorage(AppStorageKeys.smartNotifsEnabled)  private var smartNotifsOn = false
    @AppStorage(AppStorageKeys.cloudKitEnabled)     private var cloudKitOn = false

    @State private var editing: CustomReminder?
    @State private var creatingNew = false

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

            // ---- Suggestions intelligentes ----
            suggestionsSection

            // ---- Rappels perso ----
            Section {
                if reminders.isEmpty {
                    Text("Aucun rappel. Utilise les suggestions ci-dessus ou crée-en un.")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                ForEach(reminders) { r in reminderRow(r) }
                    .onDelete(perform: deleteReminders)
                Button { creatingNew = true } label: {
                    Label("Créer un rappel", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Mes rappels")
            } footer: {
                Text("Chaque rappel se déclenche selon la fréquence choisie (heure fixe, toutes les X heures, ou plusieurs horaires précis).")
            }

            // ---- Notifications intelligentes cross-pôles ----
            Section {
                Toggle("Notifications intelligentes", isOn: $smartNotifsOn)
                    .tint(.accentColor)
            } header: {
                Text("Coach intelligent")
            } footer: {
                Text("3 notifs / jour générées à partir de ton état réel (sommeil × cycle × sport × humeur).")
            }

            // ---- Sync iCloud ----
            Section {
                Toggle("Synchroniser via iCloud", isOn: $cloudKitOn)
                    .tint(.accentColor)
            } header: {
                Text("Sauvegarde")
            } footer: {
                Text("Tes données restent chiffrées de bout en bout par Apple, jamais visibles par LifeOS. Retrouve-les sur iPhone + iPad avec le même Apple ID.")
            }

            // ---- Pause générale ----
            Section {
                Toggle("Tout mettre en pause", isOn: $muted)
                    .tint(.red)
                    .onChange(of: muted) { _, v in
                        if v {
                            NotificationManager.shared.cancelAll()
                        } else {
                            SmartReminderScheduler.rescheduleAll(reminders)
                        }
                    }
            } footer: {
                Text("Coupe temporairement toutes les notifications de l'app.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { _ = await NotificationManager.shared.requestAuthorization() }
        .sheet(isPresented: $creatingNew) {
            SmartReminderEditor(reminder: nil) { newR in
                ctx.insert(newR)
                try? ctx.save()
                SmartReminderScheduler.reschedule(newR)
            }
        }
        .sheet(item: $editing) { r in
            SmartReminderEditor(reminder: r) { _ in
                try? ctx.save()
                SmartReminderScheduler.reschedule(r)
            }
        }
    }

    // MARK: - Suggestions section

    @ViewBuilder
    private var suggestionsSection: some View {
        let suggestions = SmartReminderSuggestionEngine.suggestions(existingReminders: reminders)
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { sug in
                    suggestionRow(sug)
                }
            } header: {
                Text("Suggestions pour toi")
            } footer: {
                Text("Générées à partir de tes modules actifs.")
            }
        }
    }

    private func suggestionRow(_ sug: SmartReminderSuggestionEngine.Suggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sug.category?.icon ?? "bell.badge")
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(sug.title).font(.subheadline.weight(.medium))
                Text(sug.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                addFromSuggestion(sug)
            } label: {
                Text("Ajouter")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func addFromSuggestion(_ sug: SmartReminderSuggestionEngine.Suggestion) {
        let r = CustomReminder(
            title: sug.title,
            message: sug.message,
            hour: sug.windowStartHour,
            minute: 0,
            enabled: true,
            confirm: false,
            frequencyRaw: sug.frequency.rawValue,
            intervalHours: sug.intervalHours,
            windowStartHour: sug.windowStartHour,
            windowEndHour: sug.windowEndHour,
            weekdayMask: sug.weekdayMask,
            specificHoursJSON: (try? String(data: JSONEncoder().encode(sug.specificHours), encoding: .utf8)) ?? "[]",
            categoryRaw: sug.categoryRaw
        )
        ctx.insert(r)
        try? ctx.save()
        SmartReminderScheduler.reschedule(r)
    }

    // MARK: - Reminder row

    private func reminderRow(_ r: CustomReminder) -> some View {
        Button {
            editing = r
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconFor(categoryRaw: r.categoryRaw))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title.isEmpty ? "Rappel" : r.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(scheduleDescription(r))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { r.enabled },
                    set: { r.enabled = $0; try? ctx.save(); SmartReminderScheduler.reschedule(r) }
                ))
                .labelsHidden()
            }
        }
        .buttonStyle(.plain)
    }

    private func iconFor(categoryRaw: String) -> String {
        AppCategory(rawValue: categoryRaw)?.icon ?? "bell.fill"
    }

    private func scheduleDescription(_ r: CustomReminder) -> String {
        switch r.frequency {
        case .daily:
            return String(format: "%02d:%02d — chaque jour actif", r.hour, r.minute)
        case .everyXHours:
            return "Toutes les \(r.intervalHours)h · \(r.windowStartHour)h → \(r.windowEndHour)h · \(daysLabel(r.weekdayMask))"
        case .multipleTimes:
            let hs = r.specificHours.map { String(format: "%dh", $0) }.joined(separator: " · ")
            return hs.isEmpty ? "Aucun horaire défini" : "\(hs) · \(daysLabel(r.weekdayMask))"
        }
    }

    private func daysLabel(_ mask: Int) -> String {
        if mask == WeekdayMask.all { return "tous les jours" }
        if mask == WeekdayMask.weekdays { return "en semaine" }
        if mask == WeekdayMask.weekend { return "week-end" }
        return (0...6).compactMap { WeekdayMask.isActive(mask, weekdayIndex: $0) ? WeekdayMask.dayLabels[$0] : nil }
            .joined(separator: " ")
    }

    private func deleteReminders(_ idx: IndexSet) {
        for i in idx {
            let r = reminders[i]
            SmartReminderScheduler.cancel(r)
            NotificationManager.shared.cancel(id: SmartReminderScheduler.baseIdentifier(r) + ".confirm")
            ctx.delete(r)
        }
        try? ctx.save()
    }
}
