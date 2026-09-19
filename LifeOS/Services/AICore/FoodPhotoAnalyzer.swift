import Foundation
import UIKit

/// Analyse une photo de plat avec un VRAI modèle de vision.
///
/// Avant, `FoodVision` classait l'image sur l'appareil puis lisait une table
/// de correspondance : « pizza » valait toujours 285 kcal, quelle que soit la
/// part. Ça ne regardait pas l'assiette, ça reconnaissait un mot.
///
/// Pourquoi ce fichier est autonome plutôt qu'un ajout dans `AIProvider` :
/// l'envoi d'une image change la forme du corps de requête (le `content`
/// devient un tableau de blocs au lieu d'une chaîne). Le faire dans le
/// protocole obligeait à toucher les huit providers, dont ceux du chat coach
/// qui marchent. Ici le rayon d'action est une seule fonctionnalité.
///
/// La clé vient du même trousseau que le chat : rien à configurer en plus.
enum FoodPhotoAnalyzer {

    struct Analysis {
        let name: String
        let kcal: Int
        let protein: Double
        let carbs: Double
        let fat: Double
        /// Ce que le modèle dit avoir vu, montré à l'utilisateur pour qu'il
        /// puisse juger si l'estimation est crédible.
        let note: String
    }

    enum Failure: Error {
        case noVisionKey        // aucune clé d'un provider qui sait voir
        case network(String)
        case unreadable(String) // réponse reçue mais pas exploitable
    }

    // MARK: - Providers capables de voir

    /// Uniquement des modèles dont le support image est certain. Groq et
    /// DeepSeek sont volontairement absents : leurs modèles par défaut dans
    /// cette app sont du texte seul, et proposer une analyse qui échoue est
    /// pire que ne pas la proposer.
    private struct VisionRoute {
        let slot: AIProviderCredentials.Slot
        let model: String
        let family: Family
        enum Family { case openAICompatible(url: String), anthropic }
    }

    private static let routes: [VisionRoute] = [
        .init(slot: .openai, model: "gpt-4o-mini",
              family: .openAICompatible(url: "https://api.openai.com/v1/chat/completions")),
        .init(slot: .openrouter, model: "openai/gpt-4o-mini",
              family: .openAICompatible(url: "https://openrouter.ai/api/v1/chat/completions")),
        .init(slot: .xai, model: "grok-2-vision-1212",
              family: .openAICompatible(url: "https://api.x.ai/v1/chat/completions")),
        .init(slot: .anthropic, model: "claude-haiku-4-5-20251001", family: .anthropic),
    ]

    /// Vrai si au moins une clé permet de voir. Sert à n'afficher le bouton
    /// « analyse IA » que quand il peut marcher.
    @MainActor
    static var isAvailable: Bool {
        routes.contains { AIProviderCredentials.shared.hasKey(for: $0.slot) }
    }

    @MainActor
    static var providerName: String? {
        routes.first { AIProviderCredentials.shared.hasKey(for: $0.slot) }?.slot.displayName
    }

    // MARK: - Analyse

