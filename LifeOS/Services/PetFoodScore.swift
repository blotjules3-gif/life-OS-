import Foundation

// MARK: - Methode "Animaux 1.0" (chats et chiens)
//
// Demande de Theo (29 sept): Yuka ne note pas la nourriture pour animaux, LifeOS
// doit la noter a partir de ce qu'elle contient vraiment. Reperes publics:
// - FEDIAF (federation europeenne des fabricants), recommandations nutritionnelles
//   2021: proteines minimales en matiere seche, chat adulte 25 %, chien adulte 18 %;
// - reglement (CE) 767/2009 sur l'etiquetage: "au poulet" = au moins 4 % de poulet,
//   la liste est dans l'ordre decroissant des quantites;
// - aliments toxiques documentes (oignon et ail pour chats et chiens; xylitol,
//   chocolat et raisin pour les chiens).
// Ce n'est pas un avis veterinaire: un animal malade a des besoins propres.

extension ProductScore {
    enum Species: String { case cat = "chat", dog = "chien" }

    static let petMethodVersion = "Animaux 1.0"

    /// Choix fait par l'utilisateur sur la fiche ("C'est pour : chat / chien"),
    /// quand la base ne dit pas l'espece. Remplacable dans les tests.
    nonisolated(unsafe) static var speciesChoice: (String) -> Species? = { code in
        (UserDefaults.standard.dictionary(forKey: "yuko.petSpecies")?[code] as? String).flatMap(Species.init(rawValue:))
    }

    static func setSpecies(_ s: Species, for code: String) {
        var d = UserDefaults.standard.dictionary(forKey: "yuko.petSpecies") ?? [:]
        d[code] = s.rawValue
        UserDefaults.standard.set(d, forKey: "yuko.petSpecies")
    }

    static let catBrands = ["gourmet", "felix", "whiskas", "sheba", "kitekat", "perfect fit", "applaws", "catisfactions", "dreamies", "cat chow"]
    static let dogBrands = ["pedigree", "cesar", "frolic", "chappi", "bakers", "dog chow", "beneful", "dentastix", "rodeo"]

    static func species(_ p: CatalogProduct) -> Species? {
        if let chosen = speciesChoice(p.barcode) { return chosen }
        let tags = Set(p.categories)
        if tags.contains(where: { $0.contains("cat-food") || $0.contains("cat-treats") }) { return .cat }
        if tags.contains(where: { $0.contains("dog-food") || $0.contains("dog-treats") }) { return .dog }
        let n = GenericFoods.fold(p.name + " " + (p.ingredientsText ?? "").prefix(80))
        let catWords = ["chat", " cat", "cat ", "katze", "kattenvoer", "gatto", "gato", "felin", "kitten", "chaton"]
        let dogWords = ["chien", " dog", "dog ", "hund", "hond", "cane ", "perro", "canin", "puppy", "chiot"]
        if catWords.contains(where: n.contains) { return .cat }
        if dogWords.contains(where: n.contains) { return .dog }
        // Marque connue pour une seule espece (Gourmet: la fiche du 29 sept ne disait
        // "chat" nulle part, alors que la boite montre un chat).
        let brand = GenericFoods.fold((p.brand ?? "") + " " + p.name)
        if catBrands.contains(where: brand.contains) { return .cat }
        if dogBrands.contains(where: brand.contains) { return .dog }
        return nil
    }

    static let namedMeats = ["poulet", "dinde", "canard", "boeuf", "bœuf", "veau", "agneau", "porc", "lapin", "saumon", "thon",
                             "truite", "cabillaud", "sardine", "maquereau", "hareng", "poisson blanc", "volaille", "gibier", "cerf", "chevreuil",
                             "chicken", "turkey", "duck", "beef", "lamb", "salmon", "tuna", "rabbit", "kip", "rund", "zalm", "huhn", "rind", "lachs"]
    static let fillers = ["ble", "mais", "riz", "orge", "avoine", "soja", "gluten", "cereale", "farine", "pois", "pomme de terre",
                          "sous-produits d'origine vegetale", "wheat", "corn", "maize", "rice", "cereals", "graan", "getreide"]

