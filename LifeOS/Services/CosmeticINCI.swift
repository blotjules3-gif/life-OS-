import Foundation

/// Referentiel INCI de LifeOS (version 1): ingredients cosmetiques COURANTS que
/// LifeOS sait reconnaitre et qu'il ne classe pas "a surveiller".
///
/// Pourquoi il existe (audit du 28 septembre): la note cosmetique retirait des
/// points pour les ingredients classes, et donnait donc 100 a une liste qu'elle ne
/// comprenait pas du tout ("INGREDIENT_UNRECOGNISED_123" -> 100). Ne rien trouver
/// ne prouve rien. Une note n'est donnee que si la plupart des ingredients sont
/// RECONNUS (classes ou dans ce referentiel); sinon "non evalue", avec la liste.
///
/// "Reconnu, non classe" veut dire: ingredient connu, pas dans la liste LifeOS des
/// ingredients a surveiller. Ce n'est pas un certificat d'innocuite.
enum CosmeticINCI {

    static let version = "INCI LifeOS 1.1 + CosIng (29 sept. 2026)"

    /// Liste officielle des noms INCI de la Commission europeenne (base CosIng,
    /// 33 602 noms, releve du 24 sept. 2026, licence CC BY 4.0). Elle dit qu'un nom
    /// EXISTE, pas qu'un ingredient est sans risque: CosIng "a une valeur
    /// informative et aucune valeur legale". Chargee une fois, a la premiere note.
    static let cosing: Set<String> = {
        guard let url = Bundle.main.url(forResource: "cosing_inci_names", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { String($0) })
    }()

    /// Part minimale d'ingredients reconnus pour noter.
    static let minimumCoverage = 0.8
    /// Nombre minimal d'ingredients reconnus (une liste de deux mots ne suffit pas).
    static let minimumRecognized = 3

