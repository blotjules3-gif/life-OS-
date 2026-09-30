import Foundation

// MARK: - Methode "Animaux 2.0" (chats et chiens)
//
// Reperes publics, cites a l'ecran :
// - FEDIAF, Nutritional Guidelines (publication octobre 2021), tableaux III-3a (chien)
//   et III-4a (chat), pour 100 g de matiere seche : proteines chat adulte 25 g
//   (100 kcal/kg^0,67), chat en croissance / reproduction 28 / 30 g, chien adulte 18 g
//   (110 kcal/kg^0,75), chien croissance precoce 25 g, tardive 20 g ; matieres grasses
//   chat 9 g, chien adulte 5,5 g, croissance 8,5 g ; taurine chat sec 0,10 g (adulte et
//   croissance), humide 0,20 g (adulte) / 0,25 g (croissance).
// - Reglement (CE) 767/2009 : liste dans l'ordre decroissant, "au poulet" = au moins
//   4 % ; l'humidite n'a pas a etre declaree sous 14 %.
// - Aliments toxiques documentes : oignon et ail (chat et chien) ; xylitol, chocolat,
//   raisin (chien) ; propylene glycol interdit pour les chats dans l'UE.
// Ce n'est pas un avis veterinaire : un animal malade a des besoins propres.
//
// Sans valeurs exploitables, un aliment complet a sa nutrition comptee a mi-points
// (12,5/25) : la note reste provisoire (confiance faible) et ne monte jamais a 100.
//
// Changements depuis 1.0 : l'espece et le stade de vie combinent plusieurs indices
// (etiquette, categories, nom, marque, choix de l'utilisateur) ; un chaton est compare
// aux besoins de croissance, plus a ceux d'un adulte ; l'humidite n'est plus inventee ;
// les ingredients sont decoupes sans casser "18,5 %" ni les parentheses ; tous les
// manques sont listes ensemble.

extension ProductScore {
    typealias Species = PetLabel.Species

    static let petMethodVersion = "Animaux 2.0"

    static let catBrands = ["gourmet", "felix", "whiskas", "sheba", "kitekat", "perfect fit", "applaws", "catisfactions", "dreamies", "cat chow"]
    static let dogBrands = ["pedigree", "cesar", "frolic", "chappi", "bakers", "dog chow", "beneful", "dentastix", "rodeo"]

    /// Identite complete : indices de la fiche, puis choix de l'utilisateur par-dessus.
    static func petIdentity(_ p: CatalogProduct) -> PetLabel.Identity {
        var id = PetLabel.identity(name: p.name, categories: p.categories, declaration: p.petFacts?.declaration,
                                   frontText: nil, composition: p.ingredientsText, brand: p.brand,
                                   moisture: p.petAnalysis?.moisture)
        if let s = p.petFacts?.userSpecies { id.species = s; id.ambiguous = false; id.evidence.insert("espèce choisie par toi", at: 0) }
        if let l = p.petFacts?.userLifeStage { id.lifeStage = l; id.evidence.insert("stade de vie choisi par toi", at: 0) }
        // Constituants declares a 40 % ou plus du produit tel quel : ce ne peut pas etre
        // une patee (plus de 60 % d'eau). Les chiffres passent devant les mots.
        if let a = p.petAnalysis, a.moisture == nil, let pr = a.protein,
           pr + (a.fat ?? 0) + (a.ash ?? 0) + (a.fibre ?? 0) >= 40, id.format != .dry {
            id.format = .dry
            id.evidence.append("constituants déclarés à plus de 40 % : croquettes")
        }
        return id
    }

    static func species(_ p: CatalogProduct) -> Species? { petIdentity(p).species }

    struct PetRequirement: Equatable {
        let protein: Double
        let fat: Double
        let taurineDry: Double?
        let taurineWet: Double?
        let label: String
    }

