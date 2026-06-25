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

// MARK: - Widget entry point

@available(iOS 16.1, *)
struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes.self) { context in
            LockScreenAlarmView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandPhaseIcon(phase: context.state.phase, size: 28)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                DynamicIslandPhaseIcon(phase: context.state.phase, size: 16)
            } compactTrailing: {
                Text(context.state.timeString)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            } minimal: {
                DynamicIslandPhaseIcon(phase: context.state.phase, size: 14)
            }
        }
    }
}

// MARK: - Dynamic Island icon with wave pulse animation

@available(iOS 16.1, *)
struct DynamicIslandPhaseIcon: View {
    let phase: AlarmAttributes.ContentState.Phase
    let size: CGFloat

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Pulse ring — only visible during speakingMessage
            if phase == .speakingMessage {
                Circle()
                    .stroke(Color.blue.opacity(pulseOpacity), lineWidth: 1.5)
                    .scaleEffect(pulseScale)
                    .frame(width: size * 1.6, height: size * 1.6)
            }

            Image(systemName: phaseSymbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(phaseColor)
                // SF Symbol wave animation on iOS 17+
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .speed(1.8),
                    isActive: phase == .speakingMessage
                )
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: phase) { startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        guard phase == .speakingMessage else {
            pulseScale = 1.0
            pulseOpacity = 0.6
            return
        }
        withAnimation(
            .easeOut(duration: 0.9).repeatForever(autoreverses: false)
        ) {
            pulseScale = 1.8
            pulseOpacity = 0.0
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .ringing:         .orange
        case .speakingMessage: .blue
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    private var phaseSymbol: String {
        switch phase {
        case .ringing:         "alarm.fill"
        case .speakingMessage: "waveform"
        case .briefing:        "sun.horizon.fill"
        case .dismissed:       "checkmark.circle.fill"
        }
    }
}

// MARK: - Lock Screen banner

@available(iOS 16.1, *)
struct LockScreenAlarmView: View {
    let state: AlarmAttributes.ContentState

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                // Expanding pulse ring for speakingMessage
                if state.phase == .speakingMessage {
                    Circle()
                        .stroke(phaseColor.opacity(pulseOpacity), lineWidth: 2)
                        .scaleEffect(pulseScale)
                        .frame(width: 52, height: 52)
                }

                Circle()
                    .fill(phaseColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: phaseSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .symbolEffect(
                        .variableColor.iterative.reversing,
                        options: .speed(1.8),
                        isActive: state.phase == .speakingMessage
                    )
            }
            .onAppear { startPulseIfNeeded() }
            .onChange(of: state.phase) { startPulseIfNeeded() }

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

    private func startPulseIfNeeded() {
        guard state.phase == .speakingMessage else {
            pulseScale = 1.0
            pulseOpacity = 0.5
            return
        }
        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
            pulseScale = 1.7
            pulseOpacity = 0.0
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .ringing:         .orange
        case .speakingMessage: .blue
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    private var phaseSymbol: String {
        switch state.phase {
        case .ringing:         "alarm.fill"
        case .speakingMessage: "waveform"
        case .briefing:        "sun.horizon.fill"
        case .dismissed:       "checkmark.circle.fill"
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .ringing:         "Réveil"
        case .speakingMessage: "Message vocal"
        case .briefing:        "Briefing du matin"
        case .dismissed:       "Bonne journée !"
        }
    }
}
