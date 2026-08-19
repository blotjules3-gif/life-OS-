import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extrait des valeurs typées depuis un message texte pour alimenter le profil.
///
/// Pipeline :
/// 1. Regex FR rapides (poids, taille, âge, fréquence) → confidence 0.95.
/// 2. Fallback LLM (Apple Intelligence) qui retourne un JSON structuré si les
///    regex ratent → confidence variable.
///
/// Chaque extraction est immédiatement `upsert` dans `ProfileStore`.
@MainActor
enum IntelligentExtractor {

    /// Résultat d'une extraction unitaire.
    struct Extraction {
        let fieldID: String
        let value: Any
        let confidence: Double
        /// Empreinte dans le texte source ("74 kg", "3 fois par semaine") pour l'UI toast.
        let sourceSnippet: String
    }

    /// Analyse un message user et retourne les extractions.
    /// Idempotent : n'écrit RIEN dans le store — l'appelant décide.
    static func extract(from message: String) async -> [Extraction] {
        var results: [Extraction] = []

        // 1. Regex FR déterministes (rapides, précises)
        results.append(contentsOf: regexPass(message))

        // 2. LLM fallback si Apple Intelligence dispo ET regex a rien capté
        //    OU si le message est long/complexe
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable,
           (results.isEmpty || message.count > 80) {
            let llmResults = await llmPass(message)
            // Dédup par fieldID — regex prioritaires
            let knownIDs = Set(results.map { $0.fieldID })
            results.append(contentsOf: llmResults.filter { !knownIDs.contains($0.fieldID) })
        }
        #endif

        return results
    }

    /// Extrait ET upsert dans le store. Retourne les fieldIDs mis à jour.
    /// Utilisé par le chat coach à chaque message user.
    @discardableResult
    static func extractAndPersist(from message: String, source: ProfileStore.Source) async -> [String] {
        let extractions = await extract(from: message)
        var updated: [String] = []
        for extraction in extractions {
            let result = ProfileStore.shared.upsert(
                extraction.fieldID,
                value: extraction.value,
                source: source,
                confidence: extraction.confidence,
                reason: "extracted_from_\(source.rawValue)"
            )
            if case .created = result { updated.append(extraction.fieldID) }
            if case .updated = result { updated.append(extraction.fieldID) }
        }
        return updated
    }

    // MARK: - Regex pass

