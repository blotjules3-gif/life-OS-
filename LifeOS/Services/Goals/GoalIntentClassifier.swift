import Foundation

/// Détecte un intent d'objectif dans un message user + extrait la magnitude
/// éventuelle (kg à perdre, € à économiser, séances/sem…).
///
/// Retourne `nil` si le message n'exprime pas un objectif reconnaissable.
/// Approche déterministe (regex + keywords) — pas de LLM, safe + rapide.
///
/// Loop 24 fondation Goal-Plan.
@MainActor
enum GoalIntentClassifier {

    struct Detection {
        let kind: GoalKind
        /// Valeur numérique extraite (kg, €, h…). 0 si aucune.
        let magnitude: Double
        /// Unité extraite ("kg", "€", "kg/mois"…).
        let unit: String
    }

    /// Analyse un message. Retourne la détection la plus forte ou `nil`.
    static func detect(in message: String) -> Detection? {
        let m = normalize(message)

        // 1. Perdre du poids — "perdre 5 kg", "je veux mincir", "maigrir"
        if let magnitude = extractNumber(after: #"perdre\b[^.?!]{0,15}"#, in: m) {
            return Detection(kind: .weightLoss, magnitude: magnitude, unit: "kg")
        }
        if m.range(of: #"\b(mincir|maigrir|perdre\s+du\s+(poids|gras))\b"#, options: .regularExpression) != nil {
            return Detection(kind: .weightLoss, magnitude: 0, unit: "kg")
        }

        // 2. Prendre du muscle
        if m.range(of: #"\bprendre\s+du\s+(muscle|masse)\b"#, options: .regularExpression) != nil ||
           m.range(of: #"\bme?\s+muscler\b"#, options: .regularExpression) != nil ||
           m.range(of: #"\bplus\s+de\s+muscle\b"#, options: .regularExpression) != nil {
            let mag = extractNumber(after: #"prendre\b[^.?!]{0,10}"#, in: m) ?? 0
            return Detection(kind: .muscleGain, magnitude: mag, unit: "kg")
        }

        // 3. Mieux dormir
        if m.range(of: #"\bmieux\s+dormir\b"#, options: .regularExpression) != nil ||
           m.range(of: #"\b(sommeil|dormir)\b[^.?!]{0,15}\b(ameliorer|meilleur)\b"#, options: .regularExpression) != nil ||
           m.range(of: #"\bfatigue\b"#, options: .regularExpression) != nil {
            return Detection(kind: .sleepBetter, magnitude: 0, unit: "")
        }

        // 4. Économiser
        if let magnitude = extractNumber(after: #"economiser\b[^.?!]{0,15}"#, in: m) {
            return Detection(kind: .saveMoney, magnitude: magnitude, unit: "€")
        }
        if m.range(of: #"\b(depenser\s+moins|reduire\s+depenses?|budget)\b"#, options: .regularExpression) != nil {
            return Detection(kind: .saveMoney, magnitude: 0, unit: "€")
        }

        // 5. Productivité / focus
        if m.range(of: #"\b(plus\s+productif|mieux\s+focus|deep\s+work|arreter\s+de\s+procrastiner)\b"#, options: .regularExpression) != nil {
            return Detection(kind: .moreProductive, magnitude: 0, unit: "")
        }

        // 6. Mieux manger
        if m.range(of: #"\b(mieux\s+manger|bien\s+manger|manger\s+sainement|equilibrer\s+mon\s+alimentation)\b"#, options: .regularExpression) != nil {
            return Detection(kind: .eatBetter, magnitude: 0, unit: "")
        }

        // 7. Stress / mental
        if m.range(of: #"\b(moins\s+stress|gerer\s+mon\s+stress|calm)\w*"#, options: .regularExpression) != nil {
            return Detection(kind: .reduceStress, magnitude: 0, unit: "")
        }

        // 8. Reprendre le sport
        if m.range(of: #"\b(reprendre|me\s+remettre)\s+(au\s+)?sport\b"#, options: .regularExpression) != nil ||
           m.range(of: #"\bfaire\s+plus\s+de\s+sport\b"#, options: .regularExpression) != nil {
            return Detection(kind: .fitnessGeneral, magnitude: 0, unit: "")
        }

        // Marqueur générique "je veux X" sans domaine reconnu → custom
        if m.range(of: #"\bje\s+veux\b"#, options: .regularExpression) != nil ||
           m.range(of: #"\bmon\s+objectif\b"#, options: .regularExpression) != nil {
            return Detection(kind: .custom, magnitude: 0, unit: "")
        }

        return nil
    }

    // MARK: - Helpers

    static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    /// Extrait le premier nombre (int ou décimal) après un pattern regex.
    /// Retourne `nil` si aucun nombre.
    private static func extractNumber(after pattern: String, in text: String) -> Double? {
        guard let range = text.range(of: pattern + #"\s*(\d+(?:[.,]\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(text[range])
        // Extrait le nombre à la fin
        let numberPattern = #"(\d+(?:[.,]\d+)?)\s*$"#
        guard let numberRange = matched.range(of: numberPattern, options: .regularExpression) else {
            return nil
        }
        let numberStr = String(matched[numberRange])
            .replacingOccurrences(of: ",", with: ".")
        return Double(numberStr)
    }
}
