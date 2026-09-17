import SwiftUI

/// Card premium "Ton coach" affichée dans l'onglet Profil.
///
/// Affiche : provider actif (nom + icône), coût du mois cumulé (proxy facture
/// mensuelle), nombre de requêtes du jour, bouton "Gérer" qui ouvre
/// `CoachAIProviderView`.
///
/// Design : dark hero card avec glow (skill `lifeos-card-design`), score ring
/// remplacé par un mini indicateur de cost guard si l'user a un plafond actif.
struct ProfileCoachCard: View {

    @ObservedObject private var usageTracker = AIProviderUsageTracker.shared
    @State private var appeared = false
    @State private var showCoachSettings = false

    var body: some View {
        Button {
            showCoachSettings = true
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCoachSettings) {
            NavigationStack {
                CoachAIProviderView()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    // MARK: - Card body

    private var cardBody: some View {
        ZStack {
            // Fond gradient sombre
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: UInt(0x0D1B2A)), Color(hex: 0x162636)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // Blob de lumière
            Circle()
                .fill(RadialGradient(
                    colors: [accentColor.opacity(0.35), .clear],
                    center: .center, startRadius: 0, endRadius: 100
                ))
                .frame(width: 200, height: 200)
                .offset(x: 60, y: -30)
                .blur(radius: 20)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                header
                statsRow
                cta
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    accentColor.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Ton coach")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Stats row (coûts + requêtes)

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(
                label: "Ce mois",
                value: costEURThisMonth,
                icon: "eurosign.circle.fill",
                color: Color(hex: 0x00D4B4)
            )
            statTile(
                label: "Aujourd'hui",
                value: "\(requestsToday) req.",
                icon: "arrow.up.arrow.down",
                color: Color(hex: 0x7DD3FC)
            )
        }
    }

    private func statTile(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(value)
                .font(.system(size: 18, weight: .black).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - CTA (bouton "Gérer")

    private var cta: some View {
        HStack {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            Spacer()
            Text("Gérer")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    accentColor.opacity(0.22),
                    in: Capsule()
                )
                .foregroundStyle(.white)
        }
    }

    // MARK: - Computed

    /// providerID courant (préférence user), ou best-effort par défaut.
    private var currentProviderID: String {
        AIProviderPreference.shared.preferred ?? "apple.intelligence.on-device"
    }

    private var displayName: String {
        AIProviderResolver.displayName(for: currentProviderID) ?? "Non configuré"
    }

    private var iconName: String {
        AIProviderResolver.iconName(for: currentProviderID)
    }

    private var accentColor: Color {
        if currentProviderID.hasPrefix("apple") { return Color(hex: 0x00D4B4) }
        if currentProviderID.hasPrefix("openai") { return Color(hex: 0x10A37F) }
        if currentProviderID.hasPrefix("anthropic") { return Color(hex: 0xC97D5C) }
        if currentProviderID.hasPrefix("openrouter") { return Color(hex: 0xE6A03C) }
        if currentProviderID.hasPrefix("groq") { return Color(hex: 0xF55036) }
        if currentProviderID.hasPrefix("deepseek") { return Color(hex: 0x4C6EF5) }
        if currentProviderID.hasPrefix("xai") { return Color(hex: 0xA855F7) }
        if currentProviderID.hasPrefix("google") { return Color(hex: 0x4285F4) }
        return Color(hex: 0x00D4B4)
    }

    /// Cumul EUR sur les 30 derniers jours, tous providers cloud confondus.
    private var costEURThisMonth: String {
        let usd = AIProviderCredentials.Slot.allCases.reduce(0.0) { total, slot in
            total + AIProviderUsageTracker.shared.monthlySnapshot(providerID: slot.providerID).estimatedCostUSD
        }
        let eur = usd * 0.92
        if eur < 0.01 { return "0 €" }
        return String(format: "%.2f €", eur)
    }

    /// Nombre de requêtes aujourd'hui tous providers cloud confondus.
    private var requestsToday: Int {
        AIProviderCredentials.Slot.allCases.reduce(0) { total, slot in
            total + AIProviderUsageTracker.shared.todaySnapshot(providerID: slot.providerID).requestCount
        }
    }

    private var subtitle: String {
        if currentProviderID == "apple.intelligence.on-device" {
            return "Gratuit et 100% sur ton iPhone"
        }
        if currentProviderID.hasPrefix("custom.") {
            return "Provider personnalisé"
        }
        return "Tokens facturés à ton compte"
    }
}
