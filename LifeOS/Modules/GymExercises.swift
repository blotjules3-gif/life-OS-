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
        // Nouvel objectif depuis que la question accepte plusieurs reponses.
        case "Cardio / Endurance": return "3×15"
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

    /// Nom de base sans la cible (" 4×10", " 3×8-12", " 4 x 10"...). Voir `ExerciseLabel`.
    static func baseName(_ label: String) -> String { ExerciseLabel.split(label).name }

    /// Suffixe de cible d'un libellé, espace initial compris, ou "".
    static func repsSuffix(_ label: String) -> String {
        let suffix = ExerciseLabel.split(label).suffix.trimmingCharacters(in: .whitespaces)
        return suffix.isEmpty ? "" : " " + suffix
    }

    /// Propose un exercice de remplacement du même groupe, en évitant ceux déjà présents.
    /// Avec le matériel et les exclusions de l'utilisateur : un exercice impossible ou
    /// exclu n'est jamais propose. Par defaut (salle, rien d'exclu) : comme avant.
    static func alternative(for label: String, avoiding present: [String],
                            equipment: Set<FitbotEquipment> = [.gym], excluded: Set<String> = []) -> String? {
        guard let g = group(of: label) else { return nil }
        let pool = choices(group: g, equipment: equipment, excluded: excluded)
        let presentBases = Set(present.map { baseName($0) })
        let candidate = pool.first { !presentBases.contains($0) } ?? pool.first { $0 != baseName(label) }
        guard let c = candidate else { return nil }
        return c + repsSuffix(label)
    }
}

// MARK: - Matériel disponible

/// Matériel que l'utilisateur a sous la main. Le poids du corps est toujours là.
enum FitbotEquipment: String, CaseIterable, Codable, Identifiable {
    case gym, dumbbells, bodyweight, bands
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gym: return "Salle complète"
        case .dumbbells: return "Haltères"
        case .bodyweight: return "Poids du corps"
        case .bands: return "Élastiques"
        }
    }
    var icon: String {
        switch self {
        case .gym: return "dumbbell.fill"
        case .dumbbells: return "scalemass.fill"
        case .bodyweight: return "figure.strengthtraining.functional"
        case .bands: return "lasso"
        }
    }

    /// "gym,dumbbells" → ensemble. Vide ou illisible = salle complète, le reglage
    /// d'avant (le programme supposait une salle).
    static func parse(_ raw: String) -> Set<FitbotEquipment> {
        let set = Set(raw.split(separator: ",").compactMap { FitbotEquipment(rawValue: String($0)) })
        return set.isEmpty ? [.gym] : set
    }
    static func serialize(_ set: Set<FitbotEquipment>) -> String {
        allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
    static func summary(_ set: Set<FitbotEquipment>) -> String {
        allCases.filter(set.contains).map(\.label).joined(separator: ", ")
    }
}

/// Reglages Fitbot gardes entre deux lancements (matériel, exclusions).
enum FitbotSettings {
    static let equipmentKey = "fitbot.equipment"
    static let excludedKey = "fitbot.excluded"

    static func parseExcluded(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    static func serializeExcluded(_ set: Set<String>) -> String { set.sorted().joined(separator: "|") }
}

extension GymExercises {
    /// Exercices du catalogue faisables HORS salle, et avec quoi. Tout exercice du
    /// catalogue absent d'ici demande une salle (barre, machine, poulie, barre de
    /// traction). Aucun exercice du catalogue ne se fait aux élastiques : c'est un
    /// manque de contenu, pas une regle.
    static let outsideGym: [String: Set<FitbotEquipment>] = [
        "Développé incliné haltères": [.dumbbells],
        "Développé couché haltères": [.dumbbells],
        "Extension nuque haltère": [.dumbbells],
        "Rowing haltère un bras": [.dumbbells],
        "Curl haltères incliné": [.dumbbells],
        "Curl marteau": [.dumbbells],
        "Développé haltères assis": [.dumbbells],
        "Élévations latérales haltères": [.dumbbells],
        "Oiseau (rear delt fly)": [.dumbbells],
        "Élévations frontales": [.dumbbells],
        "Fentes haltères": [.dumbbells],
        "Soulevé de terre roumain": [.dumbbells],
        "Fentes bulgares": [.bodyweight, .dumbbells],
        "Gainage planche": [.bodyweight],
        "Russian twist": [.bodyweight],
    ]

