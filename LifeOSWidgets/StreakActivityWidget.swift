import ActivityKit
import SwiftUI
import WidgetKit

/// Widget Live Activity qui affiche la streak d'habitude en cours.
/// Lock Screen : card horizontale avec icône + streak + caption.
/// Dynamic Island : compact / minimal / expanded.
@available(iOS 16.1, *)
struct StreakActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreakAttributes.self) { context in
            LockScreenStreakView(attrs: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.streakDays)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("jours")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.habitName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(context.state.caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.attributes.iconName)
                    .foregroundStyle(context.state.doneToday ? .green : .orange)
            } compactTrailing: {
                Text("\(context.state.streakDays)j")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct LockScreenStreakView: View {
    let attrs: StreakAttributes
    let state: StreakAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: attrs.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("STREAK")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.orange)
                    .kerning(1.2)
                Text(attrs.habitName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(state.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(state.streakDays)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("jours")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
            }
        }
        .padding(16)
    }
}
