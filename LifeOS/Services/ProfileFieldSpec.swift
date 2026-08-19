import Foundation

/// Spécification statique d'un champ de profil.
///
/// Ce catalog est la source of truth des données que le coach peut demander/extraire.
/// Il n'est PAS stocké en DB — c'est du code. Quand le coach a besoin de savoir
/// "quels champs manquent pour l'objectif prise de muscle", il interroge ce catalog.
struct ProfileFieldSpec: Identifiable, Hashable {

    enum ValueType: String {
        case int, double, string, bool, `enum`, array
    }

    enum Importance: Int, Comparable {
        case low = 1
        case medium = 2
        case high = 5
        case critical = 10

        static func < (lhs: Importance, rhs: Importance) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var weight: Double { Double(rawValue) }
    }

    /// Sous-objectifs supportés. `nil` = champ pertinent quel que soit le sous-objectif.
    enum SubGoal: String, Hashable {
        case muscleGain, weightLoss, performance, endurance, generalHealth
        case sleepQuality, stressReduction, focus, energyBoost
        case moneyGrowth, budgetControl, careerChange
        case none
    }

    let id: String
    let category: String  // AppCategory.rawValue
    /// Sous-objectifs pour lesquels ce champ est particulièrement pertinent.
    /// Vide = pertinent partout, pas de boost/malus goal-relevance.
    let subGoals: [SubGoal]
    let displayName: String
    let valueType: ValueType
    let importance: Importance
    /// Field ids qui doivent avoir une valeur pour que ce field soit demandable.
    /// Ex: `body.currentWeightKg` doit exister avant `body.targetWeightKg`.
    let dependsOn: [String]
    /// Keywords qui augmentent la probabilité d'extraction depuis un message user.
    let extractionHints: [String]
    let unit: String?
    let range: ClosedRange<Double>?

    // Convenience default init pour les champs simples
    init(
        id: String,
        category: String,
        subGoals: [SubGoal] = [],
        displayName: String,
        valueType: ValueType,
        importance: Importance,
        dependsOn: [String] = [],
        extractionHints: [String] = [],
        unit: String? = nil,
        range: ClosedRange<Double>? = nil
    ) {
        self.id = id
        self.category = category
        self.subGoals = subGoals
        self.displayName = displayName
        self.valueType = valueType
        self.importance = importance
        self.dependsOn = dependsOn
        self.extractionHints = extractionHints
        self.unit = unit
        self.range = range
    }
}

// MARK: - Catalog

enum ProfileFieldCatalog {

    /// Toutes les specs indexées par id.
    static let all: [String: ProfileFieldSpec] = Dictionary(
        uniqueKeysWithValues: allSpecs.map { ($0.id, $0) }
    )

    /// Retourne les specs d'une catégorie.
    static func specs(for category: String) -> [ProfileFieldSpec] {
        allSpecs.filter { $0.category == category }
    }

    /// Retourne les specs pertinentes pour un sous-objectif (soit explicites,
    /// soit universelles).
    static func specs(for subGoal: ProfileFieldSpec.SubGoal) -> [ProfileFieldSpec] {
        allSpecs.filter { $0.subGoals.isEmpty || $0.subGoals.contains(subGoal) }
    }

