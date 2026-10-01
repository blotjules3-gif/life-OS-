import Foundation
import SwiftData

// MARK: - Modeles du journal alimentaire (Yumzio)
//
// FoodEntry (Models_Health.swift) ne porte que les totaux de la portion mangee.
// Tout ce qui sert a REJOURNALISER vite (favoris, aliments perso, repas
// enregistres) et les micronutriments vivent ici, a cote, sans toucher FoodEntry.

/// Ligne prete a rejournaliser en un geste: valeurs de la portion deja choisie.
@Model final class FavoriteFood {
    var name: String = ""
    var calories: Int = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    /// nil = inconnu (la base ne le donne pas). Jamais remplace par 0.
    var fiber: Double?
    var sugars: Double?
    var salt: Double?
    var createdAt: Date = Date()

    init(name: String, calories: Int, protein: Double, carbs: Double, fat: Double,
         micros: FoodMicroValues = .unknown) {
        self.name = name; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat
        self.fiber = micros.fiber; self.sugars = micros.sugars; self.salt = micros.salt
        self.createdAt = Date()
    }

    var micros: FoodMicroValues { .init(fiber: fiber, sugars: sugars, salt: salt) }
}

/// Aliment cree par l'utilisateur (plat maison, produit absent de la base).
/// Valeurs pour 100 g, plus une portion habituelle pour l'ajouter en un geste.
@Model final class CustomFood {
    var name: String = ""
    var kcalPer100: Double = 0
    var proteinPer100: Double = 0
    var carbsPer100: Double = 0
    var fatPer100: Double = 0
    var fiberPer100: Double?
    var sugarsPer100: Double?
    var saltPer100: Double?
    var portionGrams: Double = 100
    /// "1 bol", "1 part"... vide = la portion s'affiche en grammes.
    var portionLabel: String = ""
    var createdAt: Date = Date()

    init(name: String, kcalPer100: Double, proteinPer100: Double, carbsPer100: Double, fatPer100: Double,
         microsPer100: FoodMicroValues = .unknown, portionGrams: Double = 100, portionLabel: String = "") {
        self.name = name; self.kcalPer100 = kcalPer100
        self.proteinPer100 = proteinPer100; self.carbsPer100 = carbsPer100; self.fatPer100 = fatPer100
        self.fiberPer100 = microsPer100.fiber; self.sugarsPer100 = microsPer100.sugars; self.saltPer100 = microsPer100.salt
        self.portionGrams = portionGrams; self.portionLabel = portionLabel
        self.createdAt = Date()
    }

    var per100: Per100Food {
        Per100Food(name: name, brand: portionLabel.isEmpty ? "Mon aliment" : "Mon aliment · \(portionLabel)",
                   kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100,
                   micros: .init(fiber: fiberPer100, sugars: sugarsPer100, salt: saltPer100),
                   defaultGrams: portionGrams)
    }
}

/// Repas enregistre ("mon petit-dej habituel"): plusieurs lignes ajoutees d'un coup.
/// Les lignes sont en JSON: un tableau de structures n'a pas besoin d'un modele a lui.
@Model final class SavedMeal {
    var name: String = ""
    var itemsData: Data = Data()
    var createdAt: Date = Date()

    init(name: String, items: [SavedMealItem]) {
        self.name = name
        self.itemsData = (try? JSONEncoder().encode(items)) ?? Data()
        self.createdAt = Date()
    }

