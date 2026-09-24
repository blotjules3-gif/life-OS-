import Foundation

/// Service d'envoi et de vérification des codes de sécurité par e-mail.
/// Compatible avec les APIs d'expédition transactionnelle (ex: Resend, Brevo ou backend custom).
final class EmailVerificationService {
    static let shared = EmailVerificationService()
    private init() {}

    /// Clé API Resend si configurée dans les paramètres ou UserDefaults
    private var resendApiKey: String {
        UserDefaults.standard.string(forKey: "resend_api_key") ?? ""
    }

    /// Envoie un code à 6 chiffres par email de manière asynchrone.
    @discardableResult
    func sendCode(_ code: String, to recipient: String) async -> Bool {
        AppLog.net.info("EmailVerificationService: envoi du code à \(recipient, privacy: .private)")

        let apiKey = resendApiKey
        guard !apiKey.isEmpty else {
            AppLog.net.info("EmailVerificationService: aucune clé API externe configurée — code enregistré localement")
            return false
        }

        guard let url = URL(string: "https://api.resend.com/emails") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let subject = "Votre code de confirmation LifeOS : \(code)"
        let htmlBody = """
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 500px; margin: 0 auto; padding: 24px; background-color: #0b0c0e; color: #ffffff; border-radius: 16px;">
            <h2 style="margin-top: 0; color: #ffffff; font-weight: 800;">LifeOS Sécurité</h2>
            <p style="color: #a0a0a0; font-size: 15px;">Voici votre code d'accès personnel pour valider votre compte :</p>
            <div style="background-color: #1a1c22; padding: 20px; text-align: center; border-radius: 12px; margin: 24px 0; border: 1px solid #2d3139;">
                <span style="font-size: 32px; font-weight: 800; letter-spacing: 8px; color: #4CC38A;">\(code)</span>
            </div>
            <p style="color: #707070; font-size: 13px; margin-bottom: 0;">Ce code expire dans 10 minutes. Si vous n'êtes pas à l'origine de cette demande, vous pouvez ignorer cet email.</p>
        </div>
        """

        let payload: [String: Any] = [
            "from": "LifeOS <onboarding@resend.dev>",
            "to": [recipient],
            "subject": subject,
            "html": htmlBody
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                AppLog.net.info("EmailVerificationService: email envoyé avec succès")
                return true
            } else {
                let errString = String(data: data, encoding: .utf8) ?? ""
                AppLog.net.error("EmailVerificationService: erreur HTTP \(errString, privacy: .public)")
                return false
            }
        } catch {
            AppLog.net.error("EmailVerificationService: échec réseau \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
