import Foundation
import SwiftData

/// Cycle de vie d'une seance : demarrer (exercices et prescription figes), logger,
/// repos, terminer, annuler. Et les series AUTONOMES (saisies a la main hors seance).
///
/// Regles, chacune couverte par un test :
/// - une seance se rattache a un jour de programme par son identifiant, jamais par son
///   titre, et se reprend par son propre identifiant, quel que soit le jour ;
/// - la liste d'exercices et la charge conseillee sont figees au demarrage ;
/// - chaque ecriture REMONTE son erreur, et un echec n'annule que ce qu'il a touche
///   (les suppressions passent par un contexte isole : jamais de rollback global qui
///   jetterait d'autres saisies en attente) ;
/// - seules les seances terminees et les series autonomes validees font progresser.
enum GymSessionService {

    typealias Saver = (ModelContext) throws -> Void
    static let defaultSaver: Saver = { try $0.save() }

    enum GymError: LocalizedError, Equatable {
        case invalidWeight, invalidReps, invalidExercise, notActive, saveFailed(String)
        var errorDescription: String? {
            switch self {
            case .invalidWeight: return "Charge invalide : entre un poids entre 0 et 1000 kg."
            case .invalidReps: return "Nombre de répétitions invalide."
            case .invalidExercise: return "Donne un nom à l'exercice."
            case .notActive: return "Cette séance est déjà terminée ou annulée."
            case .saveFailed(let why): return "Non enregistré (\(why)). Ta saisie est gardée : réessaie."
            }
        }
    }

    enum State: String { case active, done, cancelled }

    /// Charge saisie ("62,5", "62.5") → kg, ou nil si vide, negative, absurde.
    /// Le bouton de validation et l'action utilisent CETTE fonction.
    static func parseWeight(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v >= 0, v <= 1000 else { return nil }
        return v
    }

    // MARK: Retrouver une seance

    /// Seance en cours rattachee a CE jour de programme (par identifiant).
    static func activeSession(for day: GymDay, in sessions: [TrainingSession]) -> TrainingSession? {
        let id = day.stableID
        return sessions.first { $0.state == State.active.rawValue && $0.dayUID == id }
    }

    /// N'importe quelle seance en cours, la plus recente : pour la reprendre meme un
    /// autre jour (commencee la veille d'un jour de repos, par exemple).
    static func anyActive(_ sessions: [TrainingSession]) -> TrainingSession? {
        sessions.filter { $0.state == State.active.rawValue }.max { $0.start < $1.start }
    }

    static func doneIDs(_ sessions: [TrainingSession]) -> Set<UUID> {
        Set(sessions.filter { $0.state == State.done.rawValue }.map(\.id))
    }

    // MARK: Demarrage

    /// Cree la seance, fige la liste ordonnee d'exercices et la prescription de chacun
    /// (a partir de l'historique TERMINE seulement).
    @discardableResult
    static func start(day: GymDay?, title: String, exercises: [String], history: [StrengthProgression.LoggedSet],
                      doneSessions: Set<UUID>, profile1RM: (String) -> Double? = { _ in nil },
                      minIncrement: Double = 0, in ctx: ModelContext, now: Date = .now,
                      save: Saver = defaultSaver) throws -> TrainingSession {
        let session = TrainingSession(title: title, start: now)
        session.dayUID = day?.stableID
        session.supersetsJSON = day?.supersetsJSON ?? ""
        let list = exercises.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        session.exercisesJSON = encode(list)
        let done = StrengthProgression.completed(history, doneSessions: doneSessions)
        var map: [String: StrengthProgression.Prescription] = [:]
        for label in list where GymExercises.group(of: label) != "Cardio" {
            let target = StrengthProgression.target(from: label) ?? StrengthProgression.defaultTarget
            map[GymExercises.baseName(label)] = StrengthProgression.next(
                exercise: label, target: target, history: done,
                profile1RM: profile1RM(label), minIncrement: minIncrement)
        }
        session.prescriptionJSON = encode(map)
        ctx.insert(session)
        do { try save(ctx) } catch {
            ctx.delete(session)
            throw GymError.saveFailed(error.localizedDescription)
        }
        return session
    }

    /// Repos apres une serie : aucun entre les deux exercices d'un superset (on enchaine
    /// sur le second), le repos normal apres le second.
    static func restSeconds(after exercise: String, in session: TrainingSession, default seconds: Int) -> Int {
        let pairs = FitbotSupersets.decode(session.supersetsJSON)
        let name = GymExercises.baseName(exercise)
        return pairs.contains { $0.first == name } ? 0 : seconds
    }

    /// Partenaire de superset d'un exercice dans la seance, pour l'afficher.
    static func supersetPartner(of exercise: String, in session: TrainingSession) -> String? {
        FitbotSupersets.partner(of: exercise, in: FitbotSupersets.decode(session.supersetsJSON))
    }

    static func frozenExercises(of session: TrainingSession) -> [String] {
        guard let d = session.exercisesJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return list
    }

