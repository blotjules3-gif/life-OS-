import Foundation

/// Pré-processing déterministe qui invoque les tools du `ToolRegistry`
/// AVANT l'appel au LLM.
///
/// Contexte : Apple Intelligence sur iOS 26.0 n'expose pas encore une API
/// `LanguageModelSession(tools:)` fiable pour du tool-calling multi-tour.
/// En attendant, on détecte 3 patterns simples dans le message user et on
/// exécute nous-mêmes le tool correspondant. Le résultat JSON est injecté
/// dans le contexte du prompt sous forme de bloc "INFO RÉCUPÉRÉE".
///
/// Patterns supportés v1 :
///  - `get_profile_field` : "combien je pèse", "mon poids", "mon âge", "ma taille",
///     "mon objectif poids", "mes calories" …
///  - `get_user_profile`  : "qui suis-je", "résume mon profil", "que sais-tu de moi"
///  - `search_memory`     : "tu te souviens de X", "qu'est-ce que je t'ai dit sur X"
///
/// Toute exécution passe par `ToolRegistry.shared.execute` → permissions
/// vérifiées + journalisation via `AIActivityLogger`.
@MainActor
enum ToolEnrichment {

    /// Sortie prête à concaténer dans le prompt système.
    /// Vide si aucun pattern ne matche (aucun tool invoqué).
    static func enrich(message: String, sessionID: UUID? = nil) async -> String {
        let normalized = message.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        var blocks: [String] = []

        // 1. Détection lookup profil ciblé — le plus fréquent.
        if let fieldID = matchProfileFieldQuery(normalized) {
            let argsJSON = #"{"fieldID":"\#(fieldID)"}"#
            let result = await ToolRegistry.shared.execute("get_profile_field", argsJSON: argsJSON)
            if let block = formatToolResult(name: "get_profile_field", result: result) {
                blocks.append(block)
                AIActivityLogger.shared.recordToolExecuted(
                    sessionID: sessionID, name: "get_profile_field",
                    argsJSON: argsJSON, ok: !isError(result)
                )
            }
        }

        // 2. Demande de résumé profil global — cas explicite uniquement.
        if matchesProfileSummary(normalized) {
            let result = await ToolRegistry.shared.execute("get_user_profile", argsJSON: "{}")
            if let block = formatToolResult(name: "get_user_profile", result: result) {
                blocks.append(block)
                AIActivityLogger.shared.recordToolExecuted(
                    sessionID: sessionID, name: "get_user_profile",
                    argsJSON: "{}", ok: !isError(result)
                )
            }
        }

        // 3. Recherche mémoire ciblée sur ce que le user a déjà dit.
        if let query = matchMemorySearch(normalized) {
            let argsJSON = #"{"query":"\#(escapeJSON(query))","limit":5}"#
            let result = await ToolRegistry.shared.execute("search_memory", argsJSON: argsJSON)
            if let block = formatToolResult(name: "search_memory", result: result) {
                blocks.append(block)
                AIActivityLogger.shared.recordToolExecuted(
                    sessionID: sessionID, name: "search_memory",
                    argsJSON: argsJSON, ok: !isError(result)
                )
            }
        }

        guard !blocks.isEmpty else { return "" }
        return """
        --- INFO RÉCUPÉRÉE POUR TOI (source fiable, ne pas inventer) ---
        \(blocks.joined(separator: "\n\n"))
        --- FIN INFO ---
        """
    }

    // MARK: - Pattern matching