    /// Ingredients de tete (ordre decroissant des quantites) et pourcentage de
    /// viande declare le plus eleve.
    static func petIngredients(_ text: String) -> (first: [String], meatPercent: Double?) {
        let t = GenericFoods.fold(text)
        let parts = t.components(separatedBy: CharacterSet(charactersIn: ",;.")).map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^[^:]*:\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        var best: Double?
        let meats = namedMeats.map(GenericFoods.fold) + ["viande", "meat"]
        let regex = try! NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)\s?%"#)
        for part in parts where meats.contains(where: part.contains) {
            for m in regex.matches(in: part, range: NSRange(part.startIndex..., in: part)) {
                if let r = Range(m.range(at: 1), in: part), let v = Double(part[r].replacingOccurrences(of: ",", with: ".")), v <= 100 {
                    best = max(best ?? 0, v)
                }
            }
        }
        return (Array(parts.prefix(5)), best)
    }

    static func petFood(_ p: CatalogProduct) -> Result {
        let method = petMethodVersion
        guard let sp = species(p) else {
            return Result(outcome: .notApplicable("Aliment pour animaux : LifeOS note pour l'instant les aliments pour chats et chiens. Espèce non reconnue sur cette fiche."),
                          method: method, components: [], flags: [], missing: ["espèce (chat ou chien)"])
        }
        guard let text = p.ingredientsText, text.count > 10 else {
            return Result(outcome: .notEvaluated("Composition absente : impossible de juger cet aliment pour \(sp.rawValue). Photographie la liste au dos du paquet."),
                          method: method, components: [], flags: [], missing: ["composition"])
        }
        let folded = GenericFoods.fold(text)
        let (first, meatPct) = petIngredients(text)
        var flags: [Flag] = []

        // 1. Composition /45 (le coeur de la note: ce qu'il y a vraiment dedans)
        var comp = 0.0
        var cd: [String] = []
        // "viande et sous-produits animaux (dont poulet 4%)": la parenthese ne fait
        // pas du poulet le premier ingredient.
        let head = (first.first ?? "").replacingOccurrences(of: #"\([^)]*\)?|\(.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let meats = namedMeats.map(GenericFoods.fold)
        if meats.contains(where: head.contains) {
            comp += 15; cd.append("Premier ingrédient : une viande ou un poisson nommé (+15)")
        } else if head.contains("viande") || head.contains("sous-produits animaux") || head.contains("meat") {
            comp += 5; cd.append("Premier ingrédient : « viandes et sous-produits », sans espèce nommée (+5)")
        } else {
            cd.append("Premier ingrédient : « \(head.prefix(40)) », pas une viande (+0)")
        }
        switch meatPct {
        case let v? where v >= 50: comp += 20; cd.append("Viande déclarée : \(fmt(v)) % (+20)")
        case let v? where v >= 26: comp += 14; cd.append("Viande déclarée : \(fmt(v)) % (+14)")
        case let v? where v >= 14: comp += 8; cd.append("Viande déclarée : \(fmt(v)) % (+8)")
        case let v? where v > 4: comp += 3; cd.append("Viande déclarée : \(fmt(v)) % (+3)")
        case let v?: cd.append("Viande déclarée : \(fmt(v)) %, le minimum légal pour écrire « au poulet » (+0)")
        case nil: cd.append("Part de viande non déclarée (+0)")
        }
        let fillerCount = first.filter { part in fillers.contains(where: { part.contains(GenericFoods.fold($0)) }) }.count
        if fillerCount == 0 { comp += 10; cd.append("Aucune céréale ni protéine végétale dans les 5 premiers ingrédients (+10)") }
        else { comp += Double(max(0, 10 - 4 * fillerCount)); cd.append("\(fillerCount) céréale(s) ou protéine(s) végétale(s) dans les 5 premiers ingrédients (−\(min(10, 4 * fillerCount)))") }
        if folded.contains("sous-produits") || folded.contains("by-product") || folded.contains("bijproduct") {
            comp = max(0, comp - 8); cd.append("« Sous-produits » : origine imprécise (−8)")
        }
        let composition = Component(name: "Composition", points: comp.rounded(), max: 45, details: cd)

        // 2. Nutrition /25 (proteines sur matiere seche, glucides estimes pour un chat)
        var nutrition: Component?
        if let a = p.petAnalysis, let pr = a.protein {
            let dry = p.categories.contains(where: { $0.contains("dry") }) || GenericFoods.fold(p.name).contains("croquette")
            let moisture = a.moisture ?? (dry ? 10 : 78)
            let dm = max(1, 100 - moisture)
            let proteinDM = pr / dm * 100
            let (minimum, steps): (Double, [Double]) = sp == .cat ? (25, [30, 35, 45]) : (18, [22, 26, 32])
            var pts: Double
            if proteinDM < minimum { pts = 0 }
            else if proteinDM < steps[0] { pts = 8 }
            else if proteinDM < steps[1] { pts = 14 }
            else if proteinDM < steps[2] { pts = 20 }
            else { pts = 25 }
            var nd = ["Protéines : \(fmt(proteinDM)) % de la matière sèche (minimum FEDIAF \(sp.rawValue) adulte : \(fmt(minimum)) %)"]
            if a.moisture == nil { nd.append("Humidité non déclarée : \(fmt(moisture)) % supposée (\(dry ? "croquettes" : "pâtée"))") }
            if a.convertedFromFraction { nd.append("Valeurs saisies en fractions dans la base, converties en %") }
            if sp == .cat, let fat = a.fat, let ash = a.ash {
                let nfe = max(0, 100 - moisture - pr - fat - (a.fibre ?? 0) - ash) / dm * 100
                nd.append("Glucides estimés : \(fmt(nfe)) % de la matière sèche")
                if nfe > 40 { pts = max(0, pts - 8); nd.append("Beaucoup de glucides pour un carnivore strict (−8)") }
                else if nfe > 25 { pts = max(0, pts - 4); nd.append("Glucides élevés pour un chat (−4)") }
            }
            nutrition = Component(name: "Nutrition", points: pts, max: 25, details: nd)
        }

        // 3. Additifs et ingredients a eviter /30
        var add = 30.0
        var ad: [String] = []
        func flag(_ code: String, _ name: String, _ level: Level, _ reason: String, _ penalty: Double) {
            flags.append(Flag(code: code, name: name, level: level, reason: reason)); add -= penalty
            ad.append("\(name) : −\(Int(penalty))")
        }
        if folded.range(of: #"\bsucres?\b|caramel|sirop|sugar|suiker|zucker"#, options: .regularExpression) != nil {
            flag("sucre", "Sucres ajoutés", .moderate, "Inutile pour un chat ou un chien : appétence et calories vides.", 15)
        }
        if folded.contains("colorant") || folded.range(of: #"\be1[0-9]{2}\b"#, options: .regularExpression) != nil {
            flag("colorant", "Colorants", .moderate, "Sans intérêt pour l'animal : la couleur est faite pour le maître.", 6)
        }
        for (code, name) in [("e320", "BHA"), ("e321", "BHT"), ("e324", "Éthoxyquine")] where folded.contains(code) || folded.contains(GenericFoods.fold(name)) {
            flag(code.uppercased(), name, .high, "Antioxydant de synthèse surveillé (CIRC 2B pour le BHA, éthoxyquine suspendue en additif dans l'UE).", 10)
        }
        if sp == .cat, folded.contains("propylene glycol") || folded.contains("propylene-glycol") || folded.contains("e1520") {
            flag("E1520", "Propylène glycol", .high, "Interdit dans l'alimentation des chats dans l'UE (anémie).", 15)
        }
        var toxic: [String] = []
        if folded.range(of: #"\boignons?\b|\bail\b|\bonion|garlic"#, options: .regularExpression) != nil { toxic.append("oignon ou ail") }
        if sp == .dog {
            if folded.contains("xylitol") || folded.contains("e967") { toxic.append("xylitol") }
            if folded.contains("chocolat") || folded.contains("chocolate") || folded.contains("cacao") { toxic.append("chocolat") }
            if folded.range(of: #"\braisins?\b|grape"#, options: .regularExpression) != nil { toxic.append("raisin") }
        }
        for t in toxic { flag(t, t.capitalized, .high, "Toxique pour le \(sp.rawValue).", 25) }
        if ad.isEmpty { ad = ["Ni sucre, ni colorant, ni antioxydant surveillé, ni ingrédient toxique repéré"] }
        let additives = Component(name: "Additifs et ingrédients à éviter", points: max(0, add), max: 30, details: ad)

        // Total: sans constituants analytiques, composition et additifs ramenes sur 100,
        // avec une confiance faible annoncee.
        var comps = [composition]
        let total: Double
        let confidence: Confidence
        if let nutrition {
            comps.append(nutrition)
            total = composition.points! + nutrition.points! + additives.points!
            confidence = .init(level: p.petAnalysis?.moisture == nil ? .medium : .high,
                               reason: "Composition et constituants analytiques lus sur la fiche. Pas un avis vétérinaire.")
        } else {
            total = (composition.points! + additives.points!) / 75 * 100
            confidence = .init(level: .low, reason: "Constituants analytiques absents (protéines, humidité) : note sur la composition seule.")
        }
        comps.append(additives)
        var value = Int(total.rounded())
        if !toxic.isEmpty || flags.contains(where: { $0.level == .high }), value > highRiskCap {
            comps.append(Component(name: "Plafond", points: nil, max: 0, details: ["Ingrédient toxique ou additif à risque élevé : note plafonnée à \(highRiskCap)/100 au lieu de \(value)"]))
            value = highRiskCap
        }
        return Result(outcome: .scored(min(100, max(0, value))), method: "\(method) · \(sp.rawValue)",
                      components: comps, flags: flags, missing: nutrition == nil ? ["constituants analytiques"] : [], confidence: confidence)
    }
}
