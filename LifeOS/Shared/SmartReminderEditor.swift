import SwiftUI

/// Éditeur riche pour créer ou modifier un `CustomReminder` avec toutes les
/// options : fréquence (unique / toutes les X heures / plusieurs horaires),
/// fenêtre horaire, jours actifs, catégorie associée.
///
/// Fonctionne en 2 modes :
///   - Création : `reminder = nil` → construit un nouveau CustomReminder
///     via `onSave(reminder)`
///   - Édition : `reminder` fourni → mute les propriétés directement + appelle
///     `onSave(reminder)` (SwiftData observe les changements @Model).
struct SmartReminderEditor: View {
    @Environment(\.dismiss) private var dismiss

    let reminder: CustomReminder?
    var onSave: (CustomReminder) -> Void

    @State private var title: String = ""
    @State private var message: String = ""
    @State private var frequency: CustomReminder.Frequency = .daily
    @State private var dailyTime: Date = defaultTime(hour: 9)
    @State private var intervalHours: Int = 2
    @State private var windowStartHour: Int = 8
    @State private var windowEndHour: Int = 20
    @State private var weekdayMask: Int = WeekdayMask.all
    @State private var specificHours: Set<Int> = [9, 13, 18]
    @State private var confirm: Bool = false
    @State private var selectedCategory: AppCategory? = nil

    private var isNew: Bool { reminder == nil }
    private var canSave: Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        switch frequency {
        case .daily:
            return true
        case .everyXHours:
            return windowStartHour < windowEndHour && intervalHours >= 1
        case .multipleTimes:
            return !specificHours.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rappel") {
                    TextField("Titre (ex: Hydratation, Posture…)", text: $title)
                    TextField("Message (optionnel)", text: $message, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Fréquence") {
                    Picker("Type", selection: $frequency) {
                        ForEach(CustomReminder.Frequency.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .pickerStyle(.menu)

                    Group {
                        switch frequency {
                        case .daily:
                            DatePicker("Heure", selection: $dailyTime, displayedComponents: .hourAndMinute)
                        case .everyXHours:
                            Stepper(value: $intervalHours, in: 1...12) {
                                HStack {
                                    Text("Intervalle")
                                    Spacer()
                                    Text("Toutes les \(intervalHours)h")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            Stepper(value: $windowStartHour, in: 0...23) {
                                HStack {
                                    Text("De")
                                    Spacer()
                                    Text("\(windowStartHour)h00").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            Stepper(value: $windowEndHour, in: 0...23) {
                                HStack {
                                    Text("À")
                                    Spacer()
                                    Text("\(windowEndHour)h00").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            if windowEndHour <= windowStartHour {
                                Label("L'heure de fin doit être après le début.",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        case .multipleTimes:
                            multiTimesGrid
                        }
                    }
                }

                Section("Jours actifs") {
                    weekdaysRow
                    HStack {
                        presetButton("Tous", mask: WeekdayMask.all)
                        presetButton("Semaine", mask: WeekdayMask.weekdays)
                        presetButton("Week-end", mask: WeekdayMask.weekend)
                    }
                    // Loop 23 fix M3 — warning si aucun jour actif
                    if weekdayMask == 0 {
                        Label("Aucun jour sélectionné — le rappel ne se déclenchera jamais.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                Section("Catégorie") {
                    Picker("Associer à un domaine", selection: $selectedCategory) {
                        Text("Aucune").tag(AppCategory?.none)
                        ForEach(AppCategory.allCases) { cat in
                            Label(cat.title, systemImage: cat.icon).tag(AppCategory?.some(cat))
                        }
                    }
                }

                if frequency == .daily {
                    Section {
                        Toggle("Vérification « bien fait ? » ~1h30 après", isOn: $confirm)
                    } footer: {
                        Text("Une 2e notif avec « Oui / Pas encore » pour construire ta série.")
                    }
                }
            }
            .navigationTitle(isNew ? "Nouveau rappel" : "Modifier le rappel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Créer" : "Enregistrer") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadFromReminder)
        }
    }

    // MARK: - Multi-times grid

    private var multiTimesGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(0..<24) { h in
                Button {
                    if specificHours.contains(h) { specificHours.remove(h) }
                    else { specificHours.insert(h) }
                } label: {
                    Text("\(h)h")
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            specificHours.contains(h) ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(specificHours.contains(h) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Weekdays row

    private var weekdaysRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<7) { i in
                let active = WeekdayMask.isActive(weekdayMask, weekdayIndex: i)
                Button {
                    weekdayMask ^= (1 << i)
                } label: {
                    Text(WeekdayMask.dayLabels[i])
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(
                            active ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                            in: Circle()
                        )
                        .foregroundStyle(active ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presetButton(_ label: String, mask: Int) -> some View {
        Button {
            weekdayMask = mask
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load / Save

    private func loadFromReminder() {
        guard let r = reminder else { return }
        title = r.title
        message = r.message
        frequency = r.frequency
        dailyTime = Self.defaultTime(hour: r.hour, minute: r.minute)
        intervalHours = r.intervalHours
        windowStartHour = r.windowStartHour
        windowEndHour = r.windowEndHour
        weekdayMask = r.weekdayMask
        specificHours = Set(r.specificHours)
        confirm = r.confirm
        selectedCategory = AppCategory(rawValue: r.categoryRaw)
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
        let h = comps.hour ?? 9
        let m = comps.minute ?? 0

        let target: CustomReminder
        if let existing = reminder {
            target = existing
            target.title = title.trimmingCharacters(in: .whitespaces)
            target.message = message
            target.frequency = frequency
            target.hour = h
            target.minute = m
            target.intervalHours = intervalHours
            target.windowStartHour = windowStartHour
            target.windowEndHour = windowEndHour
            target.weekdayMask = weekdayMask
            target.specificHours = Array(specificHours)
            target.confirm = confirm
            target.categoryRaw = selectedCategory?.rawValue ?? ""
        } else {
            target = CustomReminder(
                title: title.trimmingCharacters(in: .whitespaces),
                message: message,
                hour: h, minute: m,
                enabled: true, confirm: confirm,
                frequencyRaw: frequency.rawValue,
                intervalHours: intervalHours,
                windowStartHour: windowStartHour,
                windowEndHour: windowEndHour,
                weekdayMask: weekdayMask,
                specificHoursJSON: (try? String(data: JSONEncoder().encode(Array(specificHours).sorted()), encoding: .utf8)) ?? "[]",
                categoryRaw: selectedCategory?.rawValue ?? ""
            )
        }
        onSave(target)
        dismiss()
    }

    // MARK: - Helpers

    private static func defaultTime(hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? .now
    }
}
