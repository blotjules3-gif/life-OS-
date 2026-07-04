import SwiftUI

struct WakeUpView: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("wakeupEnabled") private var wakeupEnabled = false
    @AppStorage("wakeupHour") private var wakeupHour = 7
    @AppStorage("wakeupMinute") private var wakeupMinute = 0
    @AppStorage("wakeupRepeatDays") private var repeatDaysRaw = "1,2,3,4,5,6,7"
    @AppStorage("snoozeMinutes") private var snoozeMinutes = 9
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var alarmTime: Date = .now
    @State private var showPicker = false
    @State private var showBriefing = false
    @State private var appeared = false

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    private var selectedDays: Set<Int> {
        Set(repeatDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    // Jours stockés en base lundi (1 = Lun … 7 = Dim), Calendar.weekday en base dimanche.
    private func mondayBasedWeekday(of date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7 + 1
    }

    private func nextAlarmDate(from ref: Date) -> Date? {
        guard wakeupEnabled, !selectedDays.isEmpty else { return nil }
        let cal = Calendar.current
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: ref),
                  let fire = cal.date(bySettingHour: wakeupHour, minute: wakeupMinute, second: 0, of: day)
            else { continue }
            if fire > ref, selectedDays.contains(mondayBasedWeekday(of: fire)) { return fire }
        }
        return nil
    }

    private func countdownLabel(from ref: Date) -> String {
        guard let fire = nextAlarmDate(from: ref) else { return "Réveil coupé" }
        let mins = max(1, Int(fire.timeIntervalSince(ref) / 60))
        let h = mins / 60, m = mins % 60
        if h >= 24 {
            let dayName = fire.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
            return "Sonne \(dayName)"
        }
        if h == 0 { return "Sonne dans \(m) min" }
        return "Sonne dans \(h) h \(String(format: "%02d", m))"
    }

    private var suggestedBedtime: String {
        let bedHour = (wakeupHour + 16) % 24
        return String(format: "%02d:%02d", bedHour, wakeupMinute)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    header
                        .staggered(0, appeared: appeared)
                    heroCard
                        .staggered(1, appeared: appeared)
                        .scrollFade()
                    daysCard
                        .staggered(2, appeared: appeared)
                        .scrollFade()
                    detailsCard
                        .staggered(3, appeared: appeared)
                        .scrollFade()
                    launchButton
                        .staggered(4, appeared: appeared)
                        .scrollFade()
                    morningPlanSection
                        .staggered(5, appeared: appeared)
                        .scrollFade()
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                alarmTime = Calendar.current.date(bySettingHour: wakeupHour, minute: wakeupMinute,
                                                  second: 0, of: .now) ?? .now
                appeared = true
            }
            .fullScreenCover(isPresented: $showBriefing) {
                DailyBriefingView(modules: recommendedModules)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Réveil")
                .font(.system(size: 40, weight: .black))
                .textCase(.uppercase)
                .kerning(-1)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(countdownLabel(from: context.date))
                    .monoLabel(11)
                    .foregroundStyle(wakeupEnabled ? AnyShapeStyle(Theme.textSecondary) : AnyShapeStyle(.tertiary))
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Heure

    private var heroCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                                           : .spring(duration: 0.45, bounce: 0.15)) {
                    showPicker.toggle()
                }
            } label: {
                VStack(spacing: 10) {
                    Text(String(format: "%02d:%02d", wakeupHour, wakeupMinute))
                        .font(.system(size: 76, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(wakeupEnabled ? .primary : .secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.38, bounce: 0.1), value: wakeupHour)
                        .animation(.spring(duration: 0.38, bounce: 0.1), value: wakeupMinute)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(showPicker ? "Valider" : "Modifier l'heure")
                            .monoLabel(10)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showPicker ? 180 : 0))
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(LifeOSPressStyle())

            if showPicker {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Réveil quotidien")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(wakeupEnabled ? "Notification + écran de réveil" : "Aucune sonnerie programmée")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $wakeupEnabled)
                    .labelsHidden()
                    .tint(Color.accentColor)
                    .onChange(of: wakeupEnabled) { _, on in
                        if on { scheduleWakeupAlarm() } else { cancelAlarm() }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .softElevation()
    }

    // MARK: - Jours actifs

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jours actifs")
                .monoLabel(10)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(dayLetters.enumerated()), id: \.offset) { idx, letter in
                    let day = idx + 1
                    let on = selectedDays.contains(day)
                    Button {
                        var days = selectedDays
                        if on { days.remove(day) } else { days.insert(day) }
                        repeatDaysRaw = days.sorted().map(String.init).joined(separator: ",")
                        if wakeupEnabled { scheduleWakeupAlarm() }
                    } label: {
                        Text(letter)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(on ? Theme.onAccent : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.05)),
                                in: RoundedRectangle(cornerRadius: Theme.radiusSmall - 2, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall - 2, style: .continuous))
                            .animation(.spring(duration: 0.3, bounce: 0.15), value: on)
                    }
                    .buttonStyle(LifeOSPressStyle())
                    .accessibilityLabel("\(letter), \(on ? "actif" : "inactif")")
                }
            }
        }
        .padding(16)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .softElevation()
    }

    // MARK: - Sommeil + snooze

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x9B6CF1))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0x9B6CF1).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Coucher conseillé")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Pour 8 h de sommeil complet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(suggestedBedtime)
                    .font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(hex: 0x9B6CF1))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.38, bounce: 0.1), value: suggestedBedtime)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 60)

            HStack(spacing: 12) {
                Image(systemName: "zzz")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x3CB2E0))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0x3CB2E0).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Snooze")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Stepper("", value: $snoozeMinutes, in: 5...30, step: 5)
                    .labelsHidden()
                Text("\(snoozeMinutes) min")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: snoozeMinutes)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .softElevation()
    }

    // MARK: - CTA

    private var launchButton: some View {
        Button { showBriefing = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("Lancer ma journée")
                    .font(.system(size: 15, weight: .black))
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.radiusSmall + 2, style: .continuous))
        }
        .buttonStyle(LifeOSPressStyle())
    }

    // MARK: - Plan du matin

    private var morningPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan du matin")
                    .font(.system(size: 20, weight: .black))
                    .textCase(.uppercase)
                    .kerning(-0.3)
                Spacer()
                if !recommendedModules.isEmpty {
                    Text("\(min(recommendedModules.count, 5)) pôles")
                        .monoLabel(10)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if recommendedModules.isEmpty {
                Text("Choisis tes pôles prioritaires dans Profil pour construire ton briefing du matin.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recommendedModules.prefix(5).enumerated()), id: \.element.rawValue) { idx, cat in
                        NavigationLink { cat.destination } label: {
                            HStack(spacing: 12) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(cat.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cat.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(cat.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(LifeOSPressStyle())
                        if idx < min(recommendedModules.count, 5) - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 60)
                        }
                    }
                }
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
                .softElevation()
            }
        }
    }

    // MARK: - Alarme

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