    static func analyze(_ image: UIImage) async -> Result<Analysis, Failure> {
        let picked: (VisionRoute, String)? = await MainActor.run {
            for r in routes {
                if let k = AIProviderCredentials.shared.key(for: r.slot) { return (r, k) }
            }
            return nil
        }
        guard let (route, apiKey) = picked else { return .failure(.noVisionKey) }
        guard let b64 = jpegBase64(image) else {
            return .failure(.unreadable("photo illisible"))
        }

        let req: URLRequest
        switch route.family {
        case .openAICompatible(let url):
            req = openAIRequest(url: url, model: route.model, key: apiKey, imageB64: b64)
        case .anthropic:
            req = anthropicRequest(model: route.model, key: apiKey, imageB64: b64)
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .failure(.network("réponse inattendue"))
            }
            guard (200..<300).contains(http.statusCode) else {
                // Le corps porte le vrai motif (quota, clé morte, modèle
                // inconnu). Sans lui on ne saurait jamais lequel des trois.
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                return .failure(.network("HTTP \(http.statusCode) — \(body)"))
            }
            guard let text = extractText(data, family: route.family) else {
                return .failure(.unreadable("pas de texte dans la réponse"))
            }
            guard let a = parse(text) else {
                return .failure(.unreadable(String(text.prefix(120))))
            }
            return .success(a)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - Image

    /// Réduit puis compresse. Une photo d'iPhone fait 12 Mpx : l'envoyer telle
    /// quelle coûte cher, prend des secondes en 4G, et n'améliore en rien la
    /// reconnaissance d'une assiette.
    private static func jpegBase64(_ image: UIImage, maxSide: CGFloat = 768) -> String? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxSide / max(w, h))
        let size = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }

    // MARK: - Requêtes

    private static let prompt = """
    Tu regardes une photo de repas. Réponds UNIQUEMENT avec un objet JSON, sans \
    texte autour et sans balises de code.

    Format exact :
    {"name": "...", "kcal": 0, "protein": 0, "carbs": 0, "fat": 0, "note": "..."}

    Règles :
    - name : le plat en français, court (ex: "Poulet riz brocolis").
    - kcal, protein, carbs, fat : pour LA PORTION VISIBLE sur la photo, pas \
    pour 100 g. Protéines, glucides et lipides en grammes, nombres entiers.
    - Sers-toi de la taille de l'assiette et des couverts pour juger la portion.
    - note : une phrase courte sur ce que tu vois et ton degré de certitude.
    - Si ce n'est pas de la nourriture, renvoie name "Aucun plat détecté" et 0 partout.
    """

    private static func openAIRequest(url: String, model: String, key: String, imageB64: String) -> URLRequest {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 400,
            "temperature": 0.2,   // une estimation chiffrée n'a pas à être créative
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/jpeg;base64,\(imageB64)"]],
                ],
            ]],
        ]
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("https://lifeos.app", forHTTPHeaderField: "HTTP-Referer")
        r.setValue("LifeOS", forHTTPHeaderField: "X-Title")
        r.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        r.timeoutInterval = 45      // une image met plus longtemps qu'un texte
        return r
    }

    private static func anthropicRequest(model: String, key: String, imageB64: String) -> URLRequest {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 400,
            "temperature": 0.2,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": imageB64]],
                    ["type": "text", "text": prompt],
                ],
            ]],
        ]
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        r.timeoutInterval = 45
        return r
    }

    // MARK: - Lecture de la réponse

    private static func extractText(_ data: Data, family: VisionRoute.Family) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch family {
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any] else { return nil }
            return msg["content"] as? String
        case .anthropic:
            guard let blocks = json["content"] as? [[String: Any]] else { return nil }
            return blocks.compactMap { $0["text"] as? String }.joined()
        }
    }

    /// Les modèles ajoutent souvent ```json autour, malgré la consigne. On
    /// récupère donc le premier objet accolades comprises plutôt que d'exiger
    /// une réponse parfaite.
    static func parse(_ text: String) -> Analysis? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(text[start...end])
        guard let d = slice.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }

        // Certains modèles renvoient "285", d'autres 285, d'autres 285.0.
        func num(_ k: String) -> Double {
            if let v = o[k] as? Double { return v }
            if let v = o[k] as? Int { return Double(v) }
            if let s = o[k] as? String { return Double(s.filter { "0123456789.".contains($0) }) ?? 0 }
            return 0
        }
        let name = (o["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        return Analysis(
            name: name,
            kcal: max(0, Int(num("kcal").rounded())),
            protein: max(0, num("protein")),
            carbs: max(0, num("carbs")),
            fat: max(0, num("fat")),
            note: (o["note"] as? String) ?? ""
        )
    }
}
