import Foundation

// MARK: - Yuko : adequation aux objectifs personnels
//
// Deux questions DIFFERENTES, jamais melangees (audit du 29 sept apres le build 42):
// - la note LifeOS sur 100 dit la qualite generale du produit, la meme pour tous;
// - l'adequation dit si CE produit va dans le sens de TES objectifs. Elle ne donne
//   pas de chiffre, seulement un verdict par objectif, avec la valeur qui le fonde.
// Une donnee absente donne "inconnu", jamais "respecte".

enum ProductGoal: String, CaseIterable, Codable, Identifiable {
    case lessSugar, lessSalt, lessSaturatedFat, moreProtein, moreFiber, noSweeteners, lessProcessed
    case fragranceFree, sensitiveSkin, avoidRestricted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lessSugar: return "Moins de sucre"
        case .lessSalt: return "Moins de sel"
        case .lessSaturatedFat: return "Moins de graisses saturées"
        case .moreProtein: return "Plus de protéines"
        case .moreFiber: return "Plus de fibres"
        case .noSweeteners: return "Éviter les édulcorants"
        case .lessProcessed: return "Moins d'ultra-transformé"
        case .fragranceFree: return "Sans parfum"
        case .sensitiveSkin: return "Peau sensible (allergènes)"
        case .avoidRestricted: return "Éviter les ingrédients restreints"
        }
    }

    var icon: String {
        switch self {
        case .lessSugar: return "cube"
        case .lessSalt: return "aqi.low"
        case .lessSaturatedFat: return "drop"
        case .moreProtein: return "figure.strengthtraining.traditional"
        case .moreFiber: return "leaf"
        case .noSweeteners: return "nosign"
        case .lessProcessed: return "gearshape.2"
        case .fragranceFree: return "wind"
        case .sensitiveSkin: return "hand.raised"
        case .avoidRestricted: return "exclamationmark.shield"
        }
    }

    var forCosmetics: Bool { [.fragranceFree, .sensitiveSkin, .avoidRestricted].contains(self) }
}

/// Objectifs choisis par l'utilisateur, dans les UserDefaults (petits, sans
/// donnees de sante precises; la sauvegarde complete emporte les reglages).
enum ProductGoals {
    static let key = "yuko.goals"

    static func load(_ d: UserDefaults = .standard) -> Set<ProductGoal> {
        Set((d.stringArray(forKey: key) ?? []).compactMap(ProductGoal.init(rawValue:)))
    }

    static func save(_ goals: Set<ProductGoal>, _ d: UserDefaults = .standard) {
        d.set(goals.map(\.rawValue).sorted(), forKey: key)
    }
}

enum ProductFit {
    enum Status: String, Equatable { case ok, watch, against, unknown }

    struct Verdict: Equatable, Identifiable {
        var id: String { goal.rawValue }
        let goal: ProductGoal
        let status: Status
        let reason: String
    }

    struct Summary: Equatable {
        let verdicts: [Verdict]
        var ok: Int { verdicts.filter { $0.status == .ok }.count }
        var watch: Int { verdicts.filter { $0.status == .watch }.count }
        var against: Int { verdicts.filter { $0.status == .against }.count }
        var unknown: Int { verdicts.filter { $0.status == .unknown }.count }
        var line: String {
            var parts: [String] = []
            if ok > 0 { parts.append("\(ok) respecté\(ok > 1 ? "s" : "")") }
            if watch > 0 { parts.append("\(watch) à surveiller") }
            if against > 0 { parts.append("\(against) contraire\(against > 1 ? "s" : "")") }
            if unknown > 0 { parts.append("\(unknown) non vérifiable\(unknown > 1 ? "s" : "")") }
            return parts.joined(separator: " · ")
        }
    }

