import SwiftUI

struct WakeUpView: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("wakeupEnabled") private var wakeupEnabled = false
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @State private var alarmTime: Date = {
        var c = Calendar.current
        return c.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    }()
    @State private var showBriefing = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    alarmCard
                    planPreviewSection
                }
                .padding(Theme.pad)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Réveil")
            .fullScreenCover(isPresented: $showBriefing) {
                DailyBriefingView(modules: recommendedModules)
            }
        }
    }

    private var alarmTimeLabel: String {
        let h = Calendar.current.component(.hour, from: alarmTime)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH'h'mm"
        formatter.locale = Locale(identifier: "fr_FR")
        let period = h < 12 ? "du matin" : h < 18 ? "de l'après-midi" : "du soir"
        return "\(formatter.string(from: alarmTime)) \(period)"
    }

    private var alarmCard: some View {
        VStack(spacing: 12) {
            Text(alarmTimeLabel)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .animation(.spring(duration: 0.3), value: alarmTimeLabel)

            DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: alarmTime) { _, val in
                    let c = Calendar.current
                    wakeupHour = c.component(.hour, from: val)
                    wakeupMinute = c.component(.minute, from: val)
                    if wakeupEnabled { scheduleWakeupAlarm() }
                }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            Toggle("Réveil quotidien activé", isOn: $wakeupEnabled)
                .tint(Color.accentColor)
                .onChange(of: wakeupEnabled) { _, on in
                    if on { scheduleWakeupAlarm() } else { cancelAlarm() }
                }
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var planPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan du jour")
            .font(.system(size: 15, weight: .semibold))

            Button { showBriefing = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFF9F0A))
                        .frame(width: 40, height: 40)
                        .background(Color(hex: 0xFF9F0A).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lancer ma journée")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Voir mes priorités et objectifs du jour")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())

            if !recommendedModules.isEmpty {
                Text("Modules prioritaires")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(recommendedModules.prefix(5)) { cat in
                    NavigationLink { cat.destination } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(cat.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cat.title).font(.system(size: 14, weight: .medium))
                                Text(cat.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
            }
        }
    }

    private func scheduleWakeupAlarm() {
        Task {
            guard await NotificationManager.shared.requestAuthorization() else { return }
            NotificationManager.shared.scheduleAlarm(hour: wakeupHour, minute: wakeupMinute, userName: userName)
            let timeString = String(format: "%02d:%02d", wakeupHour, wakeupMinute)
            if #available(iOS 16.1, *) {
                await AlarmLiveActivityManager.shared.startScheduled(alarmTimeString: timeString)
            }
        }
    }

    private func cancelAlarm() {
        NotificationManager.shared.cancel(id: "lifeos.wakeup")
        if #available(iOS 16.1, *) {
            AlarmLiveActivityManager.shared.end()
        }
    }
}
