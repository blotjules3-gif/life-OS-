// ─────────────────────────────────────────────────────────────────────────────
// AlarmActivityWidget.swift
// Target: LifeOSWidgets (Widget Extension — NOT the main LifeOS target)
//
// Xcode manual setup (one-time):
//   1. File › New › Target › Widget Extension → name: "LifeOSWidgets"
//   2. Uncheck "Include Configuration App Intent" if prompted
//   3. Add AlarmAttributes.swift to BOTH targets (check Target Membership)
//   4. In LifeOSWidgets, set Deployment Target ≥ iOS 16.1
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
                    DynamicIslandPhaseIcon(phase: context.state.phase, size: 26)
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
                DynamicIslandPhaseIcon(phase: context.state.phase, size: 15)
            } compactTrailing: {
                Text(context.state.timeString)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            } minimal: {
                DynamicIslandPhaseIcon(phase: context.state.phase, size: 14)
            }
        }
    }
}

// MARK: - Dynamic Island icon

@available(iOS 16.1, *)
struct DynamicIslandPhaseIcon: View {
    let phase: AlarmAttributes.ContentState.Phase
    let size: CGFloat

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.7

    var body: some View {
        ZStack {
            if phase == .speakingMessage || phase == .waitingUnlock {
                Circle()
                    .stroke(phaseColor.opacity(pulseOpacity), lineWidth: 1.5)
                    .scaleEffect(pulseScale)
                    .frame(width: size * 1.7, height: size * 1.7)
            }

            Image(systemName: phaseSymbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(phaseColor)
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .speed(1.8),
                    isActive: phase == .speakingMessage
                )
                .symbolEffect(
                    .bounce.up.byLayer,
                    options: .speed(0.6).repeating,
                    isActive: phase == .waitingUnlock
                )
        }
        .onAppear { animateForPhase() }
        .onChange(of: phase) { animateForPhase() }
    }

    private func animateForPhase() {
        if phase == .speakingMessage || phase == .waitingUnlock {
            withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                pulseScale = 1.9
                pulseOpacity = 0.0
            }
        } else {
            pulseScale = 1.0
            pulseOpacity = 0.7
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .ringing:         .orange
        case .waitingUnlock:   Color(red: 0.4, green: 0.8, blue: 0.7)   // teal
        case .speakingMessage: .blue
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    private var phaseSymbol: String {
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

@available(iOS 16.1, *)
struct LockScreenAlarmView: View {
    let state: AlarmAttributes.ContentState

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.55
    @State private var unlockShimmer: CGFloat = -1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Icon zone
                ZStack {
                    if state.phase == .speakingMessage || state.phase == .waitingUnlock {
                        Circle()
                            .stroke(phaseColor.opacity(pulseOpacity), lineWidth: 2)
                            .scaleEffect(pulseScale)
                            .frame(width: 52, height: 52)
                    }
                    Circle()
                        .fill(phaseColor.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: phaseSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(phaseColor)
                        .symbolEffect(
                            .variableColor.iterative.reversing,
                            options: .speed(1.8),
                            isActive: state.phase == .speakingMessage
                        )
                        .symbolEffect(
                            .bounce.up.byLayer,
                            options: .speed(0.6).repeating,
                            isActive: state.phase == .waitingUnlock
                        )
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(phaseColor)
                    Text(state.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Time
                Text(state.timeString)
                    .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, state.phase == .waitingUnlock ? 8 : 14)

            // Unlock hint bar — only in waitingUnlock phase
            if state.phase == .waitingUnlock {
                UnlockHintBar(color: phaseColor)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .onAppear { startAnimations() }
        .onChange(of: state.phase) { startAnimations() }
    }

    private func startAnimations() {
        if state.phase == .speakingMessage || state.phase == .waitingUnlock {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulseScale = 1.75
                pulseOpacity = 0.0
            }
        } else {
            pulseScale = 1.0
            pulseOpacity = 0.55
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .ringing:         .orange
        case .waitingUnlock:   Color(red: 0.2, green: 0.78, blue: 0.68)
        case .speakingMessage: .blue
        case .briefing:        .purple
        case .dismissed:       .green
        }
    }

    private var phaseSymbol: String {
        switch state.phase {
        case .ringing:         "alarm.fill"
        case .waitingUnlock:   "lock.fill"
        case .speakingMessage: "waveform"
        case .briefing:        "sun.horizon.fill"
        case .dismissed:       "checkmark.circle.fill"
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .ringing:         "Réveil"
        case .waitingUnlock:   "LifeOS — Réveil"
        case .speakingMessage: "Message vocal"
        case .briefing:        "Briefing du matin"
        case .dismissed:       "Bonne journée !"
        }
    }
}

// MARK: - Unlock hint bar

@available(iOS 16.1, *)
struct UnlockHintBar: View {
    let color: Color
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(color.opacity(0.12))
                    .frame(height: 32)

                // Shimmer highlight
                Capsule()
                    .fill(color.opacity(0.18))
                    .frame(width: geo.size.width * 0.38, height: 32)
                    .offset(x: geo.size.width * shimmerOffset)
                    .clipped()

                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Text("Déverrouillez pour lancer votre journée")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 32)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.0
            }
        }
    }
}
