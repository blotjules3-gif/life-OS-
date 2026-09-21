import Foundation

/// Horloge Tabata de la montre, calculee depuis l'heure de depart.
///
/// Pure et sans minuteur: on donne le temps ecoule, elle dit ou on en est.
/// C'est ce qui permet a la seance de rester juste quand l'ecran s'eteint au
/// poignet, meme lecon que le minuteur de l'iPhone.
struct TabataClock: Equatable {
    var work = 20
    var rest = 10
    var rounds = 8

    enum Phase: Equatable { case work, rest, done }

    struct State: Equatable {
        let phase: Phase
        let round: Int          // 1...rounds
        let remaining: Int      // secondes restantes dans la phase
    }

    /// Pas de repos apres la derniere serie.
    var totalSeconds: Int { rounds * (work + rest) - rest }

    func state(elapsed: Int) -> State {
        guard work > 0, rounds > 0 else { return State(phase: .done, round: rounds, remaining: 0) }
        let e = max(0, elapsed)
        if e >= totalSeconds { return State(phase: .done, round: rounds, remaining: 0) }
        let cycle = work + rest
        let round = e / cycle + 1
        let inCycle = e % cycle
        if inCycle < work {
            return State(phase: .work, round: round, remaining: work - inCycle)
        }
        return State(phase: .rest, round: round, remaining: cycle - inCycle)
    }
}