    /// Mappe un synonyme utilisateur ("poids", "pèse", …) vers le `fieldID`
    /// correspondant. Retourne `nil` si aucune correspondance.
    static func matchProfileFieldQuery(_ normalized: String) -> String? {
        // Chaque entrée : (regex de synonymes, fieldID cible).
        // On requiert un marqueur d'interrogation/possession ("mon", "ma",
        // "combien", "quel") pour éviter les faux positifs sur des messages
        // qui mentionnent le mot en passant.
        let patterns: [(String, String)] = [
            (#"(?:mon|combien|quel)\b[^.?!]*\b(?:poids|pese|pesee|balance)\b"#, "body.currentWeightKg"),
            (#"\b(?:objectif|cible|target|goal)\b[^.?!]*\bpoids\b"#, "body.targetWeightKg"),
            (#"(?:ma|combien|quelle)\b[^.?!]*\btaille\b"#, "body.heightCm"),
            (#"(?:mon|quel)\b[^.?!]*\b(?:age|annees|ans)\b"#, "body.ageYears"),
            (#"(?:mes|combien|quel)\b[^.?!]*\b(?:kcal|calories|calorique)\b"#, "nutrition.kcalGoal"),
            (#"(?:mes|combien|quel)\b[^.?!]*\bproteines?\b"#, "nutrition.proteinGoal"),
            (#"(?:ma|combien|quelle)\b[^.?!]*\b(?:frequence|seances)\b[^.?!]*\b(?:sport|gym|salle)\b"#, "fitness.gymFrequency"),
        ]
        for (pattern, fieldID) in patterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                return fieldID
            }
        }
        return nil
    }

    /// Détecte les demandes de résumé profil complet.
    static func matchesProfileSummary(_ normalized: String) -> Bool {
        let patterns = [
            #"\bqui\s+suis[- ]je\b"#,
            #"\bresume\b[^.?!]*\bmon\s+profil\b"#,
            #"\bque\s+sais[- ]tu\b[^.?!]*\b(?:de\s+moi|sur\s+moi)\b"#,
            #"\bque\s+connais[- ]tu\b[^.?!]*\b(?:de\s+moi|sur\s+moi)\b"#,
        ]
        return patterns.contains { normalized.range(of: $0, options: .regularExpression) != nil }
    }

    /// Extrait la query mémoire ("qu'est-ce que je t'ai dit sur X" → "X").
    /// Retourne `nil` si aucune requête mémoire n'est détectée.
    static func matchMemorySearch(_ normalized: String) -> String? {
        let patterns = [
            #"(?:tu\s+te\s+souviens|te\s+rappelles)\s+(?:de\s+|)([\w\s-]{3,40})"#,
            #"(?:qu[' ]est[- ]ce\s+que\s+je\s+t[' ]?ai\s+dit\s+sur|je\s+t[' ]?ai\s+parle\s+de)\s+([\w\s-]{3,40})"#,
        ]
        for pattern in patterns {
            if let match = normalized.range(of: pattern, options: .regularExpression) {
                // Grab the captured group manually — Foundation regex is old.
                let matched = String(normalized[match])
                // Grossièrement : prendre les derniers mots après "de" / "sur"
                let suffix = matched
                    .components(separatedBy: CharacterSet(charactersIn: " "))
                    .suffix(6)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?.!,"))
                if suffix.count >= 3 {
                    return suffix
                }
            }
        }
        return nil
    }

    // MARK: - Formatting

    /// Rend le résultat tool prêt à injecter dans le prompt. Compact,
    /// human-readable, garde la traçabilité (nom du tool).
    private static func formatToolResult(name: String, result: AIToolResult) -> String? {
        switch result {
        case .success(let json):
            let pretty = prettifyIfPossible(json)
            return "[\(name)] \(pretty)"
        case .error(let msg):
            AppLog.coach.warning("ToolEnrichment \(name, privacy: .public) error: \(msg, privacy: .public)")
            return nil
        }
    }

    private static func isError(_ result: AIToolResult) -> Bool {
        if case .error = result { return true }
        return false
    }

    /// Simplifie le JSON pour l'humain (retire les {"key": "value"} superflus).
    private static func prettifyIfPossible(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return json
        }
        if let dict = obj as? [String: Any] {
            // Cas notFound : silencieux
            if dict["notFound"] as? Bool == true {
                let name = dict["displayName"] as? String ?? "champ"
                return "\(name) : non renseigné"
            }
            // Cas get_profile_field
            if let displayName = dict["displayName"] as? String,
               let value = dict["value"] as? String {
                return "\(displayName) : \(value)"
            }
            // Cas get_user_profile
            if let fields = dict["fields"] as? [[String: Any]] {
                let lines = fields.prefix(15).compactMap { f -> String? in
                    guard let name = f["displayName"] as? String,
                          let val = f["value"] as? String else { return nil }
                    return "  • \(name) : \(val)"
                }
                return "Profil :\n" + lines.joined(separator: "\n")
            }
            // Cas search_memory
            if let memories = dict["memories"] as? [[String: Any]] {
                let lines = memories.prefix(5).compactMap { m -> String? in
                    guard let content = m["content"] as? String else { return nil }
                    return "  • \(content)"
                }
                return lines.isEmpty
                    ? "Aucune mémoire trouvée"
                    : "Mémoires pertinentes :\n" + lines.joined(separator: "\n")
            }
        }
        return json
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
