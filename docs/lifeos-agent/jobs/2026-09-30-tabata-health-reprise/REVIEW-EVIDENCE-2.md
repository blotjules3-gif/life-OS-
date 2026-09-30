# Tabata : preuves completes (30 sept., session Claude hors boucle)

Le passage 1 de la reprise a ete bloque parce que les extraits transmis etaient tronques.
Ce fichier donne les methodes COMPLETES, la liste des tests et leur resultat dans la suite
complete lancee le 30 sept. (journal: `test-run-4-full-suite.log`, extrait Tabata ci-dessous).

## `private func startHealthWrite` (LifeOS/Services/TabataSessionStore.swift)

```swift
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
```

## `private func finishHealthWrite` (LifeOS/Services/TabataSessionStore.swift)

```swift
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
```

## `func tick()` (LifeOS/Modules/TabataView.swift)

```swift
    /// Avance d'autant de secondes qu'il s'en est RÉELLEMENT écoulé.
    ///
    /// Absence courte (écran verrouillé pendant un round): rattrapée d'un coup.
    /// Absence plus longue que `maxUnattendedGap`: la séance se met en PAUSE là
    /// où elle en était, et `interruptionGap` le dit à l'écran. Personne ne se
    /// voit créditer une heure d'effort pour avoir posé son téléphone.
    func tick() {
        let currentNow = self.now()
        let base = lastTick ?? currentNow
        var steps = 1
        if let last = lastTick {
            let gap = currentNow.timeIntervalSince(last)
            if running, gap > Self.maxUnattendedGap {
                pause()
                interruptionGap = gap
                onStateChange?()
                return
            }
            steps = Int(gap.rounded())
        }
        lastTick = currentNow
        guard steps > 0 else { return }
        let catchUp = steps > 1
        steps = min(steps, 3600)
        for i in 0..<steps {
            guard running, phase != .idle, phase != .done else { break }
            // Heure réelle de la seconde consommée: une fin en rattrapage est
            // datée de sa vraie frontière, jamais de l'heure du retour.
            catchUpBoundary = min(currentNow, base.addingTimeInterval(Double(i + 1)))
            step(silent: catchUp)
        }
        catchUpBoundary = nil
        if running && intervalTotal > 0 {
            intervalEnd = currentNow.addingTimeInterval(Double(remaining))
        }
        onStateChange?()
    }
```

## `private func finish()` (LifeOS/Modules/TabataView.swift)

```swift
    private func finish() {
        pause()
        phase = .done
        if finishedAt == nil { finishedAt = catchUpBoundary ?? now() }
        remaining = 0
        intervalStart = nil
        intervalEnd = nil
        TabataSound.shared.finish()
        onFinished?()
        onStateChange?()
    }
```

## `static func restore(` (LifeOS/Modules/TabataView.swift)

```swift
    /// Reconstruit un moteur depuis un snapshot.
    /// - En pause: repris tel quel, quel que soit le temps passé.
    /// - En cours: le temps depuis `savedAt` est traité par `tick()`, donc
    ///   rattrapé si court, sinon mis en pause (`interruptionGap`).
    /// - `catchUp: false` remet le moteur en marche SANS ce premier `tick()`:
    ///   l'appelant le lance lui-même après avoir posé `onFinished`. Sinon une
    ///   séance qui se termine pendant le rattrapage finit sans que personne ne
    ///   soit prévenu, et Santé n'est jamais écrit.
    static func restore(_ s: TabataSessionSnapshot, now: @escaping () -> Date,
                        catchUp: Bool = true) -> TabataEngine {
        let e = TabataEngine(cfg: s.config)
        e.now = now
        e.sessionID = s.sessionID
        e.sessionKey = s.sessionKey
        e.sessionName = s.sessionName
        e.sessionIcon = s.sessionIcon
        e.accentColorHex = s.accentColorHex
        e.exercises = s.exercises
        e.phase = Phase(rawValue: s.phase) ?? .idle
        e.round = s.round
        e.cycle = s.cycle
        e.remaining = max(e.phase == .done ? 0 : 1, s.remaining)
        e.intervalTotal = max(1, s.intervalTotal)
        e.startedAt = s.startedAt
        e.finishedAt = s.finishedAt
        e.activeSeconds = s.activeSeconds
        e.workSecondsDone = s.workSecondsDone
        e.completedSteps = Set(s.completedSteps)
        if e.phase == .idle || e.phase == .done { return e }
        e.intervalStart = now()
        if s.running {
            e.run()
            e.lastTick = s.savedAt
            if catchUp { e.tick() }
        }
        return e
    }
```

