import Foundation

/// Note LifeOS d'un produit, sur 100, par une methode ecrite, versionnee et testee.
///
/// CE N'EST PAS LE SCORE YUKA. Yuka publie une repartition (nutrition 60 %,
/// additifs 30 %, bio 10 %) que LifeOS reprend pour les aliments, mais le calcul
/// de chaque partie est le notre, detaille ci-dessous, et nos donnees viennent
/// d'Open Food Facts / Open Beauty Facts, pas de Yuka.
///
/// Regles communes:
///   - Une donnee absente n'est JAMAIS remplacee par une valeur favorable. Sans les
///     quatre nutriments de base ou sans liste d'ingredients, pas de note sur 100:
///     "non evalue", avec la liste de ce qui manque.
///   - Le Nutri-Score A-E de la base n'entre PAS dans le calcul: on repart des
///     nutriments. Il est affiche a part, sous son vrai nom.
///   - Les preferences de l'utilisateur (regime, allergies) ne changent pas la note:
///     elles s'affichent a part.
enum ProductScore {

    static let version = "LifeOS Qualité 2.0 (29 sept. 2026)"

    struct Component: Equatable, Identifiable {
        var id: String { name }
        let name: String
        /// nil = pas evalue (donnee absente).
        let points: Double?
        let max: Double
        let details: [String]
    }

    enum Level: String, Equatable { case high = "élevé", moderate = "modéré", sensitivity = "sensibilité" }

    struct Flag: Equatable, Identifiable {
        var id: String { code }
        let code: String
        let name: String
        let level: Level
        let reason: String
    }

    struct Confidence: Equatable {
        enum Level: String, Equatable { case high = "élevée", medium = "moyenne", low = "faible" }
        let level: Level
        let reason: String
    }

    enum Outcome: Equatable {
        case scored(Int)
        case notEvaluated(String)
        case notApplicable(String)
    }

    struct Result: Equatable {
        let outcome: Outcome
        let method: String
        let components: [Component]
        let flags: [Flag]
        let missing: [String]

        /// Niveau de confiance de la note (cosmetiques pour l'instant): ce qui a ete
        /// EVALUE, pas seulement reconnu. nil = non renseigne.
        var confidence: Confidence? = nil

        var value: Int? { if case .scored(let v) = outcome { return v } else { return nil } }
        var label: String? { value.map(ProductScore.label) }
    }

    static func label(_ v: Int) -> String {
        switch v {
        case 75...: return "Excellent"
        case 50...: return "Bon"
        case 25...: return "Médiocre"
        default: return "Mauvais"
        }
    }

    static func evaluate(_ p: CatalogProduct) -> Result {
        if p.isCosmetic { return cosmetic(p) }
        if p.isPetFood { return petFood(p) }
        if p.source == .product {
            return Result(outcome: .notApplicable("Produit non alimentaire (entretien, maison…) : LifeOS n'a pas encore de méthode de note pour ce type de produit. La fiche reste consultable."),
                          method: "Produits du quotidien", components: [], flags: [], missing: [])
        }
        if isProteinPowder(p) { return capped(proteinPowder(p)) }
        if p.isSupplement { return supplement(p) }
        if isPlainWater(p) { return capped(water(p)) }
        return capped(food(p))
    }

    /// Regle publique de Yuka, reprise telle quelle pour tout ce qui se mange ou se
    /// boit: un additif a risque eleve plafonne la note a 49, quelle que soit la
    /// nutrition.
    static func capped(_ r: Result) -> Result {
        guard let v = r.value, v > highRiskCap, r.flags.contains(where: { $0.level == .high }) else { return r }
        let names = r.flags.filter { $0.level == .high }.map(\.name).joined(separator: ", ")
        return Result(outcome: .scored(highRiskCap), method: r.method,
                      components: r.components + [Component(name: "Plafond", points: nil, max: 0,
                                                            details: ["Additif à risque élevé (\(names)) : note plafonnée à \(highRiskCap)/100 au lieu de \(v)"])],
                      flags: r.flags, missing: r.missing, confidence: r.confidence)
    }

    // MARK: - Aliments et boissons

