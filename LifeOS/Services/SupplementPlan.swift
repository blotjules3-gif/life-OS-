import Foundation

// MARK: - Recommandations de compléments personnalisées (dosage + raison + timing)

struct SuppRecoItem: Identifiable, Hashable {
    let name: String
    let dosage: String      // ex: "5 g / jour"
    let reason: String      // ex: "Force & volume musculaire"
    var id: String { name }

    var reco: SuppReco { SupplementAdvisor.reco(for: name) }
}

enum SupplementPlan {
    /// Liste recommandée selon l'objectif et le sexe (connus du profil).
    static func recommended(goal: String, gender: String) -> [SuppRecoItem] {
        var items: [SuppRecoItem] = [
            .init(name: "Vitamine D", dosage: "2000 UI / jour", reason: "Immunité, os, humeur (carence très fréquente)"),
            .init(name: "Oméga 3", dosage: "2 g / jour", reason: "Cœur, cerveau, anti-inflammatoire"),
            .init(name: "Magnésium", dosage: "300 mg / soir", reason: "Sommeil, récupération, anti-stress"),
        ]
        switch goal {
        case "Prise de muscle":
            items.append(.init(name: "Créatine", dosage: "5 g / jour", reason: "Force & volume musculaire (le plus prouvé)"))
            items.append(.init(name: "Whey", dosage: "30 g post-séance", reason: "Atteindre ton quota de protéines"))
        case "Perte de gras":
            items.append(.init(name: "Whey", dosage: "30 g / jour", reason: "Satiété + préserver le muscle"))
            items.append(.init(name: "Multivitamines", dosage: "1 / jour", reason: "Combler les carences en déficit calorique"))
        case "Force":
            items.append(.init(name: "Créatine", dosage: "5 g / jour", reason: "Force maximale & récupération"))
        default: // Forme générale / maintien
            items.append(.init(name: "Multivitamines", dosage: "1 / jour", reason: "Couvre les bases au quotidien"))
            items.append(.init(name: "Probiotiques", dosage: "1 / jour", reason: "Digestion & immunité"))
        }
        if gender == "femme" {
            items.append(.init(name: "Fer", dosage: "14 mg / jour", reason: "Compense les pertes du cycle"))
            items.append(.init(name: "Collagène", dosage: "10 g / jour", reason: "Peau, cheveux, articulations"))
        } else {
            items.append(.init(name: "Zinc", dosage: "15 mg / soir", reason: "Testostérone, immunité, récupération"))
        }
        return items
    }

    /// Le reste du catalogue (pour « ajouter autre chose »).
    static let extra = [
        "Vitamine C", "Vitamine B12", "Ashwagandha", "Curcuma", "Ginseng", "Mélatonine",
        "Spiruline", "Coenzyme Q10", "Calcium", "Potassium", "Vitamine K2", "Glucosamine", "Rhodiola", "Iode"
    ]
}
