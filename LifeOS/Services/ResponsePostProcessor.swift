import Foundation

/// Nettoie et valide la réponse générée par Apple Intelligence avant affichage.
///
/// Rôles :
/// 1. **Format** : retire markdown parasites, emojis interdits, longueur excessive
/// 2. **Fact-check** : détecte les valeurs hallucinées (ex: "tes 75 kg" alors que le profil dit 70)
/// 3. **Anti-répétition** : détecte les patterns répétés d'un tour à l'autre
/// 4. **Signature** : retire les mentions "en tant que coach je..." parasites
///
/// Chaque post-processeur peut FLAG (avertir) ou RÉÉCRIRE la réponse.
@MainActor
enum ResponsePostProcessor {

    /// Résultat du post-processing.
    struct Processed {
        let text: String                // texte final à afficher
        let originalText: String
        let issues: [Issue]             // ce qui a été corrigé (pour logs)
    }

    enum Issue: String {
        case strippedMarkdown
        case strippedEmojis
        case truncatedLength
        case removedSelfReference
        case hallucinatedNumberFlagged
        case emptyResponse
    }

    // MARK: - Entry point

    /// Pipeline complet : nettoyage → fact-check → validation.
    static func process(_ raw: String) -> Processed {
        var text = raw
        var issues: [Issue] = []

        // 1. Sanitize markdown
        let (mdCleaned, mdChanged) = stripMarkdown(text)
        text = mdCleaned
        if mdChanged { issues.append(.strippedMarkdown) }

        // 2. Strip emojis (règle projet)
        let (emojiCleaned, emojiChanged) = stripEmojis(text)
        text = emojiCleaned
        if emojiChanged { issues.append(.strippedEmojis) }

        // 3. Retire les auto-références "en tant que coach"
        let (refCleaned, refChanged) = removeSelfReferences(text)
        text = refCleaned
        if refChanged { issues.append(.removedSelfReference) }

        // 4. Trim + normalize whitespace
        text = normalizeWhitespace(text)

        // 5. Truncate si excessivement long (> 800 chars)
        let (truncated, truncChanged) = truncateIfTooLong(text, maxLen: 800)
        text = truncated
        if truncChanged { issues.append(.truncatedLength) }

        // 6. Fact-check contre ProfileField (numeric hallucinations)
        let hallucinated = detectHallucinatedNumbers(text)
        if !hallucinated.isEmpty {
            issues.append(.hallucinatedNumberFlagged)
            AppLog.coach.warning("Post-process: hallucinated numbers \(hallucinated.joined(separator: ", "), privacy: .public)")
            // On ne réécrit PAS — juste flag, l'utilisateur voit la réponse.
        }

        // 7. Empty response ?
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyResponse)
            text = "Je n'arrive pas à formuler une réponse. Reformule ta demande."
        }

        return Processed(text: text, originalText: raw, issues: issues)
    }

    // MARK: - Cleaners

    /// Retire les patterns markdown courants que le LLM peut glisser malgré l'instruction.
    private static func stripMarkdown(_ text: String) -> (String, Bool) {
        var out = text
        let before = out

        // **gras** → gras
        out = out.replacingOccurrences(
            of: #"\*\*([^\*]+)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        // *italique* → italique
        out = out.replacingOccurrences(
            of: #"(?<!\*)\*([^\*\n]+)\*(?!\*)"#,
            with: "$1",
            options: .regularExpression
        )
        // Puces "- " en début de ligne → retire
        out = out.replacingOccurrences(
            of: #"(?m)^[-•]\s+"#,
            with: "",
            options: .regularExpression
        )
        // Numérotées "1. " en début de ligne → retire
        out = out.replacingOccurrences(
            of: #"(?m)^\d+\.\s+"#,
            with: "",
            options: .regularExpression
        )
        // Headers markdown "# " en début de ligne → retire
        out = out.replacingOccurrences(
            of: #"(?m)^#+\s+"#,
            with: "",
            options: .regularExpression
        )

        return (out, out != before)
    }

    /// Retire tous les emojis (Unicode E0.6+ heuristique large).
    private static func stripEmojis(_ text: String) -> (String, Bool) {
        var changed = false
        var out = String()
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            // Blocks emoji principaux (heuristique conservatrice)
            let v = scalar.value
            let isEmoji =
                (0x1F300...0x1FAFF).contains(v) ||   // Symbols & Pictographs + suppl.
                (0x2600...0x27BF).contains(v) ||     // Misc symbols + Dingbats
                (0x1F1E6...0x1F1FF).contains(v) ||   // Flags
                v == 0xFE0F || v == 0x200D           // Variation selector, ZWJ
            if isEmoji {
                changed = true
                continue
            }
            out.unicodeScalars.append(scalar)
        }
        return (out, changed)
    }

    /// Retire les phrases où le coach parle de lui à la 1ère personne comme un système
    /// ("je suis là pour t'aider", "en tant qu'assistant", etc.). Volontairement conservateur.
    private static func removeSelfReferences(_ text: String) -> (String, Bool) {
        let patterns = [
            #"(?i)en tant qu['e]?\s*(assistant|coach|ia|intelligence artificielle)[,\.]?\s*"#,
            #"(?i)je suis (?:un[e]?)?\s*(assistant|coach virtuel|programme|système|modèle)[,\.]?\s*"#,
            #"(?i)je suis là pour t'aider[,\.]?\s*"#,
        ]
        var out = text
        let before = out
        for p in patterns {
            out = out.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return (out, out != before)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        // Multiple espaces → 1 espace ; multiple \n\n\n → \n\n
        var out = text.replacingOccurrences(
            of: #"[ \t]+"#, with: " ", options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression
        )
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncateIfTooLong(_ text: String, maxLen: Int) -> (String, Bool) {
        guard text.count > maxLen else { return (text, false) }
        // On coupe à la dernière phrase complète avant maxLen
        let prefix = String(text.prefix(maxLen))
        if let lastPeriod = prefix.lastIndex(where: { ".!?".contains($0) }) {
            return (String(prefix[...lastPeriod]), true)
        }
        return (prefix + "…", true)
    }

    // MARK: - Fact-check

    /// Cherche des valeurs numériques dans la réponse qui NE correspondent pas
    /// à ce qui est dans le profil. Ex : coach dit "tes 75 kg" alors que ProfileField = 70.
    /// N'écrase PAS la réponse — juste log un warning. Détection conservatrice.
    private static func detectHallucinatedNumbers(_ text: String) -> [String] {
        // Poids : "tes X kg" / "ton poids de X kg"
        var hallucinated: [String] = []

        if let weight: Double = ProfileStore.shared.value("body.currentWeightKg"),
           let match = text.range(of: #"(?i)(?:tes|ton poids de|tu fais)\s+(\d{2,3})\s*kg"#, options: .regularExpression) {
            let matched = String(text[match])
            let digits = matched.filter { $0.isNumber || $0 == "." }
            if let quoted = Double(digits), abs(quoted - weight) > 3 {
                hallucinated.append("poids: coach dit \(matched) mais profil = \(weight) kg")
            }
        }

        if let height: Double = ProfileStore.shared.value("body.heightCm"),
           let match = text.range(of: #"(?i)(?:tes|ta taille de|tu mesures)\s+(\d{3})\s*cm"#, options: .regularExpression) {
            let matched = String(text[match])
            let digits = matched.filter { $0.isNumber }
            if let quoted = Double(digits), abs(quoted - height) > 3 {
                hallucinated.append("taille: coach dit \(matched) mais profil = \(height) cm")
            }
        }

        return hallucinated
    }
}