    /// Nutrition sur 60, a partir des seuils publies du Nutri-Score (tableaux 2017
    /// de Sante publique France; penalite edulcorants des boissons reprise de la
    /// version 2023). Difference assumee: la part fruits/legumes/legumineuses est
    /// omise, la base ne la donne pas de facon fiable. Ecart brut = negatif -
    /// positif, de -10 a 44; note = 60 x (40 - ecart) / 50, bornee a 0...60.
    static func food(_ p: CatalogProduct) -> Result {
        let n = p.nutriments
        let beverage = p.isBeverage
        var missing: [String] = []
        if n.energyKcal == nil { missing.append("énergie") }
        if n.sugars == nil { missing.append("sucres") }
        if n.saturatedFat == nil { missing.append("graisses saturées") }
        if n.salt == nil { missing.append("sel") }

        let nutrition = nutritionComponent(p, missing: missing)
        let (additives, flags, additivesKnown) = additiveComponent(p)
        if !additivesKnown { missing.append("liste des ingrédients") }
        let organic = Component(name: "Bio", points: p.isOrganic ? 10 : 0, max: 10,
                                details: [p.isOrganic ? "Label bio déclaré" : "Aucun label bio déclaré"])
        let comps = [nutrition, additives, organic]

        guard let np = nutrition.points, let ap = additives.points else {
            return Result(outcome: .notEvaluated("Données insuffisantes pour une note sur 100."),
                          method: beverage ? "Boissons" : "Aliments", components: comps, flags: flags, missing: missing)
        }
        let total = Int((np + ap + (organic.points ?? 0)).rounded())
        return Result(outcome: .scored(min(100, max(0, total))), method: beverage ? "Boissons" : "Aliments",
                      components: comps, flags: flags, missing: missing)
    }

    static let highRiskCap = 49

    // MARK: - Nutrition (Nutri-Score 2023)

    enum NutriTable: String { case general = "aliments", beverage = "boissons", fats = "matières grasses, noix et graines" }

    /// Bornes des lettres (points Nutri-Score 2023) et leur traduction en points
    /// LifeOS sur 60: A en haut, E presque a zero. Les noeuds tombent entre deux
    /// lettres, la note est lineaire entre eux. Une lettre E vaut au plus 12/60:
    /// c'est ce qui manquait (l'ancienne echelle lineaire donnait 31/60 a un soda E).
    static func knots(_ t: NutriTable) -> [(Double, Double)] {
        switch t {
        case .general: return [(-10, 60), (0.5, 48), (2.5, 36), (10.5, 24), (18.5, 12), (28.5, 0)]
        case .fats:    return [(-15, 60), (-5.5, 48), (2.5, 36), (10.5, 24), (18.5, 12), (28.5, 0)]
        case .beverage: return [(-5, 48), (2.5, 36), (6.5, 24), (9.5, 12), (17.5, 0)]
        }
    }

    static func grade(_ score: Int, _ t: NutriTable) -> String {
        let s = Double(score)
        let k = knots(t)
        let letters = t == .beverage ? ["b", "c", "d", "e"] : ["a", "b", "c", "d", "e"]
        // Premier noeud (hors borne haute) depasse = la lettre.
        let bounds = Array(k.dropFirst().dropLast().map(\.0))
        for (i, b) in bounds.enumerated() where s < b { return letters[i] }
        return "e"
    }

    static func nutritionPoints(_ score: Int, _ t: NutriTable) -> Double {
        let s = Double(score), k = knots(t)
        if s <= k.first!.0 { return k.first!.1 }
        if s >= k.last!.0 { return 0 }
        for i in 1..<k.count where s <= k[i].0 {
            let (x0, y0) = k[i - 1], (x1, y1) = k[i]
            return (y0 + (s - x0) / (x1 - x0) * (y1 - y0)).rounded()
        }
        return 0
    }

    static let fatTags: Set<String> = ["en:fats", "en:vegetable-fats", "en:vegetable-oils", "en:olive-oils", "en:oils",
                                        "en:nuts", "en:nut-butters", "en:seeds", "en:butters", "en:margarines"]

    /// Table du Nutri-Score. Quand la base donne la lettre officielle, la table
    /// retenue est celle qui la redonne (un soda n'est jamais lu sur la table des
    /// aliments).
    static func table(for p: CatalogProduct, official: (Int, String)? = nil) -> NutriTable {
        var guess: NutriTable = p.isBeverage ? .beverage : (p.categories.contains(where: fatTags.contains) ? .fats : .general)
        if let (score, letter) = official, grade(score, guess) != letter {
            if let t = [NutriTable.beverage, .general, .fats].first(where: { grade(score, $0) == letter }) { guess = t }
        }
        return guess
    }