    /// Seuils "faible / eleve" des feux tricolores de la FSA (Royaume-Uni), pour 100 g
    /// ou, pour une boisson, pour 100 ml. Ce sont des reperes publics, pas une norme
    /// medicale personnalisee.
    struct Thresholds { let low: Double; let high: Double }
    static func thresholds(_ nutrient: ProductGoal, beverage: Bool) -> Thresholds? {
        switch (nutrient, beverage) {
        case (.lessSugar, false): return .init(low: 5, high: 22.5)
        case (.lessSugar, true): return .init(low: 2.5, high: 11.25)
        case (.lessSaturatedFat, false): return .init(low: 1.5, high: 5)
        case (.lessSaturatedFat, true): return .init(low: 0.75, high: 2.5)
        case (.lessSalt, false): return .init(low: 0.3, high: 1.5)
        case (.lessSalt, true): return .init(low: 0.3, high: 0.75)
        default: return nil
        }
    }

    /// Seuils affiches tels quels (22,5 et 11,25 ne s'arrondissent pas).
    static func exact(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_FR")))
    }

    static let sweeteners: Set<String> = ["e950", "e951", "e952", "e954", "e955", "e957", "e959", "e960", "e961", "e962", "e965", "e966", "e967", "e968", "e969"]

    /// Verdicts pour les objectifs qui s'appliquent a ce type de produit.
    static func evaluate(_ p: CatalogProduct, goals: Set<ProductGoal>) -> Summary {
        // Tes objectifs sont les tiens: ils ne s'appliquent pas a la gamelle du chat.
        guard p.source != .pet && p.source != .product else { return Summary(verdicts: []) }
        let applicable = ProductGoal.allCases.filter { goals.contains($0) && $0.forCosmetics == p.isCosmetic }
        return Summary(verdicts: applicable.map { verdict($0, p) })
    }

