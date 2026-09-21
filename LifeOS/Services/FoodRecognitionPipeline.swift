import Foundation
import UIKit
@preconcurrency import Vision

/// Reconnaissance d'un plat en photo, SANS aucune cle d'API.
///
/// Trois etages, tous gratuits:
///   1. Vision, sur l'appareil, reconnait ce qu'il y a dans l'image.
///   2. OpenFoodFacts donne les VRAIES valeurs pour 100 g de cet aliment.
///   3. Une portion par defaut, affichee et modifiable, convertit en calories.
///
/// Ce que ca remplace: une table de correspondance ou "pizza" valait toujours
/// 285 kcal, quelle que soit la part. Le chiffre ne venait de nulle part.
///
/// Ce que ca n'est PAS: une mesure. On ne sait pas peser une assiette sur une
/// photo. La portion est une HYPOTHESE, elle est annoncee comme telle et
/// l'utilisateur la corrige. Mieux vaut un chiffre honnete et modifiable
/// qu'une fausse precision.
enum FoodRecognitionPipeline {

    /// D'ou vient la valeur nutritionnelle, pour pouvoir le dire a l'ecran.
    enum Source: String {
        case openFoodFacts   // valeurs reelles, base publique
        case estimate        // repli hors ligne, ordre de grandeur
    }

    struct DetectedFood: Identifiable, Equatable {
        let id = UUID()
        var name: String            // nom francais affiche
        var confidence: Double      // 0...1, confiance de la reconnaissance
        var grams: Double           // portion supposee, modifiable
        var kcal100: Double         // pour 100 g
        var protein100: Double
        var carbs100: Double
        var fat100: Double
        var source: Source

        var kcal: Int      { Int((kcal100    * grams / 100).rounded()) }
        var protein: Double { (protein100 * grams / 100 * 10).rounded() / 10 }
        var carbs: Double   { (carbs100   * grams / 100 * 10).rounded() / 10 }
        var fat: Double     { (fat100     * grams / 100 * 10).rounded() / 10 }

        static func == (l: DetectedFood, r: DetectedFood) -> Bool { l.id == r.id }
    }

    // MARK: - Dictionnaire des aliments

    /// label Vision (anglais) → (nom FR, terme de recherche OFF, portion type en g)
    ///
    /// La portion vient de ce qu'on sert habituellement, pas d'une mesure: une
    /// part de pizza fait autour de 125 g, une banane epluchee autour de 120 g.
    struct FoodKey {
        let match: String
        let fr: String
        let query: String
        let grams: Double
    }