    static let common: Set<String> = [
        // Solvants, humectants
        "aqua", "water", "eau", "glycerin", "glycerine", "propylene glycol", "butylene glycol", "propanediol",
        "pentylene glycol", "hexylene glycol", "caprylyl glycol", "1,2-hexanediol", "sorbitol", "alcohol",
        "alcohol denat", "ethanol", "isopropyl alcohol", "dipropylene glycol", "glycereth-26", "urea",
        "sodium pca", "sodium lactate", "lactic acid", "betaine", "panthenol", "d-panthenol", "allantoin",
        "hyaluronic acid", "sodium hyaluronate", "niacinamide", "tocopherol", "tocopheryl acetate",
        "ascorbic acid", "ascorbyl glucoside", "retinol", "retinyl palmitate", "squalane", "ceramide np",
        "ceramide ap", "ceramide eop", "phytosphingosine", "cholesterol", "bisabolol", "caffeine",
        "salicylic acid", "glycolic acid", "zinc pca", "adenosine", "biotin", "inositol", "ectoin",
        // Tensioactifs
        "sodium laureth sulfate", "sodium lauroyl sarcosinate", "cocamidopropyl betaine", "coco-betaine",
        "coco betaine", "decyl glucoside", "lauryl glucoside", "coco-glucoside", "coco glucoside",
        "sodium cocoyl isethionate", "sodium coco-sulfate", "sodium lauroyl methyl isethionate",
        "disodium laureth sulfosuccinate", "sodium cocoamphoacetate", "disodium cocoamphodiacetate",
        "ammonium lauryl sulfate", "ammonium laureth sulfate", "sodium c14-16 olefin sulfonate",
        "cocamide mea", "cocamide dea", "peg-7 glyceryl cocoate", "peg-40 hydrogenated castor oil",
        "polysorbate 20", "polysorbate 60", "polysorbate 80", "peg-200 hydrogenated glyceryl palmate",
        "peg-4 rapeseedamide", "glycol distearate", "laureth-4", "poloxamer 184",
        // Emollients, cires, alcools gras
        "cetearyl alcohol", "cetyl alcohol", "stearyl alcohol", "behenyl alcohol", "glyceryl stearate",
        "glyceryl stearate se", "peg-100 stearate", "cetearyl glucoside", "ceteareth-20", "steareth-2",
        "steareth-21", "isopropyl myristate", "isopropyl palmitate", "caprylic/capric triglyceride",
        "caprylic", "capric triglyceride", "coco-caprylate", "coco-caprylate/caprate", "c12-15 alkyl benzoate",
        "dicaprylyl carbonate", "dicaprylyl ether", "ethylhexyl palmitate", "octyldodecanol", "isononyl isononanoate",
        "isohexadecane", "isododecane", "hydrogenated polyisobutene", "paraffinum liquidum", "mineral oil",
        "petrolatum", "paraffin", "cera alba", "beeswax", "cera microcristallina", "microcrystalline wax",
        "candelilla cera", "copernicia cerifera cera", "carnauba wax", "lanolin", "cetyl palmitate",
        "myristyl myristate", "stearic acid", "palmitic acid", "myristic acid", "lauric acid", "oleic acid",
        "hydrogenated vegetable oil", "shea butter", "cocoa butter", "hydrogenated castor oil",
        // Silicones (hors D4/D5 classes)
        "dimethicone", "dimethiconol", "amodimethicone", "cyclohexasiloxane", "phenyl trimethicone",
        "cetyl dimethicone", "bis-peg-18 methyl ether dimethyl silane", "dimethicone crosspolymer",
        "trimethylsiloxysilicate", "peg-12 dimethicone",
        // Epaississants, polymeres
        "xanthan gum", "carbomer", "acrylates/c10-30 alkyl acrylate crosspolymer", "acrylates copolymer",
        "hydroxyethylcellulose", "hydroxypropyl methylcellulose", "cellulose", "sclerotium gum", "guar gum",
        "guar hydroxypropyltrimonium chloride", "polyquaternium-7", "polyquaternium-10", "polyquaternium-11",
        "polyquaternium-37", "sodium polyacrylate", "ammonium acryloyldimethyltaurate/vp copolymer",
        "polyacrylate crosspolymer-6", "sodium acrylates copolymer", "pvp", "vp/va copolymer",
        "silica", "kaolin", "bentonite", "talc", "mica", "magnesium aluminum silicate", "starch",
        "zea mays starch", "tapioca starch", "aluminum starch octenylsuccinate", "nylon-12",
        // Conditionneurs
        "behentrimonium chloride", "cetrimonium chloride", "stearamidopropyl dimethylamine",
        "hydrolyzed wheat protein", "hydrolyzed keratin", "hydrolyzed silk", "hydrolyzed collagen",
        // Ajusteurs de pH, sels, chelatants
        "citric acid", "sodium citrate", "sodium hydroxide", "potassium hydroxide", "triethanolamine",
        "aminomethyl propanol", "sodium chloride", "magnesium sulfate", "sodium sulfate", "disodium edta",
        "tetrasodium edta", "tetrasodium glutamate diacetate", "trisodium ethylenediamine disuccinate",
        "sodium phytate", "phytic acid", "sodium gluconate", "gluconolactone", "sodium bicarbonate",
        "calcium carbonate", "zinc oxide", "titanium dioxide", "iron oxides", "aluminum hydroxide",
        "aluminum chlorohydrate", "potassium alum", "magnesium stearate", "zinc stearate",
        // Conservateurs non classes par LifeOS 1.0
        "phenoxyethanol", "ethylhexylglycerin", "sodium benzoate", "potassium sorbate", "benzoic acid",
        "sorbic acid", "dehydroacetic acid", "sodium dehydroacetate", "chlorphenesin",
        "methylparaben", "ethylparaben", "sodium levulinate", "sodium anisate", "levulinic acid",
        "p-anisic acid", "caprylhydroxamic acid", "piroctone olamine", "zinc pyrithione",
        // Filtres UV non classes par LifeOS 1.0
        "ethylhexyl salicylate", "octocrylene", "butyl methoxydibenzoylmethane", "avobenzone",
        "bis-ethylhexyloxyphenol methoxyphenyl triazine", "ethylhexyl triazone", "diethylamino hydroxybenzoyl hexyl benzoate",
        "methylene bis-benzotriazolyl tetramethylbutylphenol", "drometrizole trisiloxane", "ethylhexyl methoxycinnamate",
        // Divers
        "sodium hydroxide", "maltodextrin", "sucrose", "glucose", "fructose", "honey", "mel", "lecithin",
        "sodium stearate", "sodium palmate", "sodium cocoate", "sodium tallowate", "sodium palm kernelate",
        "glycine", "arginine", "lysine", "serine", "proline", "alanine", "sodium lauroyl lactylate",
        "polyglyceryl-4 caprate", "polyglyceryl-3 diisostearate", "sorbitan olivate", "cetearyl olivate",
        "sorbitan stearate", "sorbitan oleate", "sucrose stearate", "hydrogenated lecithin", "menthol",
        "camphor", "linalyl acetate",
    ]