    static func verdict(_ goal: ProductGoal, _ p: CatalogProduct) -> Verdict {
        let unit = p.isBeverage ? "100 ml" : "100 g"
        let n = p.nutriments
        func limit(_ value: Double?, _ label: String) -> Verdict {
            guard let v = value, let t = thresholds(goal, beverage: p.isBeverage) else {
                return .init(goal: goal, status: .unknown, reason: "\(label) : valeur absente de la fiche.")
            }
            let base = "\(label) : \(frNumber(v)) g pour \(unit)"
            if v <= t.low { return .init(goal: goal, status: .ok, reason: "\(base), faible (≤ \(exact(t.low)) g).") }
            if v > t.high { return .init(goal: goal, status: .against, reason: "\(base), élevé (> \(exact(t.high)) g).") }
            return .init(goal: goal, status: .watch, reason: "\(base), moyen (entre \(exact(t.low)) et \(exact(t.high)) g).")
        }
        let flags = p.isCosmetic ? ProductScore.evaluate(p).flags : []
        switch goal {
        case .lessSugar: return limit(n.sugars, "Sucres")
        case .lessSalt: return limit(n.salt, "Sel")
        case .lessSaturatedFat: return limit(n.saturatedFat, "Graisses saturées")
        case .moreProtein:
            guard let v = n.proteins else { return .init(goal: goal, status: .unknown, reason: "Protéines : valeur absente de la fiche.") }
            // Allegation UE "riche en protéines" : au moins 20 % de l'energie.
            if let kcal = n.energyKcal, kcal > 0 {
                let share = v * 4 / kcal
                let base = "Protéines : \(frNumber(v)) g pour \(unit), \(Int((share * 100).rounded())) % de l'énergie"
                if share >= 0.2 { return .init(goal: goal, status: .ok, reason: "\(base) (riche, seuil UE 20 %).") }
                if share >= 0.12 { return .init(goal: goal, status: .watch, reason: "\(base) (source, seuil UE 12 %).") }
                return .init(goal: goal, status: .against, reason: "\(base) (sous le seuil UE de 12 %).")
            }
            return .init(goal: goal, status: .unknown, reason: "Protéines : \(frNumber(v)) g, mais énergie absente : part inconnue.")
        case .moreFiber:
            guard let v = n.fiber else { return .init(goal: goal, status: .unknown, reason: "Fibres : valeur absente de la fiche.") }
            let base = "Fibres : \(frNumber(v)) g pour \(unit)"
            // Allegations UE : "source" 3 g, "riche" 6 g pour 100 g.
            if v >= 6 { return .init(goal: goal, status: .ok, reason: "\(base) (riche, seuil UE 6 g).") }
            if v >= 3 { return .init(goal: goal, status: .watch, reason: "\(base) (source, seuil UE 3 g).") }
            return .init(goal: goal, status: .against, reason: "\(base) (sous le seuil UE de 3 g).")
        case .noSweeteners:
            let found = p.additives.map { CatalogProduct.plain($0).lowercased().replacingOccurrences(of: " ", with: "") }.filter(sweeteners.contains)
            if !found.isEmpty { return .init(goal: goal, status: .against, reason: "Contient : " + found.map { $0.uppercased() }.joined(separator: ", ") + ".") }
            if p.ingredientsText == nil { return .init(goal: goal, status: .unknown, reason: "Liste des ingrédients absente : impossible de vérifier.") }
            return .init(goal: goal, status: .ok, reason: "Aucun édulcorant dans les additifs déclarés.")
        case .lessProcessed:
            guard let nova = p.novaGroup else { return .init(goal: goal, status: .unknown, reason: "Groupe NOVA absent de la fiche.") }
            switch nova {
            case 4: return .init(goal: goal, status: .against, reason: "NOVA 4 : ultra-transformé.")
            case 3: return .init(goal: goal, status: .watch, reason: "NOVA 3 : transformé.")
            default: return .init(goal: goal, status: .ok, reason: "NOVA \(nova) : peu ou pas transformé.")
            }
        case .fragranceFree:
            if p.ingredientsText == nil { return .init(goal: goal, status: .unknown, reason: "Liste des ingrédients absente.") }
            return flags.contains { $0.code == "parfum" }
                ? .init(goal: goal, status: .against, reason: "Contient du parfum.")
                : .init(goal: goal, status: .ok, reason: "Pas de parfum dans la liste lue.")
        case .sensitiveSkin:
            if p.ingredientsText == nil { return .init(goal: goal, status: .unknown, reason: "Liste des ingrédients absente.") }
            let allergens = flags.filter { $0.level == .sensitivity && $0.code != "parfum" }.map(\.name)
            return allergens.isEmpty
                ? .init(goal: goal, status: .ok, reason: "Aucun des allergènes suivis par LifeOS dans la liste lue.")
                : .init(goal: goal, status: .against, reason: "Allergènes : " + allergens.joined(separator: ", ") + ".")
        case .avoidRestricted:
            if p.ingredientsText == nil { return .init(goal: goal, status: .unknown, reason: "Liste des ingrédients absente.") }
            let restricted = flags.filter { $0.level == .high }.map(\.name)
            return restricted.isEmpty
                ? .init(goal: goal, status: .ok, reason: "Aucun ingrédient restreint de la liste LifeOS trouvé.")
                : .init(goal: goal, status: .against, reason: "Restreint dans l'UE : " + restricted.joined(separator: ", ") + ".")
        }
    }

    /// Pourquoi une alternative est proposee: ecart de note et, pour un aliment,
    /// les ecarts nutritionnels qui comptent (seulement quand les deux valeurs existent).
    static func reasons(alternative a: CatalogProduct, versus p: CatalogProduct) -> [String] {
        var out: [String] = []
        if let va = ProductScore.evaluate(a).value, let vp = ProductScore.evaluate(p).value, va > vp {
            out.append("Note \(va) contre \(vp)")
        }
        if p.isCosmetic {
            let fa = Set(ProductScore.evaluate(a).flags.map(\.code)), fp = Set(ProductScore.evaluate(p).flags.map(\.code))
            let gone = fp.subtracting(fa)
            if !gone.isEmpty { out.append("sans " + gone.sorted().joined(separator: ", ")) }
            return out
        }
        func diff(_ x: Double?, _ y: Double?, _ label: String, lowerIsBetter: Bool, min: Double) {
            guard let x, let y else { return }
            let d = x - y
            guard abs(d) >= min, (d < 0) == lowerIsBetter else { return }
            out.append("\(label) \(d < 0 ? "−" : "+")\(frNumber(abs(d))) g")
        }
        diff(a.nutriments.sugars, p.nutriments.sugars, "sucres", lowerIsBetter: true, min: 1)
        diff(a.nutriments.saturatedFat, p.nutriments.saturatedFat, "graisses saturées", lowerIsBetter: true, min: 0.5)
        diff(a.nutriments.salt, p.nutriments.salt, "sel", lowerIsBetter: true, min: 0.1)
        diff(a.nutriments.fiber, p.nutriments.fiber, "fibres", lowerIsBetter: false, min: 1)
        diff(a.nutriments.proteins, p.nutriments.proteins, "protéines", lowerIsBetter: false, min: 2)
        let addA = a.additives.count, addP = p.additives.count
        if a.ingredientsText != nil, p.ingredientsText != nil, addA < addP { out.append("\(addP - addA) additif\(addP - addA > 1 ? "s" : "") de moins") }
        return out
    }
}