    static func nutritionComponent(_ p: CatalogProduct, missing: [String]) -> Component {
        if let score = p.nutriscoreScore, let letter = p.nutriscoreGrade {
            let t = table(for: p, official: (score, letter))
            let pts = nutritionPoints(score, t)
            return Component(name: "Nutrition", points: pts, max: 60, details: [
                "Nutri-Score 2023 officiel : \(letter.uppercased()) (\(score) points, tableau \(t.rawValue))",
                "Calculé par Open Food Facts, estimation fruits, légumes et légumineuses comprise",
                "Converti en \(Int(pts))/60 : A en haut de l'échelle, E au plus 12/60",
            ])
        }
        guard missing.isEmpty, let own = computeNutriScore(p) else {
            return Component(name: "Nutrition", points: nil, max: 60, details: ["Manque : " + missing.joined(separator: ", ")])
        }
        let t = table(for: p)
        let pts = nutritionPoints(own.score, t)
        return Component(name: "Nutrition", points: pts, max: 60, details: [
            "Nutri-Score 2023 calculé par LifeOS : \(grade(own.score, t).uppercased()) (\(own.score) points, tableau \(t.rawValue))",
        ] + own.details + [
            "Fruits, légumes et légumineuses : non renseignés, 0 point positif (la note peut être un peu sévère)",
            "Converti en \(Int(pts))/60",
        ])
    }