    /// Patterns regex FR ancrés sur les hints des specs les plus communes.
    /// Ordre = priorité. Chaque pattern retourne (fieldID, decoded value, snippet).
    private static func regexPass(_ message: String) -> [Extraction] {
        let m = message.lowercased()
        var out: [Extraction] = []

        // Poids : "je fais 74 kg", "je pèse 68,5 kg", "74kg"
        if let match = firstMatch(pattern: #"\b(?:je\s*(?:fais|pese|pèse)|poids)\s*(?:de\s*)?(\d{2,3}(?:[,.]\d)?)\s*kg\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Double(raw.replacingOccurrences(of: ",", with: ".")),
           (30...250).contains(v) {
            out.append(.init(fieldID: "body.currentWeightKg", value: v, confidence: 0.95, sourceSnippet: "\(v) kg"))
        }

        // Taille : "je mesure 1m78", "je fais 178 cm", "taille 1,80"
        if let match = firstMatch(pattern: #"\b(?:je\s*mesure|taille|hauteur)\s*(?:de\s*)?(?:(\d)\s*m\s*(\d{1,2})|(\d{3})\s*cm)\b"#, in: m) {
            if let m1 = groupValue(match, group: 1, in: m), let m2 = groupValue(match, group: 2, in: m),
               let meters = Double(m1), let cm = Double(m2) {
                let total = meters * 100 + cm
                if (100...230).contains(total) {
                    out.append(.init(fieldID: "body.heightCm", value: total, confidence: 0.95, sourceSnippet: "\(Int(total)) cm"))
                }
            } else if let m3 = groupValue(match, group: 3, in: m), let v = Double(m3), (100...230).contains(v) {
                out.append(.init(fieldID: "body.heightCm", value: v, confidence: 0.95, sourceSnippet: "\(Int(v)) cm"))
            }
        }

        // Âge : "j'ai 28 ans", "28 ans"
        if let match = firstMatch(pattern: #"\b(?:j'?ai\s*)?(\d{2})\s*ans\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Int(raw), (10...120).contains(v) {
            out.append(.init(fieldID: "body.ageYears", value: v, confidence: 0.9, sourceSnippet: "\(v) ans"))
        }

        // Fréquence entraînement : "4 fois par semaine", "je vais 3x/semaine à la salle"
        if let match = firstMatch(pattern: #"\b(\d)\s*(?:fois|x)\s*(?:par|/)\s*semaine\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Int(raw), (0...14).contains(v) {
            out.append(.init(fieldID: "fitness.gymFrequency", value: v, confidence: 0.9, sourceSnippet: "\(v)x/sem"))
        }

        // Sommeil cible : "je vise 8h de sommeil", "8 heures par nuit"
        if let match = firstMatch(pattern: #"\b(\d(?:[,.]\d)?)\s*(?:h|heures?)\s*(?:de\s*sommeil|par\s*nuit)\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Double(raw.replacingOccurrences(of: ",", with: ".")),
           (3...12).contains(v) {
            out.append(.init(fieldID: "sleep.targetHours", value: v, confidence: 0.85, sourceSnippet: "\(v)h"))
        }

        // Calories cible : "je vise 2400 kcal", "2400 calories"
        if let match = firstMatch(pattern: #"\b(\d{3,4})\s*(?:kcal|calories?)\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Int(raw), (800...6000).contains(v) {
            out.append(.init(fieldID: "nutrition.kcalGoal", value: v, confidence: 0.85, sourceSnippet: "\(v) kcal"))
        }

        // Bench 1RM : "je bench 100", "développé couché 100 kg"
        if let match = firstMatch(pattern: #"\b(?:bench|dc|développé\s*couché)\s*(?:à\s*|de\s*)?(\d{2,3})\s*(?:kg)?\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Double(raw), (20...300).contains(v) {
            out.append(.init(fieldID: "fitness.bench1RM", value: v, confidence: 0.85, sourceSnippet: "bench \(Int(v)) kg"))
        }

        // Squat 1RM
        if let match = firstMatch(pattern: #"\bsquat\s*(?:à\s*|de\s*)?(\d{2,3})\s*(?:kg)?\b"#, in: m),
           let raw = groupValue(match, group: 1, in: m),
           let v = Double(raw), (20...400).contains(v) {
            out.append(.init(fieldID: "fitness.squat1RM", value: v, confidence: 0.85, sourceSnippet: "squat \(Int(v)) kg"))
        }

        // Régime alimentaire
        for (needle, value) in [
            ("végétarien", "végétarien"), ("vegetarien", "végétarien"),
            ("végan", "vegan"), ("vegan", "vegan"),
            ("flexitarien", "flexitarien"),
            ("keto", "keto"), ("cétogène", "keto")
        ] {
            if m.contains(needle) {
                out.append(.init(fieldID: "nutrition.diet", value: value, confidence: 0.9, sourceSnippet: value))
                break
            }
        }

        return out
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private static func groupValue(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    // MARK: - LLM pass

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func llmPass(_ message: String) async -> [Extraction] {
        // On expose au LLM UNIQUEMENT les fieldIDs qu'on veut qu'il extrait — sinon
        // il hallucine des ids non existants. Limité aux hints les plus courants.
        let hints = ProfileFieldCatalog.allSpecs
            .filter { $0.importance >= .high }
            .prefix(30)
            .map { "\($0.id) (\($0.displayName))" }
            .joined(separator: "\n")

        let instructions = """
        Tu extrais des données typées d'un message utilisateur.

        Champs possibles (fieldID + libellé) :
        \(hints)

        Retourne un JSON STRICT sous la forme :
        [{"fieldID": "body.currentWeightKg", "value": 74.5, "confidence": 0.9}, ...]

        Règles :
        - Ne retourne QUE les champs présents dans la liste.
        - confidence entre 0.6 et 1.0 selon la clarté du message.
        - value en type natif (nombre non-string pour poids/âge, string pour enum).
        - Ne retourne PAS de champ si l'info n'est pas explicitement présente.
        - Si rien à extraire, retourne : []
        - Uniquement le JSON, aucun autre texte.
        """

        let session = LanguageModelSession(instructions: instructions)
        let raw = await RetryHelper.withBackoffOrNil(
            attempts: 1,
            delays: [],
            operation: "IntelligentExtractor.llmPass"
        ) {
            let response = try await session.respond(to: message)
            return response.content
        }
        guard let raw else { return [] }
        return parseLLMResponse(raw)
    }
    #endif

    /// Parse le JSON retourné par le LLM. Tolérant : ignore les items malformés.
    private static func parseLLMResponse(_ raw: String) -> [Extraction] {
        // Le LLM peut préfixer/suffixer — on cherche le premier `[` et le dernier `]`.
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]") else { return [] }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item -> Extraction? in
            guard let fieldID = item["fieldID"] as? String,
                  let value = item["value"],
                  let confidence = (item["confidence"] as? Double) ?? (item["confidence"] as? Int).map(Double.init) else {
                return nil
            }
            guard ProfileFieldCatalog.all[fieldID] != nil else { return nil }
            return Extraction(
                fieldID: fieldID,
                value: value,
                confidence: min(max(confidence, 0), 1),
                sourceSnippet: "\(value)"
            )
        }
    }
}
