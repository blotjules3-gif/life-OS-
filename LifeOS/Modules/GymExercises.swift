import Foundation

// MARK: - Base d'exercices réels (machines + mouvements) pour guider à 100%

enum GymExercises {
    /// Groupe musculaire → exercices concrets (machine / mouvement nommé).
    static let catalog: [String: [String]] = [
        "Pecs": ["Développé couché barre", "Développé incliné haltères", "Pec deck (butterfly)",
                 "Écarté à la poulie", "Développé couché haltères", "Pompes lestées"],
        "Triceps": ["Dips", "Extension triceps à la poulie", "Barre au front (skull crusher)",
                    "Pushdown à la corde", "Extension nuque haltère"],
        "Dos": ["Tractions pronation", "Tirage vertical poulie (lat pulldown)", "Rowing barre",
                "Rowing haltère un bras", "Tirage horizontal assis (seated row)", "Tirage poulie prise serrée"],
        "Biceps": ["Curl barre EZ", "Curl haltères incliné", "Curl marteau", "Curl pupitre (preacher)", "Curl à la poulie basse"],
        "Épaules": ["Développé militaire barre", "Développé haltères assis", "Élévations latérales haltères",
                    "Oiseau (rear delt fly)", "Face pull à la poulie", "Élévations frontales"],
        "Quadriceps": ["Squat barre", "Presse à cuisses (leg press)", "Leg extension", "Hack squat", "Fentes haltères"],
        "Ischios": ["Soulevé de terre roumain", "Leg curl allongé", "Hip thrust", "Good morning", "Fentes bulgares"],
        "Mollets": ["Mollets debout machine", "Mollets assis machine", "Mollets à la presse"],
        "Abdos": ["Relevés de jambes suspendu", "Crunch à la poulie", "Gainage planche", "Roue abdominale", "Russian twist"],
        "Cardio": ["Tapis de course 15 min", "Vélo 15 min", "Rameur 10 min", "Corde à sauter 10 min"],
    ]

    /// Composition de chaque séance : suite de groupes musculaires (un exercice par entrée).
    static let templates: [String: [String]] = [
        "Pecs + Triceps":   ["Pecs", "Pecs", "Pecs", "Triceps", "Triceps", "Abdos"],
        "Dos + Biceps":     ["Dos", "Dos", "Dos", "Biceps", "Biceps", "Abdos"],
        "Jambes":           ["Quadriceps", "Quadriceps", "Ischios", "Ischios", "Mollets", "Abdos"],
        "Épaules + Abdos":  ["Épaules", "Épaules", "Épaules", "Abdos", "Abdos", "Cardio"],
        "Full / Faiblesses":["Pecs", "Dos", "Épaules", "Biceps", "Triceps", "Cardio"],
        "Push":             ["Pecs", "Pecs", "Épaules", "Épaules", "Triceps", "Triceps"],
        "Pull":             ["Dos", "Dos", "Dos", "Épaules", "Biceps", "Biceps"],
        "Legs":             ["Quadriceps", "Quadriceps", "Ischios", "Ischios", "Mollets", "Abdos"],
        "Full body A":      ["Quadriceps", "Pecs", "Dos", "Épaules", "Abdos", "Cardio"],
        "Full body B":      ["Ischios", "Pecs", "Dos", "Biceps", "Triceps", "Abdos"],
        "Haut du corps A":  ["Pecs", "Pecs", "Dos", "Dos", "Épaules", "Triceps"],
        "Haut du corps B":  ["Dos", "Dos", "Épaules", "Biceps", "Triceps", "Abdos"],
        "Bas du corps A":   ["Quadriceps", "Quadriceps", "Ischios", "Mollets", "Abdos", "Cardio"],
        "Bas du corps B":   ["Ischios", "Quadriceps", "Ischios", "Mollets", "Abdos", "Cardio"],
        "Squat focus":      ["Quadriceps", "Quadriceps", "Quadriceps", "Ischios", "Mollets", "Abdos"],
        "Bench focus":      ["Pecs", "Pecs", "Pecs", "Triceps", "Triceps", "Épaules"],
        "Deadlift focus":   ["Ischios", "Ischios", "Dos", "Dos", "Biceps", "Abdos"],
    ]

    /// Séries × reps selon l'objectif.
    static func repScheme(goal: String) -> String {
        switch goal {
        case "Force":           return "5×5"
        case "Perte de gras":   return "3×15"
        case "Forme générale":  return "3×12"
        default:                return "4×10"   // Prise de muscle
        }
    }

    /// Construit le détail d'une séance : "Développé couché barre 4×10 · …".
    /// Déterministe (pas de random) : varie l'exercice choisi par position.
    static func focus(for sessionTitle: String, goal: String) -> String {
        guard let groups = templates[sessionTitle] else { return "" }
        let reps = repScheme(goal: goal)
        var used = Set<String>()
        var items: [String] = []
        var perGroupCount: [String: Int] = [:]
        for g in groups {
            let pool = catalog[g] ?? []
            guard !pool.isEmpty else { continue }
            let n = perGroupCount[g, default: 0]
            perGroupCount[g] = n + 1
            // choisit le n-ième exercice non déjà utilisé du groupe
            let pick = pool.first { !used.contains($0) } ?? pool[min(n, pool.count - 1)]
            used.insert(pick)
            // Cardio sans reps
            items.append(g == "Cardio" ? pick : "\(pick) \(reps)")
        }
        return items.joined(separator: " · ")
    }

    /// Groupe d'un exercice à partir de son libellé (en ignorant le suffixe reps).
    static func group(of label: String) -> String? {
        let name = baseName(label)
        return catalog.first { _, list in list.contains(name) }?.key
    }

    /// Nom de base sans " 4×10".
    static func baseName(_ label: String) -> String {
        if let r = label.range(of: #" \d+×\d+$"#, options: .regularExpression) {
            return String(label[..<r.lowerBound])
        }
        return label.trimmingCharacters(in: .whitespaces)
    }

    /// Suffixe reps d'un libellé (" 4×10") ou "".
    static func repsSuffix(_ label: String) -> String {
        if let r = label.range(of: #" \d+×\d+$"#, options: .regularExpression) {
            return String(label[r])
        }
        return ""
    }

    /// Propose un exercice de remplacement du même groupe, en évitant ceux déjà présents.
    static func alternative(for label: String, avoiding present: [String]) -> String? {
        guard let g = group(of: label) else { return nil }
        let pool = catalog[g] ?? []
        let presentBases = Set(present.map { baseName($0) })
        let candidate = pool.first { !presentBases.contains($0) } ?? pool.first { $0 != baseName(label) }
        guard let c = candidate else { return nil }
        return c + repsSuffix(label)
    }
}