    static func requirement(_ sp: Species, _ stage: PetLabel.LifeStage?) -> PetRequirement {
        switch (sp, stage) {
        case (.cat, .young?):
            return .init(protein: 28, fat: 9, taurineDry: 0.10, taurineWet: 0.25, label: "chaton en croissance (FEDIAF 2021)")
        case (.cat, _):
            return .init(protein: 25, fat: 9, taurineDry: 0.10, taurineWet: 0.20, label: "chat adulte (FEDIAF 2021)")
        case (.dog, .young?):
            return .init(protein: 25, fat: 8.5, taurineDry: nil, taurineWet: nil, label: "chiot, croissance précoce (FEDIAF 2021)")
        case (.dog, _):
            return .init(protein: 18, fat: 5.5, taurineDry: nil, taurineWet: nil, label: "chien adulte (FEDIAF 2021)")
        }
    }

    static let namedMeats = ["poulet", "dinde", "canard", "boeuf", "veau", "agneau", "porc", "lapin", "saumon", "thon",
                             "truite", "cabillaud", "sardine", "maquereau", "hareng", "poisson blanc", "poisson", "volaille", "gibier",
                             "cerf", "chevreuil", "chicken", "turkey", "duck", "beef", "lamb", "salmon", "tuna", "rabbit", "fish",
                             "poultry", "kip", "rund", "zalm", "huhn", "rind", "lachs", "gefluegel", "geflugel", "pollo", "salmone", "tacchino"]
    static let vagueMeats = ["viandes et sous-produits", "viande et sous-produits", "sous-produits animaux", "meat and animal derivatives",
                             "meat and animal by-products", "fleisch und tierische nebenerzeugnisse", "vlees en dierlijke bijproducten", "viande", "meat"]
    static let cereals = ["ble", "mais", "riz", "orge", "avoine", "sorgho", "seigle", "millet", "cereale", "cereales", "amidon",
                          "wheat", "corn", "maize", "rice", "barley", "oats", "cereals", "graan", "getreide", "weizen"]
    static let plantProteins = ["proteines de pois", "gluten", "farine de proteines de mais", "proteines de soja", "farine de soja",
                                "soja", "pea protein", "soy", "maize gluten", "corn gluten", "pois"]

