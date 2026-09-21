import Foundation

/// Liste d'ids stockee en texte ("a,b,c"), lue sans doublon ni id inconnu.
///
/// Un id inconnu reste dans le texte quand un outil disparait d'une mise a
/// jour: il etait invisible et impossible a retirer. Un doublon donnait deux
/// vues au meme identifiant, et SwiftUI les melange a l'animation.
enum HomeOrder {
    static func parse(_ raw: String, valid: Set<String>) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: ",").map(String.init)
            .filter { valid.contains($0) && seen.insert($0).inserted }
    }
}
