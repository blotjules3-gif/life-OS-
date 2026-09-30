import Foundation

// MARK: - Lecture d'une etiquette d'aliment pour animaux
//
// Une etiquette europeenne (reglement 767/2009) suit toujours le meme plan :
// "Aliment complet pour chatons." puis "Composition :", "Additifs :",
// "Constituants analytiques :". Ce fichier le decoupe, sans rien inventer : un champ
// absent reste absent.

enum PetLabel {

    // MARK: Constituants analytiques

    /// Valeurs pour 100 g TEL QUEL (comme imprime), en %.
    struct Analytics: Codable, Hashable {
        var protein: Double?
        var fat: Double?
        var ash: Double?
        var fibre: Double?
        var moisture: Double?
        var taurine: Double?
        var calcium: Double?
        var phosphorus: Double?
        var omega3: Double?
        var omega6: Double?
        var dha: Double?
        var isEmpty: Bool { protein == nil && fat == nil && ash == nil && fibre == nil && moisture == nil }
    }

    /// Ordre important : la premiere regle qui correspond gagne ("acides gras omega 3"
    /// avant "matieres grasses", "cendres" avant tout).
    private static let analyticRules: [(WritableKeyPath<Analytics, Double?>, [String])] = [
        (\.dha, ["dha", "docosahexa"]),
        (\.omega3, ["omega 3", "omega-3", "omega3", "ω-3", "ω3"]),
        (\.omega6, ["omega 6", "omega-6", "omega6", "ω-6", "ω6"]),
        (\.taurine, ["taurine", "taurin", "taurina"]),
        (\.phosphorus, ["phosphore", "phosphorus", "phosphor", "fosforo", "fosfor"]),
        (\.calcium, ["calcium", "calcio", "kalzium"]),
        (\.ash, ["cendres", "crude ash", "ash", "rohasche", "ruwe as", "ceneri", "cenizas", "matieres minerales", "matiere minerale", "inorganic matter"]),
        (\.fibre, ["cellulose", "fibre", "fiber", "rohfaser", "ruwe celstof", "fibra"]),
        (\.moisture, ["humidite", "moisture", "feuchtigkeit", "feuchte", "vocht", "umidita", "humedad"]),
        (\.fat, ["matieres grasses", "matiere grasse", "fat", "graisses", "rohfett", "vet", "grassi", "grasa", "lipides", "oils and fats"]),
        (\.protein, ["proteine", "protein", "rohprotein", "eiwit", "proteina", "proteinas"]),
    ]

    /// Maximum credible par constituant, tel quel (bien au-dessus des aliments du commerce).
    private static let plausibleMax: [WritableKeyPath<Analytics, Double?>: Double] = [
        \.protein: 90, \.fat: 60, \.ash: 20, \.fibre: 30, \.moisture: 90, \.taurine: 1, \.calcium: 5,
        \.phosphorus: 4, \.omega3: 5, \.omega6: 10, \.dha: 3,
    ]

    private static let numberRegex = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*%"#)

