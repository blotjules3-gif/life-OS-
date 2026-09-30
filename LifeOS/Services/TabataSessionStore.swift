import Foundation
import SwiftUI

// MARK: - Session Tabata durable
//
// Avant, le moteur vivait dans un `@State` de l'ecran: fermer la vue creait un
// moteur neuf et la seance etait perdue. Trois pieces reglent ca:
//
// 1. `TabataSessionSnapshot`: tout ce qu'il faut pour reprendre (config, liste
//    d'exercices, phase, round, serie, temps restant, horodatages, etat).
// 2. `TabataSessionStore`: ecrit et relit ce snapshot (UserDefaults, JSON).
// 3. `TabataSessionKeeper`: garde UN moteur vivant pour tout le processus.
//    Quitter l'ecran ne touche pas au moteur. Le relancement de l'app relit le
//    snapshot. L'ecriture dans Apple Sante passe ici, une seule fois par
//    identifiant de seance, meme si l'ecran est ferme quand la seance finit.
//
// Regle d'arriere-plan, au meme endroit que le moteur (`TabataEngine.tick`):
// une absence courte (<= 5 min) est rattrapee, comme avant. Une absence plus
// longue met la seance en PAUSE la ou elle en etait: on ne credite pas une
// heure d'effort a quelqu'un qui a pose son telephone.

struct TabataSessionSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = TabataSessionSnapshot.currentVersion
    var sessionID: UUID
    /// Identifiant de la seance choisie (preset, "gym-3"...), nil = intervalles libres.
    var sessionKey: String?
    var sessionName: String?
    var sessionIcon: String?
    var accentColorHex: UInt?
    var exercises: [String]
    var config: TabataConfig
    var phase: String
    var round: Int
    var cycle: Int
    var remaining: Int
    var intervalTotal: Int
    var running: Bool
    var startedAt: Date?
    /// Fin reelle de la seance, posee une fois a `.done`. Ne bouge jamais,
    /// contrairement a `savedAt` qui change a chaque sauvegarde.
    var finishedAt: Date? = nil
    /// Heure de la sauvegarde: c'est elle qui sert a mesurer l'absence au retour.
    var savedAt: Date
    /// Secondes reellement ecoulees en seance (tous intervalles), via l'horloge.
    var activeSeconds: Int
    /// Secondes reellement ecoulees en EFFORT.
    var workSecondsDone: Int
    /// Index des etapes dont le temps a ete entierement fait (jamais un saut).
    var completedSteps: [Int]
    /// La seance a deja ete ecrite dans Sante: ne jamais recommencer.
    var healthSaved: Bool
}

