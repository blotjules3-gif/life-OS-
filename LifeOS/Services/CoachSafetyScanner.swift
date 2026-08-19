import Foundation

/// Filet de sécurité côté iOS pour les réponses du coach.
///
/// Deux usages :
/// 1. **Court-circuit détresse** : détecte les messages user à risque avant même
///    d'appeler Apple Intelligence — on répond immédiatement avec le message
///    officiel 3114 (prévention suicide) au lieu de laisser le LLM improviser.
/// 2. **Scan de la réponse coach** : après génération, on tag les réponses qui
///    contiennent des dosages, noms de médicaments ou recos financières
///    précises — la vue insère un badge "consulte un pro" sous la bulle.
///
/// Le SLM Apple a ses propres guardrails mais ils sont opaques et anglophones.
/// Ce filet reste indispensable pour tenir la promesse App Store.
@MainActor
enum CoachSafetyScanner {

    // MARK: - Détresse (court-circuit avant LLM)

    /// Message affiché tel quel quand une détresse est détectée. Format exact
    /// aligné avec la ligne officielle du prompt backend prompts.py:65.
    static let distressReply = """
    Ce que tu ressens compte. Je ne suis pas la bonne ressource pour t'accompagner sur ça. Appelle le 3114 (numéro national de prévention du suicide, gratuit, 24/7) ou le 15 si c'est urgent. Tu n'es pas seul.
    """

    /// Détecte les signaux de détresse aiguë. Volontairement strict — un faux
    /// positif est infiniment moins grave qu'un faux négatif ici. On requiert
    /// une expression à la première personne pour éviter les mentions tierces
    /// ("un documentaire sur le suicide" → non déclenché).
    static func detectsDistress(in raw: String) -> Bool {
        let m = raw.folding(options: .diacriticInsensitive, locale: .current).lowercased()

        // Patterns qui parlent explicitement de soi. Chaque item doit inclure
        // un pronom ou une conjugaison à la 1re personne pour matcher.
        let firstPersonPatterns: [String] = [
            "me suicider", "me tuer", "veux mourir", "envie de mourir",
            "plus envie de vivre", "plus la force de vivre",
            "je vais en finir", "envie d'en finir", "envie den finir",
            "me faire du mal", "me faire mal", "je vais me faire",
            "mautomutil", "auto-mutil", "je vais me pendre", "me pendre",
            "je vais sauter", "avaler mes medoc", "trop de medoc",
            "je veux disparaitre", "envie de disparaitre",
            "je veux en finir",
        ]
        return firstPersonPatterns.contains(where: { m.contains($0) })
    }

    // MARK: - Scan de la réponse générée

    /// Type de badge à afficher sous une bulle coach.
    enum RiskBadge: Equatable {
        case dosage        // "500 mg", "10 UI"
        case medication    // nom de médicament identifié
        case finance       // conseil d'achat/vente ciblé
        case restriction   // suggestion de régime extrême

        var icon: String {
            switch self {
            case .dosage, .medication: return "cross.case.fill"
            case .finance: return "chart.line.uptrend.xyaxis"
            case .restriction: return "exclamationmark.triangle.fill"
            }
        }

        var label: String {
            switch self {
            case .dosage: return "Dosage mentionné — consulte un médecin"
            case .medication: return "Médicament mentionné — consulte un médecin"
            case .finance: return "Conseil financier — simulation uniquement"
            case .restriction: return "Restriction extrême — consulte un pro"
            }
        }
    }

    /// Analyse la réponse coach et retourne le premier badge à risque
    /// détecté (au plus un badge par bulle pour rester lisible).
    ///
    /// Ordre de priorité : médicament > dosage > restriction > finance.
    /// Un nom de médicament est plus informatif qu'un simple dosage.
    static func scan(_ response: String) -> RiskBadge? {
        let lower = response.lowercased()

        // 1) Noms de médicaments courants — plus spécifique que le dosage
        let meds: [String] = [
            "paracetamol", "paracétamol", "ibuprofene", "ibuprofène",
            "doliprane", "efferalgan", "aspirine", "aspegic",
            "levothyrox", "metformine", "insuline",
            "amoxicilline", "cortisone", "prednisolone",
            "ritaline", "concerta", "adderall", "xanax", "lexomil",
            "seroplex", "prozac", "zoloft", "lithium",
            "codeine", "codéine", "tramadol", "morphine"
        ]
        if meds.contains(where: { lower.contains($0) }) {
            return .medication
        }

        // 2) Dosage nu — nombre suivi d'une unité pharmaco
        let dosageRegex = #"\b\d{1,4}\s?(mg|mcg|µg|ug|ui|ml)\b"#
        if response.range(of: dosageRegex, options: .regularExpression) != nil {
            return .dosage
        }

        // 3) Restriction extrême / régimes dangereux
        // Regex kcal < 1200/j détecte 500 kcal par jour, 800 kcal/jour, etc.
        let kcalRestrictionRegex = #"\b([1-9]\d{0,2}|1[01]\d{2})\s?kcal\s?(par|/)\s?jour\b"#
        if lower.range(of: kcalRestrictionRegex, options: .regularExpression) != nil {
            return .restriction
        }
        let restrictionCues: [String] = [
            "moins de 1000 kcal", "moins de 800 kcal",
            "jeune de 3 jours", "jeûne de 3 jours", "jeune de 4 jours", "jeûne de 4 jours",
            "arrete de manger", "arrête de manger", "saute tous les repas"
        ]
        if restrictionCues.contains(where: { lower.contains($0) }) {
            return .restriction
        }

        // 4) Conseil d'achat/vente ciblé (crypto, actions nommées)
        let financeCues: [String] = [
            "achete du btc", "achète du btc", "achete du bitcoin", "achète du bitcoin",
            "achete de l'eth", "achète de l'eth", "achete de l'ether",
            "achete des actions", "achète des actions",
            "vends tes ", "vends ton ", "vends toute ", "vends tes crypto",
            "mets tout en etf", "mets tout sur ", "all-in sur "
        ]
        if financeCues.contains(where: { lower.contains($0) }) {
            return .finance
        }

        return nil
    }
}
