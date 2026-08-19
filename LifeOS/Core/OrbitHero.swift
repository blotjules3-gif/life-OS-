import SwiftUI

// MARK: - OrbitHero — système orbital (orbe Life Score + satellites)
//
// Extrait de `ProfileView.swift` pour réduire le God file. Utilisé uniquement
// par ProfileView.body. OrbitSatellite reste défini dans ProfileView.swift
// (partagé, accès target).

struct OrbitHero: View {
    let displayName: String
    let initial: String
    let greeting: String
    let score: Int
    let streak: Int
    let totalDays: Int
    let habitsWeek: Int
    let satellites: [OrbitSatellite]
    let appeared: Bool
    let pinnedIDs: Set<String>
    let onPin: (AppCategory) -> Void
    let onHide: (AppCategory) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            identityRow
            orbitalField
                .frame(height: 340)
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            statsRow
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadowMd()
    }

    // MARK: Identité

    private var identityRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 40, height: 40)
                Text(initial)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .monoLabel(10)
                    .foregroundStyle(.secondary)
                Text(displayName)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0xE0A23C))
                    Text("\(streak)")
                        .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: 0xE0A23C).opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: Champ orbital

    private var orbitalField: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { tl in
            let phase = reduceMotion ? 0.0
                : tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 360) * (2 * .pi / 360)
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                    .frame(width: 252, height: 252)

                connections(phase: phase)

                coreOrb

                ForEach(Array(satellites.enumerated()), id: \.element.id) { i, sat in
                    satelliteNode(sat, index: i)
                        .offset(x: cos(angle(i, phase)) * 126,
                                y: sin(angle(i, phase)) * 126)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func angle(_ i: Int, _ phase: Double) -> Double {
        -Double.pi / 2 + Double(i) * (2 * .pi / Double(max(1, satellites.count))) + phase
    }

    private func connections(phase: Double) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for (i, sat) in satellites.enumerated() {
                let a = angle(i, phase)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * 92, y: c.y + sin(a) * 92))
                p.addLine(to: CGPoint(x: c.x + cos(a) * 100, y: c.y + sin(a) * 100))
                ctx.stroke(p, with: .color(sat.category.tint.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Orbe central

    private var coreOrb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(0.16), .clear],
                                     center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 220, height: 220)
                .blur(radius: 18)
                .allowsHitTesting(false)

            ForEach(0..<60, id: \.self) { i in
                Capsule()
                    .fill(Color.primary.opacity(i % 5 == 0 ? 0.30 : 0.10))
                    .frame(width: 1.5, height: i % 5 == 0 ? 7 : 4)
                    .offset(y: -84)
                    .rotationEffect(.degrees(Double(i) * 6))
            }

            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 9)
                .frame(width: 144, height: 144)
            Circle()
                .trim(from: 0, to: appeared ? CGFloat(score) / 100 : 0)
                .stroke(AngularGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 144, height: 144)
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2)
                                 : .spring(duration: 1.3, bounce: 0.1).delay(0.4),
                    value: appeared
                )

            Circle()
                .fill(Color.primary.opacity(0.03))
                .frame(width: 118, height: 118)
            Circle()
                .strokeBorder(Theme.hairline, lineWidth: 1)
                .frame(width: 118, height: 118)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.5), value: score)
                Text("Life Score")
                    .monoLabel(8)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Satellites

    private func satelliteNode(_ sat: OrbitSatellite, index i: Int) -> some View {
        NavigationLink(value: sat.category) {
            ZStack {
                Circle()
                    .fill(sat.category.tint.opacity(0.12))
                    .frame(width: 52, height: 52)
                Circle()
                    .strokeBorder(sat.category.tint.opacity(0.18), lineWidth: 1)
                    .frame(width: 52, height: 52)
                if let progress = sat.progress {
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(progress) : 0)
                        .stroke(sat.category.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.2)
                                         : .spring(duration: 0.9, bounce: 0.1).delay(0.5 + Double(i) * 0.08),
                            value: appeared
                        )
                }
                Image(systemName: sat.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sat.category.tint)
            }
            .overlay(alignment: .center) {
                Text(sat.category.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 36)
            }
        }
        .buttonStyle(LifeOSPressStyle())
        .contextMenu {
            Button {
                onPin(sat.category)
            } label: {
                Label(pinnedIDs.contains(sat.category.rawValue) ? "Désépingler" : "Épingler en premier",
                      systemImage: pinnedIDs.contains(sat.category.rawValue) ? "pin.slash" : "pin.fill")
            }
            Button(role: .destructive) {
                onHide(sat.category)
            } label: {
                Label("Masquer", systemImage: "eye.slash")
            }
        }
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                         : .spring(duration: 0.6, bounce: 0.25).delay(0.3 + Double(i) * 0.07),
            value: appeared
        )
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            heroStat("\(streak)", "d'affilée")
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1, height: 30)
            heroStat("\(totalDays)", "jours actifs")
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1, height: 30)
            heroStat("\(habitsWeek)", "habitudes / 7 j")
        }
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
