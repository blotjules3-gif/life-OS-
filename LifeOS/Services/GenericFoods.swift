import Foundation

/// Aliments GENERIQUES (non emballes) de la table Ciqual 2020 de l'ANSES
/// (Licence Ouverte Etalab, 2 298 aliments avec energie), embarquee dans l'app.
///
/// Pourquoi: un plat fait maison ("haricots verts", "poulet rôti") etait chiffre
/// avec la mediane des produits EMBALLES trouves par mot cle dans Open Food Facts,
/// c'est a dire des plats prepares et des conserves. Ciqual donne la composition
/// de l'aliment lui-meme, cuit ou cru, pour 100 g, hors ligne.
enum GenericFoods {
    struct Food: Identifiable, Equatable {
        let id: Int
        let name: String
        let englishName: String
        let group: String
        let kcal: Double
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        let sugars: Double?
        let fiber: Double?
        let salt: Double?
        let saturatedFat: Double?
    }

    static let source = "Table Ciqual 2020, ANSES (Licence Ouverte)"

    static let all: [Food] = {
        guard let url = Bundle.main.url(forResource: "ciqual_2020", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").dropFirst().compactMap { line in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 12, let id = Int(c[0]), let kcal = Double(c[4]) else { return nil }
            func d(_ i: Int) -> Double? { Double(c[i]) }
            return Food(id: id, name: c[1], englishName: c[2], group: c[3], kcal: kcal, protein: d(5), carbs: d(6),
                        fat: d(7), sugars: d(8), fiber: d(9), salt: d(10), saturatedFat: d(11))
        }
    }()

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
    }

    /// Recherche par mots (francais ou anglais). Tous les mots doivent apparaitre;
    /// un nom qui COMMENCE par le premier mot passe devant, puis le nom le plus
    /// court (l'aliment simple avant ses variantes), puis les formes cuites quand
    /// `cooked` est vrai.
    static func search(_ query: String, limit: Int = 12, cooked: Bool = false) -> [Food] {
        var words: [String] = []
        for part in fold(query).split(whereSeparator: { !$0.isLetter }) where part.count >= 2 {
            let w = String(part)
            // Pluriel simple: "haricots" trouve "haricot".
            words.append(w.hasSuffix("s") && w.count > 3 ? String(w.dropLast()) : w)
        }
        guard !words.isEmpty else { return [] }
        let hits = all.filter { f in
            let hay = fold(f.name + " " + f.englishName)
            return words.allSatisfy { hay.contains($0) }
        }
        func rank(_ f: Food) -> (Int, Int, Int) {
            let n = fold(f.name)
            let starts = n.hasPrefix(words[0]) ? 0 : 1
            let cookedRank = cooked ? ((n.contains("cuit") || n.contains("roti") || n.contains("poele") || n.contains("saute")) ? 0 : 1) : 0
            return (starts, cookedRank, f.name.count)
        }
        return Array(hits.sorted { rank($0) < rank($1) }.prefix(limit))
    }

    static func best(_ query: String, cooked: Bool = true) -> Food? { search(query, limit: 1, cooked: cooked).first }
}