    /// Motifs de noms reconnus: huiles, beurres, extraits vegetaux, colorants CI.
    static let patterns: [String] = [
        #"(seed|fruit|kernel|nut|leaf|flower|root|peel|bark|germ|oil|butter|extract|water|juice|powder|wax|cera)$"#,
        #"^ci [0-9]{5}$"#,                    // colorants: CI 77891...
        #"^(parfum|fragrance|aroma|flavor)$"#,
        #"^(hydrolyzed|hydrogenated) "#,
        // Nom americain des colorants, ecrit apres le CI: "CI 19140/Yellow 5".
        #"^(yellow|red|blue|green|violet|orange|black|brown|ext\. violet) [0-9]{1,2}( lake)?$"#,
    ]

    enum Status: Equatable { case flagged, known, unknown }

    /// Nettoyage d'un nom tel qu'il sort d'une liste d'etiquette.
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
            .replacingOccurrences(of: #"[0-9]+([.,][0-9]+)?\s?%"#, with: "", options: .regularExpression)
            // "Ingredients:" n'est retire qu'avec ses deux points, sinon un nom qui
            // commence par "ingredient" serait ampute.
            .replacingOccurrences(of: #"^(\+/-|may contain|peut contenir)\s*:?\s*|^(ingredients?|ingrédients?)\s*:\s*"#, with: "", options: .regularExpression)
            // Orthographe britannique de l'etiquette: CosIng ecrit "aluminum".
            .replacingOccurrences(of: "aluminium", with: "aluminum")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-")))
        return s
    }

    static func isKnown(_ name: String) -> Bool {
        if common.contains(name) || cosing.contains(name) { return true }
        return patterns.contains { name.range(of: $0, options: .regularExpression) != nil }
    }
}

// MARK: - Annexes du reglement cosmetique (CosIng)

/// Annexes II (interdits) et III (restreints) du reglement (CE) 1223/2009, telles que
/// publiees par CosIng (Commission europeenne, CC BY 4.0). Genere par
/// `tools/cosing/fetch_annexes.py`. Seules les entrees qu'une etiquette peut porter
/// (nom INCI) sont gardees.
enum CosmeticRegulation {
    enum Kind: String { case prohibited, allergen, restricted }
    struct Entry: Equatable { let annex: String; let ref: String; let kind: Kind }

    static let version = "CosIng annexes II et III (relevé du 30 sept. 2026)"

    static let entries: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "cosing_annexes", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: Entry] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let kind = Kind(rawValue: f[3]) else { continue }
            out[CosmeticINCI.normalize(f[0])] = Entry(annex: f[1], ref: f[2], kind: kind)
        }
        return out
    }()

    static func lookup(_ normalizedName: String) -> Entry? { entries[normalizedName] }
}
