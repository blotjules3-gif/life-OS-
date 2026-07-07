import SwiftUI

// MARK: - Formulaire de configuration « Sommeil & réveil »
// Pré-remplit : heure de réveil, durée cible, réveil activé, heure de coucher conseillée.

struct SleepSetupView: View {
    @AppStorage("wakeupHour")      private var wakeupHour = 7
    @AppStorage("wakeupMinute")    private var wakeupMinute = 0
    @AppStorage("wakeupEnabled")   private var wakeupEnabled = false
    @AppStorage("sleepTargetHours") private var sleepTarget = 8

    @State private var wake = 7
    @State private var duration = 8
    @State private var enable = "Oui"

    private let tint = AppCategory.sleep.tint

    var body: some View {
        SetupFlow(title: "Sommeil & réveil", accent: tint, pages: pages, onComplete: commit)
            .onAppear { wake = wakeupHour; duration = sleepTargetHours; enable = wakeupEnabled ? "Oui" : "Non" }
    }
    private var sleepTargetHours: Int { sleepTarget }

    private var bedHour: Int {
        var h = wake - duration
        if h < 0 { h += 24 }
        return h
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "moon.stars.fill", title: "Ton réveil",
                                subtitle: "À quelle heure veux-tu te lever en semaine ?", accent: tint)
                    SetupNumber(value: $wake, unit: "h", range: 4...12, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "bed.double.fill", title: "Combien d'heures de sommeil ?",
                                subtitle: "La plupart des adultes ont besoin de 7 à 9 h.", accent: tint)
                    SetupNumber(value: $duration, unit: "h", range: 5...11, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "alarm.fill", title: "Activer le réveil LifeOS ?", accent: tint)
                    SetupChoice(options: ["Oui", "Non"], selection: $enable, accent: tint,
                                icons: ["checkmark.circle", "xmark.circle"])
                    summary
                }
            }
        ]
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric(String(format: "%02d:00", bedHour), "Coucher conseillé", "moon.fill")
            metric(String(format: "%02d:00", wake), "Réveil", "sunrise.fill")
        }.padding(.horizontal, 14)
    }
    private func metric(_ v: String, _ l: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(v).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func commit() {
        wakeupHour = wake
        wakeupMinute = 0
        sleepTarget = duration
        wakeupEnabled = (enable == "Oui")
        if wakeupEnabled {
            Task { _ = await NotificationManager.shared.requestAuthorization() }
            NotificationManager.shared.scheduleAlarm(hour: wake, minute: 0,
                                                     userName: UserDefaults.standard.string(forKey: "userName") ?? "")
        }
        CategorySetup.markDone(.sleep)
        Haptics.success()
    }
}