    static func prescriptions(of session: TrainingSession) -> [String: StrengthProgression.Prescription] {
        guard let d = session.prescriptionJSON.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: StrengthProgression.Prescription].self, from: d)
        else { return [:] }
        return map
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? ""
    }

    // MARK: Series

    /// Serie d'une seance. `restSeconds` > 0 pose la fin du repos DANS la seance
    /// (meme enregistrement), sauf pour un echauffement.
    @discardableResult
    static func log(exercise: String, weightText: String, reps: Int, rpe: Double, kind: WorkoutSetKind,
                    session: TrainingSession, restSeconds: Int = 0, in ctx: ModelContext, now: Date = .now,
                    save: Saver = defaultSaver) throws -> WorkoutSet {
        guard session.state == State.active.rawValue else { throw GymError.notActive }
        let set = try makeSet(exercise: exercise, weightText: weightText, reps: reps, rpe: rpe, kind: kind, now: now)
        set.sessionID = session.id
        let previousRest = session.restEnd
        if restSeconds > 0 && kind != .warmup { session.restEnd = now.addingTimeInterval(TimeInterval(restSeconds)) }
        ctx.insert(set)
        do { try save(ctx) } catch {
            ctx.delete(set)
            session.restEnd = previousRest
            throw GymError.saveFailed(error.localizedDescription)
        }
        return set
    }

    /// Serie saisie a la main hors seance (Hevvy, ajout rapide, raccourci Siri) : une
    /// entree autonome VALIDEE, qui compte donc pour la progression.
    @discardableResult
    static func logStandalone(exercise: String, weightText: String, reps: Int, rpe: Double = 8,
                              kind: WorkoutSetKind = .work, in ctx: ModelContext, now: Date = .now,
                              save: Saver = defaultSaver) throws -> WorkoutSet {
        let set = try makeSet(exercise: exercise, weightText: weightText, reps: reps, rpe: rpe, kind: kind, now: now)
        ctx.insert(set)
        do { try save(ctx) } catch {
            ctx.delete(set)
            throw GymError.saveFailed(error.localizedDescription)
        }
        return set
    }

    /// Le SEUL endroit qui construit une serie : nom canonique, charge et reps valides.
    private static func makeSet(exercise: String, weightText: String, reps: Int, rpe: Double,
                                kind: WorkoutSetKind, now: Date) throws -> WorkoutSet {
        let name = GymExercises.baseName(exercise)
        guard !name.isEmpty else { throw GymError.invalidExercise }
        guard let w = parseWeight(weightText) else { throw GymError.invalidWeight }
        guard reps > 0, reps <= 200 else { throw GymError.invalidReps }
        return WorkoutSet(date: now, exercise: name, weightKg: w, reps: reps,
                          rpe: min(10, max(1, rpe)), kind: kind.rawValue)
    }

    static func skipRest(_ session: TrainingSession, in ctx: ModelContext, save: Saver = defaultSaver) throws {
        let previous = session.restEnd
        session.restEnd = nil
        do { try save(ctx) } catch {
            session.restEnd = previous
            throw GymError.saveFailed(error.localizedDescription)
        }
    }

    /// Supprime une serie dans un contexte ISOLE : si l'enregistrement echoue, le
    /// contexte partage n'est pas touche (ses autres modifications en attente restent).
    static func delete(_ set: WorkoutSet, in ctx: ModelContext, save: Saver = defaultSaver) throws {
        try deleteIsolated([set.persistentModelID], in: ctx, save: save)
    }

    private static func deleteIsolated(_ ids: [PersistentIdentifier], in ctx: ModelContext, save: Saver) throws {
        guard !ids.isEmpty else { return }
        let tx = ModelContext(ctx.container)
        tx.autosaveEnabled = false
        for id in ids {
            if let obj = tx.model(for: id) as? WorkoutSet { tx.delete(obj) }
        }
        do { try save(tx) } catch {
            throw GymError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: Fin

    static func finish(_ session: TrainingSession, in ctx: ModelContext, now: Date = .now,
                       save: Saver = defaultSaver) throws {
        try close(session, as: .done, in: ctx, now: now, save: save)
    }

    /// Annule : la seance ne servira jamais de base de progression. Les series sont
    /// gardees (historique honnete) sauf si `deleteSets` ; leur suppression passe par un
    /// contexte isole, d'abord, pour ne rien jeter d'autre en cas d'echec.
    static func cancel(_ session: TrainingSession, deleteSets: Bool, sets: [WorkoutSet],
                       in ctx: ModelContext, now: Date = .now, save: Saver = defaultSaver) throws {
        guard session.state == State.active.rawValue else { throw GymError.notActive }
        if deleteSets {
            try deleteIsolated(sets.filter { $0.sessionID == session.id }.map(\.persistentModelID), in: ctx, save: save)
        }
        try close(session, as: .cancelled, in: ctx, now: now, save: save)
    }

    private static func close(_ session: TrainingSession, as state: State, in ctx: ModelContext,
                              now: Date, save: Saver) throws {
        guard session.state == State.active.rawValue else { throw GymError.notActive }
        let previousRest = session.restEnd
        session.state = state.rawValue
        session.end = now
        session.restEnd = nil
        do { try save(ctx) } catch {
            // Retour cible : seules les valeurs de cette seance reviennent.
            session.state = State.active.rawValue
            session.end = nil
            session.restEnd = previousRest
            throw GymError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: Migration

    /// Noms historiques portant une cible ("Rowing 4×10") ramenes au nom canonique :
    /// une seule identite par exercice pour l'historique et les records. Rend le nombre
    /// de series renommees. Sans effet si rien a changer.
    @discardableResult
    static func migrateExerciseNames(in ctx: ModelContext, save: Saver = defaultSaver) throws -> Int {
        let all = try ctx.fetch(FetchDescriptor<WorkoutSet>())
        var changed: [(WorkoutSet, String)] = []
        for s in all {
            let base = GymExercises.baseName(s.exercise)
            if base != s.exercise && !base.isEmpty { changed.append((s, s.exercise)); s.exercise = base }
        }
        guard !changed.isEmpty else { return 0 }
        do { try save(ctx) } catch {
            for (s, old) in changed { s.exercise = old }
            throw GymError.saveFailed(error.localizedDescription)
        }
        return changed.count
    }
}
