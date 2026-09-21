import Foundation

/// Petit portail texte au-dessus du routeur IA.
///
/// Plusieurs ecrans ont besoin de la meme chose: envoyer une consigne, lire une
/// reponse en texte. Sans ce portail, chacun rebranchait le routeur a sa facon
/// et gerait l'absence de cle differemment, ce qui donnait trois messages
/// d'erreur differents pour un seul probleme.
enum AIText {

    /// Message d'erreur lisible. Un `String` nu ne peut pas servir d'erreur
    /// dans un `Result`, il ne conforme pas a `Error`.
    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Vrai si au moins un fournisseur a une cle. Sert a afficher un vrai
    /// bouton plutot qu'un bouton qui echouera a coup sur.
    @MainActor
    static var isConfigured: Bool {
        AIProviderCredentials.Slot.allCases.contains { AIProviderCredentials.shared.hasKey(for: $0) }
    }

    /// Envoie une consigne et rend le texte, ou un message lisible par un humain.
    static func ask(system: String,
                    user: String,
                    maxTokens: Int = 700,
                    temperature: Double = 0.4) async -> Result<String, Failure> {
        let req = AIRequest(
            messages: [.system(system), .user(user)],
            maxOutputTokens: maxTokens,
            temperature: temperature,
            timeout: 45
        )
        let resp = await AIModelRouter.shared.execute(req)
        if let err = resp.error {
            return .failure(Failure(message: String(describing: err)))
        }
        let text = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(Failure(message: "Réponse vide du modèle")) }
        return .success(text)
    }
}
