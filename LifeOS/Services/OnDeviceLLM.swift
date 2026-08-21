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

    /// Résultat d'une réponse coach — texte + drapeau source + providerID
    /// précis pour affichage sous la bulle chat (transparence user).
    struct Reply {
        let text: String
        let source: Source
        /// ID exact du provider qui a répondu (ex: "openai.gpt", "apple.intelligence.on-device",
        /// "local.rules.coach"). Résolu en nom affichable via `AIProviderResolver`.
        let providerID: String?

        init(text: String, source: Source, providerID: String? = nil) {
            self.text = text
            self.source = source
            self.providerID = providerID
        }
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
                source: .localRules,
                providerID: "local.rules.coach"
            )
        }

        // Étape 1 — si le message ressemble à une action locale (créer une
        // habitude, logger un verre d'eau, ajouter une tâche), on laisse
        // LocalCoach l'exécuter directement. Sinon un LLM répondrait « ok je
        // vais créer ça » sans rien créer côté SwiftData.
        if isLikelyLocalAction(message), let ctx {
            return Reply(
                text: LocalCoach.respond(to: message, ctx: ctx),
                source: .localRules,
                providerID: "local.rules.coach"
            )
        }

        // Étape 2 — Apple Intelligence si dispo pour du vrai coaching.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                if let result = await respondViaAppleIntelligence(
                    message: message,
                    moduleContext: moduleContext,
                    injectContext: injectContext,
                    recentUpdates: recentUpdates
                ) {
                    return Reply(text: result.text, source: .onDeviceLLM, providerID: result.providerID)
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
                source: .localRules,
                providerID: "local.rules.coach"
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

    /// Statut détaillé — exposé à l'UI pour afficher une bannière si indispo.
    enum Status: Equatable {
        case available                 // Apple Intelligence actif, chat = LLM
        case iosTooOld                 // iOS < 26 → aucune chance
        case deviceNotEligible         // iOS 26 mais iPhone < 15 Pro
        case notEnabledInSettings      // User doit l'activer dans Réglages
        case modelDownloading          // Modèle en cours de téléchargement
        case unknownUnavailable        // Autre cas Apple ne nous dit pas
        case fallbackLocalCoach        // Fallback règles Swift (pas de LLM)

        var userFacingTitle: String {
            switch self {
            case .available:
                return "Apple Intelligence actif"
            case .iosTooOld:
                return "iOS trop ancien"
            case .deviceNotEligible:
                return "iPhone non compatible"
            case .notEnabledInSettings:
                return "Apple Intelligence désactivé"
            case .modelDownloading:
                return "Modèle en téléchargement"
            case .unknownUnavailable:
                return "Apple Intelligence indisponible"
            case .fallbackLocalCoach:
                return "Coach en mode dégradé"
            }
        }

        var userFacingMessage: String {
            switch self {
            case .available:
                return "Ton coach tourne entièrement sur ton iPhone. Rien n'en sort."
            case .iosTooOld:
                return "Ton coach fonctionne en mode règles. Mets à jour iOS pour activer le coach intelligent."
            case .deviceNotEligible:
                return "Ton iPhone n'a pas le neural engine requis. Ton coach fonctionne en mode règles limité."
            case .notEnabledInSettings:
                return "Active Apple Intelligence dans Réglages pour un coach beaucoup plus intelligent."
            case .modelDownloading:
                return "Apple Intelligence est en cours de téléchargement — patiente quelques minutes."
            case .unknownUnavailable:
                return "Apple Intelligence n'est pas disponible pour l'instant. Ton coach continue en mode règles."
            case .fallbackLocalCoach:
                return "Coach en mode règles (fallback). Vérifie qu'Apple Intelligence est actif dans Réglages."
            }
        }

        /// Vrai si le user peut FAIRE quelque chose (bouton "Activer" pertinent).
        var isActionable: Bool {
            self == .notEnabledInSettings
        }
    }

    /// Retourne le statut actuel — appelable depuis l'UI (synchrone, léger).
    static var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .notEnabledInSettings
                case .modelNotReady:
                    return .modelDownloading
                @unknown default:
                    return .unknownUnavailable
                }
            }
        } else {
            return .iosTooOld
        }
        #else
        return .iosTooOld
        #endif
    }

    // MARK: - Apple Intelligence

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    /// Tuple retour : texte final post-processed + providerID exact ayant
    /// répondu (utile pour l'affichage "via X" sous la bulle chat).
    struct RouterResult {
        let text: String
        let providerID: String?
    }

    private static func respondViaAppleIntelligence(
        message: String,
        moduleContext: String?,
        injectContext: Bool,
        recentUpdates: [String]
    ) async -> RouterResult? {
        // Pipeline via AI Core (Phase 1 branchée) :
        // 1. Classify le message
        // 2. Assemble le prompt via AIContextManager (budget tokens explicite)
        // 3. Route vers le meilleur provider (Apple Intelligence en priorité)
        // 4. Post-process la réponse

        // Sessions IA — début (log AIActivityLogger)
        let correlationID = UUID()

        // Awareness contextuel : heure, jour, saison, location (best-effort)
        let awareness = await AwarenessContext.snapshot()

        // Tool enrichment déterministe — invoque les tools du ToolRegistry
        // AVANT le LLM pour lui fournir des données fraîches et fiables
        // (poids réel, mémoires pertinentes, résumé profil). Silencieux si
        // aucun pattern ne matche.
        let toolBlock = await ToolEnrichment.enrich(message: message, sessionID: correlationID)

        // Assemble prompt via PromptAssembler (garde la logique adaptative existante),
        // puis wrap via AIContextManager pour tracking budget tokens.
        var systemPrompt = PromptAssembler.assemble(config: .init(
            message: message,
            moduleContext: moduleContext,
            injectContext: injectContext,
            recentUpdates: recentUpdates
        ))
        // Ajout du contexte temporel/location en fin de prompt système
        systemPrompt += "\n\n" + awareness
        if !toolBlock.isEmpty {
            systemPrompt += "\n\n" + toolBlock
        }

        // Récupère les définitions de tools autorisés (permissions user OK).
        // Pas encore envoyés au LLM Apple (nécessite iOS 26.1+ tools API — Phase P5),
        // mais visibles dans le budget de contexte + debug view.
        let toolDefinitions = ToolRegistry.shared.availableDefinitions()

        let assembled = AIContextManager.build(
            userMessage: message,
            previousMessages: [],
            systemInstructions: systemPrompt,
            contextBlock: nil,               // déjà inclus dans systemPrompt via PromptAssembler
            recentUpdates: [],               // idem, déjà dans systemPrompt
            toolDefinitions: toolDefinitions,
            tokenBudget: 4000
        )

        // Route via AIModelRouter — Apple Intelligence en priorité.
        let request = AIRequest(
            messages: assembled.messages,
            tools: toolDefinitions,
            correlationID: correlationID
        )
        let response = await AIModelRouter.shared.execute(request)

        // Log tokens et truncations dans AIActivityLogger
        AIActivityLogger.shared.recordContext(
            sessionID: correlationID,
            totalTokens: assembled.usedTokens,
            budgetTokens: assembled.budgetTokens,
            sectionUsage: assembled.sectionUsage,
            truncations: assembled.truncations
        )
        AIActivityLogger.shared.recordResponse(sessionID: correlationID, response: response)

        // Erreur ? → fallback
        guard response.isSuccess, !response.text.isEmpty else {
            AppLog.coach.warning("AIModelRouter no success: \(response.error.map(String.init(describing:)) ?? "empty", privacy: .public)")
            return nil
        }

        // Post-processing : markdown/emojis, fact-check
        let processed = ResponsePostProcessor.process(response.text)
        if !processed.issues.isEmpty {
            AIActivityLogger.shared.recordPostProcessing(
                sessionID: correlationID,
                issues: processed.issues.map(\.rawValue)
            )
        }
        return RouterResult(text: processed.text, providerID: response.providerID)
    }
    #endif

    // MARK: - System prompt
    // La construction du prompt système est maintenant déléguée à PromptAssembler.
    // Il classe le message, choisit la stratégie, sélectionne l'expertise pertinente.
}
