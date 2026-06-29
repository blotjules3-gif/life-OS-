import SwiftUI
import StoreKit

// MARK: - Paywall

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isPremium") private var isPremium = false

    @State private var monthlyProduct: Product? = nil
    @State private var annualProduct: Product?  = nil
    @State private var purchasing = false
    @State private var storeError: String? = nil

    private static let monthlyID = "com.lifeos.premium.monthly"
    private static let annualID  = "com.lifeos.premium.annual"

    private let perks: [(icon: String, title: String, sub: String, color: Color)] = [
        ("sparkles",               "Bilan IA hebdomadaire",    "Analyse narrative personnalisée chaque semaine",      Color.accentColor),
        ("icloud.fill",            "Sync iCloud",              "Retrouve tes données sur tous tes appareils",         Color(hex: 0x3CB2E0)),
        ("brain.head.profile",     "Coach IA illimité",        "Conversations illimitées avec ton assistant",         Color(hex: 0x9B6CF1)),
        ("chart.line.uptrend.xyaxis", "Rapports avancés",      "Graphiques détaillés sur 30 et 90 jours",            Color(hex: 0x4CC38A)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(Color(hex: 0xE0A23C))
                        Text("LifeOS Premium")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                        Text("Débloque toutes les fonctionnalités IA et le suivi avancé.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(perks, id: \.title) { perk in
                            HStack(spacing: 14) {
                                Image(systemName: perk.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(perk.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(perk.title)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(perk.sub)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(hex: 0x4CC38A))
                            }
                            .padding(14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        }
                    }

                    VStack(spacing: 10) {
                        purchaseButton(product: monthlyProduct, fallbackLabel: "4,99 € / mois", primary: true)
                        purchaseButton(product: annualProduct,  fallbackLabel: "39,99 € / an — 2 mois offerts", primary: false)

                        Button("Restaurer les achats") {
                            Task { await restorePurchases() }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .disabled(purchasing)

                        if let err = storeError {
                            Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                        }

                        Text("Paiement via Apple. Résiliable à tout moment.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .task { await loadProducts() }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
