import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Moteur de génération de la prochaine question à poser à l'utilisateur.
///
/// Étapes :
/// 1. Collecter les `ProfileFieldSpec` manquants et éligibles (dépendances OK).
/// 2. Les ranker par `priorityScore`.
/// 3. Passer le top 3 + snapshot user + dernière conversation à Apple Intelligence
///    pour formuler UNE question naturelle et contextuelle.
/// 4. Fallback template si Apple Intelligence indispo.
///
/// Le moteur ne stocke aucun état — chaque appel est indépendant.
@MainActor
enum QuestionEngine {

    /// Résultat exposé à l'appelant.
    struct Suggestion {
        let text: String
        let targetFieldID: String
        let reason: String
        /// Source du texte : `.llm` (Apple Intelligence) ou `.template` (fallback).
        let source: Source

        enum Source { case llm, template }
    }

    /// Retourne la meilleure prochaine question à poser, ou `nil` si le profil
    /// est "complet" (aucun champ éligible manquant à l'importance requise).
    ///
    /// - Parameters:
    ///   - subGoal: sous-objectif courant. Filtre les specs pertinents.
    ///   - minImportance: seuil d'importance à considérer (défaut `.medium`).
    ///   - recentConversation: 3-5 derniers messages (rôle + texte) pour aider
    ///     le LLM à formuler une question qui fait le lien.
    static func nextQuestion(
        subGoal: ProfileFieldSpec.SubGoal? = nil,
        minImportance: ProfileFieldSpec.Importance = .medium,
        recentConversation: [(role: String, text: String)] = []
    ) async -> Suggestion? {
        let candidates = rankedCandidates(subGoal: subGoal, minImportance: minImportance)
        guard let top = candidates.first else { return nil }

        // Apple Intelligence pour formuler naturellement
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let text = await formulateViaLLM(
                candidates: Array(candidates.prefix(3)),
                recentConversation: recentConversation
            ) {
                return Suggestion(
                    text: text,
                    targetFieldID: top.spec.id,
                    reason: "llm formulated for top candidate: \(top.reason)",
                    source: .llm
                )
            }
        }
        #endif

        // Fallback template
        return Suggestion(
            text: templateQuestion(for: top.spec),
            targetFieldID: top.spec.id,
            reason: top.reason,
            source: .template
        )
    }

    // MARK: - Ranking

    struct Candidate {
        let spec: ProfileFieldSpec
        let score: Double
        let reason: String
    }

    /// Calcule le priorityScore pour chaque field manquant et retourne les
    /// candidats triés par score décroissant.
    static func rankedCandidates(
        subGoal: ProfileFieldSpec.SubGoal?,
        minImportance: ProfileFieldSpec.Importance
    ) -> [Candidate] {
        let missing = ProfileStore.shared.missingFields(
            for: subGoal,
            minImportance: minImportance
        )
        return missing.map { spec in
            let score = priorityScore(spec: spec, subGoal: subGoal)
            let reason = "importance=\(spec.importance) goalMatch=\(goalMatch(spec: spec, subGoal: subGoal))"
            return Candidate(spec: spec, score: score, reason: reason)
        }
        .sorted { $0.score > $1.score }
    }

    /// Formule : `importance.weight * goalRelevance * (1 - existingConfidence) * ageBoost`
    static func priorityScore(spec: ProfileFieldSpec, subGoal: ProfileFieldSpec.SubGoal?) -> Double {
        let importanceWeight = spec.importance.weight
        let goalRelevance = goalMatch(spec: spec, subGoal: subGoal)

        let existing = ProfileStore.shared.field(spec.id)
        let existingConfidence = existing?.confidence ?? 0
        let confidenceGap = max(0.0, 1.0 - existingConfidence)

        let ageBoost: Double = {
            guard let existing else { return 1.0 }
            let daysStale = Date().timeIntervalSince(existing.updatedAt) / 86400
            return daysStale > 90 ? 1.5 : 1.0
        }()

        return importanceWeight * goalRelevance * confidenceGap * ageBoost
    }

    /// 1.0 si aligné, 0.5 si neutre (spec universel), 0.2 si off-goal.
    private static func goalMatch(spec: ProfileFieldSpec, subGoal: ProfileFieldSpec.SubGoal?) -> Double {
        guard let subGoal, !spec.subGoals.isEmpty else { return spec.subGoals.isEmpty ? 0.5 : 1.0 }
        return spec.subGoals.contains(subGoal) ? 1.0 : 0.2
    }

    // MARK: - LLM formulation

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func formulateViaLLM(
        candidates: [Candidate],
        recentConversation: [(role: String, text: String)]
    ) async -> String? {
        let candidateList = candidates.map {
            "- \($0.spec.id) (\($0.spec.displayName)) [importance:\($0.spec.importance) score:\(String(format: "%.1f", $0.score))]"
        }.joined(separator: "\n")

        let conversationBlock = recentConversation.suffix(6).map { "[\($0.role)] \($0.text)" }.joined(separator: "\n")

        let instructions = """
        Tu es le coach LifeOS. Tu dois formuler la PROCHAINE question à poser à l'utilisateur pour compléter son profil.

        Champs prioritaires à demander (le premier est le plus important) :
        \(candidateList)

        Dernière conversation :
        \(conversationBlock.isEmpty ? "(aucune)" : conversationBlock)

        Consignes :
        - Choisis le champ le plus prioritaire (le premier de la liste).
        - Formule UNE seule question naturelle, en français, tutoiement.
        - Fais le lien avec la dernière réponse si pertinent (ex: "Tu m'as dit vouloir prendre du muscle. Quel est ton poids actuel ?").
        - Pas d'introduction inutile, va droit au but.
        - MAX 2 phrases.
        - Jamais d'emojis.

        Retourne UNIQUEMENT la question, rien d'autre.
        """

        let session = LanguageModelSession(instructions: instructions)
        let raw = await RetryHelper.withBackoffOrNil(
            attempts: 2,
            delays: [1],
            operation: "QuestionEngine.formulateViaLLM"
        ) {
            let response = try await session.respond(to: "Formule la question maintenant.")
            return response.content
        }
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    #endif

    // MARK: - Template fallback

    /// Format déterministe pour quand Apple Intelligence n'est pas disponible.
    /// Il est intentionnellement moins naturel — c'est un filet, pas l'expérience nominale.
    static func templateQuestion(for spec: ProfileFieldSpec) -> String {
        if let unit = spec.unit {
            return "\(spec.displayName) (\(unit)) ?"
        }
        return "\(spec.displayName) ?"
    }
}
