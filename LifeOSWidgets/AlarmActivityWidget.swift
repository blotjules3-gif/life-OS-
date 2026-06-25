import ActivityKit
import SwiftUI
import WidgetKit

struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes.self) { context in
            LockScreenAlarmView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseIconView(phase: context.state.phase, size: 24)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.timeString)
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                PhaseIconView(phase: context.state.phase, size: 14)
            } compactTrailing: {
                Text(context.state.timeString)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            } minimal: {
                PhaseIconView(phase: context.state.phase, size: 13)
            }
        }
    }
}

// MARK: - Phase icon (no animations — widget extension safe)

struct PhaseIconView: View {
    let phase: AlarmAttributes.ContentState.Phase
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    var color: Color {
        switch phase {
        case .ringing:         .orange
        case .waitingUnlock:   Color(red: 0.2, green: 0.78, blue: 0.68)
        case .speakingMessage: .blue
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    var symbol: String {
        switch phase {
        case .ringing:         "alarm.fill"
        case .waitingUnlock:   "lock.fill"
        case .speakingMessage: "waveform"
        case .briefing:        "sun.horizon.fill"
        case .dismissed:       "checkmark.circle.fill"
        }
    }
}

// MARK: - Lock Screen banner

struct LockScreenAlarmView: View {
    let state: AlarmAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(phaseColor.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: phaseSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(phaseColor)
                        .symbolEffect(.variableColor.iterative.reversing,
                                      options: .speed(1.6),
                                      isActive: state.phase == .speakingMessage)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(phaseColor)
                    Text(state.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(state.timeString)
                    .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, state.phase == .waitingUnlock ? 8 : 14)

            if state.phase == .waitingUnlock {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(phaseColor)
                    Text("Déverrouillez pour lancer votre journée")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(phaseColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(phaseColor.opacity(0.10), in: Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.92))
    }

    var phaseColor: Color {
        switch state.phase {
        case .ringing:         .orange
        case .waitingUnlock:   Color(red: 0.2, green: 0.78, blue: 0.68)
        case .speakingMessage: .blue
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    var phaseSymbol: String {
        switch state.phase {
        case .ringing:         "alarm.fill"
        case .waitingUnlock:   "lock.fill"
        case .speakingMessage: "waveform"
        case .briefing:        "sun.horizon.fill"
        case .dismissed:       "checkmark.circle.fill"
        }
    }

    var phaseLabel: String {
        switch state.phase {
        case .ringing:         "Réveil"
        case .waitingUnlock:   "LifeOS — Réveil"
        case .speakingMessage: "Message vocal"
        case .briefing:        "Briefing du matin"
        case .dismissed:       "Bonne journée !"
        }
    }
}
