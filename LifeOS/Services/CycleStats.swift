import Foundation

/// Statistiques de cycle calculees a partir des jours de flux enregistres.
///
/// Le defaut corrige: l'ecran Historique mesurait l'ecart entre deux ENTREES
/// consecutives avec flux, puis ne gardait que les ecarts de plus de 20 jours.
/// Or on enregistre son flux plusieurs jours de suite. Les cinq derniers
/// ecarts valaient donc 1 jour, tous rejetes, et "Durée moyenne" ne
/// s'affichait jamais pour quelqu'un qui remplit l'app tous les jours,
/// c'est a dire l'utilisatrice la plus assidue.
///
/// La bonne unite n'est pas le jour enregistre, c'est le REGLE: on regroupe
/// les jours qui se suivent, puis on mesure d'un debut de regles au suivant.
enum CycleStats {

    struct Summary: Equatable {
        /// Duree moyenne en jours, sur les cycles retenus.
        let averageDays: Double
        /// Nombre de cycles ayant servi au calcul, affiche pour que la
        /// moyenne soit lisible: une moyenne sur un cycle ne veut rien dire.
        let cycleCount: Int
        /// Ecart entre le cycle le plus court et le plus long.
        let shortestDays: Int
        let longestDays: Int

        var isRegular: Bool { longestDays - shortestDays <= 7 }
    }

    /// Un trou d'un jour ne coupe pas les regles en deux: on oublie de
    /// remplir. Deux jours de silence, en revanche, sont une interruption.
    static let maxGapWithinPeriod = 2

    /// Bornes de plausibilite. En dehors, c'est une saisie fausse ou une
    /// longue interruption d'usage, pas un cycle: la moyenne ne doit pas
    /// etre tiree par un "cycle" de six mois.
    static let plausibleRange = 15...60

    /// Nombre de cycles pris en compte, les plus recents.
    static let window = 6

    /// Premiers jours de chaque episode de regles, du plus ancien au plus
    /// recent.
    static func periodStarts(flowDays: [Date], calendar: Calendar = .current) -> [Date] {
        let days = Set(flowDays.map { calendar.startOfDay(for: $0) }).sorted()
        guard var previous = days.first else { return [] }
        var starts: [Date] = [previous]
        for day in days.dropFirst() {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap > maxGapWithinPeriod { starts.append(day) }
            previous = day
        }
        return starts
    }

    /// Duree moyenne du cycle, ou `nil` s'il n'y a pas encore de quoi la dire.
    static func summary(flowDays: [Date], calendar: Calendar = .current) -> Summary? {
        let starts = periodStarts(flowDays: flowDays, calendar: calendar)
        guard starts.count >= 2 else { return nil }

        var lengths: [Int] = []
        for (a, b) in zip(starts, starts.dropFirst()) {
            // En jours de calendrier, jamais en secondes: aux changements
            // d'heure un cycle de 28 jours ne fait pas 28 x 86400 secondes.
            let d = calendar.dateComponents([.day], from: a, to: b).day ?? 0
            if plausibleRange.contains(d) { lengths.append(d) }
        }
        let recent = Array(lengths.suffix(window))
        guard let low = recent.min(), let high = recent.max() else { return nil }

        return Summary(
            averageDays: Double(recent.reduce(0, +)) / Double(recent.count),
            cycleCount: recent.count,
            shortestDays: low,
            longestDays: high
        )
    }
}