    static let foods: [FoodKey] = [
        .init(match: "pizza",       fr: "Pizza",            query: "pizza",            grams: 125),
        .init(match: "cheeseburger",fr: "Burger",           query: "hamburger",        grams: 200),
        .init(match: "hamburger",   fr: "Burger",           query: "hamburger",        grams: 200),
        .init(match: "hotdog",      fr: "Hot-dog",          query: "hot dog",          grams: 110),
        .init(match: "hot dog",     fr: "Hot-dog",          query: "hot dog",          grams: 110),
        .init(match: "banana",      fr: "Banane",           query: "banane",           grams: 120),
        .init(match: "orange",      fr: "Orange",           query: "orange",           grams: 130),
        .init(match: "lemon",       fr: "Citron",           query: "citron",           grams: 60),
        .init(match: "strawberr",   fr: "Fraises",          query: "fraise",           grams: 150),
        .init(match: "pineapple",   fr: "Ananas",           query: "ananas",           grams: 165),
        .init(match: "apple",       fr: "Pomme",            query: "pomme",            grams: 180),
        .init(match: "granny smith",fr: "Pomme",            query: "pomme",            grams: 180),
        .init(match: "grape",       fr: "Raisin",           query: "raisin",           grams: 150),
        .init(match: "watermelon",  fr: "Pastèque",         query: "pasteque",         grams: 280),
        .init(match: "avocado",     fr: "Avocat",           query: "avocat",           grams: 100),
        .init(match: "broccoli",    fr: "Brocoli",          query: "brocoli",          grams: 150),
        .init(match: "cauliflower", fr: "Chou-fleur",       query: "chou-fleur",       grams: 150),
        .init(match: "cucumber",    fr: "Concombre",        query: "concombre",        grams: 120),
        .init(match: "mushroom",    fr: "Champignons",      query: "champignon",       grams: 100),
        .init(match: "bell pepper", fr: "Poivron",          query: "poivron",          grams: 120),
        .init(match: "carrot",      fr: "Carottes",         query: "carotte",          grams: 120),
        .init(match: "tomato",      fr: "Tomate",           query: "tomate",           grams: 120),
        .init(match: "salad",       fr: "Salade",           query: "salade verte",     grams: 150),
        .init(match: "bagel",       fr: "Bagel",            query: "bagel",            grams: 100),
        .init(match: "pretzel",     fr: "Bretzel",          query: "bretzel",          grams: 60),
        .init(match: "croissant",   fr: "Croissant",        query: "croissant",        grams: 65),
        .init(match: "french loaf", fr: "Pain",             query: "baguette",         grams: 80),
        .init(match: "baguette",    fr: "Pain",             query: "baguette",         grams: 80),
        .init(match: "bread",       fr: "Pain",             query: "pain",             grams: 80),
        .init(match: "rice",        fr: "Riz",              query: "riz cuit",         grams: 200),
        .init(match: "pasta",       fr: "Pâtes",            query: "pates cuites",     grams: 220),
        .init(match: "spaghetti",   fr: "Pâtes",            query: "spaghetti",        grams: 220),
        .init(match: "noodle",      fr: "Nouilles",         query: "nouilles",         grams: 220),
        .init(match: "sushi",       fr: "Sushi",            query: "sushi",            grams: 180),
        .init(match: "taco",        fr: "Taco",             query: "taco",             grams: 150),
        .init(match: "burrito",     fr: "Burrito",          query: "burrito",          grams: 250),
        .init(match: "sandwich",    fr: "Sandwich",         query: "sandwich",         grams: 200),
        .init(match: "soup",        fr: "Soupe",            query: "soupe",            grams: 300),
        .init(match: "steak",       fr: "Steak",            query: "steak boeuf",      grams: 150),
        .init(match: "chicken",     fr: "Poulet",           query: "poulet",           grams: 150),
        .init(match: "fish",        fr: "Poisson",          query: "poisson",          grams: 150),
        .init(match: "salmon",      fr: "Saumon",           query: "saumon",           grams: 150),
        .init(match: "shrimp",      fr: "Crevettes",        query: "crevette",         grams: 120),
        .init(match: "egg",         fr: "Œufs",             query: "oeuf",             grams: 110),
        .init(match: "omelet",      fr: "Omelette",         query: "omelette",         grams: 160),
        .init(match: "cheese",      fr: "Fromage",          query: "fromage",          grams: 40),
        .init(match: "yogurt",      fr: "Yaourt",           query: "yaourt",           grams: 125),
        .init(match: "ice cream",   fr: "Glace",            query: "creme glacee",     grams: 100),
        .init(match: "chocolate",   fr: "Chocolat",         query: "chocolat",         grams: 30),
        .init(match: "cookie",      fr: "Biscuits",         query: "biscuit",          grams: 40),
        .init(match: "cake",        fr: "Gâteau",           query: "gateau",           grams: 100),
        .init(match: "donut",       fr: "Donut",            query: "donut",            grams: 70),
        .init(match: "pancake",     fr: "Pancakes",         query: "pancake",          grams: 150),
        .init(match: "waffle",      fr: "Gaufre",           query: "gaufre",           grams: 90),
        .init(match: "french fries",fr: "Frites",           query: "frites",           grams: 150),
        .init(match: "potato",      fr: "Pommes de terre",  query: "pomme de terre",   grams: 200),
        .init(match: "popcorn",     fr: "Popcorn",          query: "popcorn",          grams: 30),
        .init(match: "coffee",      fr: "Café",             query: "cafe",             grams: 200),
        .init(match: "beer",        fr: "Bière",            query: "biere",            grams: 250),
        .init(match: "wine",        fr: "Vin",              query: "vin",              grams: 150),
        .init(match: "juice",       fr: "Jus de fruit",     query: "jus orange",       grams: 250),
        .init(match: "soda",        fr: "Soda",             query: "soda",             grams: 330),
        .init(match: "milk",        fr: "Lait",             query: "lait",             grams: 250),
    ]

