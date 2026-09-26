import SwiftUI

/// Composant partagé affiché au-dessus du champ SecureField dans les 2 écrans
/// d'entrée de clé (`QuickKeyEntry` premier lancement, `ProviderKeyEditor` réglages).
///
/// Trois blocs pour rendre l'obtention d'une clé la plus rapide possible :
///   1. Header : nom provider, badge "Gratuit" / "Carte requise", temps estimé
///   2. Bouton primaire "Ouvrir le site" → Safari IN-APP sur la page de création
///   3. Bouton secondaire "Coller depuis le presse-papier" → lit UIPasteboard,
///      valide le préfixe, remplit + déclenche le test automatiquement
///   4. Timeline étapes numérotées (fallback si l'user préfère manuel)
///
/// Design : sobre, Theme.card, palette accent, concentric radius.
struct ProviderKeyHelpView: View {

    let slot: AIProviderCredentials.Slot
    /// Callback appelé quand l'user tape "Coller" et qu'une clé valide est
    /// détectée. Fournit la clé brute — l'écran parent la valide + teste.
    let onPasteKey: (String) -> Void

    @State private var showSafari = false
    @State private var pasteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            openSiteButton
            pasteButton
            if let pasteError {
                Label(pasteError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            stepsTimeline
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showSafari) {
            if let url = slot.docsURL {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Obtenir ta clé \(slot.displayName)")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Label(slot.hasFreeTier ? "Gratuit possible" : "Carte bancaire requise",
                          systemImage: slot.hasFreeTier ? "checkmark.circle.fill" : "creditcard")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (slot.hasFreeTier ? Color.green : Color.orange).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(slot.hasFreeTier ? .green : .orange)
                    Text("environ \(slot.estimatedSetupMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Bouton "Ouvrir le site"

    private var openSiteButton: some View {
        Button {
            showSafari = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "safari.fill")
                    .font(.callout.weight(.semibold))
                Text("Ouvrir le site pour récupérer ma clé")
                    .font(.callout.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(slot.docsURL == nil)
    }

    // MARK: - Bouton "Coller depuis presse-papier"

    private var pasteButton: some View {
        Button {
            pasteFromClipboard()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.callout.weight(.semibold))
                Text("Coller ma clé depuis le presse-papier")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timeline étapes numérotées

    private var stepsTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment faire (si tu préfères manuel)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(Array(slot.keyRetrievalSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Étape \(index + 1). \(step)")
            }
        }
    }

    // MARK: - Coller depuis presse-papier

    private func pasteFromClipboard() {
        // Aucune log du contenu presse-papier même en DEBUG (règle sécurité).
        let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !raw.isEmpty else {
            showError("Ton presse-papier est vide.")
            return
        }

        // Si un préfixe est attendu et ne match pas → erreur claire
        if let prefix = slot.expectedPrefix, !raw.hasPrefix(prefix) {
            showError("La clé du presse-papier ne semble pas être une clé \(slot.displayName). Vérifie qu'elle commence par \"\(prefix)\".")
            return
        }

        // Longueur suspecte
        if raw.count < slot.minLength {
            showError("La clé du presse-papier semble tronquée. Recopie-la depuis le site.")
            return
        }

        pasteError = nil
        onPasteKey(raw)
    }

    private func showError(_ msg: String) {
        withAnimation(.easeOut(duration: 0.2)) { pasteError = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeOut(duration: 0.2)) { pasteError = nil }
        }
    }
}