    /// L'exercice se fait-il avec ce matériel ? Un libellé libre (hors catalogue)
    /// passe : on ne sait pas juger, et l'utilisateur l'a ecrit lui-meme.
    static func isAllowed(_ label: String, with available: Set<FitbotEquipment>) -> Bool {
        let name = baseName(label)
        guard group(of: name) != nil else { return true }
        if available.contains(.gym) { return true }
        let kit = outsideGym[name] ?? []
        // Le poids du corps est toujours disponible.
        return !kit.intersection(available.union([.bodyweight])).isEmpty
    }

    /// Exercices d'un groupe faisables avec ce matériel, sans les exclus, dans
    /// l'ordre du catalogue.
    static func choices(group: String, equipment: Set<FitbotEquipment>, excluded: Set<String> = []) -> [String] {
        (catalog[group] ?? []).filter { isAllowed($0, with: equipment) && !excluded.contains($0) }
    }

    /// Tous les remplaçants possibles : meme groupe musculaire, faisables avec le
    /// matériel, ni exclus ni deja dans la seance. Gardent la cible du libellé.
    static func alternatives(for label: String, avoiding present: [String],
                             equipment: Set<FitbotEquipment> = [.gym], excluded: Set<String> = []) -> [String] {
        guard let g = group(of: label) else { return [] }
        let presentBases = Set(present.map { baseName($0) }).union([baseName(label)])
        return choices(group: g, equipment: equipment, excluded: excluded)
            .filter { !presentBases.contains($0) }
            .map { $0 + repsSuffix(label) }
    }
}

// MARK: - Supersets

/// Deux exercices enchaines sans repos entre eux. Stockes sur `GymDay.supersetsJSON`
/// par NOMS de base (pas par position : la liste se reordonne), et toujours voisins
/// dans la liste du jour, pour que la seance les enchaine dans l'ordre.
enum FitbotSupersets {
    static func decode(_ json: String) -> [[String]] {
        guard let d = json.data(using: .utf8), let v = try? JSONDecoder().decode([[String]].self, from: d) else { return [] }
        return v.filter { $0.count == 2 }
    }
    static func encode(_ pairs: [[String]]) -> String {
        guard !pairs.isEmpty, let d = try? JSONEncoder().encode(pairs) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    static func partner(of label: String, in pairs: [[String]]) -> String? {
        let n = GymExercises.baseName(label)
        for p in pairs where p.contains(n) { return p[0] == n ? p[1] : p[0] }
        return nil
    }

    /// Associe l'exercice `index` au suivant. Rien si l'un des deux est deja en paire
    /// ou s'il n'y a pas de suivant.
    static func pair(at index: Int, exercises: [String], pairs: [[String]]) -> [[String]] {
        guard exercises.indices.contains(index), exercises.indices.contains(index + 1) else { return pairs }
        let a = GymExercises.baseName(exercises[index]), b = GymExercises.baseName(exercises[index + 1])
        guard a != b, partner(of: a, in: pairs) == nil, partner(of: b, in: pairs) == nil else { return pairs }
        return pairs + [[a, b]]
    }

    static func unpair(_ label: String, pairs: [[String]]) -> [[String]] {
        let n = GymExercises.baseName(label)
        return pairs.filter { !$0.contains(n) }
    }

    /// Un exercice remplacé garde sa place dans la paire.
    static func rename(_ old: String, to new: String, pairs: [[String]]) -> [[String]] {
        let o = GymExercises.baseName(old), n = GymExercises.baseName(new)
        return pairs.map { $0.map { $0 == o ? n : $0 } }
    }

    /// Ne garde que les paires dont les deux exercices sont encore la ET voisins.
    static func prune(_ pairs: [[String]], exercises: [String]) -> [[String]] {
        let names = exercises.map { GymExercises.baseName($0) }
        return pairs.filter { p in
            guard let i = names.firstIndex(of: p[0]), let j = names.firstIndex(of: p[1]) else { return false }
            return abs(i - j) == 1
        }
    }
}

// MARK: - Générateur de programme

/// Objectif du programme et ses reperes generaux de series, repetitions et repos.
/// Ce sont des fourchettes d'usage courant en musculation, pas une prescription
/// medicale : l'ecran le dit.
enum FitbotGoal: String, CaseIterable, Codable, Identifiable {
    case force, hypertrophie, endurance, pertePoids
    var id: String { rawValue }
    var label: String {
        switch self {
        case .force: return "Force"
        case .hypertrophie: return "Hypertrophie"
        case .endurance: return "Endurance"
        case .pertePoids: return "Perte de poids"
        }
    }
    var sets: Int { self == .force ? 5 : 3 }
    var reps: String {
        switch self {
        case .force: return "3-5"
        case .hypertrophie: return "8-12"
        case .endurance: return "15-20"
        case .pertePoids: return "12-15"
        }
    }
    var restSeconds: Int {
        switch self {
        case .force: return 180
        case .hypertrophie: return 90
        case .endurance: return 45
        case .pertePoids: return 60
        }
    }
    /// Cible ecrite dans le libellé, lue par `StrengthProgression.target`.
    var target: String { "\(sets)×\(reps)" }
    /// Un bloc cardio en fin de seance pour ces objectifs.
    var addsCardio: Bool { self == .endurance || self == .pertePoids }
    var guidance: String {
        "\(sets) séries de \(reps.replacingOccurrences(of: "-", with: " à ")) répétitions, \(restSeconds < 60 ? "\(restSeconds) s" : "\(restSeconds / 60) min\(restSeconds % 60 == 0 ? "" : " 30")") de repos"
    }

