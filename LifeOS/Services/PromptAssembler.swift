import Foundation

/// Compose le prompt système envoyé à Apple Intelligence, adapté au message
/// courant et à sa classification.
///
/// Principe : chaque partie du prompt a un coût en tokens. Apple Intelligence a
/// une fenêtre contexte limitée (~4k tokens = ~16k chars). Envoyer TOUT à chaque
/// message = gâchis + risque de tronquage silencieux + latence.
///
/// Stratégie :
/// - Message simple (< 30 chars) → prompt minimal (~1500 chars)
/// - Message factuel → prompt + profil complet + expertise ciblée
/// - Message complexe → prompt full + tout le contexte pertinent
/// - Message émotionnel → prompt + few-shots empathiques + moins d'expertise
///
/// Résultat : prompt entre 2k et 12k chars selon le besoin réel.
@MainActor
enum PromptAssembler {

    /// Options passées au buildSystemPrompt classique.
    struct Config {
        let message: String
        let moduleContext: String?
        let injectContext: Bool
        let recentUpdates: [String]
    }

    /// Retourne le prompt système final, prêt pour LanguageModelSession.
    static func assemble(config: Config) -> String {
        let classification = MessageClassifier.classify(config.message)
        var sections: [String] = []

        // ── 1. CORPUS D'ENTRAÎNEMENT — adapté à la complexité ──────────────
        switch classification.complexity {
        case .simple:
            sections.append(CoachTraining.compact)
        case .moderate, .complex:
            sections.append(CoachTraining.full)
        }

        // ── 2. STRATÉGIE DE RÉPONSE — spécialisée par intent type ──────────
        sections.append(strategyBlock(for: classification))

        // ── 3. PRÉFÉRENCES USER (toujours) ─────────────────────────────────
        let prefs = CoachPreferences.current()
        sections.append("""
        PRÉFÉRENCES DE L'UTILISATEUR :
        - \(prefs.toneInstruction)
        - \(prefs.lengthInstruction)
        - \(prefs.expertiseInstruction)
        """)
        if !prefs.avoidTopics.isEmpty {
            sections.append("Sujets à éviter absolument : \(prefs.avoidTopics).")
        }

        // ── 4. MODULE CONTEXTUEL ────────────────────────────────────────────
        if let module = config.moduleContext, !module.isEmpty {
            sections.append("Le message porte principalement sur le module : \(module).")
        }

        // ── 5. FEEDBACK LOOP (👍/👎 passés) ─────────────────────────────────
        let feedback = CoachFeedbackStore.summary()
        if !feedback.isEmpty {
            sections.append("Retours de l'utilisateur sur tes réponses passées :\n\(feedback)")
        }

        // ── 6. ACTIONS DÉJÀ EFFECTUÉES (priorité max) ───────────────────────
        if !config.recentUpdates.isEmpty {
            sections.append("""
            --- IMPORTANT — ACTIONS DÉJÀ EFFECTUÉES ---
            Suite au message de l'utilisateur, tu as DÉJÀ effectué ces actions automatiquement :
            \(config.recentUpdates.map { "- \($0)" }.joined(separator: "\n"))
            Commence OBLIGATOIREMENT ta réponse par une confirmation naturelle de ces actions.
            Exemple : "C'est noté — j'ai bien ajouté X à tes habitudes, mis à jour ton poids à Y, ..."
            Puis réponds au reste du message si nécessaire (question, conseil).
            --- FIN ACTIONS ---
            """)
        }

        // ── 7. CONTEXTE USER (snapshot + expertise RAG) ─────────────────────
        if config.injectContext {
            let ctxSection = buildContextSection(classification: classification, message: config.message)
            if !ctxSection.isEmpty {
                sections.append(ctxSection)
            }
        }

        // ── 8. REFORMULATION (Loop 15) — préfixe [REFORMULE] envoyé par le VM
        // quand l'user tape "Reformule ta réponse" dans le menu contextuel.
        if config.message.hasPrefix("[REFORMULE]") {
            sections.append("""
            --- REFORMULATION DEMANDÉE ---
            L'utilisateur n'a PAS été satisfait de ta dernière réponse. Cette fois :
            - Change d'ANGLE (perspective différente, exemple différent)
            - Sois plus CONCRET (chiffre, action, étape)
            - Évite le pattern précédent (ton, longueur, structure)
            NE t'excuse PAS. Va direct à la nouvelle réponse.
            --- FIN REFORMULATION ---
            """)
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Stratégie par intent

    /// Bloc court expliquant à Apple Intelligence COMMENT répondre à ce type de message.
    /// Plus efficace qu'un mégaprompt uniforme — le LLM sait quoi prioriser.
    private static func strategyBlock(for c: MessageClassifier.Classification) -> String {
        var lines = ["--- STRATÉGIE POUR CE MESSAGE ---"]

        // Instruction principale selon intent
        switch c.intentType {
        case .actionRequest:
            lines.append("Le user demande une ACTION. Reconnais-la clairement dans ta réponse.")
            lines.append("Si l'action a été exécutée (voir ACTIONS EFFECTUÉES) → confirme brièvement.")
            lines.append("Sinon → dis franchement que tu ne peux pas l'exécuter directement, propose une alternative.")

        case .profileUpdate:
            lines.append("Le user te donne une INFO factuelle sur lui.")
            lines.append("Confirme brièvement en 1 phrase max : 'C'est noté, X.'")
            lines.append("NE fais PAS un plan complet non demandé. NE pose PAS de suivi si pas nécessaire.")

        case .factualQuestion:
            lines.append("Le user pose une QUESTION FACTUELLE.")
            lines.append("Réponds directement avec les données de son profil (voir SNAPSHOT).")
            lines.append("Cite les valeurs EXACTES ('tes 72 kg') si dispo dans le profil.")
            lines.append("Si l'info manque, demande-la précisément.")

        case .adviceRequest:
            lines.append("Le user demande un CONSEIL.")
            lines.append("Donne UN conseil actionnable ancré dans son profil (pas une liste de 5).")
            lines.append("Formule concret : 'Vu tes X, essaie Y demain.'")

        case .emotionalShare:
            lines.append("Le user PARTAGE UNE ÉMOTION.")
            lines.append("Valide sans minimiser. Reformule ce qu'il vit en 1 phrase.")
            lines.append("Propose UNE micro-action faisable aujourd'hui même.")

        case .complaint:
            lines.append("⚠️ Le user est FRUSTRÉ — probablement parce que tu l'as mal compris.")
            lines.append("Reconnais l'agacement en 1 phrase courte ('OK, j'ai mal lu').")
            lines.append("Demande-lui de reformuler ce qu'il voulait vraiment.")
            lines.append("NE renforce PAS ta position précédente.")

        case .chitchat:
            lines.append("Message social court. Réponds naturellement, 1 phrase, sans en profiter pour poser 10 questions.")

        case .unknown:
            lines.append("Intent ambigu. Reformule ce que tu comprends et demande UNE clarification.")
        }

        // Adaptation au sentiment
        switch c.sentiment {
        case .frustrated:
            lines.append("TON : reconnaître l'agacement d'abord, factuel ensuite. PAS d'enthousiasme.")
        case .discouraged:
            lines.append("TON : chaleureux, empathique, valorise chaque effort. PAS de morale.")
        case .anxious:
            lines.append("TON : rassurant sans nier. Aide à trancher avec un critère simple.")
        case .positive:
            lines.append("TON : célèbre brièvement, prolonge le momentum.")
        case .neutral:
            break
        }

        // Longueur adaptée
        switch c.complexity {
        case .simple:
            lines.append("LONGUEUR : 1-2 phrases MAX.")
        case .moderate:
            lines.append("LONGUEUR : 2-3 phrases MAX.")
        case .complex:
            lines.append("LONGUEUR : 3-5 phrases MAX. Structure claire, pas de blabla.")
        }

        lines.append("--- FIN STRATÉGIE ---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Context section

    /// Assemble snapshot user + expertise CIBLÉE (RAG).
    /// L'expertise est sélectionnée selon les topics détectés — pas de dump complet.
    private static func buildContextSection(
        classification: MessageClassifier.Classification,
        message: String
    ) -> String {
        var parts: [String] = []

        // Snapshot user (déjà bien sélectionné par UserContextBuilder)
        let snapshot = UserContextBuilder.shared.build(message: message)
        if !snapshot.isEmpty {
            // Budget : jusqu'à 6000 chars pour le snapshot complet
            let truncated = snapshot.count > 6000
                ? String(snapshot.prefix(6000)) + "\n[…]"
                : snapshot
            parts.append("""
            --- CONTEXTE UTILISATEUR (à utiliser sans le citer littéralement) ---
            \(truncated)
            --- FIN CONTEXTE ---
            Ne repose PAS de question dont la réponse est déjà dans le contexte ci-dessus.
            """)
        }

        // Note : UserContextBuilder.build() inclut déjà CoachExpertise ciblée
        // via detectTopics(in: message) — pas de dump complet.

        return parts.joined(separator: "\n\n")
    }
}
