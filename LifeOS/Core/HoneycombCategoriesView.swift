import SwiftUI

// MARK: - Catégories : grille propre, symétrique, façon app Apple

struct HoneycombCategoriesView: View {
    @State private var path: [AppCategory] = []
    @AppStorage("bubbleWeights") private var weightsRaw = ""

    private static let order: [AppCategory] = [
        .fitness, .nutrition, .looks, .mind, .finance, .social,
        .sleep, .productivity, .learning, .home, .mobility, .travel,
        .career, .invest, .admin
    ]
    private let columns = [GridItem(.flexible(), spacing: 18),
                           GridItem(.flexible(), spacing: 18),
                           GridItem(.flexible(), spacing: 18)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(Self.order, id: \.self) { cat in
                        Button {
                            bump(cat); Haptics.soft(); path.append(cat)
                        } label: {
                            GlossyBubble(color: BubbleStyle.color(cat),
                                         icon: cat.icon,
                                         label: BubbleStyle.label(cat))
                        }
                        .buttonStyle(BubblePress())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(BubbleMesh().ignoresSafeArea())
            .navigationTitle("Catégories")
            .navigationDestination(for: AppCategory.self) { $0.destination }
        }
    }

    private func bump(_ cat: AppCategory) {
        var m: [String: Int] = [:]
        for pair in weightsRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        m[cat.rawValue, default: 0] += 1
        weightsRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
    }
}

// Petit effet d'appui propre (scale + ressort)
private struct BubblePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Bulle glossy (shader Metal), taille uniforme

struct GlossyBubble: View {
    let color: Color
    let icon: String
    let label: String
    var size: CGFloat = 104

    @State private var appeared = false

    var body: some View {
        Circle()
            .fill(ShaderLibrary.bubble(.float2(Float(size), Float(size)),
                                       .color(color),
                                       .float2(-0.42, -0.5)))
            .frame(width: size, height: size)
            .overlay {
                VStack(spacing: size * 0.04) {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    Text(label)
                        .font(.system(size: size * 0.125, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
            }
            .shadow(color: color.opacity(0.45), radius: size * 0.13, y: size * 0.05)
            .frame(maxWidth: .infinity)         // centre la bulle dans sa cellule
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
            }
    }
}

// MARK: - Fond mesh pâle lumineux

struct BubbleMesh: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
            ],
            colors: [
                .init(.sRGB, red: 0.88, green: 0.95, blue: 1.00),
                .init(.sRGB, red: 0.96, green: 0.97, blue: 1.00),
                .init(.sRGB, red: 0.97, green: 0.94, blue: 1.00),
                .init(.sRGB, red: 0.95, green: 0.99, blue: 1.00),
                .init(.sRGB, red: 0.99, green: 0.99, blue: 1.00),
                .init(.sRGB, red: 0.98, green: 0.96, blue: 1.00),
                .init(.sRGB, red: 0.93, green: 0.97, blue: 1.00),
                .init(.sRGB, red: 0.95, green: 0.98, blue: 1.00),
                .init(.sRGB, red: 0.95, green: 0.96, blue: 1.00)
            ]
        )
    }
}

// MARK: - Couleurs & labels (mapping de la référence)

enum BubbleStyle {
    static func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness: return .red
        case .mind: return .purple
        case .social: return .pink
        case .looks: return .orange
        case .finance: return .blue
        case .travel: return .blue
        case .nutrition: return .green
        case .sleep: return .indigo
        case .learning: return .yellow
        case .home: return .blue
        case .mobility: return .teal
        case .productivity: return .teal
        case .career: return .brown
        case .invest: return .mint
        case .admin: return Color(white: 0.72)
        }
    }
    static func label(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil"; case .nutrition: return "Alimentation"; case .fitness: return "Sport"
        case .looks: return "Bien-être"; case .mind: return "Mental"; case .productivity: return "Tâches"
        case .finance: return "Finance"; case .invest: return "Bourse"; case .career: return "Travail"
        case .learning: return "Éducation"; case .home: return "Maison"; case .mobility: return "Transports"
        case .social: return "Social"; case .admin: return "Documents"; case .travel: return "Voyage"
        }
    }
}
