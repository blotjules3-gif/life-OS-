import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Palette douce par phase

private enum PhaseColor {
    static let scheduled  = Color(red: 0.52, green: 0.62, blue: 0.95)  // indigo doux
    static let ringing    = Color(red: 0.95, green: 0.65, blue: 0.28)  // ambre chaud
    static let speaking   = Color(red: 0.28, green: 0.78, blue: 0.88)  // cyan doux
    static let unlock     = Color(red: 0.26, green: 0.82, blue: 0.68)  // menthe
    static let briefing   = Color(red: 0.95, green: 0.80, blue: 0.35)  // or chaud
    static let dismissed  = Color(red: 0.45, green: 0.80, blue: 0.56)  // sauge
}

struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes.self) { context in
            LockScreenAlarmView(state: context.state)
                .widgetURL(URL(string: "lifeos://briefing"))
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

// MARK: - Vue principale lock screen

struct LockScreenAlarmView: View {
    let state: AlarmAttributes.ContentState

    @ViewBuilder
    private var phaseView: some View {
        switch state.phase {
        case .scheduled:
            ScheduledView(
                alarmTime: state.timeString,
                temperature: state.temperature,
                weatherSymbol: state.weatherSymbol
            )
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

    var body: some View {
        phaseView
            .id(state.phase)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            .animation(.easeInOut(duration: 0.38), value: state.phase)
    }
}

// MARK: - Programmé (avec météo)

struct ScheduledView: View {
    let alarmTime: String
    let temperature: Double?
    let weatherSymbol: String?
    private let accent = PhaseColor.scheduled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.75))
                Text("RÉVEIL PROGRAMMÉ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent.opacity(0.75))
                    .kerning(0.8)
                Spacer()
                if let temp = temperature, let symbol = weatherSymbol {
                    HStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accent.opacity(0.8))
                        Text("\(Int(temp.rounded()))°")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("LifeOS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            Text(alarmTime)
                .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.bottom, 4)

            Text("Écoute ce que tu as de prévu.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)

            Text("Déverouille ton téléphone pour suivre le reste.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

// MARK: - Sonnerie

struct RingingView: View {
    let timeString: String
    private let accent = PhaseColor.ringing

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: "alarm.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, options: .repeating)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("RÉVEIL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .kerning(0.8)
                Text("C'est l'heure de te lever")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text(timeString)
                .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}

// MARK: - Message vocal

struct SpeakingView: View {
    let timeString: String
    let message: String
    private let accent = PhaseColor.speaking

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                        .symbolEffect(.variableColor.iterative.reversing, options: .speed(1.6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MESSAGE VOCAL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                        .kerning(0.8)
                    Text(timeString)
                        .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}

// MARK: - Attente déverrouillage

struct WaitingUnlockView: View {
    let timeString: String
    private let accent = PhaseColor.unlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BRIEFING PRÊT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                        .kerning(0.8)
                    Text(timeString)
                        .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                Text("Déverouille pour le briefing visuel complet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(accent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}

// MARK: - Briefing ouvert

struct BriefingView: View {
    let timeString: String
    private let accent = PhaseColor.briefing

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 46, height: 46)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("BRIEFING DU MATIN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .kerning(0.8)
                Text("Bonne journée !")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text(timeString)
                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}

// MARK: - Terminé

struct DismissedView: View {
    private let accent = PhaseColor.dismissed

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(accent)
            Text("Bonne journée !")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}

// MARK: - Icône Dynamic Island

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
        case .scheduled:       PhaseColor.scheduled
        case .ringing:         PhaseColor.ringing
        case .speakingMessage: PhaseColor.speaking
        case .waitingUnlock:   PhaseColor.unlock
        case .briefing:        PhaseColor.briefing
        case .dismissed:       PhaseColor.dismissed
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
