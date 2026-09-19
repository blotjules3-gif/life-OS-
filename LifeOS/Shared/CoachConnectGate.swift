import SwiftUI

/// Gate plein écran affiché tant que l'user n'a pas connecté son coach.
///
/// Bloque totalement l'accès au chat : aucun input, aucun historique, juste
/// un grand rectangle sombre centré avec un CTA clair "Choisir mon coach".
///
/// Détection "connecté" : voir `AIAssistantView.isCoachConnected`.
///
/// Design : hero card sombre skill lifeos-card-design, glow orange, dot grid.
struct CoachConnectGate: View {

    let onChoose: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            heroCard
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) { appeared = true }
        }
    }

    private var heroCard: some View {
        ZStack {
            // Fond gradient sombre
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x0D1B2A), Color(hex: 0x162636)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // Glow orange (allowsHitTesting: false, blur 20)
            Circle()
                .fill(RadialGradient(
                    colors: [Color.accentColor.opacity(0.45), .clear],
                    center: .center, startRadius: 0, endRadius: 120
                ))
                .frame(width: 240, height: 240)
                .offset(x: 60, y: -60)
                .blur(radius: 20)
                .allowsHitTesting(false)

            // Contenu
            VStack(spacing: 22) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Connecte ton coach")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Ton coach a besoin d'être branché à une IA pour te répondre. Choisis-la, colle ta clé, c'est prêt.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                Button {
                    onChoose()
                } label: {
                    HStack(spacing: 8) {
                        Text("Choisir mon coach")
                            .font(.callout.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(Color(hex: 0x0D1B2A))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(minHeight: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choisir mon coach")

                Text("Ton coach reste chez toi. Ta clé est stockée dans le Trousseau iOS.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 360)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
        .scaleEffect(appeared ? 1 : 0.96)
    }
}
