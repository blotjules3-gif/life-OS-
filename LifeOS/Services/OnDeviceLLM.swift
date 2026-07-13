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
    static func respond(
        to message: String,
        ctx: ModelContext,
        moduleContext: String? = nil
    ) async -> Reply {
        // Étape 1 — si le message ressemble à une action locale (créer une
        // habitude, logger un verre d'eau, ajouter une tâche), on laisse
        // LocalCoach l'exécuter directement. Sinon un LLM répondrait « ok je
        // vais créer ça » sans rien créer côté SwiftData.
        if isLikelyLocalAction(message) {
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
                    moduleContext: moduleContext
                ) {
                    return Reply(text: text, source: .onDeviceLLM)
                }
            case .unavailable:
                break // → fallback
            }
        }
        #endif

        // Étape 3 — LocalCoach rule-based comme filet.
        return Reply(
            text: LocalCoach.respond(to: message, ctx: ctx),
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
        moduleContext: String?
    ) async -> String? {
        let system = buildSystemPrompt(moduleContext: moduleContext)
        let session = LanguageModelSession(instructions: system)
        do {
            let response = try await session.respond(to: message)
            return response.content
        } catch {
            // Modèle indisponible temporairement, contenu bloqué par les
            // guardrails, ou autre : on retourne nil pour retomber sur
            // le fallback règles au lieu de laisser l'utilisateur muet.
            return nil
        }
    }
    #endif

    // MARK: - System prompt

    /// Construit le prompt système envoyé au LLM on-device.
    /// Reste court : le contexte utilisateur riche est déjà accessible localement
    /// via `UserContextBuilder`, et on l'injecte séparément si besoin d'un
    /// tour ciblé.
    private static func buildSystemPrompt(moduleContext: String?) -> String {
        var parts: [String] = [
            "Tu es le coach LifeOS, un coach de vie holistique.",
            "Tu réponds en français, tutoiement, ton direct.",
            "Jamais d'emojis, jamais de markdown (pas de gras, pas de listes à puces).",
            "Phrases courtes, 2 à 4 lignes pour une question simple.",
            "Si tu n'as pas d'information solide, dis-le au lieu d'inventer."
        ]
        if let module = moduleContext, !module.isEmpty {
            parts.append("La conversation porte sur le module: \(module).")
        }
        return parts.joined(separator: "\n")
    }
}
