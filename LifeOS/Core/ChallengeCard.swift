import SwiftUI

struct ChallengeCard: View {
    let challenge: ChallengeOut
    let onCheckin: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var neoCard: Color {
        colorScheme == .dark ? Color(hex: 0x252528) : Color(hex: 0xECEBE8)
    }
    private var neoShadowLight: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.85)
    }
    private var neoShadowDark: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color(hex: 0xB0ADA8).opacity(0.6)
    }

    private var typeColor: Color {
        switch challenge.challenge_type {
        case "water":      return Color(hex: 0x3CB2E0)
        case "sport":      return Color(hex: 0x4CC38A)
        case "smoking":    return Color(hex: 0xE05A7A)
        case "meditation": return Color(hex: 0x9B6CF1)
        case "nutrition":  return Color(hex: 0xF1746C)
        case "sleep":      return Color(hex: 0x6C7BF1)
        default:           return Color.accentColor
        }
    }

    private var typeIcon: String {
        switch challenge.challenge_type {
        case "water":      return "drop.fill"
        case "sport":      return "figure.run"
        case "smoking":    return "smoke.fill"
        case "meditation": return "brain.head.profile"
        case "nutrition":  return "leaf.fill"
        case "sleep":      return "moon.stars.fill"
        default:           return "flame.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(typeColor.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(typeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let days = challenge.duration_days {
                            Text("J\(challenge.days_elapsed)/\(days)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .animation(.spring(duration: 0.38, bounce: 0.1), value: challenge.days_elapsed)
                        }
                        if challenge.streak_days > 0 {
                            Label("\(challenge.streak_days)j", systemImage: "flame.fill")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color(hex: 0xE07B3C))
                                .contentTransition(.numericText())
                                .animation(.spring(duration: 0.38, bounce: 0.1), value: challenge.streak_days)
                        }
                    }
                }

                Spacer()

                Button(action: onCheckin) {
                    ZStack {
                        Circle()
                            .fill(challenge.checkedInToday ? typeColor : typeColor.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: challenge.checkedInToday ? "checkmark" : "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(challenge.checkedInToday ? .white : typeColor)
                            .scaleEffect(challenge.checkedInToday ? 1.0 : 0.85)
                    }
                    .animation(.spring(duration: 0.38, bounce: 0.25), value: challenge.checkedInToday)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(LifeOSPressStyle())
                .disabled(challenge.checkedInToday)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let total = challenge.duration_days, total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(typeColor.opacity(0.1)).frame(height: 3)
                        Capsule()
                            .fill(typeColor)
                            .frame(width: geo.size.width * challenge.progressFraction, height: 3)
                            .animation(.spring(duration: 0.6, bounce: 0.1), value: challenge.progressFraction)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(neoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: neoShadowLight, radius: 8, x: -4, y: -4)
        .shadow(color: neoShadowDark, radius: 8, x: 4, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    challenge.checkedInToday ? typeColor.opacity(0.55) :
                    challenge.isAbandoned ? Color(hex: 0xF1746C).opacity(0.45) : Color.clear,
                    lineWidth: 1.5
                )
                .animation(.spring(duration: 0.38, bounce: 0.1), value: challenge.checkedInToday)
                .animation(.spring(duration: 0.38, bounce: 0.1), value: challenge.isAbandoned)
        )
    }
}
