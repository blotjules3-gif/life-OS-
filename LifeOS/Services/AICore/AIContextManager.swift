import Foundation

/// Compose et budgétise le contexte envoyé au LLM.
///
/// Responsabilité :
/// - Assembler system prompt + messages user/assistant précédents + tools disponibles
/// - Respecter un budget total en tokens (défini par le provider cible)
/// - Prioriser les infos critiques (safety, provenance, actions récentes)
/// - Truncate/résumer les infos secondaires si dépassement
/// - Exposer un `AIContextBudget` observable (debug)
///
/// Utilisation :
///   let ctx = AIContextManager()
///   let messages = ctx.build(
///     userMessage: "…",
///     previousMessages: [...],
///     systemInstructions: "…",
///     recentUpdates: [...],
///     tokenBudget: 4000
///   )
///
/// Aujourd'hui : approximation tokens = chars/4 (règle empirique GPT/Mistral).
/// Demain : integration `Tokenizer` Apple si exposé.
@MainActor
enum AIContextManager {

    /// Approximation tokens (chars/4). Suffisant pour dimensionner un budget.
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Budget par section — la somme doit tenir dans le budget total.
    struct SectionBudgets {
        let system: Int         // instructions permanentes
        let history: Int        // messages passés
        let context: Int        // profil user + expertise + mémoire
        let recentUpdates: Int  // actions déjà exécutées
        let tools: Int          // descriptions tools

        /// Répartition par défaut pour un budget total donné.
        /// Priorité : system > recentUpdates > context > history > tools
        static func defaults(for total: Int) -> SectionBudgets {
            SectionBudgets(
                system: min(1200, total * 30 / 100),           // 30% max, 1200 tokens
                history: total * 20 / 100,                      // 20%
                context: total * 35 / 100,                      // 35%
                recentUpdates: min(300, total * 10 / 100),      // 10% max, 300 tokens
                tools: total * 5 / 100                          // 5%
            )
        }
    }

    /// Résultat de l'assemblage — messages prêts pour `AIRequest` + telemetry.
    struct AssembledContext {
        let messages: [AIChatMessage]
        let usedTokens: Int
        let budgetTokens: Int
        let sectionUsage: [String: Int]     // ex: {"system": 800, "history": 400, ...}
        let truncations: [String]           // sections tronquées
    }

    /// Assemble le contexte final.
    static func build(
        userMessage: String,
        previousMessages: [AIChatMessage] = [],
        systemInstructions: String,
        contextBlock: String? = nil,
        recentUpdates: [String] = [],
        toolDefinitions: [AIToolDefinition] = [],
        tokenBudget: Int = 4000
    ) -> AssembledContext {
        let budgets = SectionBudgets.defaults(for: tokenBudget)
        var truncations: [String] = []
        var usage: [String: Int] = [:]

        // 1. System instructions — tronqué si nécessaire (mais on garde le début)
        let systemTokens = estimateTokens(systemInstructions)
        let (systemFinal, systemTrunc) = truncateToTokens(
            systemInstructions,
            maxTokens: budgets.system,
            sectionName: "system"
        )
        usage["system"] = estimateTokens(systemFinal)
        if systemTrunc { truncations.append("system") }

        // 2. Recent updates (priorité MAX après system) — appended au system
        var systemWithUpdates = systemFinal
        if !recentUpdates.isEmpty {
            let updatesBlock = """


            --- ACTIONS DÉJÀ EFFECTUÉES ---
            \(recentUpdates.map { "- \($0)" }.joined(separator: "\n"))
            Confirme obligatoirement ces actions au début de ta réponse.
            --- FIN ACTIONS ---
            """
            let (updatesFinal, updatesTrunc) = truncateToTokens(
                updatesBlock,
                maxTokens: budgets.recentUpdates,
                sectionName: "recentUpdates"
            )
            systemWithUpdates += updatesFinal
            usage["recentUpdates"] = estimateTokens(updatesFinal)
            if updatesTrunc { truncations.append("recentUpdates") }
        }

        // 3. Context block (profil user + expertise + mémoire)
        if let ctx = contextBlock, !ctx.isEmpty {
            let ctxHeader = "\n\n--- CONTEXTE UTILISATEUR ---\n"
            let ctxFooter = "\n--- FIN CONTEXTE ---"
            let ctxAvailable = budgets.context - estimateTokens(ctxHeader) - estimateTokens(ctxFooter)
            let (ctxFinal, ctxTrunc) = truncateToTokens(
                ctx,
                maxTokens: max(200, ctxAvailable),
                sectionName: "context"
            )
            systemWithUpdates += ctxHeader + ctxFinal + ctxFooter
            usage["context"] = estimateTokens(ctxHeader + ctxFinal + ctxFooter)
            if ctxTrunc { truncations.append("context") }
        }

        // 4. Tools description (si présents)
        if !toolDefinitions.isEmpty {
            let toolsBlock = "\n\n--- OUTILS DISPONIBLES ---\n" + toolDefinitions.map {
                "- \($0.name) : \($0.description)"
            }.joined(separator: "\n") + "\n--- FIN OUTILS ---"
            let (toolsFinal, toolsTrunc) = truncateToTokens(
                toolsBlock,
                maxTokens: budgets.tools,
                sectionName: "tools"
            )
            systemWithUpdates += toolsFinal
            usage["tools"] = estimateTokens(toolsFinal)
            if toolsTrunc { truncations.append("tools") }
        }

        // 5. History — on prend les N derniers messages qui tiennent dans le budget history
        let historyMessages = fitMessagesInBudget(
            messages: previousMessages,
            budget: budgets.history
        )
        usage["history"] = historyMessages.reduce(0) { $0 + estimateTokens($1.content) }
        if historyMessages.count < previousMessages.count { truncations.append("history") }

        // 6. Compose final
        var finalMessages: [AIChatMessage] = [.system(systemWithUpdates)]
        finalMessages.append(contentsOf: historyMessages)
        finalMessages.append(.user(userMessage))

        let totalUsed = usage.values.reduce(0, +) + estimateTokens(userMessage)
        return AssembledContext(
            messages: finalMessages,
            usedTokens: totalUsed,
            budgetTokens: tokenBudget,
            sectionUsage: usage,
            truncations: truncations
        )
    }

    // MARK: - Helpers

    /// Tronque un texte à un budget tokens. Coupe à la fin de phrase la plus proche.
    private static func truncateToTokens(
        _ text: String,
        maxTokens: Int,
        sectionName: String
    ) -> (String, Bool) {
        let currentTokens = estimateTokens(text)
        guard currentTokens > maxTokens else { return (text, false) }
        let maxChars = maxTokens * 4
        let prefix = String(text.prefix(maxChars))
        if let lastPeriod = prefix.lastIndex(where: { ".!?\n".contains($0) }) {
            let truncated = String(prefix[..<lastPeriod]) + "\n[…tronqué…]"
            return (truncated, true)
        }
        return (prefix + "…[tronqué…]", true)
    }

    /// Sélectionne le max de messages historiques qui tiennent dans le budget.
    /// Priorise les plus récents (fin de la liste).
    private static func fitMessagesInBudget(
        messages: [AIChatMessage],
        budget: Int
    ) -> [AIChatMessage] {
        var remaining = budget
        var selected: [AIChatMessage] = []
        for msg in messages.reversed() {
            let tokens = estimateTokens(msg.content)
            if tokens > remaining { break }
            selected.insert(msg, at: 0)
            remaining -= tokens
        }
        return selected
    }
}