## Resultat, suite complete du 30 sept. (768 tests, 0 echec, 1 ignore)

```
Test Case '-[LifeOSTests.TabataCatchUpTests testBeginRecordsStartFromInjectedClock]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testBeginRecordsStartFromInjectedClock]' passed (0.323 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testCatchesUpAfterBackgroundGap]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testCatchesUpAfterBackgroundGap]' passed (0.002 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testCatchUpCrossesPhaseBoundary]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testCatchUpCrossesPhaseBoundary]' passed (0.017 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testFinishDuringCatchUpIsDatedAtRealBoundary]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testFinishDuringCatchUpIsDatedAtRealBoundary]' passed (0.085 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testFinishOnNormalTickIsDatedNow]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testFinishOnNormalTickIsDatedNow]' passed (0.341 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testGapUnderLimitIsCaughtUp]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testGapUnderLimitIsCaughtUp]' passed (0.096 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testOneTickRemovesOneSecond]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testOneTickRemovesOneSecond]' passed (0.002 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testPausedEngineIgnoresElapsedTime]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testPausedEngineIgnoresElapsedTime]' passed (0.002 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testResetClearsStart]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testResetClearsStart]' passed (0.017 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testResetReturnsToIdle]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testResetReturnsToIdle]' passed (0.001 seconds).
Test Case '-[LifeOSTests.TabataCatchUpTests testVeryLongGapPausesInsteadOfCrediting]' started.
Test Case '-[LifeOSTests.TabataCatchUpTests testVeryLongGapPausesInsteadOfCrediting]' passed (0.001 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testConcurrentDoneCallbacksWriteOnce]' started.
Test Case '-[LifeOSTests.TabataSessionTests testConcurrentDoneCallbacksWriteOnce]' passed (0.100 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testDelayedFailureThenRelaunchKeepsOriginalFinishTime]' started.
Test Case '-[LifeOSTests.TabataSessionTests testDelayedFailureThenRelaunchKeepsOriginalFinishTime]' passed (0.096 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testDiscardAfterFailedWriteKeepsQueue]' started.
Test Case '-[LifeOSTests.TabataSessionTests testDiscardAfterFailedWriteKeepsQueue]' passed (0.193 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testFailedHealthWriteIsNotMarkedSavedAndCanBeRetried]' started.
Test Case '-[LifeOSTests.TabataSessionTests testFailedHealthWriteIsNotMarkedSavedAndCanBeRetried]' passed (0.190 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testFailedWorkoutSurvivesNewSessionAndRelaunch]' started.
Test Case '-[LifeOSTests.TabataSessionTests testFailedWorkoutSurvivesNewSessionAndRelaunch]' passed (0.195 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testFinishDuringRestoreCatchUpWritesHealth]' started.
Test Case '-[LifeOSTests.TabataSessionTests testFinishDuringRestoreCatchUpWritesHealth]' passed (0.299 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testHealthNotWrittenWhenActiveTimeUnderOneMinute]' started.
Test Case '-[LifeOSTests.TabataSessionTests testHealthNotWrittenWhenActiveTimeUnderOneMinute]' passed (0.105 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testHealthWindowExcludesHourLongPause]' started.
Test Case '-[LifeOSTests.TabataSessionTests testHealthWindowExcludesHourLongPause]' passed (0.304 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testHealthWrittenOnceEvenAfterRestore]' started.
Test Case '-[LifeOSTests.TabataSessionTests testHealthWrittenOnceEvenAfterRestore]' passed (0.293 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testInFlightWriteSurvivesSessionReplacementAndTermination]' started.
Test Case '-[LifeOSTests.TabataSessionTests testInFlightWriteSurvivesSessionReplacementAndTermination]' passed (0.297 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testJumpingThroughWholeSessionIsNotAWorkout]' started.
Test Case '-[LifeOSTests.TabataSessionTests testJumpingThroughWholeSessionIsNotAWorkout]' passed (0.106 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testKeeperPersistsOnEveryStateChangeAndClearsOnDiscard]' started.
Test Case '-[LifeOSTests.TabataSessionTests testKeeperPersistsOnEveryStateChangeAndClearsOnDiscard]' passed (0.004 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testKeeperRestoresFromStoreBeforeDefaults]' started.
Test Case '-[LifeOSTests.TabataSessionTests testKeeperRestoresFromStoreBeforeDefaults]' passed (0.017 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testPausedSessionResumesWhereItStoppedAfterRelaunch]' started.
Test Case '-[LifeOSTests.TabataSessionTests testPausedSessionResumesWhereItStoppedAfterRelaunch]' passed (0.041 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testRelaunchRetriesUnsavedFinishedSession]' started.
Test Case '-[LifeOSTests.TabataSessionTests testRelaunchRetriesUnsavedFinishedSession]' passed (0.402 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testRestartAfterLongGapPausesWithoutCrediting]' started.
Test Case '-[LifeOSTests.TabataSessionTests testRestartAfterLongGapPausesWithoutCrediting]' passed (0.014 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testRestartWhileRunningCatchesUpShortGap]' started.
Test Case '-[LifeOSTests.TabataSessionTests testRestartWhileRunningCatchesUpShortGap]' passed (0.021 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testRestoreDoneSnapshotStaysDone]' started.
Test Case '-[LifeOSTests.TabataSessionTests testRestoreDoneSnapshotStaysDone]' passed (0.117 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testRetryCoversQueuedSessionNotOnlyLiveOne]' started.
Test Case '-[LifeOSTests.TabataSessionTests testRetryCoversQueuedSessionNotOnlyLiveOne]' passed (0.401 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSelectingFutureStepIsNotCompletedWork]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSelectingFutureStepIsNotCompletedWork]' passed (0.014 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSelectingPastStepMakesItCurrentAgain]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSelectingPastStepMakesItCurrentAgain]' passed (0.064 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSelectWhilePausedStaysPaused]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSelectWhilePausedStaysPaused]' passed (0.001 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSequenceCoversWholeSessionInOrder]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSequenceCoversWholeSessionInOrder]' passed (0.001 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSkipBackwardGoesToPreviousWorkRound]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSkipBackwardGoesToPreviousWorkRound]' passed (0.060 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSkipForwardToEndDoesNotCompleteAnything]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSkipForwardToEndDoesNotCompleteAnything]' passed (0.106 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testSnapshotRoundTripKeepsEverything]' started.
Test Case '-[LifeOSTests.TabataSessionTests testSnapshotRoundTripKeepsEverything]' passed (0.069 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testStatusesPastCurrentFutureAcrossPhases]' started.
Test Case '-[LifeOSTests.TabataSessionTests testStatusesPastCurrentFutureAcrossPhases]' passed (0.186 seconds).
Test Case '-[LifeOSTests.TabataSessionTests testStoreIgnoresUnreadableSnapshot]' started.
Test Case '-[LifeOSTests.TabataSessionTests testStoreIgnoresUnreadableSnapshot]' passed (0.005 seconds).
	 Executed 768 tests, with 1 test skipped and 0 failures (0 unexpected) in 56.416 (56.796) seconds
```