    var items: [SavedMealItem] {
        get { (try? JSONDecoder().decode([SavedMealItem].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var calories: Int { items.reduce(0) { $0 + $1.calories } }
}

struct SavedMealItem: Codable, Equatable, Hashable {
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugars: Double?
    var salt: Double?
}

/// Micronutriments d'une ligne du journal (FoodEntry n'a pas ces champs).
/// Retrouves par une cle nom + instant exact: l'editeur la recalcule quand il
/// change le nom ou la date, sinon la ligne perdrait ses valeurs.
@Model final class FoodMicros {
    var entryKey: String = ""
    var fiber: Double?
    var sugars: Double?
    var salt: Double?

    init(entryKey: String, values: FoodMicroValues) {
        self.entryKey = entryKey
        self.fiber = values.fiber; self.sugars = values.sugars; self.salt = values.salt
    }
    var values: FoodMicroValues { .init(fiber: fiber, sugars: sugars, salt: salt) }
}

// MARK: - Valeurs pures

/// Fibres, sucres, sel en grammes. nil = inconnu, 0 = vrai zero.
struct FoodMicroValues: Equatable, Hashable {
    var fiber: Double?
    var sugars: Double?
    var salt: Double?
    static let unknown = FoodMicroValues(fiber: nil, sugars: nil, salt: nil)
    var isAllUnknown: Bool { fiber == nil && sugars == nil && salt == nil }

    /// Mise a l'echelle d'une portion: un inconnu reste inconnu.
    func scaled(_ factor: Double) -> FoodMicroValues {
        .init(fiber: fiber.map { $0 * factor }, sugars: sugars.map { $0 * factor }, salt: salt.map { $0 * factor })
    }
}

/// Un aliment decrit pour 100 g (produit de la base ou aliment perso).
struct Per100Food: Equatable, Hashable {
    var name: String
    var brand: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var micros: FoodMicroValues
    var defaultGrams: Double = 100
    var nutriscore: String? = nil
}

/// Une ligne a ecrire: le brouillon du service + ses micronutriments.
struct JournalLine: Equatable {
    var draft: FoodLogService.Draft
    var micros: FoodMicroValues = .unknown
}

// MARK: - Regles du journal (pures, testees dans Lot6FoodLogTests)

@MainActor
enum FoodJournal {

    struct Totals: Equatable {
        var kcal = 0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
    }

    /// Totaux d'UN jour. Le widget et le coach lisent toujours aujourd'hui:
    /// avant, regarder un jour passe ecrasait les chiffres du jour avec ceux-la.
    static func totals(_ entries: [FoodEntry], day: Date, calendar: Calendar = .current) -> Totals {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(into: Totals()) {
            $0.kcal += $1.calories; $0.protein += $1.protein; $0.carbs += $1.carbs; $0.fat += $1.fat
        }
    }

    // MARK: Navigation par jour

    /// Les 7 jours de la bande: finit 3 jours apres le jour choisi, jamais apres aujourd'hui.
    static func stripDays(selected: Date, today: Date = .now, calendar: Calendar = .current) -> [Date] {
        let t = calendar.startOfDay(for: today)
        let s = calendar.startOfDay(for: selected)
        let end = min(t, calendar.date(byAdding: .day, value: 3, to: s) ?? s)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
    }

    /// Jour suivant ou precedent, borne a aujourd'hui (pas de repas dans le futur).
    static func shift(_ day: Date, by days: Int, today: Date = .now, calendar: Calendar = .current) -> Date {
        let target = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: day)) ?? day
        return min(target, calendar.startOfDay(for: today))
    }

    static func dayTitle(_ day: Date, today: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return "Aujourd'hui" }
        if let y = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: y) { return "Hier" }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.calendar = calendar
        f.timeZone = calendar.timeZone; f.dateFormat = "EEEE d MMMM"
        return f.string(from: day).capitalized(with: Locale(identifier: "fr_FR"))
    }

    // MARK: Recents

    struct Recent: Equatable, Identifiable {
        var id: String { name.lowercased() }
        var name: String
        var calories: Int
        var protein: Double
        var carbs: Double
        var fat: Double
        var lastDate: Date
        var microsKey: String
    }

