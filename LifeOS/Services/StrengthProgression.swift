import Foundation

/// Progression de charge fondee sur les series REELLEMENT faites.
///
/// Avant, le programme etait une liste d'exercices par jour, et le journal de series
/// (Hevvy) proposait toujours "+2,5 kg" quoi qu'il se soit passe. Ce moteur relie les
/// deux : la cible vient du programme ("4×10"), l'historique vient des series logguees,
/// et la decision suit une double progression classique.
///
/// Regles, dans l'ordre :
/// 1. Aucune seance : charge de depart depuis le 1RM du profil si on le connait, sinon
///    on demande une charge "que tu ferais 2 fois de plus".
/// 2. Toutes les series au haut de la fourchette ET effort moyen <= 8,5 : on monte.
/// 3. Haut atteint mais effort au maximum (>= 9,5) : on garde, pour consolider.
/// 4. Sous le bas de la fourchette deux seances de suite : on baisse de 10 %.
/// 5. Sous le bas une seule fois : on refait la meme charge.
/// 6. Sinon : meme charge, une repetition de plus.
enum StrengthProgression {

    struct LoggedSet: Equatable {
        let date: Date
        let exercise: String
        let weight: Double
        let reps: Int
        let rpe: Double
    }

    struct Target: Equatable {
        let sets: Int
        let repLow: Int
        let repHigh: Int
    }

    enum Decision: String, Equatable {
        case start, increase, hold, repeatLoad, deload, addRep
    }

    struct Prescription: Equatable {
        let weight: Double?
        let reps: Int
        let sets: Int
        let decision: Decision
        let reason: String
    }

    /// "Développé couché barre 4×10" → 4 series, 8 à 10 reps. Une cible de force
    /// (6 reps ou moins) garde une fourchette fixe.
    static func target(from label: String) -> Target? {
        guard let r = label.range(of: #"(\d+)×(\d+)$"#, options: .regularExpression) else { return nil }
        let parts = label[r].split(separator: "×").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        let high = parts[1]
        return Target(sets: parts[0], repLow: high <= 6 ? high : max(1, high - 2), repHigh: high)
    }

    /// Pas de charge realiste pour l'exercice.
    static func increment(for exercise: String, weight: Double) -> Double {
        let n = exercise.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let lowerCompound = ["squat", "presse", "souleve", "hip thrust", "hack", "good morning"]
        if lowerCompound.contains(where: n.contains) { return weight < 40 ? 2.5 : 5 }
        if n.contains("haltere") { return 2 }
        return 2.5
    }

    /// Seances d'un exercice : series regroupees par jour, la plus recente d'abord.
    static func sessions(of exercise: String, in sets: [LoggedSet],
                         calendar: Calendar = .current) -> [[LoggedSet]] {
        let key = normalized(exercise)
        let mine = sets.filter { normalized($0.exercise) == key && $0.reps > 0 }
        let byDay = Dictionary(grouping: mine) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { byDay[$0]!.sorted { $0.date < $1.date } }
    }

    static func next(exercise: String, target: Target, history sets: [LoggedSet],
                     profile1RM: Double? = nil) -> Prescription {
        let sessions = self.sessions(of: exercise, in: sets)
        guard let last = sessions.first else {
            if let orm = profile1RM, orm > 0 {
                // Epley inverse, avec 2 reps de marge : charge ~ 1RM / (1 + (reps+2)/30).
                let w = round2(orm / (1 + Double(target.repHigh + 2) / 30))
                return Prescription(weight: w, reps: target.repLow, sets: target.sets, decision: .start,
                                    reason: "Départ calculé depuis ton max de \(fmt(orm)) kg, avec 2 répétitions de marge.")
            }
            return Prescription(weight: nil, reps: target.repLow, sets: target.sets, decision: .start,
                                reason: "Première séance : prends une charge que tu pourrais soulever \(target.repLow + 2) fois.")
        }
        let weight = last.map(\.weight).max() ?? 0
        let working = last.filter { $0.weight >= weight - 0.01 }
        let avgRPE = working.map(\.rpe).reduce(0, +) / Double(max(1, working.count))
        let topHit = working.filter { $0.reps >= target.repHigh }.count >= target.sets
        let best = working.map(\.reps).max() ?? 0
        let inc = increment(for: exercise, weight: weight)

        if topHit && avgRPE <= 8.5 {
            return Prescription(weight: round2(weight + inc), reps: target.repLow, sets: target.sets, decision: .increase,
                                reason: "Toutes tes séries à \(target.repHigh) reps sans forcer : +\(fmt(inc)) kg.")
        }
        if topHit {
            return Prescription(weight: weight, reps: target.repHigh, sets: target.sets, decision: .hold,
                                reason: "Objectif atteint mais à la limite (effort \(fmt(avgRPE))/10) : garde la charge pour consolider.")
        }
        if best < target.repLow {
            let previousAlsoLow = sessions.dropFirst().first.map { prev in
                let w = prev.map(\.weight).max() ?? 0
                return (prev.filter { $0.weight >= w - 0.01 }.map(\.reps).max() ?? 0) < target.repLow
            } ?? false
            if previousAlsoLow {
                return Prescription(weight: round2(weight * 0.9), reps: target.repLow, sets: target.sets, decision: .deload,
                                    reason: "Deux séances sous \(target.repLow) reps : on baisse de 10 % pour repartir proprement.")
            }
            return Prescription(weight: weight, reps: target.repLow, sets: target.sets, decision: .repeatLoad,
                                reason: "Sous \(target.repLow) reps la dernière fois : refais la même charge.")
        }
        return Prescription(weight: weight, reps: min(target.repHigh, best + 1), sets: target.sets, decision: .addRep,
                            reason: "Même charge, vise une répétition de plus (\(min(target.repHigh, best + 1))).")
    }

    /// Series difficiles (effort >= 7) par groupe musculaire sur 7 jours. Repere
    /// courant : 10 a 20 series par groupe et par semaine pour progresser.
    static func weeklyHardSets(_ sets: [LoggedSet], now: Date = .now) -> [String: Int] {
        let since = now.addingTimeInterval(-7 * 86_400)
        var out: [String: Int] = [:]
        for s in sets where s.date >= since && s.date <= now && s.rpe >= 7 && s.reps > 0 {
            if let g = GymExercises.group(of: s.exercise) { out[g, default: 0] += 1 }
        }
        return out
    }

    /// Heures depuis la derniere serie d'un groupe (nil si jamais travaille).
    static func hoursSince(group: String, in sets: [LoggedSet], now: Date = .now) -> Double? {
        sets.filter { $0.date <= now && GymExercises.group(of: $0.exercise) == group }
            .map(\.date).max().map { now.timeIntervalSince($0) / 3600 }
    }

    static func normalized(_ s: String) -> String {
        GymExercises.baseName(s).lowercased().folding(options: .diacriticInsensitive, locale: .current)
    }

    private static func round2(_ w: Double) -> Double { (w * 2).rounded() / 2 }
    static func fmt(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }
}

extension WorkoutSet {
    var logged: StrengthProgression.LoggedSet {
        .init(date: date, exercise: exercise, weight: weightKg, reps: reps, rpe: rpe)
    }
}
