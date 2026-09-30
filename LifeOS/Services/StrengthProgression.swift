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
        /// Seance d'origine; nil = serie loguee hors seance (regroupee par jour).
        var sessionID: UUID? = nil
        var kind: WorkoutSetKind = .work
    }

    struct Target: Equatable, Codable {
        let sets: Int
        let repLow: Int
        let repHigh: Int
    }

    enum Decision: String, Equatable, Codable {
        case start, increase, hold, repeatLoad, deload, addRep
    }

    struct Prescription: Equatable, Codable {
        let weight: Double?
        let reps: Int
        let sets: Int
        let decision: Decision
        let reason: String
    }

    /// Cible quand le libelle n'en donne pas ("Rowing" tout court) : fourchette
    /// classique d'hypertrophie, annoncee comme telle a l'ecran.
    static let defaultTarget = Target(sets: 3, repLow: 8, repHigh: 12)

    /// "Développé couché barre 4×10" → 4 series, 8 à 10 reps; "3×8-12" → 8 à 12.
    /// Une cible de force (6 reps ou moins) garde une fourchette fixe. nil si le
    /// libelle n'a pas de cible. Meme decoupage que `ExerciseLabel` (un seul parseur).
    static func target(from label: String) -> Target? {
        let suffix = ExerciseLabel.split(label).suffix
        guard !suffix.isEmpty else { return nil }
        let nums = suffix.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 2, nums[0] > 0, nums[1] > 0 else { return nil }
        if nums.count == 3, nums[2] >= nums[1] {
            return Target(sets: nums[0], repLow: nums[1], repHigh: nums[2])
        }
        let high = nums[1]
        return Target(sets: nums[0], repLow: high <= 6 ? high : max(1, high - 2), repHigh: high)
    }

    /// Pas de charge realiste pour l'exercice. `override` > 0 = pas choisi par
    /// l'utilisateur (Reglages du programme : plus petits disques disponibles).
    static func increment(for exercise: String, weight: Double, override: Double = 0) -> Double {
        if override > 0 { return override }
        let n = exercise.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let lowerCompound = ["squat", "presse", "souleve", "hip thrust", "hack", "good morning"]
        if lowerCompound.contains(where: n.contains) { return weight < 40 ? 2.5 : 5 }
        if n.contains("haltere") { return 2 }
        return 2.5
    }

    /// Seances d'un exercice, la plus recente d'abord. Groupees par seance quand la
    /// serie en porte une (deux seances le meme jour restent deux seances), sinon par
    /// jour. Seules les series de TRAVAIL comptent : echauffement et degressives non.
    static func sessions(of exercise: String, in sets: [LoggedSet],
                         calendar: Calendar = .current) -> [[LoggedSet]] {
        let key = normalized(exercise)
        let mine = sets.filter { normalized($0.exercise) == key && $0.reps > 0 && $0.kind == .work }
        let groups = Dictionary(grouping: mine) { s -> String in
            s.sessionID.map { "s:" + $0.uuidString } ?? "d:\(calendar.startOfDay(for: s.date).timeIntervalSince1970)"
        }
        return groups.values
            .map { $0.sorted { $0.date < $1.date } }
            .sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
    }

    /// Historique utilisable pour progresser : series hors seance, et series des
    /// seances TERMINEES. Une seance en cours, abandonnee ou annulee n'en fait pas partie.
    static func completed(_ sets: [LoggedSet], doneSessions: Set<UUID>) -> [LoggedSet] {
        sets.filter { s in s.sessionID.map(doneSessions.contains) ?? true }
    }

    /// Record personnel : 1RM estime au-dessus du meilleur de l'historique termine.
    static func isPersonalRecord(_ set: LoggedSet, history: [LoggedSet]) -> Bool {
        guard set.kind == .work, set.reps > 0, set.weight > 0 else { return false }
        let key = normalized(set.exercise)
        let best = history.filter { normalized($0.exercise) == key && $0.kind == .work && $0.reps > 0 }
            .map { e1RM($0.weight, $0.reps) }.max()
        guard let best else { return false }
        return e1RM(set.weight, set.reps) > best + 0.01
    }

    static func e1RM(_ w: Double, _ reps: Int) -> Double { reps <= 1 ? w : w * (1 + Double(reps) / 30) }

    static func next(exercise: String, target: Target, history sets: [LoggedSet],
                     profile1RM: Double? = nil, minIncrement: Double = 0) -> Prescription {
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
        let inc = increment(for: exercise, weight: weight, override: minIncrement)

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
        for s in sets where s.date >= since && s.date <= now && s.rpe >= 7 && s.reps > 0 && s.kind == .work {
            if let g = GymExercises.group(of: s.exercise) { out[g, default: 0] += 1 }
        }
        return out
    }

    /// Heures depuis la derniere serie d'un groupe (nil si jamais travaille), sans
    /// compter la seance en cours : une seance plus tot le MEME jour compte bien.
    static func hoursSince(group: String, in sets: [LoggedSet], excludingSession current: UUID? = nil,
                           now: Date = .now) -> Double? {
        sets.filter { $0.date <= now && GymExercises.group(of: $0.exercise) == group
                      && ($0.sessionID == nil || $0.sessionID != current) }
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

/// Parseur UNIQUE d'un libelle d'exercice : "Rowing barre 3×8-12" = nom "Rowing barre"
/// + cible " 3×8-12". Avant, `GymExercises.baseName` ne retirait que " N×N" alors que la
/// cible acceptait "3×8-12", "3x8-12", "4 x 10" : le meme exercice avait plusieurs
/// identites et perdait son historique et ses records quand sa cible changeait.
enum ExerciseLabel {
    static let suffixPattern = #"\s*\d+\s*[×xX*]\s*\d+(?:\s*[-–]\s*\d+)?\s*$"#

    static func split(_ label: String) -> (name: String, suffix: String) {
        let t = label.trimmingCharacters(in: .whitespaces)
        guard let r = t.range(of: suffixPattern, options: .regularExpression), r.lowerBound > t.startIndex else {
            return (t, "")
        }
        return (String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), String(t[r]))
    }
}

/// Type d'une serie.
enum WorkoutSetKind: String, CaseIterable, Codable, Identifiable {
    case warmup, work, drop
    var id: String { rawValue }
    var label: String {
        switch self { case .warmup: return "Échauffement"; case .work: return "Travail"; case .drop: return "Dégressive" }
    }
}

extension WorkoutSet {
    var logged: StrengthProgression.LoggedSet {
        .init(date: date, exercise: exercise, weight: weightKg, reps: reps, rpe: rpe,
              sessionID: sessionID, kind: WorkoutSetKind(rawValue: kind) ?? .work)
    }
}