    /// Aliments deja journalises, un par nom (le dernier enregistrement gagne),
    /// du plus recent au plus ancien. Rejournaliser reprend la portion mangee.
    static func recents(_ entries: [FoodEntry], limit: Int = 25) -> [Recent] {
        var seen = Set<String>()
        var out: [Recent] = []
        for e in entries.sorted(by: { $0.date > $1.date }) {
            let k = e.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !k.isEmpty, seen.insert(k).inserted else { continue }
            out.append(Recent(name: e.name, calories: e.calories, protein: e.protein, carbs: e.carbs,
                              fat: e.fat, lastDate: e.date, microsKey: microsKey(e)))
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Copier un repas ou une journee

    /// Recopie des lignes vers un autre jour, a la meme heure, meme repas.
    /// `meal` limite la copie a un repas (ex. le dejeuner d'hier).
    static func copyLines(from entries: [FoodEntry], micros: [String: FoodMicroValues] = [:],
                          sourceDay: Date, toDay: Date, meal: String? = nil,
                          calendar: Calendar = .current) -> [JournalLine] {
        entries
            .filter { calendar.isDate($0.date, inSameDayAs: sourceDay) && (meal == nil || $0.meal == meal) }
            .sorted { $0.date < $1.date }
            .map { e in
                let t = calendar.dateComponents([.hour, .minute, .second], from: e.date)
                let d = calendar.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: t.second ?? 0,
                                      of: toDay) ?? toDay
                return JournalLine(draft: .init(name: e.name, calories: e.calories, protein: e.protein,
                                                carbs: e.carbs, fat: e.fat, meal: e.meal, date: d),
                                   micros: micros[microsKey(e)] ?? .unknown)
            }
    }

    /// Lignes d'un repas enregistre, posees sur le jour et le repas choisis.
    static func lines(from meal: [SavedMealItem], day: Date, mealName: String, now: Date = .now,
                      calendar: Calendar = .current) -> [JournalLine] {
        let at = FoodLogService.mealDate(day: day, now: now, calendar: calendar)
        return meal.map {
            JournalLine(draft: .init(name: $0.name, calories: $0.calories, protein: $0.protein, carbs: $0.carbs,
                                     fat: $0.fat, meal: mealName, date: at),
                        micros: .init(fiber: $0.fiber, sugars: $0.sugars, salt: $0.salt))
        }
    }

    static func savedItems(from entries: [FoodEntry], micros: [String: FoodMicroValues]) -> [SavedMealItem] {
        entries.sorted { $0.date < $1.date }.map { e in
            let m = micros[microsKey(e)] ?? .unknown
            return SavedMealItem(name: e.name, calories: e.calories, protein: e.protein, carbs: e.carbs,
                                 fat: e.fat, fiber: m.fiber, sugars: m.sugars, salt: m.salt)
        }
    }

    // MARK: Portions

    /// Une portion en grammes d'un aliment decrit pour 100 g.
    static func line(_ food: Per100Food, grams: Double, meal: String, date: Date) -> JournalLine {
        let f = max(0, grams) / 100
        return JournalLine(draft: .init(name: food.name, calories: Int((food.kcal * f).rounded()),
                                        protein: food.protein * f, carbs: food.carbs * f, fat: food.fat * f,
                                        meal: meal, date: date),
                           micros: food.micros.scaled(f))
    }

    /// "12,5" ou "12.5" -> 12.5 ; vide -> nil (inconnu) ; texte -> .invalid.
    enum Parsed: Equatable { case value(Double), empty, invalid }
    static func parse(_ s: String) -> Parsed {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return .empty }
        guard let v = Double(t), v.isFinite, v >= 0 else { return .invalid }
        return .value(v)
    }

