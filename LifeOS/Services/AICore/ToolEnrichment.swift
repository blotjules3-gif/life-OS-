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
            let start = Date()
            let result = await ToolRegistry.shared.execute("get_profile_field", argsJSON: argsJSON)
            if let block = formatToolResult(name: "get_profile_field", result: result) {
                blocks.append(block)
                logTool(sessionID: sessionID, name: "get_profile_field", result: result, since: start)
            }
        }

        // 2. Demande de résumé profil global — cas explicite uniquement.
        if matchesProfileSummary(normalized) {
            let start = Date()
            let result = await ToolRegistry.shared.execute("get_user_profile", argsJSON: "{}")
            if let block = formatToolResult(name: "get_user_profile", result: result) {
                blocks.append(block)
                logTool(sessionID: sessionID, name: "get_user_profile", result: result, since: start)
            }
        }

        // 4. Nutrition du jour — patterns : "j'ai mangé combien", "mes calories aujourd'hui"
        if matchesTodayNutrition(normalized) {
            let start = Date()
            let result = await ToolRegistry.shared.execute("get_today_nutrition", argsJSON: "{}")
            if let block = formatToolResult(name: "get_today_nutrition", result: result) {
                blocks.append(block)
                logTool(sessionID: sessionID, name: "get_today_nutrition", result: result, since: start)
            }
        }

        // 5. Habitudes complétées — patterns : "combien de séances", "j'ai fait quoi cette semaine"
        if matchesHabitCompletions(normalized) {
            let start = Date()
            let result = await ToolRegistry.shared.execute("get_habit_completions", argsJSON: "{}")
            if let block = formatToolResult(name: "get_habit_completions", result: result) {
                blocks.append(block)
                logTool(sessionID: sessionID, name: "get_habit_completions", result: result, since: start)
            }
        }

        // 6. Todos du jour — patterns : "mes tâches", "quoi faire aujourd'hui"
        if matchesTodayTodos(normalized) {
            let start = Date()
            let result = await ToolRegistry.shared.execute("get_today_todos", argsJSON: "{}")
            if let block = formatToolResult(name: "get_today_todos", result: result) {
                blocks.append(block)
                logTool(sessionID: sessionID, name: "get_today_todos", result: result, since: start)
            }
        }

        // 3. Recherche mémoire ciblée sur ce que le user a déjà dit.
        if let query = matchMemorySearch(normalized) {
            let argsJSON = #"{"query":"\#(escapeJSON(query))","limit":5}"#
            let start = Date()
            let result = await ToolRegistry.shared.execute("search_memory", argsJSON: argsJSON)
            if let block = formatToolResult(name: "search_memory", result: result) {
                blocks.append(block)
                logTool(sessionID: sessionID, name: "search_memory", result: result, since: start)
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
        // Ordre important : spécifique AVANT général (targetWeight avant
        // currentWeight, sinon la regex "mon poids" attrape "mon objectif poids").
        let patterns: [(String, String)] = [
            (#"\b(?:objectif|cible|target|goal)\b[^.?!]*\bpoids\b"#, "body.targetWeightKg"),
            (#"(?:mon|combien|quel)\b[^.?!]*\b(?:poids|pese|pesee|balance)\b"#, "body.currentWeightKg"),
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

    /// Détecte les demandes sur la nutrition du jour.
    /// Loop 12 fix M2 — patterns plus permissifs (retire le "j'ai" strict).
    static func matchesTodayNutrition(_ normalized: String) -> Bool {
        let patterns = [
            #"\b(?:mange|manger|mange[er]|bouffe|repas|manges)\b[^.?!]{0,30}\b(?:aujourd[' ]hui|matin|midi|soir|jour)\b"#,
            #"\b(?:mes|combien|quel|quelle)\b[^.?!]{0,20}\b(?:kcal|calories|proteines?|glucides|lipides|macros)\b"#,
            #"\b(?:mange|bouffe|manges)\b[^.?!]{0,20}\bquoi\b"#,
            #"\bquoi\b[^.?!]{0,20}\b(?:mange|manger|manges|bouffe)\b"#,
        ]
        return patterns.contains { normalized.range(of: $0, options: .regularExpression) != nil }
    }

    /// Détecte les demandes sur les habitudes / séances.
    static func matchesHabitCompletions(_ normalized: String) -> Bool {
        let patterns = [
            #"\b(?:mes|combien|quelles?)\b[^.?!]{0,20}\bhabitudes?\b"#,
            #"\bcombien\b[^.?!]{0,20}\b(?:seances?|entrainements?|sport)\b[^.?!]{0,15}\b(?:cette\s+semaine|aujourd[' ]hui|hier)\b"#,
            #"\b(?:mon|ma)\s+streak\b"#,
            #"\b(?:j[' ]?ai\s+fait\s+quoi|jai\s+fait\s+quoi)\b"#,
        ]
        return patterns.contains { normalized.range(of: $0, options: .regularExpression) != nil }
    }

    /// Détecte les demandes sur les todos / tâches.
    static func matchesTodayTodos(_ normalized: String) -> Bool {
        let patterns = [
            #"\b(?:mes|quelles?)\s+t[âa]ches?\b"#,
            #"\bquoi\s+faire\b[^.?!]{0,15}\b(?:aujourd[' ]hui|maintenant|ce\s+soir)\b"#,
            #"\bma\s+to[- ]?do\b"#,
        ]
        return patterns.contains { normalized.range(of: $0, options: .regularExpression) != nil }
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

    // MARK: - Formatting + logging

    /// Rend le résultat tool prêt à injecter dans le prompt. Compact,
    /// human-readable, garde la traçabilité (nom du tool).
    private static func formatToolResult(name: String, result: AIToolResult) -> String? {
        if result.success {
            return "[\(name)] \(prettifyIfPossible(result.json))"
        } else {
            AppLog.coach.warning("ToolEnrichment \(name, privacy: .public) error: \(result.error ?? "", privacy: .public)")
            return nil
        }
    }

    /// Log l'exécution dans AIActivityLogger si une session est en cours.
    private static func logTool(sessionID: UUID?, name: String, result: AIToolResult, since: Date) {
        guard let sessionID else { return }
        let durationMs = Int(Date().timeIntervalSince(since) * 1000)
        AIActivityLogger.shared.recordToolExecution(
            sessionID: sessionID,
            toolName: name,
            success: result.success,
            durationMs: durationMs
        )
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
            // Cas get_today_nutrition
            if let kcal = dict["totalKcal"] as? Int {
                let protein = dict["totalProtein"] as? Double ?? 0
                let carbs = dict["totalCarbs"] as? Double ?? 0
                let fat = dict["totalFat"] as? Double ?? 0
                let meals = dict["mealCount"] as? Int ?? 0
                let last = dict["lastMealName"] as? String
                var parts = ["Nutrition aujourd'hui : \(kcal) kcal (\(meals) repas)"]
                if protein + carbs + fat > 0 {
                    parts.append(String(format: "  %.0fg protéines, %.0fg glucides, %.0fg lipides", protein, carbs, fat))
                }
                if let last { parts.append("  Dernier repas : \(last)") }
                return parts.joined(separator: "\n")
            }
            // Cas get_habit_completions
            if let habits = dict["habits"] as? [[String: Any]] {
                let done = dict["totalCompletedToday"] as? Int ?? 0
                let total = dict["totalActiveHabits"] as? Int ?? 0
                var parts = ["Habitudes aujourd'hui : \(done)/\(total) faites"]
                let notes = habits.compactMap { h -> String? in
                    guard let name = h["name"] as? String,
                          let streak = h["currentStreak"] as? Int else { return nil }
                    let check = (h["completedToday"] as? Bool ?? false) ? "✓" : "○"
                    return "  \(check) \(name) (streak \(streak))"
                }
                if !notes.isEmpty { parts.append(contentsOf: notes.prefix(8)) }
                return parts.joined(separator: "\n")
            }
            // Cas get_today_todos (Loop 12 fix B2 : nouvelle structure)
            if let pending = dict["pending"] as? [[String: Any]] {
                let dueToday = dict["dueTodayCount"] as? Int ?? 0
                let totalPending = dict["totalPending"] as? Int ?? pending.count
                var parts = ["Todos : \(totalPending) en cours, \(dueToday) à faire aujourd'hui"]
                let items = pending.prefix(5).compactMap { t -> String? in
                    guard let title = t["title"] as? String else { return nil }
                    let prio = (t["priority"] as? Int ?? 0) >= 1 ? " !" : ""
                    let today = (t["dueToday"] as? Bool == true) ? " (aujourd'hui)" : ""
                    return "  - \(title)\(prio)\(today)"
                }
                if !items.isEmpty { parts.append(contentsOf: items) }
                return parts.joined(separator: "\n")
            }
        }
        return json
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
