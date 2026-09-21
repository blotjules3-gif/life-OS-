import Foundation

/// Calcul local du Score d'Énergie (0–100), 100 % on-device.
///
/// Portage de l'algo backend (`backend/app/services/energy.py`) qui tournait
/// jusqu'ici sur Railway. Depuis Option C, le score est calculé sur l'iPhone
/// à partir des données SwiftData déjà présentes localement (sommeil, humeur,
/// eau, habitudes du jour).
enum EnergyScore {

    /// Résultat consolidé — utilisable directement en UI.
    struct Result: Equatable {
        let score: Int         // 0…100
        let label: String      // Excellent / Bon / Correct / Faible / Très faible
        let colorHex: String   // "#RRGGBB"
        /// Part des criteres reellement renseignes, 0…1. Un score calcule
        /// sur un seul critere ne vaut pas un score calcule sur cinq, et
        /// l'ecran doit pouvoir le dire.
        let coverage: Double
    }

    /// Snapshot brut d'entrée du calcul — évite d'aller lire les Query 6 fois.
    struct Input {
        var sleepHours: Double?     // heures dormies dernière nuit
        var sleepQuality: Int?      // 1…5
        var mood: Int?              // 1…5
        var fatigue: Int?           // 1 (reposé) … 5 (épuisé)
        var waterML: Int?
        var habitsDone: Int?
        var habitsTotal: Int?
    }

    // MARK: - Calcul du score

    /// En dessous de cette part de criteres renseignes, un score n'a pas de
    /// sens et vaut mieux ne pas etre affiche du tout.
    static let minimumCoverage = 0.35

    /// Ponderation, heritee du backend Python d'origine:
    /// sommeil qualite 30 · sommeil duree 10 · hydratation 20 · habitudes 20 ·
    /// humeur 15 · anti-fatigue 5.
    ///
    /// Le defaut corrige: le total etait divise par 100 quoi qu'il arrive,
    /// meme quand un seul critere etait renseigne. Quelqu'un qui notait
    /// uniquement une humeur a 5 sur 5 obtenait 15 sur 100, affiche
    /// "Tres faible": l'app annoncait un effondrement d'energie a quelqu'un
    /// qui venait de dire qu'il allait tres bien. Et comme `fatigue` n'est
    /// jamais renseigne cote iOS, meme une journee complete plafonnait a 95.
    ///
    /// Le score est donc rapporte aux criteres REELLEMENT renseignes, et la
    /// couverture est rendue avec lui.
    static func compute(_ input: Input) -> Result {
        var earned = 0.0
        var available = 0.0

        func add(_ ratio: Double, weight: Double) {
            earned += min(max(ratio, 0), 1) * weight
            available += weight
        }

        if let q = input.sleepQuality { add(Double(q) / 5.0, weight: 30) }
        if let h = input.sleepHours   { add(h / 8.0, weight: 10) }
        if let ml = input.waterML     { add(Double(ml) / 2500.0, weight: 20) }
        if let total = input.habitsTotal, total > 0, let done = input.habitsDone {
            add(Double(done) / Double(total), weight: 20)
        }
        if let m = input.mood         { add(Double(m) / 5.0, weight: 15) }
        if let f = input.fatigue      { add(Double(6 - f) / 5.0, weight: 5) }

        guard available > 0 else {
            return Result(score: 0, label: label(0), colorHex: colorHex(0), coverage: 0)
        }
        let pct = Int((earned / available * 100).rounded().clamped(to: 0...100))
        return Result(score: pct, label: label(pct), colorHex: colorHex(pct),
                      coverage: available / 100)
    }

    // MARK: - App Group publish (pour EnergyScoreWidget)

    /// Persiste le résultat courant dans App Group defaults pour lecture
    /// par le widget. Appeler après chaque calcul depuis l'app :
    ///   `EnergyScore.publishToAppGroup(EnergyScore.today(ctx))`
    /// puis `WidgetCenter.shared.reloadTimelines(ofKind: "EnergyScoreWidget")`
    /// pour forcer le refresh visuel.
    static func publishToAppGroup(_ result: Result?) {
        guard let grp = UserDefaults(suiteName: "group.com.chifandco.lifeos") else { return }
        if let r = result {
            grp.set(r.score, forKey: "energyScore.value")
            grp.set(r.label, forKey: "energyScore.label")
            grp.set(r.colorHex, forKey: "energyScore.colorHex")
            grp.set(Date().timeIntervalSince1970, forKey: "energyScore.updatedAt")
        } else {
            grp.removeObject(forKey: "energyScore.value")
            grp.removeObject(forKey: "energyScore.label")
            grp.removeObject(forKey: "energyScore.colorHex")
        }
    }

    // MARK: - Palettes

    private static func label(_ score: Int) -> String {
        switch score {
        case 85...: return "Excellent"
        case 70...: return "Bon"
        case 50...: return "Correct"
        case 30...: return "Faible"
        default:    return "Très faible"
        }
    }

    private static func colorHex(_ score: Int) -> String {
        switch score {
        case 85...: return "#34C759"
        case 70...: return "#30D158"
        case 50...: return "#FF9F0A"
        case 30...: return "#FF6B35"
        default:    return "#FF3B30"
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