    /// Objectif du questionnaire « Sport & fitness » → objectif du générateur.
    static func fromSetup(_ goal: String) -> FitbotGoal {
        switch goal {
        case "Force": return .force
        case "Perte de gras": return .pertePoids
        case "Cardio / Endurance": return .endurance
        default: return .hypertrophie   // Prise de muscle, Forme générale
        }
    }
}

/// Decoupage de la semaine, choisi par la frequence.
enum FitbotSplit: String, CaseIterable, Codable {
    case fullBody, upperLower, pushPullLegs
    var label: String {
        switch self {
        case .fullBody: return "Full body"
        case .upperLower: return "Haut / bas"
        case .pushPullLegs: return "Push / pull / legs"
        }
    }
    /// 2 ou 3 seances : tout le corps a chaque fois (chaque muscle 2 a 3 fois par
    /// semaine). 4 : haut / bas. 5 et 6 : push / pull / legs.
    static func forDays(_ n: Int) -> FitbotSplit {
        switch n {
        case ...3: return .fullBody
        case 4: return .upperLower
        default: return .pushPullLegs
        }
    }
}

enum FitbotGenerator {
    struct Week: Equatable {
        let goal: FitbotGoal
        let split: FitbotSplit
        let daysPerWeek: Int
        let sessionMinutes: Int
        let equipment: Set<FitbotEquipment>
        /// Les 7 jours, lundi → dimanche.
        var days: [GymDaySnapshot]
        /// Groupes musculaires sans aucun exercice du catalogue pour ce matériel.
        let uncoveredGroups: [String]
        /// Chaque jour d'entraînement a au moins un exercice.
        var isUsable: Bool { days.allSatisfy { $0.isRest || !$0.exercises.isEmpty } }
    }

    static let allowedDays = 2...6
    static let sessionLengths = [30, 45, 60, 75, 90]

    /// Groupes par seance, du plus important au moins important : on coupe la fin
    /// quand le temps manque.
    private static let fullBody: [[String]] = [
        ["Quadriceps", "Pecs", "Dos", "Épaules", "Ischios", "Biceps", "Triceps", "Abdos", "Mollets"],
        ["Ischios", "Dos", "Pecs", "Épaules", "Quadriceps", "Triceps", "Biceps", "Abdos", "Mollets"],
        ["Quadriceps", "Dos", "Pecs", "Ischios", "Épaules", "Abdos", "Biceps", "Triceps", "Mollets"],
    ]
    private static let upper: [String] = ["Pecs", "Dos", "Épaules", "Pecs", "Dos", "Triceps", "Biceps", "Épaules"]
    private static let lower: [String] = ["Quadriceps", "Ischios", "Quadriceps", "Ischios", "Mollets", "Abdos", "Abdos"]
    private static let push: [String] = ["Pecs", "Épaules", "Pecs", "Triceps", "Épaules", "Triceps", "Pecs", "Abdos"]
    private static let pull: [String] = ["Dos", "Dos", "Biceps", "Épaules", "Dos", "Biceps", "Abdos", "Dos"]
    private static let legs: [String] = ["Quadriceps", "Ischios", "Quadriceps", "Ischios", "Mollets", "Abdos", "Quadriceps"]

    /// (titre, groupes, variante) de chaque seance de la semaine.
    static func sessions(split: FitbotSplit, days: Int) -> [(title: String, groups: [String], variant: Int)] {
        switch split {
        case .fullBody:
            let names = ["Full body A", "Full body B", "Full body C"]
            return (0..<days).map { (names[$0 % 3], fullBody[$0 % 3], $0) }
        case .upperLower:
            return [("Haut du corps A", upper, 0), ("Bas du corps A", lower, 0),
                    ("Haut du corps B", upper, 1), ("Bas du corps B", lower, 1)]
        case .pushPullLegs:
            if days >= 6 {
                return [("Push A", push, 0), ("Pull A", pull, 0), ("Legs A", legs, 0),
                        ("Push B", push, 1), ("Pull B", pull, 1), ("Legs B", legs, 1)]
            }
            return [("Push", push, 0), ("Pull", pull, 0), ("Legs", legs, 0),
                    ("Haut du corps", upper, 1), ("Bas du corps", lower, 1)]
        }
    }

