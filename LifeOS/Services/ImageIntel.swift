import Foundation
import UIKit
@preconcurrency import Vision

/// Analyse d'image on-device via Vision (classification + OCR) et routage
/// vers le bon pôle LifeOS (Nutrition si aliment reconnu, Admin si document,
/// général sinon).
///
/// Extrait d'`AIAssistantView.swift` pour réduire le God file. Rien ne quitte
/// l'iPhone — pas de réseau.
enum ImageRoute {
    case food(FoodGuess)
    case document(String)
    case general(String)
}

enum ImageIntel {
    /// Classe l'image, lit le texte éventuel, et décide vers quel pôle router — 100% on-device.
    static func analyze(_ image: UIImage) async -> (route: ImageRoute, reply: String, actions: [AIAction]) {
        let labels = await classify(image)

        // 1) Aliment reconnu → journalisation calories (pôle Nutrition)
        if let hit = labels.first(where: { FoodCalorieDB.match($0.label) != nil }),
           let m = FoodCalorieDB.match(hit.label) {
            let g = FoodGuess(name: m.0, kcal: m.1, protein: m.2, carbs: m.3, fat: m.4, confidence: Double(hit.confidence))
            let reply = "On dirait : \(g.name) (~\(g.kcal) kcal). Je l'ai ajouté à ton journal du jour — tu peux l'ajuster dans Nutrition."
            return (.food(g), reply, [AIAction(type: .openModule, title: "Nutrition", module: "nutrition")])
        }

        // 2) Beaucoup de texte → document / justificatif (pôle Admin)
        let text = await recognizeText(image)
        if text.count >= 20 {
            let snippet = String(text.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let reply = "J'ai lu du texte sur cette image :\n« \(snippet)… »\nÇa ressemble à un document — tu peux le classer dans Documents / Admin."
            return (.document(text), reply, [AIAction(type: .openModule, title: "Documents", module: "admin")])
        }

        // 3) Sinon : description brute + suggestion
        let top = labels.first?.label.split(separator: ",").first.map(String.init)?.capitalized ?? "quelque chose"
        let reply = "J'ai analysé ta photo : \(top). Dis-moi ce que tu veux en faire (l'ajouter quelque part, créer un rappel…)."
        return (.general(top), reply, [])
    }

    private static func classify(_ image: UIImage) async -> [(label: String, confidence: Float)] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                let obs = (req.results ?? []).filter { $0.confidence > 0.05 }
                cont.resume(returning: obs.prefix(15).map { ($0.identifier, $0.confidence) })
            }
        }
    }

    private static func recognizeText(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .fast
            req.recognitionLanguages = ["fr-FR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                let strings = (req.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: strings.joined(separator: "\n"))
            }
        }
    }
}