    /// Message d'erreur pour un aliment perso, nil si tout va bien.
    static func validateCustom(name: String, kcal: Double, protein: Double, carbs: Double, fat: Double,
                               portion: Double) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Donne un nom à l'aliment." }
        if kcal > 900 { return "Plus de 900 kcal pour 100 g, c'est impossible : vérifie la valeur." }
        if protein + carbs + fat > 100.5 { return "Protéines, glucides et lipides dépassent 100 g pour 100 g." }
        if portion <= 0 || portion > 5_000 { return "La portion doit être entre 1 et 5 000 g." }
        return nil
    }

    // MARK: Micronutriments

    /// Cle qui relie une ligne du journal a ses micronutriments.
    static func microsKey(name: String, date: Date) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines))|\(date.timeIntervalSinceReferenceDate)"
    }
    static func microsKey(_ e: FoodEntry) -> String { microsKey(name: e.name, date: e.date) }

    static func microsIndex(_ rows: [FoodMicros]) -> [String: FoodMicroValues] {
        var out: [String: FoodMicroValues] = [:]
        for r in rows { out[r.entryKey] = r.values }
        return out
    }

    /// Total d'un micronutriment sur une journee. Les lignes sans valeur ne
    /// comptent pas pour 0: on dit combien sont inconnues.
    struct MicroTotal: Equatable {
        var known: Double
        var knownCount: Int
        var unknownCount: Int
        var label: String {
            if knownCount == 0 { return "inconnu" }
            let v = known < 10 ? String(format: "%.1f g", known) : "\(Int(known.rounded())) g"
            return unknownCount == 0 ? v : "≥ \(v)"
        }
    }

    /// "inconnu" quand la base ne donne pas la valeur, jamais "0 g".
    static func microText(_ v: Double?) -> String {
        guard let v else { return "inconnu" }
        return v < 10 ? String(format: "%.1f g", v) : "\(Int(v.rounded())) g"
    }

    static func gramsText(_ g: Double) -> String {
        g.rounded() == g ? "\(Int(g))" : String(format: "%.1f", g)
    }

    static func microTotal(_ values: [Double?]) -> MicroTotal {
        let known = values.compactMap { $0 }
        return MicroTotal(known: known.reduce(0, +), knownCount: known.count, unknownCount: values.count - known.count)
    }

    // MARK: Ecriture (toujours via FoodLogService)

    /// Ecrit les lignes (tout ou rien, par FoodLogService), puis leurs
    /// micronutriments connus. Si ces derniers ne s'enregistrent pas, le repas
    /// reste: c'est lui qui compte, les micros sont un plus.
    @discardableResult
    static func log(_ lines: [JournalLine], in ctx: ModelContext,
                    saver: FoodLogService.Saver? = nil) throws -> [FoodEntry] {
        let saver = saver ?? FoodLogService.defaultSaver
        let entries = try FoodLogService.log(lines.map(\.draft), in: ctx, saver: saver)
        var added: [FoodMicros] = []
        for (e, l) in zip(entries, lines) where !l.micros.isAllUnknown {
            let m = FoodMicros(entryKey: microsKey(e), values: l.micros)
            ctx.insert(m); added.append(m)
        }
        if !added.isEmpty {
            do { try saver(ctx) } catch {
                added.forEach { ctx.delete($0) }
                AppLog.data.error("micronutriments non enregistres: \(error.localizedDescription, privacy: .public)")
            }
        }
        return entries
    }

    /// Apres modification d'une ligne: deplace ses micros sur la nouvelle cle
    /// et applique les valeurs saisies (tout inconnu = la fiche disparait).
    static func updateMicros(oldKey: String, newKey: String, values: FoodMicroValues,
                             in ctx: ModelContext) throws {
        let rows = (try? ctx.fetch(FetchDescriptor<FoodMicros>(predicate: #Predicate { $0.entryKey == oldKey }))) ?? []
        if values.isAllUnknown {
            rows.forEach { ctx.delete($0) }
        } else if let first = rows.first {
            first.entryKey = newKey; first.fiber = values.fiber; first.sugars = values.sugars; first.salt = values.salt
            rows.dropFirst().forEach { ctx.delete($0) }
        } else {
            ctx.insert(FoodMicros(entryKey: newKey, values: values))
        }
        try ctx.save()
    }

    /// Fiches de micros dont la ligne n'existe plus (supprimee ailleurs).
    static func orphanKeys(micros: [FoodMicros], entries: [FoodEntry]) -> Set<String> {
        let live = Set(entries.map(microsKey))
        return Set(micros.map(\.entryKey)).subtracting(live)
    }
}