// MARK: - Lecture d'un tableau nutritionnel photographie

/// Extrait les valeurs pour 100 g d'un texte OCR de tableau nutritionnel (FR / EN).
/// Ne remplit que ce qu'il lit clairement; l'utilisateur confirme chaque champ.
/// Sur une ligne, la PREMIERE valeur est prise: sur les etiquettes europeennes la
/// premiere colonne est "pour 100 g", la suivante "par portion".
enum NutritionLabelParser {
    struct Values: Equatable {
        var kcal: Double?; var sugars: Double?; var saturatedFat: Double?
        var salt: Double?; var proteins: Double?; var fiber: Double?
        var isEmpty: Bool { [kcal, sugars, saturatedFat, salt, proteins, fiber].allSatisfy { $0 == nil } }
    }

    static func parse(_ text: String) -> Values {
        var v = Values()
        let lines = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            // Libelle et valeur sont parfois sur deux lignes dans l'OCR.
            let here = line + " " + (i + 1 < lines.count ? lines[i + 1] : "")
            if v.kcal == nil, line.contains("energ") || line.contains("kcal") {
                // "394 kcal" ou "Énergie (kcal) 394".
                v.kcal = number(before: "kcal", in: here) ?? firstNumber(in: here, after: "kcal")
            }
            if v.saturatedFat == nil, line.contains("satur") { v.saturatedFat = firstNumber(in: here, after: "satur") }
            if v.sugars == nil, line.contains("sucre") || line.contains("sugar") {
                v.sugars = firstNumber(in: here, after: line.contains("sucre") ? "sucre" : "sugar")
            }
            if v.proteins == nil, line.contains("protei") { v.proteins = firstNumber(in: here, after: "protei") }
            if v.fiber == nil, line.contains("fibre") || line.contains("fiber") {
                v.fiber = firstNumber(in: here, after: line.contains("fibre") ? "fibre" : "fiber")
            }
            if v.salt == nil, line.range(of: #"\b(sel|salt)\b"#, options: .regularExpression) != nil {
                v.salt = firstNumber(in: here, after: line.contains("sel") ? "sel" : "salt")
            }
        }
        return v
    }

    private static let numberPattern = #"(<\s*)?([0-9]+(?:[.,][0-9]+)?)"#

    private static func firstNumber(in s: String, after label: String) -> Double? {
        guard let r = s.range(of: label) else { return nil }
        let rest = String(s[r.upperBound...])
        guard let m = rest.range(of: numberPattern, options: .regularExpression) else { return nil }
        return Double(rest[m].replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    /// "1 650 kJ / 394 kcal": la valeur juste avant "kcal".
    private static func number(before unit: String, in s: String) -> Double? {
        guard let r = s.range(of: unit) else { return nil }
        let head = String(s[..<r.lowerBound])
        let matches = head.matches(of: /([0-9][0-9 ]*(?:[.,][0-9]+)?)\s*$/)
        guard let m = matches.last else { return nil }
        return Double(String(m.1).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
    }
}
