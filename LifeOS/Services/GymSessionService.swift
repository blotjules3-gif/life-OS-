import Foundation
import SwiftData

/// Cycle de vie d'une seance : demarrer (prescription figee), logger, terminer, annuler.
///
/// Chaque ecriture passe par `save` et REMONTE son erreur : avant, `try? ctx.save()`
/// suivi d'une vibration de succes faisait croire qu'une serie etait gardee alors que
/// l'enregistrement avait echoue. En cas d'echec la modification est annulee, et
/// l'ecran garde la saisie pour reessayer.
enum GymSessionService {

    typealias Saver = (ModelContext) throws -> Void
    static let defaultSaver: Saver = { try $0.save() }

    enum GymError: LocalizedError, Equatable {
        case invalidWeight, invalidReps, notActive, saveFailed(String)
        var errorDescription: String? {
            switch self {
            case .invalidWeight: return "Charge invalide : entre un poids entre 0 et 1000 kg."
            case .invalidReps: return "Nombre de répétitions invalide."
            case .notActive: return "Cette séance est déjà terminée ou annulée."
            case .saveFailed(let why): return "La série n'a pas été enregistrée (\(why)). Ta saisie est gardée : réessaie."
            }
        }
    }

    enum State: String { case active, done, cancelled }

    /// Charge saisie ("62,5", "62.5") → kg, ou nil si vide, negative, absurde.
    /// Le bouton de validation et l'action utilisent CETTE fonction, pour qu'un
    /// bouton actif ne mene jamais a un refus silencieux.
    static func parseWeight(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v >= 0, v <= 1000 else { return nil }
        return v
    }

    // MARK: Demarrage

    /// Cree la seance et fige la prescription de chaque exercice a partir de
    /// l'historique TERMINE seulement.
    @discardableResult
    static func start(title: String, exercises: [String], history: [StrengthProgression.LoggedSet],
                      doneSessions: Set<UUID>, profile1RM: (String) -> Double? = { _ in nil },
                      minIncrement: Double = 0, in ctx: ModelContext, now: Date = .now,
                      save: Saver = defaultSaver) throws -> TrainingSession {
        let session = TrainingSession(title: title, start: now)
        let done = StrengthProgression.completed(history, doneSessions: doneSessions)
        var map: [String: StrengthProgression.Prescription] = [:]
        for label in exercises where GymExercises.group(of: label) != "Cardio" {
            let target = StrengthProgression.target(from: label) ?? StrengthProgression.defaultTarget
            map[GymExercises.baseName(label)] = StrengthProgression.next(
                exercise: label, target: target, history: done,
                profile1RM: profile1RM(label), minIncrement: minIncrement)
        }
        session.prescriptionJSON = (try? String(data: JSONEncoder().encode(map), encoding: .utf8)) ?? ""
        ctx.insert(session)
        do { try save(ctx) } catch {
            ctx.delete(session)
            throw GymError.saveFailed(error.localizedDescription)
        }
        return session
    }

    static func prescriptions(of session: TrainingSession) -> [String: StrengthProgression.Prescription] {
        guard let d = session.prescriptionJSON.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: StrengthProgression.Prescription].self, from: d)
        else { return [:] }
        return map
    }

    // MARK: Series

    @discardableResult
    static func log(exercise: String, weightText: String, reps: Int, rpe: Double, kind: WorkoutSetKind,
                    session: TrainingSession, in ctx: ModelContext, now: Date = .now,
                    save: Saver = defaultSaver) throws -> WorkoutSet {
        guard session.state == State.active.rawValue else { throw GymError.notActive }
        guard let w = parseWeight(weightText) else { throw GymError.invalidWeight }
        guard reps > 0, reps <= 200 else { throw GymError.invalidReps }
        let set = WorkoutSet(date: now, exercise: GymExercises.baseName(exercise), weightKg: w, reps: reps,
                             rpe: rpe, sessionID: session.id, kind: kind.rawValue)
        ctx.insert(set)
        do { try save(ctx) } catch {
            ctx.delete(set)
            throw GymError.saveFailed(error.localizedDescription)
        }
        return set
    }

    static func delete(_ set: WorkoutSet, in ctx: ModelContext, save: Saver = defaultSaver) throws {
        ctx.delete(set)
        do { try save(ctx) } catch {
            ctx.rollback()
            throw GymError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: Fin

    static func finish(_ session: TrainingSession, in ctx: ModelContext, now: Date = .now,
                       save: Saver = defaultSaver) throws {
        try close(session, as: .done, in: ctx, now: now, save: save)
    }

    /// Annule : la seance ne servira jamais de base de progression. Les series sont
    /// gardees (historique honnete) sauf si `deleteSets`.
    static func cancel(_ session: TrainingSession, deleteSets: Bool, sets: [WorkoutSet],
                       in ctx: ModelContext, now: Date = .now, save: Saver = defaultSaver) throws {
        if deleteSets { sets.filter { $0.sessionID == session.id }.forEach(ctx.delete) }
        do { try close(session, as: .cancelled, in: ctx, now: now, save: save) } catch {
            // Les suppressions en attente ne doivent pas partir au prochain enregistrement.
            if deleteSets { ctx.rollback() }
            throw error
        }
    }

    private static func close(_ session: TrainingSession, as state: State, in ctx: ModelContext,
                              now: Date, save: Saver) throws {
        guard session.state == State.active.rawValue else { throw GymError.notActive }
        session.state = state.rawValue
        session.end = now
        do { try save(ctx) } catch {
            // Retour cible (pas de rollback global, qui jetterait d'autres saisies).
            session.state = State.active.rawValue
            session.end = nil
            throw GymError.saveFailed(error.localizedDescription)
        }
    }

    static func doneIDs(_ sessions: [TrainingSession]) -> Set<UUID> {
        Set(sessions.filter { $0.state == State.done.rawValue }.map(\.id))
    }
}