    /// Catalog complet — ~80 specs couvrant les 17 catégories LifeOS.
    /// Nommage : `<category>.<field>` en camelCase.
    static let allSpecs: [ProfileFieldSpec] = [
        // MARK: Body (identité physique — utilisé transversalement)
        .init(id: "body.currentWeightKg", category: "fitness",
              subGoals: [.muscleGain, .weightLoss],
              displayName: "Poids actuel", valueType: .double, importance: .critical,
              extractionHints: ["poids", "kg", "kilos", "je pèse", "je fais"],
              unit: "kg", range: 30...250),
        .init(id: "body.targetWeightKg", category: "fitness",
              subGoals: [.muscleGain, .weightLoss],
              displayName: "Poids cible", valueType: .double, importance: .high,
              dependsOn: ["body.currentWeightKg"],
              extractionHints: ["objectif poids", "atteindre", "vouloir peser"],
              unit: "kg", range: 30...250),
        .init(id: "body.heightCm", category: "fitness",
              displayName: "Taille", valueType: .double, importance: .high,
              extractionHints: ["taille", "cm", "mètre", "mesure"],
              unit: "cm", range: 100...230),
        .init(id: "body.ageYears", category: "fitness",
              displayName: "Âge", valueType: .int, importance: .high,
              extractionHints: ["ans", "âge", "j'ai"],
              unit: "ans", range: 10...120),
        .init(id: "body.gender", category: "fitness",
              displayName: "Genre", valueType: .enum, importance: .high,
              extractionHints: ["homme", "femme", "non-binaire"]),
        .init(id: "body.hasCycle", category: "cycle",
              displayName: "Cycle menstruel actif", valueType: .bool, importance: .medium,
              dependsOn: ["body.gender"]),
        .init(id: "body.activityLevel", category: "fitness",
              displayName: "Niveau d'activité quotidien", valueType: .enum, importance: .high,
              extractionHints: ["sédentaire", "actif", "assis", "debout"]),

        // MARK: Goals (méta-objectifs)
        .init(id: "goals.primary", category: "productivity",
              displayName: "Objectif principal", valueType: .enum, importance: .critical,
              extractionHints: ["je veux", "mon objectif", "je vise", "j'aimerais"]),
        .init(id: "goals.horizon", category: "productivity",
              subGoals: [.muscleGain, .weightLoss, .performance],
              displayName: "Horizon de l'objectif", valueType: .string, importance: .medium,
              dependsOn: ["goals.primary"],
              extractionHints: ["dans X mois", "avant", "d'ici", "cette année"]),

        // MARK: Fitness
        .init(id: "fitness.gymFrequency", category: "fitness",
              subGoals: [.muscleGain, .performance],
              displayName: "Fréquence entraînement par semaine", valueType: .int, importance: .critical,
              extractionHints: ["salle", "gym", "fois par semaine", "séances", "entraîne"],
              unit: "/sem", range: 0...14),
        .init(id: "fitness.gymType", category: "fitness",
              subGoals: [.muscleGain, .performance],
              displayName: "Type d'entraînement principal", valueType: .enum, importance: .high,
              extractionHints: ["muscu", "cardio", "hiit", "crossfit", "yoga", "course"]),
        .init(id: "fitness.location", category: "fitness",
              displayName: "Où tu t'entraînes", valueType: .enum, importance: .medium,
              extractionHints: ["salle", "maison", "chez moi", "dehors", "parc"]),
        .init(id: "fitness.bench1RM", category: "fitness",
              subGoals: [.muscleGain, .performance],
              displayName: "Développé couché 1RM", valueType: .double, importance: .medium,
              extractionHints: ["bench", "développé couché", "dc"],
              unit: "kg", range: 20...300),
        .init(id: "fitness.squat1RM", category: "fitness",
              subGoals: [.muscleGain, .performance],
              displayName: "Squat 1RM", valueType: .double, importance: .medium,
              extractionHints: ["squat"],
              unit: "kg", range: 20...400),
        .init(id: "fitness.deadlift1RM", category: "fitness",
              subGoals: [.muscleGain, .performance],
              displayName: "Soulevé de terre 1RM", valueType: .double, importance: .medium,
              extractionHints: ["soulevé", "deadlift", "dl", "sdt"],
              unit: "kg", range: 20...500),
        .init(id: "fitness.runningPace", category: "fitness",
              subGoals: [.endurance, .performance],
              displayName: "Allure de course habituelle (min/km)", valueType: .double, importance: .medium,
              extractionHints: ["allure", "min/km", "pace", "vitesse course"],
              unit: "min/km", range: 3...15),
        .init(id: "fitness.weeklyRunKm", category: "fitness",
              subGoals: [.endurance],
              displayName: "Volume course hebdomadaire", valueType: .double, importance: .medium,
              extractionHints: ["km par semaine", "kilomètres par semaine", "volume"],
              unit: "km", range: 0...300),
        .init(id: "fitness.trainingYears", category: "fitness",
              displayName: "Années d'entraînement", valueType: .int, importance: .medium,
              extractionHints: ["depuis X ans", "je m'entraîne depuis"],
              unit: "ans", range: 0...80),

        // MARK: Nutrition
        .init(id: "nutrition.kcalGoal", category: "nutrition",
              subGoals: [.muscleGain, .weightLoss, .performance],
              displayName: "Objectif calorique quotidien", valueType: .int, importance: .critical,
              extractionHints: ["kcal", "calories"],
              unit: "kcal", range: 800...6000),
        .init(id: "nutrition.proteinGoal", category: "nutrition",
              subGoals: [.muscleGain],
              displayName: "Objectif protéines quotidien", valueType: .int, importance: .high,
              extractionHints: ["protéines", "protein", "grammes de protéines"],
              unit: "g", range: 20...400),
        .init(id: "nutrition.waterGoal", category: "nutrition",
              displayName: "Objectif hydratation", valueType: .int, importance: .high,
              extractionHints: ["eau", "hydrat", "verres d'eau", "litres"],
              unit: "ml", range: 500...6000),
        .init(id: "nutrition.diet", category: "nutrition",
              displayName: "Régime alimentaire", valueType: .enum, importance: .high,
              extractionHints: ["végétarien", "vegan", "flexitarien", "carnivore", "keto"]),
        .init(id: "nutrition.mealsPerDay", category: "nutrition",
              subGoals: [.muscleGain, .weightLoss],
              displayName: "Nombre de repas quotidiens", valueType: .int, importance: .medium,
              extractionHints: ["repas par jour", "repas jour"],
              unit: "/jour", range: 1...8),
        .init(id: "nutrition.breakfastAppetite", category: "nutrition",
              subGoals: [.muscleGain],
              displayName: "Appétit au réveil", valueType: .enum, importance: .medium,
              extractionHints: ["matin", "petit-déj", "faim le matin", "appétit matin"]),
        .init(id: "nutrition.allergies", category: "nutrition",
              displayName: "Allergies alimentaires", valueType: .array, importance: .high,
              extractionHints: ["allergique", "allergie", "je ne tolère pas"]),
        .init(id: "nutrition.dislikes", category: "nutrition",
              displayName: "Aliments non appréciés", valueType: .array, importance: .low,
              extractionHints: ["j'aime pas", "je déteste", "je ne mange pas"]),

        // MARK: Sleep
        .init(id: "sleep.targetHours", category: "sleep",
              displayName: "Durée de sommeil cible", valueType: .double, importance: .high,
              extractionHints: ["heures de sommeil", "dormir", "sommeil"],
              unit: "h", range: 3...12),
        .init(id: "sleep.bedtimeHour", category: "sleep",
              displayName: "Heure de coucher habituelle", valueType: .int, importance: .high,
              extractionHints: ["coucher", "je me couche", "au lit"],
              unit: "h", range: 18...30),
        .init(id: "sleep.wakeupHour", category: "sleep",
              displayName: "Heure de réveil habituelle", valueType: .int, importance: .high,
              extractionHints: ["réveil", "je me lève", "matin"],
              unit: "h", range: 3...12),
        .init(id: "sleep.issues", category: "sleep",
              subGoals: [.sleepQuality],
              displayName: "Problèmes de sommeil", valueType: .array, importance: .medium,
              extractionHints: ["insomnie", "réveil nocturne", "difficulté à dormir"]),

        // MARK: Mind
        .init(id: "mind.stressLevel", category: "mind",
              subGoals: [.stressReduction],
              displayName: "Niveau de stress actuel", valueType: .enum, importance: .high,
              extractionHints: ["stress", "anxiété", "tendu", "angoissé"]),
        .init(id: "mind.meditationMinutes", category: "mind",
              subGoals: [.stressReduction, .focus],
              displayName: "Méditation quotidienne", valueType: .int, importance: .medium,
              extractionHints: ["médite", "méditation", "pleine conscience"],
              unit: "min/jour", range: 0...180),

        // MARK: Productivity
        .init(id: "productivity.focusMinutes", category: "productivity",
              subGoals: [.focus],
              displayName: "Minutes focus par jour", valueType: .int, importance: .high,
              extractionHints: ["focus", "concentré", "deep work"],
              unit: "min", range: 0...600),
        .init(id: "productivity.method", category: "productivity",
              displayName: "Méthode de productivité préférée", valueType: .enum, importance: .low,
              extractionHints: ["pomodoro", "time blocking", "gtd", "eisenhower"]),

        // MARK: Finance
        .init(id: "finance.monthlyIncome", category: "finance",
              subGoals: [.moneyGrowth, .budgetControl],
              displayName: "Revenu mensuel net", valueType: .double, importance: .critical,
              extractionHints: ["salaire", "revenu", "je gagne"],
              unit: "€", range: 0...100000),
        .init(id: "finance.monthlyBudget", category: "finance",
              subGoals: [.budgetControl],
              displayName: "Budget mensuel dépenses", valueType: .double, importance: .high,
              extractionHints: ["budget", "dépenses"],
              unit: "€", range: 0...50000),
        .init(id: "finance.emergencyFundMonths", category: "finance",
              subGoals: [.moneyGrowth],
              displayName: "Fonds d'urgence (mois de dépenses)", valueType: .double, importance: .high,
              extractionHints: ["fonds d'urgence", "épargne", "coussin"],
              unit: "mois", range: 0...36),

        // MARK: Invest
        .init(id: "invest.riskProfile", category: "invest",
              subGoals: [.moneyGrowth],
              displayName: "Profil de risque investisseur", valueType: .enum, importance: .high,
              extractionHints: ["risque", "conservateur", "agressif", "prudent"]),
        .init(id: "invest.experienceLevel", category: "invest",
              displayName: "Niveau d'expérience investissement", valueType: .enum, importance: .medium,
              extractionHints: ["débutant", "intermédiaire", "expert"]),

        // MARK: Career
        .init(id: "career.currentRole", category: "career",
              displayName: "Poste actuel", valueType: .string, importance: .medium,
              extractionHints: ["je bosse", "je travaille comme", "mon métier"]),
        .init(id: "career.goal", category: "career",
              subGoals: [.careerChange],
              displayName: "Objectif carrière", valueType: .enum, importance: .high,
              extractionHints: ["reconversion", "promotion", "changer de job"]),

        // MARK: Learning
        .init(id: "learning.dailyMinutes", category: "learning",
              displayName: "Minutes apprentissage par jour", valueType: .int, importance: .medium,
              extractionHints: ["apprendre", "étudier"],
              unit: "min", range: 0...600),
        .init(id: "learning.domain", category: "learning",
              displayName: "Domaine d'apprentissage principal", valueType: .string, importance: .low,
              extractionHints: ["j'apprends", "j'étudie"]),

        // MARK: Looks
        .init(id: "looks.skinType", category: "looks",
              displayName: "Type de peau", valueType: .enum, importance: .medium,
              extractionHints: ["peau", "grasse", "sèche", "mixte", "sensible"]),
        .init(id: "looks.skincareRoutine", category: "looks",
              displayName: "Routine skincare actuelle", valueType: .enum, importance: .low,
              extractionHints: ["skincare", "soins", "crème"]),

        // MARK: Social
        .init(id: "social.personality", category: "social",
              displayName: "Personnalité sociale", valueType: .enum, importance: .low,
              extractionHints: ["introverti", "extraverti", "timide"]),

        // MARK: Home
        .init(id: "home.type", category: "home",
              displayName: "Type de logement", valueType: .enum, importance: .low,
              extractionHints: ["appart", "maison", "studio", "colocation"]),

        // MARK: Mobility
        .init(id: "mobility.mainVehicle", category: "mobility",
              displayName: "Transport principal", valueType: .enum, importance: .low,
              extractionHints: ["voiture", "vélo", "moto", "transports"]),

        // MARK: Travel
        .init(id: "travel.style", category: "travel",
              displayName: "Style de voyage préféré", valueType: .enum, importance: .low,
              extractionHints: ["voyage", "confort", "aventure", "backpack"]),

        // MARK: Medical
        .init(id: "medical.conditions", category: "medical",
              displayName: "Conditions médicales", valueType: .array, importance: .critical,
              extractionHints: ["diabète", "asthme", "hypertension", "allergie", "cardio"]),
        .init(id: "medical.medications", category: "medical",
              displayName: "Traitements en cours", valueType: .array, importance: .high,
              extractionHints: ["médicament", "traitement", "je prends"]),

        // MARK: Cycle
        .init(id: "cycle.averageLengthDays", category: "cycle",
              displayName: "Longueur moyenne du cycle", valueType: .int, importance: .high,
              dependsOn: ["body.hasCycle"],
              unit: "j", range: 20...45),
    ]
}
