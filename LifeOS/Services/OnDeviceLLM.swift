import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Coach LifeOS 100 % on-device.
///
/// - iOS 26+ avec Apple Intelligence disponible → utilise `SystemLanguageModel`
///   via `FoundationModels`. Rien ne quitte l'iPhone.
/// - iOS < 26 ou Apple Intelligence indisponible (device non éligible, modèle
///   pas encore téléchargé, langue non supportée) → fallback `LocalCoach`
///   (règles).
///
/// Remplace tous les anciens appels `AgentAPI.shared.chat(...)` qui envoyaient
/// le contexte utilisateur vers Railway + Mistral. Depuis cette bascule, la
/// promesse « 100 % local » de la privacy policy tient dans les faits.
@MainActor
enum OnDeviceLLM {

    /// Résultat d'une réponse coach — texte + drapeau indiquant s'il vient
    /// du LLM on-device ou du fallback règles. Aucune donnée réseau.
    struct Reply {
        let text: String
        let source: Source
    }

    enum Source {
        case onDeviceLLM      // Apple Intelligence
        case localRules       // LocalCoach fallback
    }

    /// Point d'entrée principal du chat coach.
    /// - Parameters:
    ///   - message: message brut de l'utilisateur.
    ///   - ctx: `ModelContext` SwiftData pour laisser le fallback lire les données locales.
    ///   - moduleContext: nom optionnel du module actif (nutrition, fitness…) —
    ///     injecté dans les instructions système pour cibler la réponse.
    ///   - injectContext: quand true (défaut) on assemble contexte user + expertise + mémoire
    ///     dans le prompt système. Passer false pour un tour "premier lancement" où le prompt
    ///     est déjà auto-suffisant.
    ///   - recentUpdates: liste courte de ce que le pipeline (extraction, intent executor)
    ///     vient de faire suite au message user. Le coach DOIT les confirmer explicitement.
    ///     Format : `["Poids : 74 kg", "Habitude créée : BPC-157", "Tâche ajoutée : Appeler dentiste"]`
    static func respond(
        to message: String,
        ctx: ModelContext?,
        moduleContext: String? = nil,
        injectContext: Bool = true,
        recentUpdates: [String] = []
    ) async -> Reply {
        // Étape 0 — court-circuit détresse (jamais le LLM sur ces sujets).
        // Ce filet doit passer AVANT toute logique action locale pour ne pas être
        // détourné vers un LocalCoach qui écrirait une habitude "arrêter de vivre".
        if CoachSafetyScanner.detectsDistress(in: message) {
            return Reply(
                text: CoachSafetyScanner.distressReply,
                source: .localRules
            )
        }

        // Étape 1 — si le message ressemble à une action locale (créer une
        // habitude, logger un verre d'eau, ajouter une tâche), on laisse
        // LocalCoach l'exécuter directement. Sinon un LLM répondrait « ok je
        // vais créer ça » sans rien créer côté SwiftData.
        if isLikelyLocalAction(message), let ctx {
            return Reply(
                text: LocalCoach.respond(to: message, ctx: ctx),
                source: .localRules
            )
        }

        // Étape 2 — Apple Intelligence si dispo pour du vrai coaching.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                if let text = await respondViaAppleIntelligence(
                    message: message,
                    moduleContext: moduleContext,
                    injectContext: injectContext,
                    recentUpdates: recentUpdates
                ) {
                    return Reply(text: text, source: .onDeviceLLM)
                }
            case .unavailable:
                break // → fallback
            }
        }
        #endif

        // Étape 3 — LocalCoach rule-based comme filet, sinon message générique.
        if let ctx {
            return Reply(
                text: LocalCoach.respond(to: message, ctx: ctx),
                source: .localRules
            )
        }
        return Reply(
            text: "Je te retrouve dès que ton coach est prêt.",
            source: .localRules
        )
    }

    /// Détecte les intentions à effet local (SwiftData) déjà gérées par
    /// LocalCoach.respond : création d'habitude, tâche, note, log d'eau.
    /// Priorité au chemin déterministe : un LLM ne peut pas écrire dans SwiftData.
    private static func isLikelyLocalAction(_ message: String) -> Bool {
        let m = message.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let createVerbs = ["cree ", "creer ", "ajoute ", "ajouter ", "nouvelle ",
                           "nouveau ", "note moi ", "rappelle", "faut que", "il faut"]
        let objects = ["habitude", "habit", "tache", "tâche", "todo", "to-do",
                       "note", "rappel", "verre d'eau", "verre deau", "j'ai bu",
                       "jai bu", "bu de l'eau", "ajoute de l'eau"]
        let hasVerb = createVerbs.contains { m.contains($0) }
        let hasObject = objects.contains { m.contains($0) }
        return hasVerb && hasObject
            || objects.contains(where: { m.contains($0) && m.count < 50 })
    }

    /// Vrai si Apple Intelligence est prêt à répondre localement.
    static var isOnDeviceLLMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: - Apple Intelligence

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func respondViaAppleIntelligence(
        message: String,
        moduleContext: String?,
        injectContext: Bool,
        recentUpdates: [String]
    ) async -> String? {
        let system = buildSystemPrompt(
            message: message,
            moduleContext: moduleContext,
            injectContext: injectContext,
            recentUpdates: recentUpdates
        )
        let session = LanguageModelSession(instructions: system)
        // Retry léger : 2 tentatives avec 1s de délai entre les deux.
        // Un échec ponctuel (modèle qui charge, guardrail transitoire) peut
        // se rejouer avec succès. Si les deux échouent, on retombe sur le
        // fallback règles au lieu de laisser l'utilisateur muet.
        return await RetryHelper.withBackoffOrNil(
            attempts: 2,
            delays: [1],
            operation: "AppleIntelligence.respond"
        ) {
            let response = try await session.respond(to: message)
            return response.content
        }
    }
    #endif

    // MARK: - System prompt

    /// Construit le prompt système envoyé au LLM on-device.
    /// Contient : identité coach, préférences user, snapshot utilisateur riche
    /// (UserContextBuilder), blocs d'expertise détectés pour le message courant,
    /// mémoire long terme (via UserContextBuilder), feedback loop.
    private static func buildSystemPrompt(
        message: String,
        moduleContext: String?,
        injectContext: Bool,
        recentUpdates: [String] = []
    ) -> String {
        var parts: [String] = []

        // ── Identité + ton ──────────────────────────────────────────────────
        parts.append("Tu es le coach LifeOS, un coach de vie holistique.")
        parts.append("Tu réponds en français, tutoiement.")

        // Préférences user (ton, longueur, sujets à éviter, niveau expertise)
        let prefs = CoachPreferences.current()
        parts.append(prefs.toneInstruction)
        parts.append(prefs.lengthInstruction)
        if !prefs.avoidTopics.isEmpty {
            parts.append("Sujets à éviter absolument : \(prefs.avoidTopics).")
        }
        parts.append(prefs.expertiseInstruction)

        // Règles de forme
        parts.append("Jamais d'emojis, jamais de markdown (pas de gras, pas de listes à puces).")
        parts.append("Si tu n'as pas d'information solide, dis-le au lieu d'inventer.")

        // ── COMPRÉHENSION D'INTENT — règles absolues ────────────────────────
        // L'utilisateur parle en langage naturel. Sa demande peut être formulée
        // de mille façons ("crée", "ajoute", "tu peux mettre", "je veux tracker").
        // Le coach DOIT toujours reconnaître l'intent et le confirmer.
        parts.append("")
        parts.append("--- COMPRÉHENSION DES DEMANDES ---")
        parts.append("Quand l'utilisateur demande une ACTION (créer/ajouter/tracker une habitude, tâche, rappel) :")
        parts.append("- Reconnais l'intent même si tu ne peux pas l'exécuter techniquement dans ce tour.")
        parts.append("- Confirme explicitement ce qu'il veut : \"OK, tu veux tracker X quotidiennement, c'est noté.\"")
        parts.append("- N'IGNORE JAMAIS une demande d'action pour partir sur un conseil non demandé.")
        parts.append("- Si l'action a été automatiquement exécutée (voir bloc ACTIONS ci-dessous), confirme-la.")
        parts.append("- Si l'action n'a pas pu être exécutée automatiquement, dis-le franchement et propose au user de le faire manuellement.")
        parts.append("Quand l'utilisateur donne une INFO factuelle (poids, taille, kcal…) :")
        parts.append("- Confirme brièvement : \"C'est noté, X kg.\"")
        parts.append("- Ne fais PAS un plan complet non demandé.")

        if let module = moduleContext, !module.isEmpty {
            parts.append("La conversation porte sur le module: \(module).")
        }

        // ── Boucle feedback : préférences apprises depuis les 👍/👎 ─────────
        let feedback = CoachFeedbackStore.summary()
        if !feedback.isEmpty {
            parts.append("")
            parts.append("Retours de l'utilisateur sur tes réponses passées :")
            parts.append(feedback)
        }

        // ── Actions déjà exécutées suite au message user (priorité MAX) ─────
        // Le pipeline (extraction + intent executor) vient de faire ces choses.
        // Le coach DOIT les mentionner explicitement en début de réponse
        // (sinon l'utilisateur croit qu'il n'a rien pris en compte).
        if !recentUpdates.isEmpty {
            parts.append("")
            parts.append("--- IMPORTANT — ACTIONS DÉJÀ EFFECTUÉES ---")
            parts.append("Suite au message de l'utilisateur, tu as DÉJÀ effectué ces actions automatiquement :")
            for update in recentUpdates {
                parts.append("- \(update)")
            }
            parts.append("Commence OBLIGATOIREMENT ta réponse par une confirmation naturelle de ces actions.")
            parts.append("Exemple : \"C'est noté — j'ai bien ajouté X à tes habitudes, mis à jour ton poids à Y, ...\"")
            parts.append("Puis réponds au reste du message si nécessaire (question, conseil).")
            parts.append("--- FIN ACTIONS ---")
        }

        // ── Contexte user riche (snapshot + expertise + mémoire) ────────────
        if injectContext {
            let ctxText = UserContextBuilder.shared.build(message: message)
            if !ctxText.isEmpty {
                // On tronque à 6000 chars — la fenêtre du SLM Apple est bornée
                // et le message + réponse doivent tenir sinon la génération est
                // interrompue silencieusement.
                let truncated = ctxText.count > 6000
                    ? String(ctxText.prefix(6000)) + "\n[…]"
                    : ctxText
                parts.append("")
                parts.append("--- CONTEXTE UTILISATEUR (à utiliser sans le citer littéralement) ---")
                parts.append(truncated)
                parts.append("--- FIN CONTEXTE ---")
                parts.append("Ne repose PAS de question dont la réponse est déjà dans le contexte ci-dessus.")
            }
        }

        return parts.joined(separator: "\n")
    }
}
