import SwiftUI

struct WakeUpPersonalizationSheet: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var enabled: Bool
    @Binding var modulesRaw: String
    let onSchedule: () -> Void

    @AppStorage("userName") private var userName = ""
    @AppStorage("wakeupRepeatDays") private var repeatDaysRaw = "1,2,3,4,5,6,7"
    @AppStorage("wakeupMessage") private var customMessage = ""
    @AppStorage("snoozeMinutes") private var snoozeMinutes = 9
    @Environment(\.dismiss) private var dismiss

    @State private var alarmTime: Date = .now

    private let allModules: [(AppCategory, String, String)] = [
        (.nutrition, "Nutrition", "fork.knife"),
        (.fitness,   "Fitness",   "figure.run"),
        (.sleep,     "Sommeil",   "moon.stars.fill"),
        (.mind,      "Mental",    "brain.head.profile"),
        (.productivity, "Productivité", "checklist"),
        (.finance,   "Finance",   "creditcard.fill"),
    ]

    private let dayNames = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private var selectedDays: Set<Int> {
        Set(repeatDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var selectedModules: Set<String> {
        Set(modulesRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            alarmTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
                        }
                        .onChange(of: alarmTime) { _, val in
                            let c = Calendar.current
                            hour = c.component(.hour, from: val)
                            minute = c.component(.minute, from: val)
                        }
                    Toggle("Réveil activé", isOn: $enabled)
                        .tint(Color(hex: 0xE07B3C))
                } header: { Text("Heure de réveil") }

                Section {
                    HStack(spacing: 6) {
                        ForEach(Array(dayNames.enumerated()), id: \.offset) { idx, name in
                            let day = idx + 1
                            let on = selectedDays.contains(day)
                            Button {
                                var days = selectedDays
                                if on { days.remove(day) } else { days.insert(day) }
                                repeatDaysRaw = days.sorted().map(String.init).joined(separator: ",")
                            } label: {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(on ? Color(hex: 0xE07B3C) : Theme.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(on ? .white : .secondary)
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(LifeOSPressStyle())
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Jours actifs") }

                Section {
                    ForEach(allModules, id: \.0.rawValue) { cat, label, icon in
                        let on = selectedModules.contains(cat.rawValue)
                        Button {
                            var mods = selectedModules
                            if on { mods.remove(cat.rawValue) } else { mods.insert(cat.rawValue) }
                            modulesRaw = mods.joined(separator: ",")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(cat.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? cat.tint : Color.secondary)
                                    .font(.system(size: 18))
                            }
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }
                } header: { Text("Plan du matin") }
                  footer: { Text("Ces pôles apparaissent en priorité dans ton briefing du matin.") }

                Section {
                    TextField("Ex: C'est ton moment. Fonce.", text: $customMessage)
                        .foregroundStyle(.primary)
                    Stepper("Rappel snooze : \(snoozeMinutes) min", value: $snoozeMinutes, in: 5...30, step: 5)
                } header: { Text("Personnalisation") }
            }
            .navigationTitle("Mon réveil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        if enabled { onSchedule() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}
