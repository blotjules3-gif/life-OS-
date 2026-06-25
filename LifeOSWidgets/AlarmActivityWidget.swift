import ActivityKit
import SwiftUI
import WidgetKit

struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes.self) { context in
            LockScreenAlarmView(state: context.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.07, blue: 0.12))
                .widgetURL(URL(string: "lifeos://briefing")!)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseIcon(phase: context.state.phase, size: 22)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.timeString)
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                PhaseIcon(phase: context.state.phase, size: 14)
            } compactTrailing: {
                Text(context.state.timeString)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                PhaseIcon(phase: context.state.phase, size: 13)
            }
        }
    }
}

// MARK: - Lock Screen — grande vue principale

struct LockScreenAlarmView: View {
    let state: AlarmAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .scheduled:
            ScheduledView(alarmTime: state.timeString)
        case .ringing:
            RingingView(timeString: state.timeString)
        case .speakingMessage:
            SpeakingView(timeString: state.timeString, message: state.message)
        case .waitingUnlock:
            WaitingUnlockView(timeString: state.timeString)
        case .briefing:
            BriefingView(timeString: state.timeString)
        case .dismissed:
            DismissedView()
        }
    }
}

// MARK: - Phase : Programmé (toute la nuit)

struct ScheduledView: View {
    let alarmTime: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("RÉVEIL PROGRAMMÉ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .kerning(0.8)
                Spacer()
                Text("LifeOS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.bottom, 10)

            Text(alarmTime)
                .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.bottom, 4)

            Text("Écoute ce que tu as de prévu.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 0.95))

            Text("Déverouille ton téléphone pour suivre le reste.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

// MARK: - Phase : Sonnerie

struct RingingView: View {
    let timeString: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: "alarm.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, options: .repeating)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("RÉVEIL")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.orange).kerning(0.8)
                Text("C'est l'heure de te lever")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Text(timeString)
                .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}

// MARK: - Phase : Message vocal en cours

struct SpeakingView: View {
    let timeString: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)
                        .symbolEffect(.variableColor.iterative.reversing, options: .speed(1.6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MESSAGE VOCAL")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.blue).kerning(0.8)
                    Text(timeString)
                        .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(3)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}

// MARK: - Phase : Attente déverrouillage

struct WaitingUnlockView: View {
    let timeString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(red: 0.2, green: 0.78, blue: 0.68).opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.68))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BRIEFING PRÊT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.68))
                        .kerning(0.8)
                    Text(timeString)
                        .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.68))
                Text("Déverouille pour le briefing visuel complet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.68))
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Color(red: 0.2, green: 0.78, blue: 0.68).opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}

// MARK: - Phase : Briefing ouvert

struct BriefingView: View {
    let timeString: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.18)).frame(width: 46, height: 46)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.purple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("BRIEFING DU MATIN")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.purple).kerning(0.8)
                Text("Bonne journée !").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Text(timeString)
                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}

// MARK: - Phase : Terminé

struct DismissedView: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.green)
            Text("Bonne journée !")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}

// MARK: - Dynamic Island icon

struct PhaseIcon: View {
    let phase: AlarmAttributes.ContentState.Phase
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    var color: Color {
        switch phase {
        case .scheduled:       .white.opacity(0.7)
        case .ringing:         .orange
        case .speakingMessage: .blue
        case .waitingUnlock:   Color(red: 0.2, green: 0.78, blue: 0.68)
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    var symbol: String {
        switch phase {
        case .scheduled:       "moon.stars.fill"
        case .ringing:         "alarm.fill"
        case .speakingMessage: "waveform"
        case .waitingUnlock:   "lock.open.fill"
        case .briefing:        "sun.horizon.fill"
        case .dismissed:       "checkmark.circle.fill"
        }
    }
}
