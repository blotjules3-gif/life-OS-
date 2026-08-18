import Foundation

/// Préférences utilisateur pour le comportement du coach.
///
/// Chargées depuis UserDefaults à chaque `send()` (léger, pas de cache) pour que
/// tout changement dans l'écran Préférences se reflète au message suivant sans
/// redémarrage.
///
/// Chaque enum expose une phrase d'instruction prête à être injectée dans le
/// prompt système. Pas d'exposition du raw string au LLM (« coachTone=cash »)
/// qui polluerait la lecture.
@MainActor
struct CoachPreferences {

    enum Tone: String, CaseIterable, Identifiable {
        case pose      // calme, mesuré
        case motivant  // enthousiaste, coaching sportif
        case cash      // direct, cru, sans langue de bois
        case empathique // doux, à l'écoute

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pose: return "Posé"
            case .motivant: return "Motivant"
            case .cash: return "Cash"
            case .empathique: return "Empathique"
            }
        }

        var systemInstruction: String {
            switch self {
            case .pose:
                return "Ton posé, mesuré, sans emphase. Tu prends le temps de bien formuler."
            case .motivant:
                return "Ton énergique, motivant, coaching sportif. Tu pousses vers l'action."
            case .cash:
                return "Ton direct, cru, sans langue de bois. Pas de fioritures — tu dis les choses."
            case .empathique:
                return "Ton doux, à l'écoute, validant. Tu accueilles les émotions avant de conseiller."
            }
        }
    }

    enum Length: String, CaseIterable, Identifiable {
        case court     // 1 phrase
        case normal    // 2-3 phrases
        case detaille  // 4-5 phrases

        var id: String { rawValue }

        var label: String {
            switch self {
            case .court: return "Court (1 phrase)"
            case .normal: return "Normal (2-3 phrases)"
            case .detaille: return "Détaillé (4-5 phrases)"
            }
        }

        var systemInstruction: String {
            switch self {
            case .court:
                return "Réponds en UNE phrase maximum. Pas d'exception."
            case .normal:
                return "Réponds en 2 à 3 phrases maximum. Va à l'essentiel."
            case .detaille:
                return "Tu peux répondre en 4 à 5 phrases si le sujet le justifie. Reste concis."
            }
        }
    }

    enum ExpertiseLevel: String, CaseIterable, Identifiable {
        case vulgarise      // analogies, mots simples
        case intermediaire  // vocabulaire technique modéré
        case expert         // ratios, mécanismes, jargon assumé

        var id: String { rawValue }

        var label: String {
            switch self {
            case .vulgarise: return "Vulgarisé"
            case .intermediaire: return "Intermédiaire"
            case .expert: return "Expert"
            }
        }

        var systemInstruction: String {
            switch self {
            case .vulgarise:
                return "Vulgarise systématiquement : analogies, mots simples, pas de jargon."
            case .intermediaire:
                return "Vocabulaire technique modéré, expliqué quand pertinent."
            case .expert:
                return "Vocabulaire technique assumé : chiffres, ratios, mécanismes physiologiques."
            }
        }
    }

    let tone: Tone
    let length: Length
    let expertiseLevel: ExpertiseLevel
    let avoidTopics: String  // liste libre séparée par virgules

    var toneInstruction: String { tone.systemInstruction }
    var lengthInstruction: String { length.systemInstruction }
    var expertiseInstruction: String { expertiseLevel.systemInstruction }

    /// Charge les préférences actuelles depuis UserDefaults, avec valeurs par défaut.
    static func current() -> CoachPreferences {
        let ud = UserDefaults.standard
        let tone = Tone(rawValue: ud.string(forKey: AppStorageKeys.coachTone) ?? "") ?? .empathique
        let length = Length(rawValue: ud.string(forKey: AppStorageKeys.coachLength) ?? "") ?? .normal
        let expertise = ExpertiseLevel(rawValue: ud.string(forKey: AppStorageKeys.coachExpertiseLevel) ?? "") ?? .intermediaire
        let avoid = ud.string(forKey: AppStorageKeys.coachAvoidTopics) ?? ""
        return CoachPreferences(
            tone: tone,
            length: length,
            expertiseLevel: expertise,
            avoidTopics: avoid.trimmingCharacters(in: CharacterSet.whitespaces)
        )
    }
}