/// Persistance du snapshot. `UserDefaults` injectable pour les tests.
final class TabataSessionStore {
    static let key = AppStorageKeys.tabataSessionSnapshot
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TabataSessionSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(TabataSessionSnapshot.self, from: data) else {
            // Un snapshot illisible (version future, fichier corrompu) ne doit
            // pas bloquer l'ouverture du minuteur: on l'oublie.
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        guard snap.version <= TabataSessionSnapshot.currentVersion else {
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return snap
    }

    func save(_ snapshot: TabataSessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: File Sante
    //
    // Les seances finies pas encore acceptees par Sante vivent ICI, pas dans
    // le snapshot: `begin()`, `reset()` ou une autre seance remplacent le
    // snapshot, la file, elle, ne se vide qu'a l'acceptation.

    static let healthQueueKey = AppStorageKeys.tabataHealthQueue

    func loadHealthQueue() -> [TabataHealthWorkout] {
        guard let data = defaults.data(forKey: Self.healthQueueKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let queue = try? decoder.decode([TabataHealthWorkout].self, from: data) else {
            defaults.removeObject(forKey: Self.healthQueueKey)
            return []
        }
        return queue
    }

    func saveHealthQueue(_ queue: [TabataHealthWorkout]) {
        if queue.isEmpty {
            defaults.removeObject(forKey: Self.healthQueueKey)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(queue) else { return }
        defaults.set(data, forKey: Self.healthQueueKey)
    }
}

/// Ce que le gardien envoie a Sante pour une seance finie. Calcule UNE fois a
/// la fin, persiste tel quel: chaque nouvel essai renvoie exactement la meme
/// fenetre et le meme identifiant, avant comme apres un relancement.
struct TabataHealthWorkout: Codable, Equatable {
    let sessionID: UUID
    /// Fenetre d'activite REELLE: `end - start` vaut les secondes actives,
    /// calees sur la fin de la seance. Une pause d'une heure n'y entre pas.
    let start: Date
    let end: Date

    /// Identifiant stable pour Sante: rejouer l'ecriture de la meme seance
    /// remplace le workout au lieu d'en creer un second.
    var syncIdentifier: String { "lifeos.tabata.\(sessionID.uuidString)" }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Ou en est l'ecriture Sante d'une seance.
enum TabataHealthState: Equatable {
    /// Rien a ecrire: seance pas finie, ou moins d'une minute d'activite.
    case notEligible
    /// Ecriture lancee, pas encore de reponse.
    case pending
    /// Sante a accepte.
    case saved
    /// Sante a refuse: on peut reessayer.
    case failed
}

/// Garde le moteur vivant pour tout le processus et le sauvegarde a chaque
/// changement d'etat. Un seul moteur: quitter l'ecran ne le remplace jamais.
@MainActor
@Observable
final class TabataSessionKeeper {
    static let shared = TabataSessionKeeper()

    /// Duree minimale d'activite reelle pour ecrire une seance dans Sante.
    static let minimumHealthDuration = 60

    private let store: TabataSessionStore
    /// Ecriture Sante remplacable dans les tests: seance -> succes.
    private let healthWriter: (TabataHealthWorkout) async -> Bool
    /// Source de l'heure, remplacable dans les tests.
    var now: () -> Date

    /// Ignore par l'observation: il est pose une fois, au premier acces, et
    /// jamais remplace (abandonner remet CE moteur au repos). Le poser pendant
    /// un rendu SwiftUI ne doit pas compter comme une mutation observee.
    @ObservationIgnored private var liveEngine: TabataEngine?
    /// Seances ACCEPTEES par Sante, par identifiant. Persiste dans le snapshot.
    /// N'est rempli qu'apres la reponse: une ecriture en vol n'est pas "faite".
    private(set) var healthSavedSessions: Set<UUID> = []
    /// Ecritures lancees et sans reponse encore.
    private(set) var healthPendingSessions: Set<UUID> = []
    /// Seances finies, eligibles, pas encore acceptees par Sante. Persistee a
    /// part du snapshot: une nouvelle seance, un reset ou une fermeture de
    /// l'app pendant l'ecriture ne la perdent pas. Une entree sans tache en
    /// vol est un refus (`failed`), reessayable.
    private(set) var healthQueue: [TabataHealthWorkout] = []
    /// Taches d'ecriture en vol, une par seance au plus.
    @ObservationIgnored private var healthTasks: [UUID: Task<Bool, Never>] = [:]
    /// Nombre d'ecritures Sante effectivement lancees (preuve pour les tests).
    private(set) var healthWriteCount = 0

    init(store: TabataSessionStore = TabataSessionStore(),
         healthWriter: ((TabataHealthWorkout) async -> Bool)? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.healthWriter = healthWriter ?? { workout in
            await HealthService.shared.saveWorkout(kind: .hiit,
                                                   start: workout.start, end: workout.end,
                                                   kcal: 0,
                                                   syncIdentifier: workout.syncIdentifier)
        }
        self.now = now
        self.healthQueue = store.loadHealthQueue()
        // Ce qui attendait Sante a la derniere fermeture repart tout de suite,
        // sans attendre que l'ecran Tabata soit ouvert.
        retryQueuedHealthWrites()
    }

    /// Le moteur unique: vivant si l'app tourne, sinon relu depuis le disque,
    /// sinon neuf et au repos. Toujours appele AVANT d'appliquer une config par
    /// defaut: une seance en cours garde la sienne.
    var engine: TabataEngine {
        if let live = liveEngine { return live }
        let engine: TabataEngine
        if let snap = store.load() {
            // Sans rattrapage ici: les rappels sont poses par `adopt` d'abord,
            // puis le rattrapage tourne. Sinon une seance qui se termine pendant
            // l'absence finit sans `onFinished`, et Sante n'est jamais ecrit.
            engine = TabataEngine.restore(snap, now: now, catchUp: false)
            if snap.healthSaved { healthSavedSessions.insert(snap.sessionID) }
            adopt(engine)
            if engine.running { engine.tick() }
            // Finie avant une fermeture de l'app (ou pendant le rattrapage a
            // l'instant) et pas encore acceptee par Sante: on reessaie.
            if engine.phase == .done { handleFinish(engine) }
        } else {
            engine = TabataEngine(cfg: Self.defaultConfig())
            if let first = TabataPresets.all.first { engine.attach(session: first) }
            adopt(engine)
        }
        return engine
    }

    /// Vrai si une seance est en cours (lancee, pas encore finie).
    var hasActiveSession: Bool {
        let e = engine
        return e.phase != .idle && e.phase != .done
    }

    func healthSaved(for id: UUID) -> Bool { healthSavedSessions.contains(id) }

    func healthState(for id: UUID) -> TabataHealthState {
        if healthSavedSessions.contains(id) { return .saved }
        if healthPendingSessions.contains(id) { return .pending }
        if healthQueue.contains(where: { $0.sessionID == id }) { return .failed }
        return .notEligible
    }

    /// Nouvel essai apres un refus de Sante: TOUTE la file, pas seulement la
    /// seance vivante. Une seance remplacee par la suivante reste due.
    func retryHealthWrite() {
        retryQueuedHealthWrites()
    }

    private func retryQueuedHealthWrites() {
        for workout in healthQueue where healthTasks[workout.sessionID] == nil
            && !healthSavedSessions.contains(workout.sessionID) {
            startHealthWrite(workout)
        }
    }

    /// Attend la fin de l'ecriture en vol d'une seance (tests). nil = aucune.
    @discardableResult
    func awaitHealthWrite(for id: UUID) async -> Bool? {
        guard let task = healthTasks[id] else { return nil }
        return await task.value
    }

    /// Reprend un moteur construit ailleurs (tests) comme moteur vivant.
    func adopt(_ engine: TabataEngine) {
        liveEngine = engine
        engine.onStateChange = { [weak self, weak engine] in
            guard let self, let engine else { return }
            self.persist(engine)
        }
        engine.onFinished = { [weak self, weak engine] in
            guard let self, let engine else { return }
            self.handleFinish(engine)
        }
    }

    func persist() {
        guard let e = liveEngine else { return }
        persist(e)
    }

    private func persist(_ engine: TabataEngine) {
        if engine.phase == .idle {
            // Rien a reprendre: un moteur au repos se reconstruit depuis la config.
            store.clear()
            return
        }
        store.save(engine.snapshot(healthSaved: healthSavedSessions.contains(engine.sessionID),
                                   savedAt: now()))
    }

    /// Abandon explicite: la seance est jetee, rien n'est ecrit dans Sante.
    /// La file Sante n'est pas touchee: "Terminer & Fermer" sur l'ecran de
    /// fin passe aussi par ici, et une ecriture encore due doit survivre.
    func discard() {
        liveEngine?.reset()
        store.clear()
    }

    /// Fin de seance: UNE ecriture Sante par identifiant de seance, seulement si
    /// le temps reellement fait depasse la minute. Les sauts n'y comptent pas.
    /// Un second `done` pendant une ecriture en vol, ou apres un succes, ne
    /// relance rien. Un refus laisse la seance en `failed`, reessayable.
    private func handleFinish(_ engine: TabataEngine) {
        let id = engine.sessionID
        guard !healthSavedSessions.contains(id), healthTasks[id] == nil else {
            persist(engine)
            return
        }
        // La fenetre est calculee UNE fois puis mise en file: un nouvel essai,
        // avant ou apres relancement, renvoie exactement la meme.
        let workout: TabataHealthWorkout
        if let queued = healthQueue.first(where: { $0.sessionID == id }) {
            workout = queued
        } else if let fresh = healthWorkout(for: engine) {
            workout = fresh
            healthQueue.append(fresh)
            store.saveHealthQueue(healthQueue)
        } else {
            persist(engine)
            return
        }
        startHealthWrite(workout)
        persist(engine)
    }

    /// Fenetre reelle de la seance: aussi longue que les secondes ACTIVES, calee
    /// sur l'heure de fin. `startedAt -> maintenant` compterait les pauses, donc
    /// une heure de telephone pose deviendrait une heure d'exercice dans Sante.
    func healthWorkout(for engine: TabataEngine) -> TabataHealthWorkout? {
        guard engine.phase == .done, let startedAt = engine.startedAt,
              engine.activeSeconds >= Self.minimumHealthDuration else { return nil }
        // `finishedAt` est pose par le moteur a la vraie fin (frontiere reelle
        // meme en rattrapage) et voyage dans le snapshot: un relancement ne
        // deplace jamais le workout.
        let end = engine.finishedAt ?? now()
        let start = max(startedAt, end.addingTimeInterval(-Double(engine.activeSeconds)))
        guard end > start else { return nil }
        return TabataHealthWorkout(sessionID: engine.sessionID, start: start, end: end)
    }

    private func startHealthWrite(_ workout: TabataHealthWorkout) {
        let id = workout.sessionID
        healthPendingSessions.insert(id)
        healthWriteCount += 1
        let writer = healthWriter
        // Le gardien est sur l'acteur principal, la tache en herite: la mise a
        // jour d'etat apres la reponse se fait donc sans course avec l'ecran.
        let task = Task { [weak self] () -> Bool in
            let ok = await writer(workout)
            self?.finishHealthWrite(id: id, ok: ok)
            return ok
        }
        healthTasks[id] = task
    }

    private func finishHealthWrite(id: UUID, ok: Bool) {
        healthTasks[id] = nil
        healthPendingSessions.remove(id)
        if ok {
            healthSavedSessions.insert(id)
            // Seul un succes retire la seance de la file durable.
            healthQueue.removeAll { $0.sessionID == id }
            store.saveHealthQueue(healthQueue)
        }
        // Le drapeau `healthSaved` voyage avec le snapshot: seulement apres succes.
        if let e = liveEngine, e.sessionID == id { persist(e) }
    }

    /// Config par defaut lue dans les memes cles que l'ecran de reglages.
    static func defaultConfig(defaults: UserDefaults = .standard) -> TabataConfig {
        func int(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) as? Int ?? fallback
        }
        return TabataConfig(prepare: int(AppStorageKeys.tabPrepare, 10),
                            work: int(AppStorageKeys.tabWork, 30),
                            rest: int(AppStorageKeys.tabRest, 15),
                            rounds: int(AppStorageKeys.tabRounds, 8),
                            cycles: int(AppStorageKeys.tabCycles, 1),
                            restCycle: int(AppStorageKeys.tabRestCycle, 60),
                            cooldown: int(AppStorageKeys.tabCooldown, 0))
    }
}
