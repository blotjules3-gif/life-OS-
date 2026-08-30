import Foundation
import SwiftData

/// Génère des suggestions de rappels pertinentes basées sur les données
/// réelles de l'utilisateur : modules actifs, habitudes existantes, profil.
///
/// **Règle** (spéc user) : ne propose jamais de suggestion générique sans
/// avoir analysé les données. Si un module n'est pas activé, on ne suggère
/// rien pour ce domaine.
///
/// Filtre anti-doublon : ne suggère pas un rappel dont le titre est déjà
/// présent dans les rappels existants (case-insensitive).
@MainActor
enum SmartReminderSuggestionEngine {

    /// Template de suggestion prêt à insérer dans un `CustomReminder`.
    struct Suggestion: Identifiable {
        let id: String
        let title: String
        let message: String
        let categoryRaw: String
        let category: AppCategory?
        let frequency: CustomReminder.Frequency
        let intervalHours: Int
        let windowStartHour: Int
        let windowEndHour: Int
        let weekdayMask: Int
        let specificHours: [Int]
        /// Explication courte affichée à l'user pour justifier la suggestion.
        let rationale: String
    }

    /// Retourne les suggestions à afficher, filtrées par modules actifs +
    /// anti-doublons + limite raisonnable.
    static func suggestions(existingReminders: [CustomReminder], maxCount: Int = 6) -> [Suggestion] {
        let activeModules = readActiveModules()
        let existingTitles = Set(existingReminders.map { $0.title.lowercased() })

        var pool: [Suggestion] = []
        pool.append(contentsOf: universalSuggestions())
        pool.append(contentsOf: perModuleSuggestions(activeModules: activeModules))

        // Filtre anti-doublons + dédup par ID
        var seen = Set<String>()
        let filtered = pool.filter { sug in
            guard !existingTitles.contains(sug.title.lowercased()) else { return false }
            return seen.insert(sug.id).inserted
        }

        return Array(filtered.prefix(maxCount))
    }

    // MARK: - Suggestions par module

    private static func perModuleSuggestions(activeModules: Set<AppCategory>) -> [Suggestion] {
        var out: [Suggestion] = []

        if activeModules.contains(.fitness) {
            out.append(Suggestion(
                id: "sug.fitness.stretch",
                title: "Étirements",
                message: "3 min d'étirements pour tes hanches et ton dos.",
                categoryRaw: AppCategory.fitness.rawValue,
                category: .fitness,
                frequency: .everyXHours,
                intervalHours: 4,
                windowStartHour: 9, windowEndHour: 19,
                weekdayMask: WeekdayMask.all,
                specificHours: [],
                rationale: "Module Sport actif — étirements courts entre les séances."
            ))
        }

        if activeModules.contains(.looks) {
            out.append(Suggestion(
                id: "sug.looks.skincare",
                title: "Routine skincare",
                message: "Nettoyage + hydratation avant de dormir.",
                categoryRaw: AppCategory.looks.rawValue,
                category: .looks,
                frequency: .daily,
                intervalHours: 2,
                windowStartHour: 22, windowEndHour: 22,
                weekdayMask: WeekdayMask.all,
                specificHours: [],
                rationale: "Module Looksmaxx actif — rappel routine soir."
            ))
        }

        if activeModules.contains(.mind) || activeModules.contains(.productivity) {
            out.append(Suggestion(
                id: "sug.mind.breathe",
                title: "Respire",
                message: "3 respirations profondes. Relâche les épaules.",
                categoryRaw: AppCategory.mind.rawValue,
                category: .mind,
                frequency: .everyXHours,
                intervalHours: 3,
                windowStartHour: 9, windowEndHour: 18,
                weekdayMask: WeekdayMask.weekdays,
                specificHours: [],
                rationale: "Modules Mental/Productivité actifs — micro-pauses respiration."
            ))
        }

        if activeModules.contains(.productivity) {
            out.append(Suggestion(
                id: "sug.productivity.eyes",
                title: "Repose tes yeux",
                message: "Regarde au loin 20 secondes.",
                categoryRaw: AppCategory.productivity.rawValue,
                category: .productivity,
                frequency: .everyXHours,
                intervalHours: 1,
                windowStartHour: 9, windowEndHour: 18,
                weekdayMask: WeekdayMask.weekdays,
                specificHours: [],
                rationale: "Module Productivité actif — protège tes yeux devant écran."
            ))
            out.append(Suggestion(
                id: "sug.productivity.posture",
                title: "Vérifie ta posture",
                message: "Redresse-toi, épaules basses, écran à hauteur d'yeux.",
                categoryRaw: AppCategory.productivity.rawValue,
                category: .productivity,
                frequency: .everyXHours,
                intervalHours: 2,
                windowStartHour: 9, windowEndHour: 18,
                weekdayMask: WeekdayMask.weekdays,
                specificHours: [],
                rationale: "Module Productivité actif — évite les douleurs dos/nuque."
            ))
        }

        if activeModules.contains(.sleep) {
            // Utilise l'heure de coucher cible du profil si dispo
            let bedH = UserDefaults.standard.integer(forKey: "bedHour")
            let prepH = bedH > 0 ? max(0, bedH - 1) : 22
            out.append(Suggestion(
                id: "sug.sleep.wind_down",
                title: "Préparation au sommeil",
                message: "Baisse les lumières, pose ton téléphone.",
                categoryRaw: AppCategory.sleep.rawValue,
                category: .sleep,
                frequency: .daily,
                intervalHours: 2,
                windowStartHour: prepH, windowEndHour: prepH,
                weekdayMask: WeekdayMask.all,
                specificHours: [],
                rationale: "Module Sommeil actif — 1h avant ton heure de coucher (\(bedH > 0 ? "\(bedH)h" : "cible non renseignée"))."
            ))
        }

        if activeModules.contains(.nutrition) {
            out.append(Suggestion(
                id: "sug.nutrition.water",
                title: "Bois de l'eau",
                message: "Un grand verre d'eau, même si tu n'as pas soif.",
                categoryRaw: AppCategory.nutrition.rawValue,
                category: .nutrition,
                frequency: .everyXHours,
                intervalHours: 2,
                windowStartHour: 8, windowEndHour: 20,
                weekdayMask: WeekdayMask.all,
                specificHours: [],
                rationale: "Module Nutrition actif — hydratation espacée."
            ))
        }

        return out
    }

    // MARK: - Suggestions universelles (fallback si aucun module actif)

    private static func universalSuggestions() -> [Suggestion] {
        [
            Suggestion(
                id: "sug.universal.walk",
                title: "Marche 5 min",
                message: "Sors de ta chaise, marche un peu.",
                categoryRaw: "",
                category: nil,
                frequency: .everyXHours,
                intervalHours: 3,
                windowStartHour: 9, windowEndHour: 18,
                weekdayMask: WeekdayMask.weekdays,
                specificHours: [],
                rationale: "Rappel universel — bouger toutes les 3h."
            ),
        ]
    }

    // MARK: - Data access

    /// Lit les modules actifs depuis UserDefaults (source : `recommendedModules`).
    private static func readActiveModules() -> Set<AppCategory> {
        let raw = UserDefaults.standard.string(forKey: "recommendedModules") ?? ""
        let cats = raw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
        return Set(cats)
    }
}
