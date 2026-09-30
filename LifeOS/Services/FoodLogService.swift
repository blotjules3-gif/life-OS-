import Foundation
import SwiftData

/// Seul chemin d'ecriture du journal alimentaire.
///
/// POURQUOI CE SERVICE EXISTE
///
/// Six ecrans inseraient un `FoodEntry` chacun a leur facon, et tous suivaient le
/// meme schema faux : `ctx.insert(...)`, `try? ctx.save()` ou un `catch` qui ne fait
/// que journaliser, puis "Ajoute au journal" a l'ecran et la saisie effacee. Si
/// l'enregistrement echouait, l'utilisateur voyait un succes, perdait sa saisie, et
/// l'objet non enregistre restait dans le contexte pour partir (ou pas) au prochain
/// save de n'importe quel autre ecran.
///
/// Ici : on valide, on insere, on enregistre, et en cas d'echec on RETIRE ce qu'on a
/// insere puis on relance l'erreur. L'ecran garde la saisie et propose de reessayer.
///
/// Les tableaux de bord n'ont rien a faire : ils lisent tous `FoodEntry` par @Query,
/// donc une ecriture reussie les met a jour, et une ecriture ratee ne laisse rien.
@MainActor
enum FoodLogService {

    /// Ce que l'utilisateur a valide a l'ecran, avant d'etre ecrit.
    struct Draft: Equatable {
        var name: String
        var calories: Int
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var meal: String = "Déjeuner"
        var date: Date = .now
    }

    enum LogError: LocalizedError, Equatable {
        case empty
        case invalid(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Aucun aliment à enregistrer."
            case .invalid(let why):
                return why
            case .saveFailed:
                return "Le repas n'a pas pu être enregistré. Ta saisie est conservée, réessaie."
            }
        }
    }

    /// Point d'injection pour les tests : le vrai `save` du contexte par defaut.
    typealias Saver = (ModelContext) throws -> Void
    static let defaultSaver: Saver = { try $0.save() }

    // MARK: - Ecriture

    /// Ecrit toutes les lignes ou aucune.
    @discardableResult
    static func log(_ drafts: [Draft], in ctx: ModelContext,
                    saver: Saver = defaultSaver) throws -> [FoodEntry] {
        guard !drafts.isEmpty else { throw LogError.empty }
        for d in drafts { try validate(d) }

        let entries = drafts.map {
            FoodEntry(date: $0.date,
                      name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                      calories: $0.calories, protein: $0.protein,
                      carbs: $0.carbs, fat: $0.fat, meal: $0.meal)
        }
        entries.forEach { ctx.insert($0) }
        do {
            try saver(ctx)
        } catch {
            // Sans ce retrait, l'objet reste en attente dans le contexte et le
            // prochain save d'un autre ecran l'ecrirait en douce, en double
            // si l'utilisateur reessaie entre-temps.
            entries.forEach { ctx.delete($0) }
            AppLog.data.error("journal alimentaire: echec d'enregistrement \(error.localizedDescription, privacy: .public)")
            throw LogError.saveFailed(error.localizedDescription)
        }
        return entries
    }

    /// Modifie une ligne existante. En cas d'echec, les anciennes valeurs reviennent.
    static func update(_ entry: FoodEntry, to d: Draft, in ctx: ModelContext,
                       saver: Saver = defaultSaver) throws {
        try validate(d)
        let before = Draft(name: entry.name, calories: entry.calories, protein: entry.protein,
                           carbs: entry.carbs, fat: entry.fat, meal: entry.meal, date: entry.date)
        apply(d, to: entry)
        do {
            try saver(ctx)
        } catch {
            apply(before, to: entry)
            throw LogError.saveFailed(error.localizedDescription)
        }
    }

    /// Supprime une ligne. En cas d'echec, elle est remise en place.
    static func delete(_ entry: FoodEntry, in ctx: ModelContext,
                       saver: Saver = defaultSaver) throws {
        ctx.delete(entry)
        do {
            try saver(ctx)
        } catch {
            ctx.insert(entry)
            throw LogError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Regles

    static func validate(_ d: Draft) throws {
        if d.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LogError.invalid("Donne un nom à l'aliment.")
        }
        if d.calories < 0 || d.calories > 20_000 {
            throw LogError.invalid("Les calories doivent être entre 0 et 20 000.")
        }
        for (label, v) in [("protéines", d.protein), ("glucides", d.carbs), ("lipides", d.fat)] {
            if !v.isFinite || v < 0 || v > 2_000 {
                throw LogError.invalid("Valeur de \(label) invalide.")
            }
        }
    }

    private static func apply(_ d: Draft, to e: FoodEntry) {
        e.name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        e.calories = d.calories; e.protein = d.protein; e.carbs = d.carbs
        e.fat = d.fat; e.meal = d.meal; e.date = d.date
    }

    // MARK: - Date du repas

    /// Place un repas saisi pour un autre jour a l'heure courante de ce jour.
    /// Sans ca, un repas d'hier choisi dans un DatePicker "date seule" tombait a
    /// minuit, donc dans le mauvais jour pour tout fuseau a l'ouest de l'UTC
    /// selon comment la date avait ete construite.
    static func mealDate(day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0,
                             second: t.second ?? 0, of: day) ?? day
    }
}
