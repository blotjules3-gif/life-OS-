import Foundation

/// Détecte les catégories (`AppCategory`) évoquées dans un message utilisateur.
///
/// Un seul message peut concerner plusieurs catégories, ex :
///   « Je dors 6h, je suis fatigué et j'arrive pas à progresser à la salle »
///   → [.sleep, .mind, .fitness]
///
/// Approche : keywords pondérés (rapide, offline). Pas de LLM pour l'instant —
/// les mots-clés suffisent pour le routage. Le vrai raisonnement multi-catégorie
/// reste dans le coach principal (Apple Intelligence).
enum CategoryDetector {

    struct Detection {
        let category: String  // AppCategory.rawValue
        let score: Double     // 0.0 - 1.0
    }

    /// Retourne les catégories détectées par ordre de score décroissant.
    /// Score minimum 0.15 pour être retenu.
    static func detect(from message: String) -> [Detection] {
        let normalized = message.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        var scores: [String: Double] = [:]

        for (category, keywords) in keywords {
            var score = 0.0
            for (keyword, weight) in keywords {
                if normalized.contains(keyword) {
                    score += weight
                }
            }
            if score > 0 {
                scores[category] = min(1.0, score)
            }
        }

        return scores
            .filter { $0.value >= 0.15 }
            .map { Detection(category: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }
    }

    /// Dict keyword → weight par catégorie. Weights faibles (0.15-0.35) pour
    /// permettre l'accumulation multi-keyword sans faux positifs.
    private static let keywords: [String: [(String, Double)]] = [
        "fitness": [
            ("salle", 0.35), ("gym", 0.35), ("muscu", 0.35), ("s'entrain", 0.3), ("sentrain", 0.3),
            ("seance", 0.3), ("bench", 0.25), ("squat", 0.25), ("deadlift", 0.25),
            ("cardio", 0.25), ("hiit", 0.25), ("course", 0.2), ("courir", 0.25),
            ("velo", 0.2), ("natation", 0.2), ("prise de muscle", 0.4), ("perdre du muscle", 0.35),
            ("progression", 0.2), ("1rm", 0.35), ("volume", 0.2),
        ],
        "nutrition": [
            ("manger", 0.3), ("mange", 0.25), ("repas", 0.3), ("kcal", 0.4), ("calories", 0.35),
            ("proteines", 0.35), ("regime", 0.3), ("aliment", 0.3), ("appetit", 0.35),
            ("faim", 0.3), ("boire", 0.15), ("eau", 0.2), ("hydrat", 0.25),
            ("petit-dej", 0.35), ("petit dej", 0.35), ("dejeuner", 0.3), ("diner", 0.3),
            ("végétarien", 0.4), ("vegan", 0.4), ("keto", 0.4),
        ],
        "sleep": [
            ("dormi", 0.4), ("dormir", 0.35), ("dors", 0.4), ("sommeil", 0.45),
            ("nuit", 0.25), ("insomnie", 0.5), ("reveil", 0.25), ("coucher", 0.3),
            ("fatigue", 0.2), ("sieste", 0.25), ("melatonine", 0.35),
        ],
        "mind": [
            ("stress", 0.4), ("anxiete", 0.4), ("meditation", 0.45), ("mediter", 0.4),
            ("humeur", 0.35), ("mental", 0.3), ("moral", 0.3), ("depression", 0.45),
            ("focus", 0.25), ("concentr", 0.25), ("pleine conscience", 0.4),
        ],
        "productivity": [
            ("tache", 0.3), ("todo", 0.35), ("to-do", 0.35), ("productivite", 0.4),
            ("productif", 0.35), ("focus", 0.25), ("pomodoro", 0.4), ("habit", 0.25),
            ("habitude", 0.3), ("routine", 0.25), ("planning", 0.3),
        ],
        "finance": [
            ("argent", 0.3), ("budget", 0.4), ("depense", 0.35), ("depenser", 0.3),
            ("salaire", 0.4), ("epargne", 0.4), ("compte", 0.2), ("abonnement", 0.25),
            ("banque", 0.25), ("euro", 0.15), ("€", 0.15),
        ],
        "invest": [
            ("investir", 0.4), ("investissement", 0.45), ("bourse", 0.4), ("action", 0.15),
            ("etf", 0.4), ("crypto", 0.35), ("bitcoin", 0.4), ("btc", 0.35), ("portefeuille", 0.35),
            ("pea", 0.4), ("assurance vie", 0.4), ("rendement", 0.35),
        ],
        "career": [
            ("job", 0.35), ("emploi", 0.4), ("boulot", 0.3), ("travail", 0.2), ("carriere", 0.45),
            ("cv", 0.4), ("entretien", 0.35), ("promotion", 0.35), ("reconversion", 0.5),
            ("linkedin", 0.4), ("manager", 0.25),
        ],
        "learning": [
            ("apprendre", 0.4), ("etudier", 0.35), ("cours", 0.25), ("livre", 0.25),
            ("flashcard", 0.4), ("anki", 0.4), ("langue", 0.3), ("vocabulaire", 0.35),
        ],
        "looks": [
            ("peau", 0.35), ("skincare", 0.5), ("soin", 0.25), ("cheveux", 0.3),
            ("barbe", 0.3), ("dent", 0.25), ("smile", 0.3), ("mode", 0.2),
            ("photo progression", 0.4), ("looksmax", 0.5),
        ],
        "social": [
            ("ami", 0.3), ("famille", 0.3), ("relation", 0.35), ("social", 0.4),
            ("rendez-vous", 0.3), ("rdv", 0.2), ("rencontre", 0.3), ("anniversaire", 0.35),
        ],
        "home": [
            ("maison", 0.3), ("appart", 0.35), ("logement", 0.35), ("menage", 0.4),
            ("nettoy", 0.3), ("ranger", 0.3), ("cuisine", 0.2), ("chien", 0.35), ("chat", 0.35),
            ("animal", 0.3),
        ],
        "mobility": [
            ("voiture", 0.4), ("essence", 0.4), ("moto", 0.35), ("velo", 0.3),
            ("transport", 0.35), ("metro", 0.3), ("train", 0.25),
        ],
        "admin": [
            ("impot", 0.45), ("papiers", 0.4), ("administratif", 0.5), ("document", 0.25),
            ("passeport", 0.4), ("permis", 0.35), ("facture", 0.35),
        ],
        "travel": [
            ("voyage", 0.4), ("vol", 0.2), ("avion", 0.35), ("hotel", 0.35),
            ("airbnb", 0.4), ("valise", 0.35), ("bagage", 0.3), ("visa", 0.35),
            ("jet lag", 0.4),
        ],
        "cycle": [
            ("regle", 0.4), ("cycle", 0.35), ("menstruation", 0.5), ("ovulation", 0.5),
            ("spm", 0.5), ("sopk", 0.5), ("endometriose", 0.5), ("pilule", 0.4),
        ],
        "medical": [
            ("medecin", 0.45), ("docteur", 0.4), ("medicament", 0.45), ("hopital", 0.4),
            ("diabete", 0.5), ("asthme", 0.5), ("hypertension", 0.5), ("allergi", 0.35),
            ("douleur", 0.3), ("symptome", 0.4), ("cardio", 0.15),
        ],
    ]
}
