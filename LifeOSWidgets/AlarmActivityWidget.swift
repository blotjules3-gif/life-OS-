// ─────────────────────────────────────────────────────────────────────────────
// AlarmActivityWidget.swift
// Target: LifeOSWidgets (Widget Extension — NOT the main LifeOS target)
//
// Xcode manual setup (one-time):
//   1. File › New › Target › Widget Extension → name: "LifeOSWidgets"
//   2. Uncheck "Include Configuration App Intent" if prompted
//   3. Add AlarmAttributes.swift to BOTH targets (check Target Membership)
//   4. Add "NSSupportsLiveActivities = YES" to LifeOS/Info.plist
//   5. In LifeOSWidgets, set Deployment Target ≥ iOS 16.1
// ─────────────────────────────────────────────────────────────────────────────

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Dynamic Island compact / expanded views

@available(iOS 16.1, *)
struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes.self) { context in
            // Lock Screen banner
            LockScreenAlarmView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    phaseIcon(context.state.phase)
                        .font(.system(size: 24, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.timeString)
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                phaseIcon(context.state.phase)
                    .font(.system(size: 14, weight: .semibold))
            } compactTrailing: {
                Text(context.state.timeString)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            } minimal: {
                phaseIcon(context.state.phase)
                    .font(.system(size: 14))
            }
        }
    }

    @ViewBuilder
    private func phaseIcon(_ phase: AlarmAttributes.ContentState.Phase) -> some View {
        switch phase {
        case .ringing:         Image(systemName: "alarm.fill").foregroundStyle(.orange)
        case .speakingMessage: Image(systemName: "waveform").foregroundStyle(.blue)
        case .dismissed:       Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

// MARK: - Lock Screen banner

@available(iOS 16.1, *)
struct LockScreenAlarmView: View {
    let state: AlarmAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: phaseSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(phaseColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(phaseColor)
                Text(state.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(state.timeString)
                .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var phaseColor: Color {
        switch state.phase {
        case .ringing:         .orange
        case .speakingMessage: .blue
        case .dismissed:       .green
        }
    }

    private var phaseSymbol: String {
        switch state.phase {
        case .ringing:         "alarm.fill"
        case .speakingMessage: "waveform"
        case .dismissed:       "checkmark.circle.fill"
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .ringing:         "Réveil"
        case .speakingMessage: "Message vocal"
        case .dismissed:       "Bonne journée !"
        }
    }
}