    /// Ordres de grandeur pour 100 g, quand OpenFoodFacts ne repond pas.
    /// Volontairement grossiers: c'est un repli hors ligne, pas une reference.
    private static let fallback100: [String: (Double, Double, Double, Double)] = [
        "Pizza": (266, 11, 33, 10),        "Burger": (250, 13, 19, 13),
        "Banane": (89, 1.1, 23, 0.3),      "Pomme": (52, 0.3, 14, 0.2),
        "Riz": (130, 2.7, 28, 0.3),        "Pâtes": (158, 5.8, 31, 0.9),
        "Poulet": (165, 31, 0, 3.6),       "Frites": (312, 3.4, 41, 15),
        "Salade": (15, 1.4, 2.9, 0.2),     "Pain": (265, 9, 49, 3.2),
    ]

    // MARK: - Etape 1: reconnaissance sur l'appareil

    /// Labels alimentaires reconnus, du plus sur au moins sur, sans doublon.
    static func recognise(_ image: UIImage, maxItems: Int = 3) async -> [(FoodKey, Double)] {
        guard let cg = image.cgImage else { return [] }
        let observations: [VNClassificationObservation] = await withCheckedContinuation { cont in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
                cont.resume(returning: request.results ?? [])
            }
        }
        var out: [(FoodKey, Double)] = []
        var seen = Set<String>()
        for o in observations where o.confidence > 0.03 {
            let label = o.identifier.lowercased()
            // Le mot cle le PLUS LONG gagne. En prenant la premiere
            // correspondance, "cake" (declare avant) captait "pancake": une
            // photo de pancakes etait enregistree comme un gateau, avec la
            // mauvaise portion et donc les mauvaises calories.
            guard let k = foods
                .filter({ label.contains($0.match) })
                .max(by: { $0.match.count < $1.match.count })
            else { continue }
            guard !seen.contains(k.fr) else { continue }
            seen.insert(k.fr)
            out.append((k, Double(o.confidence)))
            if out.count >= maxItems { break }
        }
        return out
    }

    // MARK: - Etape 2 et 3: vraies valeurs + portion

    /// Reconnait puis chiffre. Rend une liste vide si rien d'alimentaire n'est vu.
    static func analyse(_ image: UIImage) async -> [DetectedFood] {
        let found = await recognise(image)
        var items: [DetectedFood] = []
        for (key, confidence) in found {
            let nutrition = await lookup(key)
            items.append(DetectedFood(
                name: key.fr,
                confidence: confidence,
                grams: key.grams,
                kcal100: nutrition.0, protein100: nutrition.1,
                carbs100: nutrition.2, fat100: nutrition.3,
                source: nutrition.4
            ))
        }
        return items
    }

    /// Valeurs pour 100 g: OpenFoodFacts d'abord, repli local sinon.
    ///
    /// On prend la MEDIANE des premiers resultats plutot que le premier: la
    /// base est collaborative et le premier produit peut etre une aberration
    /// (une pizza a 900 kcal/100 g saisie de travers).
    static func lookup(_ key: FoodKey) async -> (Double, Double, Double, Double, Source) {
        let products = await FoodSearchService.search(key.query)
        let usable = products.filter { $0.kcal > 0 && $0.kcal < 900 }.prefix(9)
        if usable.count >= 3 {
            func med(_ v: [Double]) -> Double {
                let s = v.sorted(); return s[s.count / 2]
            }
            return (med(usable.map { Double($0.kcal) }),
                    med(usable.map(\.protein)),
                    med(usable.map(\.carbs)),
                    med(usable.map(\.fat)),
                    .openFoodFacts)
        }
        if let f = fallback100[key.fr] { return (f.0, f.1, f.2, f.3, .estimate) }
        return (200, 8, 25, 7, .estimate)
    }
}
