import SwiftUI

// Guideline App Store 1.4.1 / 5.1 : consentement obligatoire au premier lancement.

struct CoachDisclaimerSheet: View {
    var onAccept: () -> Void
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    section(
                        title: "Ton coach n'est pas un professionnel",
                        body: "Ses réponses sont générées par l'intelligence de ton iPhone. Il ne remplace pas un médecin, un diététicien, un conseiller financier, ni un psy."
                    )
                    section(
                        title: "100 % sur ton iPhone",
                        body: "Tes messages, tes préférences et ta mémoire ne quittent jamais l'appareil. Aucun envoi à un serveur, aucune donnée utilisée pour entraîner un modèle."
                    )
                    section(
                        title: "Ce que tu peux faire",
                        body: "Long-press sur une réponse te permet de la signaler, l'aimer, ou dire qu'elle ne t'a pas plu. Le coach s'adapte à tes retours au fil du temps."
                    )
                    section(
                        title: "En cas d'urgence",
                        body: "Compose immédiatement le 15 (Samu), le 18 (pompiers) ou le 3114 (prévention suicide, gratuit, 24/7) si tu en as besoin. Le coach ne peut pas t'aider dans ces situations."
                    )
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 140)
            }
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                acceptBar
            }
            .navigationTitle("Avant de commencer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 8)
            Text("Ton coach répond avec des messages générés automatiquement.")
                .font(Theme.fontTitle2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.fontHeadline)
                .foregroundStyle(Theme.textPrimary)
            Text(body)
                .font(Theme.fontBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var acceptBar: some View {
        VStack(spacing: 10) {
            Button {
                onAccept()
                dismiss()
            } label: {
                Text("J'ai compris, continuer")
                    .font(Theme.fontHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.textPrimary)
                    .foregroundStyle(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("Tu peux retirer ton consentement à tout moment via Réglages.")
                .font(Theme.fontCaption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.thinMaterial)
    }
}

#Preview {
    CoachDisclaimerSheet(onAccept: {})
}
