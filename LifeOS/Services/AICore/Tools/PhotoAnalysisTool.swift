import Foundation
import UIKit
@preconcurrency import Vision

/// Analyse une photo pour extraire des infos exploitables par le coach.
///
/// Stratégie multi-couche :
/// 1. **On-device Vision** (rapide, sûr) — classification + OCR
/// 2. **Route sémantique** — food / document / general
/// 3. **(TODO Phase P5)** — envoi image à Apple Intelligence vision (iOS 26.1+)
///    pour analyse plus riche
///
/// Aujourd'hui, la V1 fait la même chose que `ImageIntel` existant mais structuré
/// comme `AITool` pour être exposé au LLM via `LanguageModelSession.tools` en
/// Phase P5.
struct PhotoAnalysisTool: AITool {

    struct Arguments: Codable, Sendable {
        /// Contenu image encodé en base64 (limite ~1 MB — au-delà Apple Intelligence rejette).
        let imageBase64: String
        /// Hint optionnel : "food" / "document" / "outfit" / "medical". Guide l'analyse.
        let hint: String?
    }

    struct Result: Codable, Sendable {
        /// Route détectée : "food", "document", "outfit", "medical", "general".
        let route: String
        /// Description courte de ce qui est vu (français, 1 phrase max).
        let description: String
        /// Labels bruts détectés par Vision (top 5, confiance décroissante).
        let labels: [Label]
        /// Texte OCR si présent (troncé à 500 chars).
        let extractedText: String?

        struct Label: Codable, Sendable {
            let name: String
            let confidence: Double
        }
    }

    static let definition = AIToolDefinition(
        name: "analyze_photo",
        description: "Analyse une photo (assiette, document, tenue, image médicale, générique). Retourne route + description + labels + texte OCR si présent.",
        parametersSchema: #"{"type":"object","properties":{"imageBase64":{"type":"string"},"hint":{"type":"string","enum":["food","document","outfit","medical","general"]}},"required":["imageBase64"]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.photosMetadataRead]

    func execute(_ args: Arguments) async throws -> Result {
        guard let data = Data(base64Encoded: args.imageBase64),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            throw ToolExecutionError.invalidArguments("image invalide")
        }

        async let labels = classify(cgImage: cgImage)
        async let text = recognizeText(cgImage: cgImage)

        let detectedLabels = await labels
        let ocrText = await text

        // Route heuristique — même logique qu'ImageIntel legacy
        let route = detectRoute(labels: detectedLabels, hasText: ocrText.count >= 20, hint: args.hint)

        let description: String = {
            switch route {
            case "food":
                if let top = detectedLabels.first {
                    return "Assiette avec \(top.name)"
                }
                return "Assiette non identifiée"
            case "document":
                return "Document texte détecté (\(ocrText.count) caractères)"
            case "outfit":
                return "Tenue vestimentaire"
            case "medical":
                return "Image médicale (bilan / ordonnance)"
            default:
                let top = detectedLabels.first?.name ?? "élément visuel"
                return "Image générique : \(top)"
            }
        }()

        return Result(
            route: route,
            description: description,
            labels: Array(detectedLabels.prefix(5)),
            extractedText: ocrText.isEmpty ? nil : String(ocrText.prefix(500))
        )
    }

    // MARK: - Vision helpers

    private func classify(cgImage: CGImage) async -> [Result.Label] {
        await withCheckedContinuation { cont in
            let req = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                let obs = (req.results ?? []).filter { $0.confidence > 0.05 }
                let labels = obs.prefix(10).map {
                    Result.Label(name: $0.identifier, confidence: Double($0.confidence))
                }
                cont.resume(returning: Array(labels))
            }
        }
    }

    private func recognizeText(cgImage: CGImage) async -> String {
        await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .fast
            req.recognitionLanguages = ["fr-FR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                let strings = (req.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: strings.joined(separator: "\n"))
            }
        }
    }

    private func detectRoute(labels: [Result.Label], hasText: Bool, hint: String?) -> String {
        if let hint { return hint }
        // Détection food : mots-clés dans les labels
        let foodKeywords = ["food", "meal", "dish", "plate", "salad", "burger", "pizza",
                            "pasta", "rice", "meat", "chicken", "fish", "vegetable"]
        if labels.contains(where: { l in
            foodKeywords.contains { l.name.lowercased().contains($0) }
        }) {
            return "food"
        }
        // Beaucoup de texte → document
        if hasText { return "document" }
        // Outfit : personne + vêtement
        if labels.contains(where: { $0.name.lowercased().contains("clothing") || $0.name.lowercased().contains("apparel") }) {
            return "outfit"
        }
        return "general"
    }
}
