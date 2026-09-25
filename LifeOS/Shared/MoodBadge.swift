import SwiftUI

struct MoodBadge: View {
    let score: Int
    var size: CGFloat = 44
    var showsLabel: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(tint.gradient)
                Text("\(clamped)")
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: size, height: size)
            if showsLabel {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Humeur \(clamped) sur 5, \(label)")
    }

    private var clamped: Int { max(1, min(5, score)) }

    private var tint: Color {
        switch clamped {
        case 1: return Color(red: 0.90, green: 0.22, blue: 0.22)
        case 2: return Color(red: 0.98, green: 0.55, blue: 0.20)
        case 3: return Color(red: 0.96, green: 0.80, blue: 0.22)
        case 4: return Color(red: 0.45, green: 0.80, blue: 0.36)
        default: return Color(red: 0.18, green: 0.72, blue: 0.42)
        }
    }

    private var label: String {
        switch clamped {
        case 1: return "Très bas"
        case 2: return "Bas"
        case 3: return "Neutre"
        case 4: return "Bon"
        default: return "Excellent"
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(1...5, id: \.self) { MoodBadge(score: $0) }
    }
    .padding()
}
