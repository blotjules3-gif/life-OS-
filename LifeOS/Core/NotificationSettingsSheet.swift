import SwiftUI
import UserNotifications

struct NotificationSettingsSheet: View {
    let modules: [AppCategory]
    @Binding var sportHour: Int
    @Binding var bedHour: Int
    @Binding var bedMinute: Int
    @Binding var wakeupHour: Int
    @Binding var wakeupMinute: Int

    @AppStorage("notifEnabled.morning")   private var enableMorning   = true
    @AppStorage("notifEnabled.sport")     private var enableSport      = true
    @AppStorage("notifEnabled.nutrition") private var enableNutrition  = true
    @AppStorage("notifEnabled.habits")    private var enableHabits     = true
    @AppStorage("notifEnabled.bedtime")   private var enableBedtime    = true

    @Environment(\.dismiss) private var dismiss
    @State private var authorized = false

    private var morningTime: String {
        let total = (wakeupHour * 60 + wakeupMinute + 30) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    private var bedtimeNotifTime: String {
        let total = ((bedHour * 60 + bedMinute) - 30 + 1440) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    private var wakeupDate: Date {
        var c = DateComponents(); c.hour = wakeupHour; c.minute = wakeupMinute
        return Calendar.current.date(from: c) ?? Date()
    }
    private var bedDate: Date {
        var c = DateComponents(); c.hour = bedHour; c.minute = bedMinute
        return Calendar.current.date(from: c) ?? Date()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: authorized ? "bell.badge.fill" : "bell.slash.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(authorized ? Color(hex: 0x4CC38A) : Color(hex: 0xF1746C))
                            .frame(width: 32, height: 32)
                            .background(
                                (authorized ? Color(hex: 0x4CC38A) : Color(hex: 0xF1746C)).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authorized ? "Notifications autorisées" : "Notifications désactivées")
                                .font(.system(size: 15, weight: .medium))
                            Text(authorized ? "Les rappels peuvent s'afficher." : "Appuie pour autoriser.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !authorized {
                            Button("Activer") {
                                Task {
                                    let granted = await NotificationManager.shared.requestAuthorization()
                                    withAnimation { authorized = granted }
                                    if granted { ContextualNotifications.shared.reschedule() }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Rappels programmés") {
                    if modules.contains(.sleep) || modules.contains(.fitness) || modules.contains(.mind) {
                        notifRow(
                            icon: "sunrise.fill", color: Color(hex: 0xE0A23C),
                            title: "Bilan du matin",
                            subtitle: "À \(morningTime) — 30 min après le réveil",
                            enabled: $enableMorning
                        ) {
                            DatePicker("", selection: Binding(
                                get: { wakeupDate },
                                set: { d in
                                    wakeupHour = Calendar.current.component(.hour, from: d)
                                    wakeupMinute = Calendar.current.component(.minute, from: d)
                                    ContextualNotifications.shared.reschedule()
                                }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Color(hex: 0xE0A23C))
                            Text("Réveil").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }

                    if modules.contains(.fitness) {
                        notifRow(
                            icon: "figure.run", color: Color(hex: 0x4CC38A),
                            title: "Sport",
                            subtitle: "Rappel pour bouger",
                            enabled: $enableSport
                        ) {
                            Picker("", selection: $sportHour) {
                                ForEach(6..<23) { h in
                                    Text(String(format: "%02d:00", h)).tag(h)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(hex: 0x4CC38A))
                            .onChange(of: sportHour) { _, _ in ContextualNotifications.shared.reschedule() }
                        }
                    }

                    if modules.contains(.nutrition) {
                        notifRow(
                            icon: "fork.knife", color: Color(hex: 0xE0A23C),
                            title: "Nutrition soir",
                            subtitle: "À 19:30 — noter le dîner",
                            enabled: $enableNutrition
                        )
                    }

                    if modules.contains(.productivity) || modules.contains(.fitness) || modules.contains(.mind) || modules.contains(.sleep) {
                        notifRow(
                            icon: "checklist", color: Color(hex: 0x9B6CF1),
                            title: "Habitudes du soir",
                            subtitle: "À 20:00 — bilan de journée",
                            enabled: $enableHabits
                        )
                    }

                    if modules.contains(.sleep) {
                        notifRow(
                            icon: "moon.stars.fill", color: Color(hex: 0x6C7BF1),
                            title: "Coucher",
                            subtitle: "Notif à \(bedtimeNotifTime) — 30 min avant",
                            enabled: $enableBedtime
                        ) {
                            DatePicker("", selection: Binding(
                                get: { bedDate },
                                set: { d in
                                    bedHour = Calendar.current.component(.hour, from: d)
                                    bedMinute = Calendar.current.component(.minute, from: d)
                                    ContextualNotifications.shared.reschedule()
                                }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Color(hex: 0x6C7BF1))
                            Text("Heure coucher").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }

                    if modules.isEmpty {
                        Text("Aucun module actif — aucun rappel planifié.")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }

                Section("Récurrents") {
                    notifRow(
                        icon: "calendar.badge.clock", color: Color.accentColor,
                        title: "Bilan de semaine",
                        subtitle: "Dimanche à 20:00",
                        enabled: .constant(true)
                    )
                }
            }
            .navigationTitle("Mes rappels")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                authorized = settings.authorizationStatus == .authorized
            }
        }
    }

    @ViewBuilder
    private func notifRow<Extra: View>(
        icon: String, color: Color, title: String, subtitle: String,
        enabled: Binding<Bool>,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(enabled.wrappedValue ? color : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        (enabled.wrappedValue ? color : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(enabled.wrappedValue ? .primary : .secondary)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .tint(color)
                    .onChange(of: enabled.wrappedValue) { _, _ in
                        ContextualNotifications.shared.reschedule()
                    }
            }
            .padding(.vertical, 6)

            let extraView = extra()
            if enabled.wrappedValue, !(extraView is EmptyView) {
                HStack(spacing: 8) {
                    extraView
                }
                .padding(.leading, 44)
                .padding(.bottom, 6)
            }
        }
    }
}
