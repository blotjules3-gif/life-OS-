# REVIEW-EVIDENCE — lot Tabata / Santé (2026-09-30)

Extraits des méthodes corrigées et d'un test complet par défaut ; les autres tests sont résumés. Diff complet : `diff-tabata-health.patch`.

## Défaut 1 : fin immuable, persistée, frontière réelle en rattrapage

`finishedAt` posé une fois dans `finish()`, remis à nil par `begin()`/`reset()`, écrit dans le snapshot (`var finishedAt: Date? = nil`) et relu par `restore` (`e.finishedAt = s.finishedAt`).

```swift
    private(set) var finishedAt: Date?
    /// Pendant un rattrapage, l'heure réelle de la seconde en cours de
    /// traitement, pour dater une fin qui tombe au milieu de l'absence.
    private var catchUpBoundary: Date?

        for i in 0..<steps {
            guard running, phase != .idle, phase != .done else { break }
            // Heure réelle de la seconde consommée: une fin en rattrapage est
            // datée de sa vraie frontière, jamais de l'heure du retour.
            catchUpBoundary = min(currentNow, base.addingTimeInterval(Double(i + 1)))
            step(silent: catchUp)
        }
        catchUpBoundary = nil

    func finish()    { play("fin", [(880, 0.16), (0, 0.05), (1108, 0.16), (0, 0.05), (1318, 0.36)], vol: 1.0) }
```

Gardien : la fenêtre lit `engine.finishedAt`, jamais `savedAt`.

```swift
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
```

## Défaut 2 : file Santé durable, indépendante du snapshot

Clé `AppStorageKeys.tabataHealthQueue` ; `TabataHealthWorkout: Codable` ; store `loadHealthQueue()` / `saveHealthQueue(_:)` (JSON iso8601, clé retirée quand la file est vide). L'init du gardien fait `healthQueue = store.loadHealthQueue()` puis `retryQueuedHealthWrites()` (toute entrée sans tâche en vol ni succès repart). `retryHealthWrite()` appelle la même chose. `finishHealthWrite` ne retire de la file QUE sur succès. `discard()` ne touche pas la file. `healthState` : saved > pending > failed (en file sans tâche) > notEligible.

```swift
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
```

## Nouveaux tests

```swift
    func testFinishDuringCatchUpIsDatedAtRealBoundary() {
        let start = Date(timeIntervalSince1970: 9_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        XCTAssertNil(e.finishedAt)
        clock = clock.addingTimeInterval(200)
        e.tick()
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.finishedAt, start.addingTimeInterval(85), "la vraie frontiere")
        XCTAssertEqual(e.activeSeconds, 85)

        clock = clock.addingTimeInterval(50)
        e.tick()
        XCTAssertEqual(e.finishedAt, start.addingTimeInterval(85), "posee une fois, jamais recalculee")
        e.reset()
        XCTAssertNil(e.finishedAt, "une nouvelle seance repart sans fin")
    }
```
```swift
    func testDelayedFailureThenRelaunchKeepsOriginalFinishTime() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 20_000)
        let gate = AsyncStream<Void>.makeStream()
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in
            for await _ in gate.stream { break }       // reponse retardee
            return false                                // ... puis refus
        }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(75); e.tick()
        XCTAssertEqual(e.phase, .done)
        let realFinish = clock
        XCTAssertEqual(e.finishedAt, realFinish)
        XCTAssertEqual(store.load()?.finishedAt, realFinish)

        clock = clock.addingTimeInterval(600)            // 10 min: des sauvegardes plus tard
        keeper.persist()
        XCTAssertGreaterThan(store.load()?.savedAt ?? .distantPast, realFinish, "savedAt a bouge")
        XCTAssertEqual(store.load()?.finishedAt, realFinish, "finishedAt n'a pas bouge")

        gate.continuation.yield(())
        let first = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(first, false)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .failed)

        clock = clock.addingTimeInterval(3600)           // relance une heure plus tard
        var writes: [TabataHealthWorkout] = []
        let keeper2 = TabataSessionKeeper(store: store,
                                          healthWriter: { w in writes.append(w); return true },
                                          now: { clock })
        let ok = await keeper2.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.end, realFinish, "meme fin qu'a la premiere tentative")
        XCTAssertEqual(writes.first?.start, realFinish.addingTimeInterval(-75))
        XCTAssertEqual(writes.first?.syncIdentifier, "lifeos.tabata.\(e.sessionID.uuidString)")
        XCTAssertEqual(keeper2.healthState(for: e.sessionID), .saved)
    }
```

Résumés :
- `testFinishOnNormalTickIsDatedNow` : 85 ticks de 1 s, `finishedAt == clock` du dernier tick.
- `testFailedWorkoutSurvivesNewSessionAndRelaunch` : refus de A, `reset()`+`begin()` (snapshot = B), file = [A] ; nouveau gardien → `healthWriteCount == 1` dès l'init, écrit exactement l'entrée de file (même `start`/`end`/`syncIdentifier`), file vide après, B intacte et non écrite.
- `testInFlightWriteSurvivesSessionReplacementAndTermination` : writer qui ne répond jamais ; fin de A → `pending`, file = [A] AVANT toute réponse ; B lancée ; "fermeture" = nouveau gardien sur le même store → A réécrite (`end == finA`, durée 75 s, même identifiant), file vide.
- `testRetryCoversQueuedSessionNotOnlyLiveOne` : A refusée, B à l'écran, `retryHealthWrite()` réécrit A (`writes[0] == writes[1]`), puis plus rien ne repart.
- `testDiscardAfterFailedWriteKeepsQueue` : après refus, `discard()` efface le snapshot, la file garde A.
- Modifié `testFinishDuringRestoreCatchUpWritesHealth` : fin attendue `savedAt + 5 s` (18 075), pas l'heure du relancement (18 100) ; `store.load()?.finishedAt` la porte.

## Résultats des tests (simulateur iPhone 17 Pro, `-parallel-testing-enabled NO`)

| Passe | Journal | Tests | Échecs | Code de sortie |
|---|---|---|---|---|
| 1 | test-run-1.log | 39 | 0 | absent : commande tuée par le harnais à 600 s pendant la fin de xcodebuild |
| 2 | test-run-2.log | 39 | 0 | absent : même cause |
| 3 | test-run-3.log (détachée, nohup) | 39 | 0 | **0**, `** TEST SUCCEEDED **` |

TabataCatchUpTests 11 (2 nouveaux), TabataSessionTests 28 (5 nouveaux, 1 modifié). 0 avertissement dans les fichiers touchés. Aucune passe de correction nécessaire.

**Simulateur seulement.** L'écriture réelle dans Apple Santé (autorisation, workout visible, remplacement par `syncIdentifier`) n'est pas testée : il faut un iPhone.