    /// Terme entier seulement : "pois" ne doit pas trouver "poisson", ni "ble" "comestible".
    /// (Et "farine" seul n'est pas une cereale : "farine de poisson" est animale.)
    static func hasTerm(_ folded: String, _ terms: [String]) -> Bool {
        terms.contains { t in
            folded.range(of: "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: t) + "($|[^a-z0-9])", options: .regularExpression) != nil
        }
    }

    /// Ingredients de tete et pourcentage DECLARE du premier ingredient animal.
    static func petIngredients(_ text: String) -> (first: [String], meatPercent: Double?) {
        let ings = PetLabel.ingredients(text)
        let meats = namedMeats + vagueMeats
        let firstAnimal = ings.prefix(5).first { i in hasTerm(PetLabel.fold(i.name), meats) }
        // "viande et sous-produits animaux (dont poulet 4 %)" : 4 % est la part DECLAREE de
        // poulet, pas celle de toutes les viandes. Elle compte comme part de viande nommee.
        var pct = firstAnimal?.percent
        if pct == nil, let d = firstAnimal?.detail, hasTerm(PetLabel.fold(d), namedMeats),
           let m = d.firstMatch(of: #/(\d+(?:[.,]\d+)?)\s*%/#) {
            pct = Double(m.1.replacingOccurrences(of: ",", with: "."))
        }
        return (ings.prefix(5).map { PetLabel.fold($0.name) }, pct)
    }

    static func petFood(_ p: CatalogProduct) -> Result {
        let id = petIdentity(p)
        let composition = (p.ingredientsText?.count ?? 0) > 10 ? p.ingredientsText : nil
        if id.species == nil, let other = id.otherAnimal {
            return Result(outcome: .notApplicable("Aliment pour \(other) : la méthode animaux de LifeOS ne couvre que les chats et les chiens. La fiche reste consultable."),
                          method: petMethodVersion, components: [identityComponent(id)], flags: [], missing: [])
        }
        var missing: [String] = []
        if id.species == nil {
            missing.append(id.ambiguous ? "espèce (la fiche parle de chat ET de chien)" : "espèce (chat ou chien)")
        }
        if composition == nil { missing.append("composition") }
        guard let sp = id.species, let text = composition else {
            let why = "Pas de note pour l'instant : il manque " + missing.joined(separator: " et ") + "."
            return Result(outcome: .notEvaluated(why), method: petMethodVersion,
                          components: [identityComponent(id)], flags: [], missing: missing)
        }
        let folded = PetLabel.fold(text + " " + (p.petFacts?.additivesText ?? ""))
        let ings = PetLabel.ingredients(text)
        let top = Array(ings.prefix(5))
        var flags: [Flag] = []

        // 1. Composition /45
        var comp = 0.0
        var cd: [String] = []
        let head = PetLabel.fold(top.first?.name ?? "")
        let second = top.count > 1 ? PetLabel.fold(top[1].name) : ""
        let namedHead = hasTerm(head, namedMeats) && !hasTerm(head, Array(vagueMeats.dropLast(2)))
        if namedHead {
            comp += 15; cd.append("Premier ingrédient : \(top[0].name), une viande ou un poisson nommé (+15)")
        } else if hasTerm(head, vagueMeats) {
            comp += 5; cd.append("Premier ingrédient : « \(top[0].name) », sans espèce nommée (+5)")
        } else if hasTerm(second, namedMeats) {
            comp += 6; cd.append("Premier ingrédient : « \(top.first?.name ?? "") », une viande nommée en deuxième (+6)")
        } else {
            cd.append("Premier ingrédient : « \((top.first?.name ?? "").prefix(40)) », pas une viande (+0)")
        }
        let (_, meatPct) = petIngredients(text)
        let pctLabel = "part DÉCLARÉE du premier ingrédient animal, pas le total de viande"
        switch meatPct {
        case let v? where v >= 50: comp += 20; cd.append("\(fmt(v)) % : \(pctLabel) (+20)")
        case let v? where v >= 26: comp += 14; cd.append("\(fmt(v)) % : \(pctLabel) (+14)")
        case let v? where v >= 14: comp += 8; cd.append("\(fmt(v)) % : \(pctLabel) (+8)")
        case let v? where v > 4: comp += 3; cd.append("\(fmt(v)) % : \(pctLabel) (+3)")
        case let v?: cd.append("\(fmt(v)) %, le minimum légal pour écrire « au … » (+0)")
        case nil: cd.append("Aucun pourcentage d'ingrédient animal déclaré (+0)")
        }
        let plantTop = top.filter { i in let n = PetLabel.fold(i.name); return hasTerm(n, cereals) || hasTerm(n, plantProteins) }
        let per: Double = sp == .cat ? 3 : 2
        if plantTop.isEmpty {
            comp += 10; cd.append("Ni céréale ni protéine végétale concentrée dans les 5 premiers ingrédients (+10)")
        } else {
            let lost = min(10, per * Double(plantTop.count))
            comp += 10 - lost
            cd.append("Dans les 5 premiers : \(plantTop.map(\.name).joined(separator: ", ")). Céréales et protéines végétales, moins adaptées à un \(sp == .cat ? "carnivore strict" : "chien") que la viande (−\(fmt(lost)))")
        }
        if folded.contains("sous-produit") || folded.contains("by-product") || folded.contains("bijproduct") || folded.contains("nebenerzeugnis") {
            comp = max(0, comp - 5); cd.append("« Sous-produits » : partie de l'animal non précisée (−5)")
        }
        let compositionC = Component(name: "Composition", points: comp.rounded(), max: 45, details: cd)

        // 2. Nutrition /25 : aliment complet seulement, humidite jamais inventee.
        let req = requirement(sp, id.lifeStage)
        var nutrition: Component?
        var nutritionMissing: String?
        let a = p.petAnalysis
        let complete = id.kind == nil || id.kind == .complete
        if !complete {
            nutritionMissing = nil
        } else if let a, let pr = a.protein {
            // Matiere seche : humidite declaree, sinon croquettes sous le seuil legal de 14 %.
            var dmLow: Double?, dmHigh: Double?
            var nd: [String] = []
            // Somme des constituants declares tel quel : a 40 % ou plus, ce ne peut pas
            // etre une patee (humide = plus de 60 % d'eau).
            let declaredSum = pr + (a.fat ?? 0) + (a.ash ?? 0) + (a.fibre ?? 0)
            let provenDry = a.moisture == nil && declaredSum >= 40
            if provenDry {
                nd.append("Constituants déclarés : \(fmt(declaredSum)) % du produit tel quel, donc pas une pâtée : croquettes.")
            }
            if let m = a.moisture {
                dmLow = 100 - m; dmHigh = 100 - m
            } else if id.format == .dry || provenDry {
                dmLow = 86; dmHigh = 100
                nd.append("Humidité non déclarée : pour des croquettes, elle est sous 14 % (seuil de déclaration obligatoire). Calcul sur la fourchette 0 à 14 %.")
            }
            if let lo = dmLow, let hi = dmHigh {
                // Proteines sur matiere seche : fourchette ; la note prend la valeur basse.
                let pLow = pr / hi * 100, pHigh = pr / lo * 100
                let pShown = pLow == pHigh ? "\(fmt(pLow)) %" : "\(fmt(pLow)) à \(fmt(pHigh)) %"
                var pts: Double
                let base = pLow
                if base < req.protein { pts = 0 }
                else if base < req.protein + 5 { pts = 8 }
                else if base < req.protein + 10 { pts = 14 }
                else if base < req.protein + 20 { pts = 20 }
                else { pts = 25 }
                nd.insert("Protéines : \(pShown) de la matière sèche (minimum \(req.label) : \(fmt(req.protein)) %)", at: 0)
                if let fat = a.fat {
                    let fLow = fat / hi * 100
                    if fLow < req.fat { pts = max(0, pts - 4); nd.append("Matières grasses \(fmt(fLow)) % MS, sous le minimum \(fmt(req.fat)) % (−4)") }
                    else { nd.append("Matières grasses : au moins \(fmt(fLow)) % de la matière sèche (minimum \(fmt(req.fat)) %)") }
                }
                if sp == .cat {
                    let wet = id.format == .wet || (a.moisture ?? 0) >= 40
                    let tMin = wet ? req.taurineWet : req.taurineDry
                    if let t = a.taurine, let tMin {
                        let tLow = t / hi * 100
                        if tLow + 0.0001 < tMin { pts = max(0, pts - 4); nd.append("Taurine déclarée \(fmt(t)) % : sous le repère \(fmt(tMin)) % MS (−4)") }
                        else { nd.append("Taurine déclarée : \(fmt(t)) % (repère \(fmt(tMin)) % de la matière sèche)") }
                    } else if folded.contains("taurine") {
                        nd.append("Taurine ajoutée (quantité non déclarée dans les constituants)")
                    } else {
                        nd.append("Taurine non déclarée : elle n'a à figurer que si elle est ajoutée")
                    }
                    if let fat = a.fat, let ash = a.ash, let fib = a.fibre {
                        let cLow = max(0, lo - pr - fat - ash - fib) / lo * 100
                        let cHigh = max(0, hi - pr - fat - ash - fib) / hi * 100
                        let lowC = min(cLow, cHigh), highC = max(cLow, cHigh)
                        nd.append(lowC == highC ? "Glucides estimés : \(fmt(lowC)) % de la matière sèche"
                                                : "Glucides estimés : \(fmt(lowC)) à \(fmt(highC)) % de la matière sèche")
                        if lowC > 40 { pts = max(0, pts - 8); nd.append("Beaucoup de glucides pour un carnivore strict (−8)") }
                        else if lowC > 25 { pts = max(0, pts - 4); nd.append("Glucides élevés pour un chat (−4)") }
                    } else {
                        nd.append("Glucides non estimables : cendres ou cellulose non déclarées")
                    }
                }
                if a.convertedFromFraction { nd.append("Valeurs saisies en fractions dans la base, converties en %") }
                nutrition = Component(name: "Nutrition", points: pts, max: 25, details: nd)
            } else {
                nutritionMissing = "humidité (ou préciser croquettes / pâtée)"
            }
        } else {
            nutritionMissing = "constituants analytiques"
        }

        // 3. Additifs et ingredients a eviter /30
        var add = 30.0
        var ad: [String] = []
        func flag(_ code: String, _ name: String, _ level: Level, _ reason: String, _ penalty: Double) {
            flags.append(Flag(code: code, name: name, level: level, reason: reason)); add -= penalty
            ad.append("\(name) : −\(Int(penalty))")
        }
        if folded.range(of: #"\bsucres?\b|caramel|sirop de|sugar|suiker|zucker"#, options: .regularExpression) != nil {
            flag("sucre", "Sucres ajoutés", .moderate, "Inutile pour un chat ou un chien : appétence et calories vides.", 15)
        }
        if folded.contains("colorant") || folded.range(of: #"\be1[0-9]{2}\b"#, options: .regularExpression) != nil {
            flag("colorant", "Colorants", .moderate, "Sans intérêt pour l'animal : la couleur est faite pour le maître.", 6)
        }
        for (code, name) in [("e320", "BHA"), ("e321", "BHT"), ("e324", "Éthoxyquine")] where folded.contains(code) || folded.contains(PetLabel.fold(name)) {
            flag(code.uppercased(), name, .high, "Antioxydant de synthèse surveillé (CIRC 2B pour le BHA, éthoxyquine suspendue en additif dans l'UE).", 10)
        }
        if sp == .cat, folded.contains("propylene glycol") || folded.contains("propylene-glycol") || folded.contains("e1520") {
            flag("E1520", "Propylène glycol", .high, "Interdit dans l'alimentation des chats dans l'UE (anémie).", 15)
        }
        var toxic: [String] = []
        if folded.range(of: #"\boignons?\b|\bail\b|\bonions?\b|garlic|knoblauch|zwiebel"#, options: .regularExpression) != nil { toxic.append("oignon ou ail") }
        if sp == .dog {
            if folded.contains("xylitol") || folded.contains("e967") { toxic.append("xylitol") }
            if folded.contains("chocolat") || folded.contains("chocolate") || folded.contains("cacao") { toxic.append("chocolat") }
            if folded.range(of: #"\braisins?\b|grape"#, options: .regularExpression) != nil { toxic.append("raisin") }
        }
        for t in toxic { flag(t, t.capitalized, .high, "Toxique pour le \(sp.rawValue).", 25) }
        if ad.isEmpty { ad = ["Ni sucre, ni colorant, ni antioxydant surveillé, ni ingrédient toxique repéré"] }
        if folded.contains("antioxyg") || folded.contains("antioxydant") || folded.contains("antioxidant"),
           !flags.contains(where: { ["E320", "E321", "E324"].contains($0.code) }) {
            ad.append("Antioxygènes non nommés sur l'étiquette : impossible de dire lesquels (pas de pénalité)")
        }
        ad.append("Additifs nutritionnels (vitamines, oligo-éléments, taurine) non pénalisés : ils servent à couvrir les besoins")
        let additives = Component(name: "Additifs et ingrédients à éviter", points: max(0, add), max: 30, details: ad)

        // Total et confiance (separee de la note).
        var comps = [identityComponent(id), compositionC]
        let total: Double
        let confidence: Confidence
        let readAutomatically = p.petFacts?.provenance.contains { $0.contains("lue automatiquement") } == true
        if let nutrition {
            comps.append(nutrition)
            total = compositionC.points! + nutrition.points! + additives.points!
            let assumed = p.petAnalysis?.moisture == nil
            let level: Confidence.Level = (assumed || readAutomatically) ? .medium : .high
            var reason = "Composition et constituants analytiques"
            let validated = p.petFacts?.provenance.contains { $0.contains("relue par toi") } == true
            reason += readAutomatically ? " lus automatiquement sur la photo de l'étiquette (à vérifier)."
                    : validated ? " relus par toi sur l'étiquette." : " de la fiche."
            if assumed { reason += " Humidité non déclarée : protéines données en fourchette." }
            confidence = .init(level: level, reason: reason + " Pas un avis vétérinaire.")
        } else if !complete {
            total = (compositionC.points! + additives.points!) / 75 * 100
            confidence = .init(level: .low, reason: "Aliment \(id.kind == .treat ? "friandise" : "complémentaire") : pas comparé aux besoins d'un aliment complet. Note sur la composition seule.")
        } else {
            // Aliment complet (ou type inconnu) sans valeurs exploitables : la nutrition
            // compte a mi-points. Ramener la composition seule a 100 donnait 100/100 a des
            // fiches sans aucune valeur (mesure sur le corpus du 1er oct.).
            let missingWhat = nutritionMissing ?? "des constituants"
            comps.append(Component(name: "Nutrition", points: nil, max: 25, details: [
                "Non évaluée : il manque \(missingWhat).",
                "Comptée à mi-points (12,5 sur 25), ni bonus ni pénalité, en attendant les valeurs de l'étiquette (obligatoires sur un aliment vendu dans l'UE).",
            ]))
            total = compositionC.points! + additives.points! + 12.5
            confidence = .init(level: .low, reason: "Il manque \(missingWhat) : note provisoire, nutrition comptée à mi-points.")
        }
        comps.append(additives)
        var value = Int(total.rounded())
        if !toxic.isEmpty || flags.contains(where: { $0.level == .high }), value > highRiskCap {
            comps.append(Component(name: "Plafond", points: nil, max: 0, details: ["Ingrédient toxique ou additif à risque élevé : note plafonnée à \(highRiskCap)/100 au lieu de \(value)"]))
            value = highRiskCap
        }
        let stage = id.lifeStage.map { $0 == .young ? (sp == .cat ? "chaton" : "chiot") : $0 == .senior ? "senior" : "adulte" }
        return Result(outcome: .scored(min(100, max(0, value))),
                      method: "\(petMethodVersion) · \(sp.rawValue)\(stage.map { " · \($0)" } ?? "")",
                      components: comps, flags: flags, missing: nutritionMissing.map { [$0] } ?? [], confidence: confidence)
    }

    /// "Pour qui" : ce qui a ete reconnu et sur quels indices (sans points).
    static func identityComponent(_ id: PetLabel.Identity) -> Component {
        var d: [String] = []
        let sp = id.species.map { $0 == .cat ? "Chat" : "Chien" } ?? (id.ambiguous ? "Espèce ambiguë" : "Espèce inconnue")
        let stage = id.lifeStage.map { s -> String in
            switch s { case .young: return id.species == .dog ? "chiot" : "chaton / jeune"; case .adult: return "adulte"; case .senior: return "senior" }
        } ?? "stade de vie non précisé"
        let kind = id.kind.map { $0 == .complete ? "aliment complet" : $0 == .complementary ? "aliment complémentaire" : "friandise" } ?? "type non précisé"
        let format = id.format.map { $0 == .dry ? "croquettes" : "humide" } ?? "format non précisé"
        d.append("\(sp) · \(stage) · \(kind) · \(format)")
        if !id.evidence.isEmpty { d.append("Indices : " + id.evidence.prefix(4).joined(separator: ", ")) }
        return Component(name: "Pour qui", points: nil, max: 0, details: d)
    }
}