    /// Algorithme Nutri-Score 2023 (tableaux aliments et boissons; la table des
    /// matieres grasses reutilise celle des aliments, sans le ratio acides gras
    /// satures / lipides). Donnees exigees: energie, sucres, graisses saturees, sel.
    static func computeNutriScore(_ p: CatalogProduct) -> (score: Int, details: [String])? {
        let n = p.nutriments
        guard let kcal = n.energyKcal, let sugars = n.sugars, let sat = n.saturatedFat, let salt = n.salt else { return nil }
        let kj = kcal * 4.184
        let beverage = p.isBeverage
        let energyPts = beverage ? steps(kj, [30, 90, 150, 210, 240, 270, 300, 330, 360, 390])
                                 : steps(kj, [335, 670, 1005, 1340, 1675, 2010, 2345, 2680, 3015, 3350])
        let sugarPts = beverage ? steps(sugars, [0.5, 2, 3.5, 5, 6, 7, 8, 9, 10, 11])
                                : steps(sugars, [3.4, 6.8, 10, 14, 17, 20, 24, 27, 31, 34, 37, 41, 44, 48, 51])
        let satPts = steps(sat, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        let saltPts = steps(salt, stride(from: 0.2, through: 4.0, by: 0.2).map { ($0 * 10).rounded() / 10 })
        let sweetener = beverage && p.additives.contains(where: sweeteners.contains) ? 4 : 0
        let negative = energyPts + sugarPts + satPts + saltPts + sweetener
        let fiberPts = n.fiber.map { steps($0, [3.0, 4.1, 5.2, 6.3, 7.4]) } ?? 0
        let proteinPts = n.proteins.map { beverage ? steps($0, [1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0])
                                                   : steps($0, [2.4, 4.8, 7.2, 9.6, 12, 14, 17]) } ?? 0
        // Regle 2023: pour un aliment, les proteines ne comptent que si le negatif est < 11.
        let countedProtein = (beverage || negative < 11) ? proteinPts : 0
        var details = [
            "Énergie \(fmt(kcal)) kcal : \(energyPts) pt négatif",
            "Sucres \(fmt(sugars)) g : \(sugarPts)",
            "Graisses saturées \(fmt(sat)) g : \(satPts)",
            "Sel \(fmt(salt)) g : \(saltPts)",
        ]
        if sweetener > 0 { details.append("Édulcorant dans une boisson : 4") }
        details.append(n.fiber == nil ? "Fibres : non renseignées, 0 pt positif" : "Fibres \(fmt(n.fiber!)) g : \(fiberPts) pt positif")
        details.append(n.proteins == nil ? "Protéines : non renseignées, 0"
                       : "Protéines \(fmt(n.proteins!)) g : \(countedProtein)" + (countedProtein < proteinPts ? " (ne comptent pas : négatif ≥ 11)" : ""))
        return (negative - fiberPts - countedProtein, details)
    }

    /// Routage vers la methode "Eau": categorie eau, sans categorie ni ingredient
    /// d'eau aromatisee, et aucune valeur CONNUE qui contredise (sucre, energie,
    /// additif). Des valeurs absentes ne font pas une eau notee: `water()` exige
    /// ses donnees.
    static func isPlainWater(_ p: CatalogProduct) -> Bool {
        let flavoured = ["en:flavoured-waters", "en:sweetened-beverages", "en:artificially-sweetened-beverages",
                         "en:flavored-waters", "en:sodas"]
        guard p.isWater, !p.categories.contains(where: flavoured.contains) else { return false }
        let text = (p.ingredientsText ?? "").lowercased()
        guard !["arôme", "arome", "sucre", "sirop", "jus", "édulcorant", "edulcorant", "flavour", "sugar"].contains(where: text.contains)
        else { return false }
        if let s = p.nutriments.sugars, s > 0.5 { return false }
        if let e = p.nutriments.energyKcal, e > 1 { return false }
        return p.additives.isEmpty
    }

    /// Methode "Eau" (donnees exigees: energie ET sucres renseignes, ET liste des
    /// ingredients). Elle verifie que les valeurs sont celles d'une eau plate
    /// (<= 1 kcal, <= 0,5 g de sucre pour 100 ml) et qu'aucun additif n'est
    /// declare. Elle n'evalue PAS la mineralisation, les nitrates ni l'origine: la
    /// base ne les donne pas de facon fiable. Le bio ne s'applique pas: note sur 90
    /// ramenee a 100. Il manque une donnee: "non evalue", jamais 100 par defaut.
    static func water(_ p: CatalogProduct) -> Result {
        var missing: [String] = []
        if p.nutriments.energyKcal == nil { missing.append("énergie") }
        if p.nutriments.sugars == nil { missing.append("sucres") }
        if p.ingredientsText == nil { missing.append("liste des ingrédients") }
        guard missing.isEmpty else {
            return Result(outcome: .notEvaluated("Eau : il manque des données pour vérifier qu'il s'agit d'une eau plate sans additif."),
                          method: "Eau", components: [], flags: [], missing: missing)
        }
        let (additives, flags, _) = additiveComponent(p)
        let nutrition = Component(name: "Nutrition", points: 60, max: 60,
                                  details: ["Valeurs d'une eau plate : \(fmt(p.nutriments.energyKcal!)) kcal, \(fmt(p.nutriments.sugars!)) g de sucre"])
        let total = Int(((60 + (additives.points ?? 0)) / 90 * 100).rounded())
        return Result(outcome: .scored(total), method: "Eau", components: [nutrition, additives], flags: flags, missing: [])
    }

    // MARK: - Complements

    static func isProteinPowder(_ p: CatalogProduct) -> Bool {
        let tags = ["en:protein-powders", "en:whey-proteins", "en:bodybuilding-supplements", "en:protein-supplements"]
        let n = p.name.lowercased()
        return p.categories.contains(where: tags.contains) || n.contains("whey") || n.contains("protéine en poudre")
            || n.contains("protein powder")
    }

    /// Methode "Proteines en poudre 1.0" (whey, isolats, vegetales).
    /// Donnees exigees: proteines, sucres et liste des ingredients.
    ///   - Proteines /50: densite pour 100 g, 0 a 40 g, 50 a 85 g, lineaire entre.
    ///   - Sucres /20: 20 jusqu'a 2 g, 0 a partir de 15 g, lineaire entre.
    ///   - Additifs /30: meme table que les aliments.
    /// Elle mesure la composition declaree. Elle n'evalue PAS l'efficacite, la
    /// qualite des acides amines, la contamination ni l'adaptation a une personne:
    /// la base ne donne pas ces informations.
    static func proteinPowder(_ p: CatalogProduct) -> Result {
        var missing: [String] = []
        if p.nutriments.proteins == nil { missing.append("protéines") }
        if p.nutriments.sugars == nil { missing.append("sucres") }
        let (additives, flags, known) = additiveComponent(p)
        if !known { missing.append("liste des ingrédients") }
        guard missing.isEmpty, let pr = p.nutriments.proteins, let su = p.nutriments.sugars, let ap = additives.points else {
            return Result(outcome: .notEvaluated("Protéine en poudre : données insuffisantes pour la méthode dédiée."),
                          method: "Protéines en poudre", components: [additives], flags: flags, missing: missing)
        }
        let proteinPts = min(50, max(0, (pr - 40) / 45 * 50)).rounded()
        let sugarPts = min(20, max(0, (15 - su) / 13 * 20)).rounded()
        let comps = [
            Component(name: "Protéines", points: proteinPts, max: 50, details: ["\(fmt(pr)) g pour 100 g (0 point à 40 g, 50 points à 85 g)"]),
            Component(name: "Sucres", points: sugarPts, max: 20, details: ["\(fmt(su)) g pour 100 g (20 points jusqu'à 2 g, 0 à 15 g)"]),
            additives,
        ]
        let total = Int((proteinPts + sugarPts + ap).rounded())
        return Result(outcome: .scored(min(100, max(0, total))), method: "Protéines en poudre",
                      components: comps, flags: flags, missing: [])
    }

    /// Autres complements (vitamines, gelules, extraits): pas de note sur 100.
    /// La grille des aliments ne s'applique pas et LifeOS n'a pas de methode validee.
    static func supplement(_ p: CatalogProduct) -> Result {
        let (_, flags, known) = additiveComponent(p)
        var details: [String] = []
        if let pr = p.nutriments.proteins { details.append("Protéines : \(fmt(pr)) g pour 100 g") }
        if let s = p.nutriments.sugars { details.append("Sucres : \(fmt(s)) g pour 100 g") }
        if !known { details.append("Ingrédients non renseignés") }
        return Result(outcome: .notApplicable("Complément alimentaire : pas de note sur 100. LifeOS n'a pas de méthode validée pour ce type de complément (seules les protéines en poudre en ont une). Composition et additifs affichés tels quels."),
                      method: "Complément", components: [Component(name: "Composition", points: nil, max: 0, details: details)],
                      flags: flags, missing: known ? [] : ["liste des ingrédients"])
    }

    // MARK: - Cosmetiques

    /// Liste de surveillance LifeOS: les SEULS ingredients evalues un par un.
    static let watchListVersion = "Liste de surveillance LifeOS 2.0"
    static let watchListSources = "Règlement (CE) n° 1223/2009 : annexes II (interdits) et III (restreints, allergènes à déclarer) relevées dans CosIng (Commission européenne, CC BY 4.0), plus des ingrédients commentés d'après les avis du SCCS."
    /// Nombre total d'ingredients evalues un par un (commentes + annexes CosIng).
    static var watchListCount: Int {
        Set(cosmeticTable.map(\.0)).union(CosmeticRegulation.entries.keys).count
    }

    /// Trois choses SEPAREES (audit du 29 sept apres le build 42):
    /// 1. **reconnu**: le nom existe (liste INCI CosIng ou referentiel LifeOS). Cela
    ///    dit ce qu'est l'ingredient, PAS s'il est sans risque;
    /// 2. **evalue**: l'ingredient est dans la liste de surveillance, avec un niveau
    ///    et une raison. Seuls ceux-la retirent des points (eleve 30, modere 10,
    ///    sensibilite 3);
    /// 3. **confiance**: part reconnue, taille de la formule, contexte d'usage
    ///    inconnu (rince ou non, concentration).
    /// La note dit donc "ce que la liste de surveillance trouve", jamais "sans danger".
    /// Pas de note si moins de 80 % des ingredients sont reconnus. Une formule tres
    /// courte (1 ou 2 ingredients, tous reconnus) est notee avec une confiance faible
    /// au lieu d'etre exclue.
    static func cosmetic(_ p: CatalogProduct) -> Result {
        guard let text = p.ingredientsText, !text.isEmpty else {
            return Result(outcome: .notEvaluated("Liste des ingrédients absente : impossible de noter ce cosmétique."),
                          method: "Cosmétiques", components: [], flags: [], missing: ["liste des ingrédients"])
        }
        // "PARFUM/FRAGRANCE" est un seul ingredient: compte une fois.
        var seen = Set<String>()
        let tokens = inciTokens(text).map { CosmeticINCI.normalize($0) }
            .map { $0 == "fragrance" ? "parfum" : $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        var flags: [Flag] = []
        var unknown: [String] = []
        var restricted: [String] = []
        var evaluated = 0
        for t in tokens {
            if let (name, level, reason) = cosmeticTable.first(where: { t == $0.0 || t.contains($0.0) }) {
                evaluated += 1
                if !flags.contains(where: { $0.code == name }) {
                    flags.append(Flag(code: name, name: name.capitalized, level: level, reason: reason))
                }
            } else if let e = CosmeticRegulation.lookup(t) {
                // Annexes CosIng : interdit = eleve, allergene a declarer = sensibilite,
                // restreint = autorise sous conditions (concentration absente de
                // l'etiquette), donc signale sans retirer de points.
                evaluated += 1
                switch e.kind {
                case .prohibited:
                    flags.append(Flag(code: t, name: t.capitalized, level: .high,
                                      reason: "Interdit dans les cosmétiques dans l'UE (annexe II, n° \(e.ref))."))
                case .allergen:
                    flags.append(Flag(code: t, name: t.capitalized, level: .sensitivity,
                                      reason: "Allergène à déclarer dans l'UE (annexe III, n° \(e.ref)) : gênant si tu y es sensible."))
                case .restricted:
                    restricted.append("\(t) (n° \(e.ref))")
                }
            } else if !CosmeticINCI.isKnown(t) {
                unknown.append(t)
            }
        }
        let recognized = tokens.count - unknown.count
        let identifiedOnly = recognized - evaluated
        let coverage = tokens.isEmpty ? 0 : Double(recognized) / Double(tokens.count)
        let coverageLine = "\(recognized) ingrédient(s) reconnu(s) sur \(tokens.count) (\(CosmeticINCI.version))"
        let shortFormula = !tokens.isEmpty && tokens.count < CosmeticINCI.minimumRecognized && unknown.isEmpty
        guard shortFormula || (recognized >= CosmeticINCI.minimumRecognized && coverage >= CosmeticINCI.minimumCoverage) else {
            return Result(outcome: .notEvaluated("Trop d'ingrédients non reconnus pour noter ce cosmétique : \(coverageLine)."),
                          method: "Cosmétiques",
                          components: [Component(name: "Ingrédients", points: nil, max: 100,
                                                 details: [coverageLine, "Non reconnus : " + unknown.prefix(6).joined(separator: ", ")])],
                          flags: flags, missing: ["ingrédients reconnus (au moins 80 %)"])
        }
        let penalty = flags.reduce(0) { $0 + ($1.level == .high ? 30 : $1.level == .moderate ? 10 : 3) }
        let pts = max(0, 100 - penalty)
        var details = [coverageLine]
        details += flags.isEmpty
            ? ["Aucun ingrédient de la \(watchListVersion) (\(watchListCount) entrées) trouvé dans cette liste."]
            : flags.map { "\($0.name) (\($0.level.rawValue)) : -\($0.level == .high ? 30 : $0.level == .moderate ? 10 : 3)" }
        if !restricted.isEmpty {
            details.append("Autorisés sous conditions (annexe III) : " + restricted.prefix(6).joined(separator: ", ") + ". La concentration n'est pas sur l'étiquette, donc aucun point retiré.")
        }
        if identifiedOnly > 0 {
            details.append("\(identifiedOnly) ingrédient(s) reconnu(s) mais pas évalué(s) un par un : ne pas être dans la liste de surveillance ne prouve pas qu'un ingrédient est sans risque.")
        }
        if !unknown.isEmpty { details.append("Non reconnus, donc non évalués : " + unknown.prefix(6).joined(separator: ", ")) }

        let confidence: Confidence
        if shortFormula {
            confidence = .init(level: .low, reason: "Formule très courte (\(tokens.count) ingrédient\(tokens.count > 1 ? "s" : "")) : peu d'éléments pour juger.")
        } else if coverage >= 0.95 {
            confidence = .init(level: .high, reason: "\(Int((coverage * 100).rounded())) % des ingrédients reconnus. Concentrations et usage (rincé ou non) inconnus.")
        } else {
            confidence = .init(level: .medium, reason: "\(Int((coverage * 100).rounded())) % des ingrédients reconnus : \(unknown.count) non évalué(s). Concentrations et usage inconnus.")
        }
        return Result(outcome: .scored(pts), method: "Cosmétiques",
                      components: [Component(name: "Ingrédients à surveiller", points: Double(pts), max: 100, details: details)],
                      flags: flags, missing: [], confidence: confidence)
    }

    /// Decoupe une liste INCI en ingredients.
    /// - separateurs d'ingredients: virgule, point-virgule, puce "•", point final;
    /// - un nom commun entre parentheses AU MILIEU d'un nom est retire
    ///   ("Helianthus Annuus (Sunflower) Seed Oil" -> "helianthus annuus seed oil");
    /// - "/" et les parentheses restantes ne coupent que si le nom entier n'est pas
    ///   reconnu: "acrylates/c10-30 alkyl acrylate crosspolymer" est UN ingredient,
    ///   "aqua/water" en donne deux, tous deux connus.
    static func inciTokens(_ text: String) -> [String] {
        var t = text.lowercased()
            .replacingOccurrences(of: "®", with: "")
            .replacingOccurrences(of: "™", with: "")
        // Codes de formule ("F.I.L. Z288697/2", "FIL B267999", "FLL C274733"): pas des ingredients.
        t = t.replacingOccurrences(of: #"\(?\s*\bf\.?\s*i?\.?\s*l\.?\s*l?\.?\s*[a-z]{0,2}\s*[0-9]{4,}[^,;)]*\)?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\(([^()]*)\)\s*(?=[a-z])"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\.(\s|$)"#, with: ",", options: .regularExpression)
        var out: [String] = []
        for piece in t.components(separatedBy: CharacterSet(charactersIn: ",;•")) {
            let whole = tidy(piece)
            if whole.isEmpty { continue }
            let n = CosmeticINCI.normalize(whole)
            if CosmeticINCI.isKnown(n) || cosmeticTable.contains(where: { n == $0.0 }) || CosmeticRegulation.lookup(n) != nil {
                out.append(whole); continue
            }
            out += piece.components(separatedBy: CharacterSet(charactersIn: "()[]*/.")).map(tidy).filter { !$0.isEmpty }
        }
        return out
    }

    /// Espaces ecrases; un morceau sans deux lettres ("2", "e") est un reste de ponctuation.
    private static func tidy(_ s: String) -> String {
        let x = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return x.filter(\.isLetter).count >= 2 ? x : ""
    }

    // MARK: - Additifs

    /// Sur 30: 30 - 15 par additif "élevé" - 6 par "modéré", borne a 0.
    /// Ingredients inconnus: composante NON evaluee (pas 30/30 par defaut).
    static func additiveComponent(_ p: CatalogProduct)
        -> (Component, [Flag], known: Bool) {
        // Connu seulement avec la liste des ingredients: des etiquettes d'additifs
        // sans la liste ne disent pas qu'il n'y en a pas d'autres.
        let known = p.ingredientsText != nil
        let flags: [Flag] = p.additives.compactMap { tag in
            let code = CatalogProduct.plain(tag).lowercased().replacingOccurrences(of: " ", with: "")
            guard let (name, level, reason) = additiveTable[code] else { return nil }
            return Flag(code: code.uppercased(), name: name, level: level, reason: reason)
        }
        guard known else {
            return (Component(name: "Additifs", points: nil, max: 30, details: ["Liste des ingrédients non renseignée"]), [], false)
        }
        let high = flags.filter { $0.level == .high }.count
        let moderate = flags.filter { $0.level == .moderate }.count
        let pts = max(0, 30 - 15 * high - 6 * moderate)
        var details = ["\(p.additives.count) additif(s) déclaré(s)"]
        details += flags.map { "\($0.code) \($0.name) (\($0.level.rawValue))" }
        return (Component(name: "Additifs", points: Double(pts), max: 30, details: details), flags, true)
    }

    static let sweeteners: Set<String> = ["en:e950", "en:e951", "en:e952", "en:e954", "en:e955", "en:e960", "en:e961", "en:e962", "en:e969"]

    /// Classement LifeOS 2.0 d apres des avis publics (EFSA, CIRC, etiquetage UE). Un additif classe cancerogene possible (CIRC 2B) passe en risque eleve, comme chez Yuka.
    /// Il dit "a surveiller", pas "dangereux a toute dose".
    static let additiveTable: [String: (String, Level, String)] = [
        "e171": ("Dioxyde de titane", .high, "Interdit dans les aliments dans l'UE depuis 2022 (avis EFSA 2021)."),
        "e249": ("Nitrite de potassium", .high, "Nitrites : lien avec le cancer colorectal via la viande transformée (CIRC)."),
        "e250": ("Nitrite de sodium", .high, "Nitrites : lien avec le cancer colorectal via la viande transformée (CIRC)."),
        "e251": ("Nitrate de sodium", .high, "Nitrates : transformés en nitrites (avis EFSA 2017)."),
        "e252": ("Nitrate de potassium", .high, "Nitrates : transformés en nitrites (avis EFSA 2017)."),
        "e320": ("BHA", .high, "Classé cancérogène possible (CIRC groupe 2B)."),
        "e102": ("Tartrazine", .moderate, "Colorant avec mention obligatoire UE sur l'attention des enfants."),
        "e104": ("Jaune de quinoléine", .moderate, "Colorant avec mention obligatoire UE sur l'attention des enfants."),
        "e110": ("Jaune orangé S", .moderate, "Colorant avec mention obligatoire UE sur l'attention des enfants."),
        "e122": ("Azorubine", .moderate, "Colorant avec mention obligatoire UE sur l'attention des enfants."),
        "e124": ("Ponceau 4R", .moderate, "Colorant avec mention obligatoire UE sur l'attention des enfants."),
        "e129": ("Rouge allura", .moderate, "Colorant avec mention obligatoire UE sur l'attention des enfants."),
        "e150c": ("Caramel ammoniacal", .high, "Peut contenir du 4-MEI, classé cancérogène possible (CIRC groupe 2B)."),
        "e150d": ("Caramel au sulfite d'ammonium", .high, "Peut contenir du 4-MEI, classé cancérogène possible (CIRC groupe 2B)."),
        "e338": ("Acide phosphorique", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e339": ("Phosphates de sodium", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e340": ("Phosphates de potassium", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e341": ("Phosphates de calcium", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e450": ("Diphosphates", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e451": ("Triphosphates", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e452": ("Polyphosphates", .moderate, "Phosphates ajoutés : apports à limiter (réévaluation EFSA 2019)."),
        "e407": ("Carraghénanes", .moderate, "Émulsifiant étudié pour ses effets sur l'intestin."),
        "e433": ("Polysorbate 80", .moderate, "Émulsifiant étudié pour ses effets sur l'intestin."),
        "e466": ("Carboxyméthylcellulose", .moderate, "Émulsifiant étudié pour ses effets sur l'intestin."),
        "e951": ("Aspartame", .high, "Classé cancérogène possible (CIRC groupe 2B, 2023) ; DJA maintenue par l'OMS."),
    ]

    static let cosmeticTable: [(String, Level, String)] = [
        ("triclosan", .high, "Antibactérien restreint dans l'UE, perturbateur endocrinien suspecté."),
        ("butylparaben", .high, "Paraben restreint dans l'UE, perturbateur endocrinien suspecté."),
        ("propylparaben", .high, "Paraben restreint dans l'UE, perturbateur endocrinien suspecté."),
        ("isobutylparaben", .high, "Paraben interdit dans les cosmétiques dans l'UE."),
        ("isopropylparaben", .high, "Paraben interdit dans les cosmétiques dans l'UE."),
        ("butylphenyl methylpropional", .high, "Lilial : interdit dans les cosmétiques dans l'UE depuis 2022."),
        ("cyclotetrasiloxane", .high, "D4 : restreint dans l'UE (persistance dans l'environnement)."),
        ("hydroquinone", .high, "Interdit dans les cosmétiques de soin dans l'UE."),
        ("cyclopentasiloxane", .moderate, "D5 : restreint dans les produits rincés dans l'UE."),
        ("bht", .moderate, "Antioxydant surveillé (avis SCCS 2021)."),
        ("sodium lauryl sulfate", .moderate, "Tensioactif irritant pour certaines peaux."),
        ("dmdm hydantoin", .moderate, "Libère du formaldéhyde."),
        ("quaternium-15", .moderate, "Libère du formaldéhyde."),
        ("imidazolidinyl urea", .moderate, "Libère du formaldéhyde."),
        ("diazolidinyl urea", .moderate, "Libère du formaldéhyde."),
        ("methylisothiazolinone", .moderate, "Conservateur allergisant, restreint dans l'UE."),
        ("methylchloroisothiazolinone", .moderate, "Conservateur allergisant, restreint dans l'UE."),
        ("benzophenone-3", .moderate, "Filtre UV surveillé (avis SCCS 2021)."),
        ("homosalate", .moderate, "Filtre UV à concentration limitée dans l'UE (avis SCCS)."),
        ("parfum", .sensitivity, "Parfum : gênant si tu y es sensible, pas dangereux pour tous."),
        ("limonene", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("linalool", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("citral", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("geraniol", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("citronellol", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("eugenol", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("coumarin", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("hexyl cinnamal", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("benzyl salicylate", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("alpha-isomethyl ionone", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("benzyl alcohol", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("benzyl benzoate", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
        ("farnesol", .sensitivity, "Allergène à déclarer dans l'UE : gênant si tu y es sensible."),
    ]

    // MARK: - Aides

    /// Nombre de seuils strictement depasses (seuils croissants).
    static func steps(_ value: Double, _ thresholds: [Double]) -> Int {
        thresholds.filter { value > $0 }.count
    }

    static func fmt(_ v: Double) -> String {
        // "18,0" s'affiche "18" ; sous 1, deux decimales (taurine 0,15 %, pas "0,1 %").
        var s = String(format: abs(v) < 1 ? "%.2f" : "%.1f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }
}