    /// Jours d'entraînement (positions lundi = 0 … dimanche = 6), un jour de repos
    /// entre deux seances quand la frequence le permet.
    static func trainingPositions(days: Int) -> [Int] {
        switch days {
        case ...2: return [0, 3]
        case 3: return [0, 2, 4]
        case 4: return [0, 1, 3, 4]
        case 5: return [0, 1, 2, 4, 5]
        default: return [0, 1, 2, 3, 4, 5]
        }
    }

    /// Nombre d'exercices de musculation qui tiennent dans la seance : par exercice,
    /// ~40 s d'effort par serie + le repos, + 1 min d'installation ; 5 min
    /// d'echauffement, et 15 min de cardio pour les objectifs qui en ont.
    static func exerciseCount(minutes: Int, goal: FitbotGoal) -> Int {
        let perExercise = Double(goal.sets * (40 + goal.restSeconds)) / 60 + 1
        let available = Double(minutes - 5 - (goal.addsCardio ? 15 : 0))
        return min(8, max(2, Int(available / perExercise)))
    }

    static func generate(goal: FitbotGoal, daysPerWeek: Int, sessionMinutes: Int,
                         equipment: Set<FitbotEquipment>, excluded: Set<String> = []) -> Week {
        let n = min(allowedDays.upperBound, max(allowedDays.lowerBound, daysPerWeek))
        let split = FitbotSplit.forDays(n)
        let count = exerciseCount(minutes: sessionMinutes, goal: goal)
        var uncovered = Set<String>()
        let plans = sessions(split: split, days: n).map { s -> (String, String) in
            var used = Set<String>()
            var items: [String] = []
            for g in s.groups where items.count < count {
                let pool = GymExercises.choices(group: g, equipment: equipment, excluded: excluded)
                    .filter { !used.contains($0) }
                guard !pool.isEmpty else {
                    if GymExercises.choices(group: g, equipment: equipment, excluded: excluded).isEmpty { uncovered.insert(g) }
                    continue
                }
                // La variante B decale le choix : deux seances du meme type ne font
                // pas les memes exercices quand le catalogue le permet.
                let pick = pool[(s.variant * 2) % pool.count]
                used.insert(pick)
                items.append("\(pick) \(goal.target)")
            }
            if goal.addsCardio,
               let cardio = GymExercises.choices(group: "Cardio", equipment: equipment, excluded: excluded).first {
                items.append(cardio)
            }
            return (s.title, items.joined(separator: " · "))
        }
        let positions = trainingPositions(days: n)
        let days = gymWeekOrder.enumerated().map { i, wd -> GymDaySnapshot in
            if let p = positions.firstIndex(of: i), plans.indices.contains(p) {
                return GymDaySnapshot(weekday: wd, title: plans[p].0, focus: plans[p].1, isRest: false)
            }
            return GymDaySnapshot(weekday: wd, title: "Repos", focus: "", isRest: true)
        }
        return Week(goal: goal, split: split, daysPerWeek: n, sessionMinutes: sessionMinutes,
                    equipment: equipment, days: days, uncoveredGroups: uncovered.sorted())
    }
}

// MARK: - Historique par semaine de programme

enum FitbotHistory {
    struct WeekRow: Equatable {
        let index: Int        // semaine 1, 2, 3…
        let start: Date       // lundi
        let done: Int
        let planned: Int
    }

    /// Semaines d'un programme, de son lundi de depart a `end` (programme suivant) ou
    /// a maintenant. Une seance compte dans la semaine ou elle a commence, et seulement
    /// si elle est apres le debut du programme et avant le suivant.
    static func weeks(planStart: Date, planEnd: Date?, planned: Int, doneSessionStarts: [Date],
                      now: Date = .now, calendar: Calendar = mondayCalendar) -> [WeekRow] {
        let last = min(planEnd ?? now, now)
        guard last >= planStart,
              let first = calendar.dateInterval(of: .weekOfYear, for: planStart)?.start else { return [] }
        var rows: [WeekRow] = []
        var weekStart = first
        var i = 1
        while weekStart <= last, i <= 520 {
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            let done = doneSessionStarts.filter { $0 >= weekStart && $0 < next && $0 >= planStart && (planEnd == nil || $0 < planEnd!) }.count
            rows.append(WeekRow(index: i, start: weekStart, done: done, planned: planned))
            weekStart = next; i += 1
        }
        return rows
    }

    static var mondayCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        return c
    }
}