    static func analytics(_ text: String) -> Analytics {
        var a = Analytics()
        let t = fold(text) as NSString
        // "Libelle : 41,0 %". On part de chaque nombre suivi de % et on remonte au plus
        // 60 caracteres jusqu'au separateur precedent (; % , ou ". "). Lineaire : l'ancienne
        // expression reguliere revenait en arriere sur les longs textes d'etiquette.
        for m in numberRegex.matches(in: t as String, range: NSRange(location: 0, length: t.length)) {
            guard let v = Double(t.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")), v <= 100 else { continue }
            let from = max(0, m.range.location - 60)
            var label = t.substring(with: NSRange(location: from, length: m.range.location - from))
            label = label.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ":：")))
            if let cut = label.ranges(of: #/[;%]|,(?!\d)|\.\s/#).last {
                label = String(label[cut.upperBound...])
            }
            label = label.trimmingCharacters(in: .whitespaces)
            guard label.contains(where: \.isLetter) else { continue }
            for (kp, words) in analyticRules where words.contains(where: { label.contains($0) }) {
                // Valeur impossible pour un aliment (virgule perdue a la lecture : "07 %"
                // pour 0,7 % d'omega 3) : laissee vide plutot que fausse.
                if a[keyPath: kp] == nil, v <= (plausibleMax[kp] ?? 100) { a[keyPath: kp] = v }
                break
            }
        }
        return a
    }

    // MARK: Ingredients

    struct Ingredient: Equatable {
        /// Nom sans parenthese.
        let name: String
        /// Pourcentage de l'ingredient lui-meme ("Saumon (18 %)", "poulet 4%"), pas
        /// celui d'un sous-ingredient entre parentheses ("dont poulet 4 %").
        let percent: Double?
        /// Contenu des parentheses, tel quel.
        let detail: String?
        let raw: String
    }

    /// Decoupe au premier niveau seulement : une virgule entre deux chiffres ("18,5 %")
    /// ou dans une parenthese ("Saumon (dont tete, arete)") ne coupe pas.
    static func ingredients(_ text: String) -> [Ingredient] {
        var parts: [String] = []
        var cur = ""
        var depth = 0
        // L'OCR lit parfois "}" pour ")" ("Ble (16 %}") : sans ca, la parenthese restee
        // ouverte avalait toute la suite de la liste en un seul ingredient.
        let chars = Array(text.map { $0 == "{" ? "(" : $0 == "}" ? ")" : $0 })
        // Parentheses jamais refermees : ignorees pour le decoupage.
        var unmatched = Set<Int>()
        var stack: [Int] = []
        for (i, c) in chars.enumerated() {
            if c == "(" || c == "[" { stack.append(i) }
            else if (c == ")" || c == "]"), !stack.isEmpty { stack.removeLast() }
        }
        unmatched.formUnion(stack)
        for (i, c) in chars.enumerated() {
            if (c == "(" || c == "[") && !unmatched.contains(i) { depth += 1 }
            if c == ")" || c == "]" { depth = max(0, depth - 1) }
            let prevDigit = i > 0 && chars[i - 1].isNumber
            let nextDigit = i + 1 < chars.count && chars[i + 1].isNumber
            let isDecimal = (c == "," || c == ".") && prevDigit && nextDigit
            if depth == 0 && !isDecimal && (c == "," || c == ";" || c == "." || c == "•") {
                parts.append(cur); cur = ""
            } else {
                cur.append(c)
            }
        }
        parts.append(cur)
        return parts.compactMap { p in
            let raw = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.filter(\.isLetter).count >= 2 else { return nil }
            let groups = raw.matches(of: #/\(([^()]*)\)/#).map { String($0.1).trimmingCharacters(in: .whitespaces) }
            let outside = raw.replacingOccurrences(of: #"\([^)]*\)?"#, with: " ", options: .regularExpression)
            let name = outside.replacingOccurrences(of: #"\d+(?:[.,]\d+)?\s*%"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-–:")))
            // Pourcentage propre : hors parentheses, ou parenthese qui ne contient QUE lui
            // ("Saumon (dont tete, arete, chair) (18 %)"). "(dont poulet 4 %)" n'est pas
            // le pourcentage de l'ingredient.
            let onlyPercent = groups.first { $0.range(of: #"^\d+(?:[.,]\d+)?\s*%$"#, options: .regularExpression) != nil }
            let pct = firstPercent(outside) ?? onlyPercent.flatMap(firstPercent)
            let detail = groups.filter { $0 != onlyPercent }.joined(separator: " ; ")
            return Ingredient(name: name.isEmpty ? raw : name, percent: pct, detail: detail.isEmpty ? nil : detail, raw: raw)
        }
    }

    private static func firstPercent(_ s: String) -> Double? {
        guard let m = s.firstMatch(of: #/(\d+(?:[.,]\d+)?)\s*%/#) else { return nil }
        return Double(m.1.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: Sections d'une etiquette complete (texte lu sur photo)

    struct Sections: Equatable {
        var declaration: String?
        var composition: String?
        var additives: String?
        var analytics: String?
    }

    // Variantes lues par l'OCR sur de vraies etiquettes ("compesition", corpus du 1er oct.).
    private static let compositionMarkers = ["composition", "compesition", "cornposition", "compositon", "ingredients", "zusammensetzung", "samenstelling", "composizione", "composicion"]
    private static let additiveMarkers = ["additifs", "additives", "zusatzstoffe", "toevoegingsmiddelen", "additivi", "aditivos"]
    private static let analyticMarkers = ["constituants analytiques", "analytical constituents", "analytische bestandteile",
                                          "analytische bestanddelen", "componenti analitici", "componentes analiticos"]
    private static let endMarkers = ["ce sac", "mode d'emploi", "conseils d'utilisation", "a utiliser de preference", "a conserver",
                                     "numeros de lot", "feeding guide", "best before", "keep in a cool", "futterungsempfehlung", "fuetterungsempfehlung"]

    /// Decoupe le texte d'une etiquette. Travaille sur le texte replie (sans accents)
    /// pour trouver les reperes, et rend des extraits du texte d'origine.
    static func sections(_ text: String) -> Sections {
        let original = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Repli caractere par caractere : meme longueur, donc memes positions.
        let folded = String(original.map { c -> Character in c.isASCII ? Character(c.lowercased()) : (fold(String(c)).first ?? c) })
        func find(_ markers: [String]) -> Range<String.Index>? {
            markers.compactMap { folded.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        }
        func toOriginal(_ r: Range<String.Index>) -> Range<String.Index> {
            let lo = folded.distance(from: folded.startIndex, to: r.lowerBound)
            let hi = folded.distance(from: folded.startIndex, to: r.upperBound)
            return original.index(original.startIndex, offsetBy: lo)..<original.index(original.startIndex, offsetBy: hi)
        }
        let comp = find(compositionMarkers), add = find(additiveMarkers), ana = find(analyticMarkers)
        let end = endMarkers.compactMap { folded.range(of: $0) }.map(\.lowerBound).min()
        func body(after r: Range<String.Index>?) -> String? {
            guard let r else { return nil }
            let stops = ([comp?.lowerBound, add?.lowerBound, ana?.lowerBound, end].compactMap { $0 }).filter { $0 > r.upperBound }
            let stop = stops.min() ?? folded.endIndex
            let o = toOriginal(r.upperBound..<stop)
            let s = original[o].trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ":：.")))
            return s.isEmpty ? nil : s
        }
        var decl: String?
        if let first = [comp?.lowerBound, add?.lowerBound, ana?.lowerBound].compactMap({ $0 }).min(), first > folded.startIndex {
            let s = String(original[toOriginal(folded.startIndex..<first)]).trimmingCharacters(in: .whitespaces)
            decl = s.isEmpty ? nil : s
        }
        return Sections(declaration: decl, composition: body(after: comp), additives: body(after: add), analytics: body(after: ana))
    }

    // MARK: Identite : espece, stade de vie, type d'aliment, format

    enum Species: String, Codable, CaseIterable { case cat = "chat", dog = "chien" }
    enum LifeStage: String, Codable, CaseIterable { case young, adult, senior }
    enum Kind: String, Codable { case complete, complementary, treat }
    enum Format: String, Codable { case dry, wet }

    struct Identity: Equatable {
        var species: Species?
        var lifeStage: LifeStage?
        var kind: Kind?
        var format: Format?
        /// Preuves lues, pour les afficher ("« aliment complet pour chatons » sur l'étiquette").
        var evidence: [String] = []
        /// Les deux especes ont des indices : on demande a l'utilisateur.
        var ambiguous = false
        /// Aliment pour un autre animal (oiseau, rongeur...) : hors methode chat/chien.
        var otherAnimal: String?
    }

    private static let catWords = ["chat", "chats", "chaton", "chatons", "chatte", "chattes", "kitten", "kittens", "cat", "cats",
                                   "katze", "katzen", "katzchen", "kat", "katten", "kitten", "gatto", "gatti", "gattino", "gato",
                                   "gatos", "gatito", "felin", "feline"]
    private static let dogWords = ["chien", "chiens", "chiot", "chiots", "puppy", "puppies", "dog", "dogs", "hund", "hunde", "welpe",
                                   "welpen", "hond", "honden", "pup", "cane", "cani", "cucciolo", "perro", "perros", "cachorro", "canin", "canine"]
    private static let youngWords = ["chaton", "chatons", "kitten", "kittens", "katzchen", "gattino", "gatito", "chiot", "chiots",
                                     "puppy", "welpe", "cucciolo", "cachorro", "junior", "croissance", "growth", "1-12 mois", "1 a 12 mois",
                                     "2-12 mois", "jusqu'a 12 mois", "gestation", "lactation"]
    private static let seniorWords = ["senior", "7+", "11+", "12+", "mature"]
    /// Lus dans le nom, les categories et la mention d'etiquette, jamais dans la
    /// composition ("lapin" y est un ingredient).
    private static let otherAnimalWords = ["oiseau", "oiseaux", "perruche", "perruches", "canari", "canaris", "perroquet", "rongeur",
                                          "rongeurs", "hamster", "cobaye", "cochon d'inde", "furet", "aquarium", "poisson rouge",
                                          "poissons rouges", "tortue", "tortues", "cheval", "chevaux", "poules", "bird", "birds",
                                          "rodent", "rodents", "hamsters", "horse", "vogel", "vogels", "nager", "pferd"]
    private static let adultWords = ["adulte", "adultes", "adult", "adults", "adulto", "adulti", "volwassen", "erwachsen",
                                     "erwachsene", "ausgewachsene", "1+", "1+an", "1+ans", "1+years"]

    /// Combine les indices. "Junior" ou "Purina" seuls ne disent pas l'espece : il faut
    /// un mot d'espece, une categorie structuree ou une marque reservee a une espece.
    static func identity(name: String, categories: [String], declaration: String?, frontText: String?,
                         composition: String?, brand: String?, moisture: Double?) -> Identity {
        var id = Identity()
        var cat = 0, dog = 0
        func words(_ s: String) -> Set<String> {
            Set(fold(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" && $0 != "-" && $0 != "'" }).map(String.init))
        }
        func hit(_ s: String?, _ weight: Int, _ what: String) {
            guard let s, !s.isEmpty else { return }
            let w = words(s)
            if let c = catWords.first(where: w.contains) { cat += weight; id.evidence.append("« \(c) » \(what)") }
            if let d = dogWords.first(where: w.contains) { dog += weight; id.evidence.append("« \(d) » \(what)") }
        }
        let tags = categories.map(fold)
        if tags.contains(where: { $0.contains("cat-food") || $0.contains("cat-treat") || $0.contains("kitten") || $0.contains("katzenfutter") || $0.contains("kattenvoer") }) {
            cat += 3; id.evidence.append("catégorie « aliment pour chat » de la base")
        }
        if tags.contains(where: { $0.contains("dog-food") || $0.contains("dog-treat") || $0.contains("puppy") || $0.contains("hundefutter") || $0.contains("hondenvoer") }) {
            dog += 3; id.evidence.append("catégorie « aliment pour chien » de la base")
        }
        hit(declaration, 3, "sur l'étiquette")
        hit(name, 2, "dans le nom")
        hit(frontText, 2, "sur la face avant")
        let b = fold((brand ?? "") + " " + name)
        if ProductScore.catBrands.contains(where: b.contains) { cat += 1; id.evidence.append("marque réservée aux chats") }
        if ProductScore.dogBrands.contains(where: b.contains) { dog += 1; id.evidence.append("marque réservée aux chiens") }
        if cat == 0 && dog == 0 {
            let other = fold([name, declaration ?? "", frontText ?? ""].joined(separator: " ")) + " " + tags.joined(separator: " ")
            let w = words(other)
            id.otherAnimal = otherAnimalWords.first { $0.contains(" ") || $0.contains("'") ? other.contains($0) : w.contains($0) }
                ?? (tags.contains { $0.contains("bird") || $0.contains("rodent") || $0.contains("fish-food") } ? "autre animal" : nil)
        }
        if cat > 0 && dog > 0 { id.ambiguous = true }
        else if cat >= 1 { id.species = .cat }
        else if dog >= 1 { id.species = .dog }

        // Stade de vie : seulement avec une espece (junior n'est pas un chat).
        let all = fold([name, declaration, frontText].compactMap { $0 }.joined(separator: " ")) + " " + tags.joined(separator: " ")
        let allWords = words(all)
        if youngWords.contains(where: { $0.contains(" ") || $0.contains("-") || $0.contains("'") ? all.contains($0) : allWords.contains($0) }) {
            id.lifeStage = .young
        } else if seniorWords.contains(where: { allWords.contains($0) }) {
            id.lifeStage = .senior
        } else if adultWords.contains(where: { allWords.contains($0) }) {
            id.lifeStage = .adult
        }

        let kindText = fold([declaration, name, frontText].compactMap { $0 }.joined(separator: " ")) + " " + tags.joined(separator: " ")
        if ["aliment complementaire", "complementary", "erganzungsfutter", "erganzungsfuttermittel", "aanvullend"].contains(where: kindText.contains) {
            id.kind = .complementary
        } else if ["friandise", "treat", "snack", "leckerli", "sticks"].contains(where: kindText.contains) {
            id.kind = .treat
        } else if ["aliment complet", "complete feed", "complete pet food", "complete food", "alleinfutter", "volledig", "alimento completo"].contains(where: kindText.contains) {
            id.kind = .complete
        }

        if let m = moisture { id.format = m >= 40 ? .wet : .dry }
        else {
            let f = kindText
            if ["croquette", "croquettes", "dry", "kibble", "trockenfutter", "brokjes", "crocchette", "pienso"].contains(where: f.contains) { id.format = .dry }
            else if ["pate", "patee", "mousse", "sachet", "terrine", "emince", "wet", "nassfutter", "gelee", "sauce", "gravy", "jelly", "boite", "bocconcini"].contains(where: { words(f).contains($0) }) { id.format = .wet }
        }
        return id
    }

    private static let frLocale = Locale(identifier: "fr_FR")

    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: frLocale)
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "’", with: "'")
    }
}
