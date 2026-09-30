# LifeOS real-products brief: continuation checkpoint

Brief: `~/Downloads/claude-lifeos-real-products-prompt.md` (received 2026-09-28).
Ledger: `docs/feature-parity/ledger.json` (87 rows). This file is the working log:
what was done, the evidence, and exactly where to resume. Update it every session.

Rules from the brief that change how work is closed:
- A row is not done because a screen opens or unit tests pass. It needs the journey,
  stored results, failure cases and light/dark checked.
- No upload or push without separate authorization. (Standing "push to phone" order
  is suspended for this brief: the brief says so explicitly.)
- Never invent products, prices, evidence or passing results.

## Build under test

- Branch `lifeos/chifco-testflight`, base commit `e56390f26`, plus the working tree
  (49 files already modified before this session, preserved, none reverted).
- iPad desktop layout: iPad Pro 13" (M5) simulator `C5FA9814-CAF4-4198-BEA2-DA4A06D73269`,
  launched with `-desktop` (script `scratchpad/ipadrun.sh`). Real taps through the
  simulator control, not launch hooks.
- Mac Catalyst: builds with `CODE_SIGN_IDENTITY=-` and launches after ad-hoc re-sign
  with minimal entitlements. **Clicking it was declined** (computer-use access denied),
  so Catalyst keyboard navigation and window resizing are NOT verified yet.

## Priority 1: desktop navigation

| Item | Status | Evidence |
|---|---|---|
| Root cause: Stepometer, Fitbot, Hevvy, GOMOB, Yuko did nothing on desktop | **Fixed, verified on iPad desktop layout** | The desktop detail pane rendered `CategoryHubView` with no navigation container, so every `NavigationLink` tile was inert. TabaTime worked only because it uses `fullScreenCover`. Reproduced by tapping Stepometer (no change after 3 s) and TabaTime (opens). Fix: `MacDesktopMainView` wraps the category pane in `NavigationStack`. After: Stepometer, Fitbot, Hevvy, GOMOB (Sport) and Yuko (Nutrition) all open, each with a working back button. |
| `-desktop` debug flag had stopped working | Fixed | The working tree switched layout selection to window shape and no longer read the flag. `MainTabView.realBody` reads it again, DEBUG only. |
| Sidebar category items | Verified (Sport, Nutrition) | Tapped, correct category opens. |
| Other screens own their container | Checked in code | Profile, Wake, Assistant, Tabata have their own `NavigationStack`; wrapping them again would nest stacks, so only the category pane was wrapped. |
| Every tool destination opens | **83 / 83** (the hub registers 83 tools; the ledger lists 87 rows including 4 outside categories) | Debug runner `-routeSmoke` (`LifeOS/Core/RouteSmoke.swift`) pushes each tool in a real `NavigationStack`, or presents it full screen, and writes `Documents/routesmoke.txt` after each one. First pass crashed after Floé; after the fix below: `# FIN: 83 apparus, 0 absents`, no new crash report. This proves each destination builds and appears inside a navigation container; the tap path itself is shared by every tile (`toolLink`) and was tapped by hand for 6 tools on desktop plus Floé on phone. |
| **Floé, Klue, Floé Stats unusable, and a crash** | **Fixed** | These three wrapped their screen in their own `NavigationStack`, nested inside the category's. On phone, tapping Floé threw you back to the Categories list (reproduced by tap); leaving it crashed SwiftUI (`NavigationColumnState.boundPathChange`, SIGTRAP, report `LifeOS-2026-09-28-040913.ips`). Replaced with `Group`. After: Floé opens, back returns to the Cycle hub. Guard test `NavigationNestingTests` fails if any pushed tool reintroduces a root `NavigationStack`. |
| Catalyst keyboard navigation, window resizing | Not verified | Needs clicks on the Mac app. |
| Dashboard buttons opening the coach instead of a tool | Checked, none found | "Ton coach" opens the coach (intended). Quick chips create to-dos. |

## Priority 2: shared records and truthful success

| Item | Status | Evidence |
|---|---|---|
| Single write path for food | **Done** | New `LifeOS/Services/FoodLogService.swift`. All 6 writers now use it: PhotoCalorie (2 paths), FoodSearch product detail, CalAI barcode sheet, Nutrition add sheet, AddAnything quick add. Grep for `FoodEntry(` outside the service, the model and the debug seed returns nothing. |
| False success on save failure (PhotoCalorie) | **Fixed** | On failure: inserted rows are removed from the context, the photo and lines stay, an orange message with "Réessayer" appears. Success toast only after a real save. |
| Duplicate entries on repeated taps | Fixed | `saving` guard + disabled button (PhotoCalorie); FoodSearch disables "Ajouté" (it stayed enabled and each tap added the product again). |
| Meal date | Added | "Jour du repas" picker in both photo flows; `mealDate(day:)` keeps the chosen day at the current hour. |
| Edit a logged meal | Added | `FoodEntryEditor` (tap a row in Yumzio journal, or context menu). Update and delete go through the service and revert on failure. |
| Coach silently logging photo estimates | **Changed** | The coach used to insert a `FoodEntry` from an image label with no portion. It now proposes and sends the user to Nutrition. Nothing is written without the user seeing the estimate. |
| Dashboards read the shared record | Checked | Home, desktop, profile, briefing, score ring, coach context all derive calories from `FoodEntry` via `@Query` / `caloriesToday`. No independent counter found. |
| Unit tests | 8/8 pass | `LifeOSTests/FoodLogServiceTests.swift`: all-or-nothing write, failed save leaves nothing, retry writes once, invalid drafts refused, edit recalculates and reverts, delete, historical meal not counted today, meal date around midnight. Negative control run on the rollback test. |
| Full journey on device | **Passed, manual entry path** | iPhone 17 Pro Max sim, real taps: Yumzio "+" → name + 420 kcal → Ajouter → remaining 2200→1780, meal listed, 7-day avg 420 → tap row → edit to 380 → remaining 1820, avg 380 → relaunch → Nutrition recap 380 kcal → delete (confirmation) → 2200 / 0 → relaunch → still 0. Live Open Food Facts search ran and correctly said "Aucun produit trouvé" for a made-up name. |
| Photo path and barcode path on device | Not yet run | Needs a photo in the simulator library and a real barcode. |
| Same consistency pass for workouts, finance, hydration | Not started | Finance already has `LedgerService` (earlier session). |

## Tabata theme

| Item | Status | Evidence |
|---|---|---|
| Forced dark mode | **Fixed** | Removed both `.preferredColorScheme(.dark)`. New `TabataPalette` (background, sheet, panel, card, ink, scrim) follows the theme; 60+ hardcoded white/black neutrals replaced. Neon phase accents kept; as TEXT in light mode they use deeper shades (volt 0x00F076 on white is 1.4:1). |
| Ready screen light / dark | Verified | Screenshots both themes, iPhone sim. |
| Running workout, light | Verified | Timer 28, "EFFORT", "DONNE TOUT !" readable. |
| Pause, light | Verified | Tapped pause. |
| Settings sheet, light | Verified | "Réglages Tabata" renders light. |
| Completion summary | Code changed, **not screenshot** | Needs a full session played to the end. |

## Questionnaire lifecycle (one shared implementation)

All 9 questionnaires (nutrition, fitness, sleep, finance, productivity, mind, looks,
cycle, mobility) open through `CategoryFlowView`, which now injects the category into
the shared `SetupFlow` shell. No questionnaire needed its own lifecycle code.

| Item | Status | Evidence |
|---|---|---|
| States not-started / skipped / partial / completed | Done | `SetupStatus`, `CategorySetup.status`, stored under `setup.state.*`, `setup.draftPage.*`, `setup.pageCount.*`. Unit test `testStatusLifecycleSkipPartialCompleteEdit`. |
| Visible re-entry after skipping | Done | Hub card "Personnalise X / Compléter / Reprendre (étape n sur N)" until completed, then "Modifier mes réponses et objectifs". Before: only an unlabeled slider icon. Same hub on desktop. |
| Resume after relaunch | Done, **with a limit** | Verified on device: Sleep, step 2, "Plus tard" → hub card "Personnalisation en cours · Étape 2 sur 3" → app relaunch → still there → "Reprendre" opens at step 2. Limit: answers resume fully only for Nutrition (writes settings as you go); the other 8 keep answers in memory until the end, so earlier pages reopen with the last SAVED values. Card wording says "tu reprends là où tu t'étais arrêté", not "tes réponses sont gardées", to stay true. |
| Skip | Verified on device | "Plus tard" on step 1 without answering → card "Personnalise Sommeil & réveil · Tu l'avais mis de côté · Compléter". |
| Summary before applying | Verified on device | Last button "Voir le résumé" → sheet "Vérifie avant d'appliquer": "Heure de réveil 07:00 → 08:00". Nothing is written to the database before "Appliquer". |
| Apply → completed | Verified on device | Card disappears; "Modifier mes réponses et objectifs" appears at the bottom of the hub. |
| Edit completed answers, prefilled | Verified on device | Reopens at step 1 with the saved 8 h; header shows "Annuler". Fitness did NOT save level / frequency / place / focus muscles before: now saved and reloaded. |
| Cancel | Settings: unit-tested; database: nothing to undo by design | Decision after measurement: SwiftData undo removes saved inserts but does NOT restore saved deletes (the old gym plan stayed deleted, test failed 3 times). So commits run only on "Appliquer"; cancel only restores settings written live (Nutrition). Only the settings questionnaires own are watched: on device the first version also caught background cache writes (weekly suggestion, tool names) in the summary. |
| Existing logs preserved | By design | Commits never touch WorkoutSet / FoodEntry / Txn. |
| Desktop | Same code path | The hub card and shell are shared; not yet tapped on the desktop layout. |

Bugs fixed on the way:
- Re-running the Nutrition questionnaire duplicated shopping items and supplements
  (and their daily reminders) every time. Now adds only what is missing; after a
  cancel, reminders for supplements that no longer exist are removed.
- Finance questionnaire wrote `account.balance` directly, which the ledger's next
  recompute overwrote. New `LedgerService.setCurrentBalance` adjusts the opening
  balance so the derived balance lands on the entered value.

## Brief 2 (2026-09-28): defects A to H

### B. Medication reminders: FIXED, tested
- **Weekly + end date bug:** a weekly medication with an end date was scheduled as a
  daily repeating reminder, so it kept ringing after the end date and on wrong days.
  New pure planner `MedicationSchedule.plan(...)`: open-ended and started gives a
  repeating reminder; a bounded course or a future start gives concrete dated
  reminders inside 14 days (weekly keeps the start weekday, past times skipped,
  24 per medication at most, under iOS's 64 pending limit). Renewed on every return
  to the foreground (`MedicationReminders.renewAll`).
- **Cancel/create race:** removal was fire-and-forget, so a fast edit could delete
  the reminders it had just created. `NotificationManager.replacePending(prefix:with:)`
  awaits the pending list, removes, then adds, in that order.
- Tests: `MedicationPlanTests` 6/6.

### C. Document scan: FIXED, tested, verified on simulator
- `DocScan.save()` showed "rangé" and cleared the form after a bare insert. It now
  saves, and on failure deletes the record and the page files and keeps the pages
  on screen with a retry message.
- Page strip before saving: reorder, rotate (pixels redrawn so OCR and PDF see the
  page upright), remove, add pages (menu: Scanner / Photo / Fichier / Recommencer).
  OCR re-runs on the current order. A title already there survives adding a page.
  Once a document has pages, new input always ADDS; the big source buttons hide.
- Reader "Exporter" shared loose JPEGs. Now builds ONE PDF (`DocumentPDF`, A4, one
  page per image, aspect kept). A missing page file blocks the export with a message
  instead of producing a short PDF.
- Import errors (unreadable file, photo that fails to load) are shown, not dropped.
- Verified with two synthetic invoice pages added to the simulator library: OCR,
  category Facture, reorder and back, save, relaunch, vault shows "2 pages", share
  sheet shows "Document PDF · 154 ko".
- Tests: `DocumentPDFTests` 5/5.
- New debug flag `-shotTool "<titre>"` opens any tool directly (DEBUG only).

### D. Face analysis symmetry: FIXED, tested (not seen on a real portrait)
- The axis was the midpoint of the two eyes, so "left eye to axis" and "right eye
  to axis" were equal by construction: that part always measured zero.
- New `FaceGeometry` (pure, no Vision): axis fitted through Vision's median line
  (nose crest as fallback, no number if neither exists). Each right point is
  mirrored across the axis and compared with its left twin (eyes, brows, mouth
  corners, jaw contour). Head tilt is compensated. Head turn over 12 degrees shows
  "Non mesuré" with the reason, since perspective alone narrows one side.
- Points now in image pixels, not box-relative units, so width/height is not bent.
- Removed the big "Harmonie géométrique" score and the "ideal" grades. Each value
  is shown with what it measures and its limits. A test fails if "beau", "idéal",
  "harmonie" or "/100" comes back in the text.
- Tests: `FaceGeometryTests` 9/9, including a negative control showing the old
  formula returns zero on a face with a shifted eye.

### E. Backup and profile promises: FIXED, tested
- **Full restorable backup** (`FullBackup`): one `.lifeosbackup` file with the whole
  SwiftData base (`VACUUM INTO`, a consistent copy even with the app open), every
  file in Documents (photos, scanned pages, recordings), the app and widget-group
  settings WITHOUT secrets (API keys, tokens). Versioned manifest, SHA-256 per file.
- **Restore**: file checked (magic, format version, every checksum, SQLite
  integrity, row counts equal to the manifest), staged, and applied at the next
  launch BEFORE the base opens, from both paths that open it. The previous data is
  moved to `Application Support/LifeOSBackup-restore-<date>`, never deleted. If a
  move fails halfway, everything moves back. A launch alert says what happened.
- The JSON export stays, relabelled "Résumé lisible", with a footer that says it is
  not a backup. FAQ updated.
- Proof: `FullBackupTests` 6/6. A base with documents, trips, cycles, meals and a
  habit is backed up, restored onto a "device" that had other data, and every row
  and file comes back; the old state is found in the set-aside folder; a secret
  never enters the file; one flipped byte is refused with nothing staged; a
  foreign file and a newer format give clear messages; paths cannot escape.
- **Profile**: there is no iCloud capability and no online account in this build.
  Removed "Synchronisation active", "Chiffrement bout en bout · Temps réel · Actif",
  the "Prêt" device pills, the auto-sync paragraph, and the "Compte vérifié & actif"
  badge built from a leftover email. `AccountStatus` derives every label from real
  state (`LocalStore.syncActive` = the running container really uses CloudKit).
  The iCloud toggle in Settings, which silently switched itself off at the next
  launch, is replaced by the real storage state. `AccountStatusTests` 3/3, one of
  which fails if any of those phrases comes back.
- Not done: no backup on a schedule; restore not yet exercised by hand on device.

### F. Daily energy score: FIXED, tested
- Sleep counts only if entered today (it was read with no date). Habits count only
  if planned today (a rest day lowered the score). Water and sleep use the user's
  goals (`waterGoal`, `sleepGoalHours`), not fixed 2,500 ml and 8 h. The latest mood
  of the day wins (it was an arbitrary one). The morning briefing now uses the same
  path (it had its own copy with the same flaws).
- The profile shows each input with its value and time, what is missing, and the
  coverage ("Calculé sur 55 % des critères").
- `EnergyScoreTodayTests` 7/7.

### G. Amounts that silently became 0: FIXED, tested
- `AmountInput` reads 12,50 / 12.50 / 1 234,56 (incl. the narrow no-break space iOS
  uses) / 1.234,56 / 1,234.56 / "12 €", and returns an explained error for anything
  else. `AmountInputTests` 3/3.
- Finance forms (account, operation, envelope, subscription, split, savings) show
  the error under the field and cannot be saved with it. They save and close only
  if the base wrote. An operation with no account used to close the form and save
  nothing: now it says to create an account first. A split with nobody selected is
  refused.
- Same fix in quick add, investments and fuel logs.
- **Money bug found on the way**: quick-add "Dépense" stored +20 € for a 20 € expense,
  so the balance went UP. Now negative, like the Finance screen.

### H. Translator on Mac: FIXED, proven on the real Mac app
- The Mac branch was excluded by `#if` and showed "iOS 18 requis". Apple's
  Translation framework exists on Mac Catalyst 26+. Enabled; the fallback message
  now names the right system for each platform.
- Proof on the real Catalyst build (DEBUG probe `-translateProbe`, since Mac
  screenshots are blocked here): "Bonjour, où est la gare ?" -> "Hello, where is the
  train station?".

### Questionnaires keep their ANSWERS: FIXED, tested, verified on simulator
- 9 questionnaires held answers only in memory. New `SetupDraft` + `SetupDraftIO`:
  each gives the shared flow a save/restore pair. Saved on every page change and
  whenever the app leaves the foreground (a killed app never taps "Plus tard").
  Restored on reopen, after the module's own loader (found by testing: restoring in
  a `.task` was overwritten by the loader). Opening then leaving is not "answered".
  Cleared when applied.
- Verified: Sleep questionnaire, values changed, Home button, app killed,
  relaunched: reopens on page 2 with 10 h, page 1 shows 4 h, exactly as left.
- `SetupDraftTests` 4/4, one of which fails if a questionnaire is not wired.

### Test runs
- Full unit suite after all of the above, Yuko included: **580 passed, 0 failed**
  (non-parallel run; the parallel clone run hangs on this machine, use
  `-parallel-testing-enabled NO`).

### A. Yuko: REBUILT, tested, verified on live data (phone simulator)
- **Data** (`ProductCatalog`): Open Food Facts (food, drinks, supplements) and Open
  Beauty Facts (cosmetics). Real front photo fields, ingredients, allergens, traces,
  additives, labels, categories, countries, serving size, last update. A missing
  nutrient stays unknown (shown "—"), a true zero stays zero. Three distinct
  outcomes: found / not in either base / unavailable (network, timeout, 5xx). Offline
  falls back to the cache with its date. Search keeps water and zero drinks, pages,
  and throws away answers from an older query.
- **Search engine**: the legacy `cgi/search.pl` answered 503 to every request on
  28 Sept (also from curl). Search now uses the current official engine
  `search.openfoodfacts.org` (search-a-licious) with the old one as fallback. That
  engine returns no ingredients/additives, so results are "short records": the row
  says "ouvrir", and opening loads the full record before scoring.
- **Score** (`ProductScore`, "LifeOS Qualité 1.0"): not the Yuka score, and not a
  conversion of A–E. Food/drinks: nutrition 60 (from nutrients, published
  Nutri-Score thresholds, fruit/veg part omitted and said so; sweetener penalty for
  drinks), additives 30 (small table from EFSA/IARC/EU rules, "à surveiller" not
  "dangereux"), organic 10. Water: own rule, and flavoured/sweetened waters are
  excluded. Cosmetics: ingredient penalties (high/moderate/sensitivity, perfume
  counted once). Supplements such as whey: no score on 100, with the reason.
  Missing base nutrient or ingredient list = "non évalué", never a fake number.
  Unknown fiber/protein count as 0, never as a bonus. Official Nutri-Score and NOVA
  shown separately under their real names. Diet preferences shown apart ("Pour toi").
- **Screens** (`Yuko.swift`): name search, code entry and camera scan always
  available (camera only where it exists); real thumbnails and large photo (cache,
  loading, broken, absent states, proportions kept); breakdown per component;
  nutrition table; ingredients; allergens and traces in French; flagged additives
  with reasons; history (with age), favorites, comparison, alternatives taken from
  the same category and scoring higher; add to journal via FoodLogService; unknown
  product form with label photo + OCR, saved locally as "non vérifiée"; method and
  coverage sheet. No price anywhere: no verified price source.
- History, favorites and local records live in `Documents/Yuko`, so the full backup
  carries them. The meal-logging screens keep their small adapter, which no longer
  drops water.
- Verified live: Nutella 47 (photo, breakdown), spring water 100, Coca-Cola Zero 60
  (sweetener and additives counted), whey "no score", Mixa shampoo 97, unknown code
  form, search "yaourt nature" with photos, full record 79, six real alternatives.
- Tests: `ProductCatalogTests` 11/11 (fake network: photos decoded, unknown stays
  nil, network ≠ absent, 5xx, cosmetic base, offline cache, water/zero kept,
  paging, fallback engine), `ProductScoreTests` 12/12.
- Not done: comparison checked only by build; camera scan not tested on a real
  iPhone; OFF contribution upload (needs an OFF account) not built, local only.

### Also fixed on the way
- **Recap cards invented data**: with no night recorded the sleep card showed
  "7.5h" and "85%"; other cards showed hard-coded "Actif", "À jour", "Sécurisé",
  "Prêt". All replaced by real counts (`RecapHonestyTests` guards it).
- Glass surface script: 4 text fields moved to nested glass (their hand-drawn
  outline was a second edge). CV export button moved to the glass button style.

## Found while working, not yet fixed

- **Fitbot is a bare weekday list** with "À définir" rows. Confirms the gym-planning gap.
- `DataEraser` wipes ~52 model types by name; the schema may hold more. The full
  backup does not have this problem (it copies the base), but erase might.

## Audit V2 (`PROMPT-CLAUDE-LIFEOS-AUDIT-V2.md`), Priority 1: done, tested

### E. Backup root on a Mac without sandbox (found live, most dangerous)
- The installed Mac copy runs without sandbox, so "Documents" was the REAL
  `~/Documents`. LifeOS already wrote `analytics.jsonl` there, next to Theo's
  `Codex`, `Insta360`, `Untitled.mp4`. A backup would have copied them; a restore
  would have MOVED them aside. No backup/restore ever ran on the Mac.
- New `AppPaths`: one storage root for the whole app. On an unsandboxed Mac it is
  `~/Library/Application Support/com.chifandco.lifeos/{Documents,...}`; elsewhere
  the app's own folders. All 12 writers moved to it. At launch, only LifeOS-owned
  files (fixed names, `<prefix>-<UUID>.jpg`, `dream-<time>.m4a`) move out of
  `~/Documents`, never overwriting.
- `FullBackup.checkRoot` refuses `/`, short paths, and on an unsandboxed Mac any
  personal folder or any path outside the LifeOS folder. Folder listing errors now
  fail the backup instead of looking empty. Rollback no longer deletes the safety
  copy unless every file came back; otherwise `rollbackIncomplete` says what did
  not return and where the copy is.
- Verified on the real Mac after reinstall: `analytics.jsonl` moved to the private
  folder, `~/Documents` listing identical otherwise.
- Tests: `FullBackupSafetyTests` 4 (personal folders refused, forward failure
  restores everything, forward+rollback failure keeps the copy, migration moves
  only LifeOS files with sentinel user files untouched).

### A. Scores
- Cosmetics: a score needs >= 80 % of ingredients RECOGNISED (flagged, or in the
  new `CosmeticINCI` reference of ~300 common names + name patterns) and >= 3.
  "INGREDIENT_UNRECOGNISED_123" is now "non évalué" with the unknown names listed.
  Found on the way: the label cleanup cut a leading "ingredient" word; fixed.
- Water: the water method now REQUIRES energy, sugars and the ingredient list;
  missing = "non évalué". Unknown additives are no longer assumed absent anywhere.
- Protein powders: new documented method (protein density /50, sugars /20,
  additives /30), limits stated. Other supplements stay "no score" with reason.
- Tests: 17 score tests incl. recognised/unknown/mixed, empty list, water without
  data, sugary water, whey, sweetened whey, vitamins.

### B. Yuko catalogue and persistence
- Cosmetics search by name (Open Beauty Facts), type switch in the screen.
  Alternatives now for cosmetics and protein powders too, same method only.
- `ProductStore`: every mutation writes FIRST, then updates the screen; failures
  surface (history, favorites, local records). An unreadable file is set aside as
  `<name>.illisible-<date>` and reported, never overwritten. Tests 3.
- Diet compatibility text no longer implies a guarantee.

### C. Reminders
- One global budget (iOS 64 per app, minus other pending, minus 8 spare). Repeating
  first, then the nearest dated doses across all treatments. 60 days x 3/day now
  covers ~18 days instead of 7. Each reconcile waits for the previous one (no old
  plan coming back). Coverage shown under each medication, "notifications refusées"
  shown when denied. Background refresh (existing coach task) also renews. Local
  clock times kept across DST (test on 25 Oct).
- Not proven: behaviour with the app never reopened for weeks (iOS decides when
  background refresh runs; the coverage line says how far it goes).

### D. Erase
- `LocalStore.modelTypes` is the single list for schema and erase (54 types, incl.
  the two forgotten). Erase covers pending restore, all types (then recounts),
  LifeOS files, safety copies, product cache, Yuko in-memory lists, settings,
  widget group, pending and delivered notifications. Returns a report; the screen
  shows "Effacé" only if every step succeeded, otherwise lists failures.
- Tests: `DataEraserTests` 3 (schema coverage, full synthetic erase + reopen,
  refusal to empty a non-LifeOS root).

Full suite after Priority 1: **601 passed, 0 failed**. Mac app reinstalled with it.

## Audit V2, Priority 2 (started)

- **Xchange (converter)**: real rates. ECB daily reference rates (no key) first,
  ExchangeRate-API (open access, no key, attribution) ONLY for currencies the ECB
  does not publish (MAD, AED). 27 currencies. Cached with date; the screen shows
  source and date per currency, "Taux enregistrés il y a N h" offline, and
  "Taux intégrés (anciens)" with their date when offline without cache. Invalid
  amounts refused. Tests `ExchangeRatesTests` 5. Seen live on the simulator:
  "Taux à jour, USD : BCE, taux du 28 sept. 2026".
- **Zetty (CV)**: real A4 PDF (TextKit pagination, selectable text, accents,
  empty sections removed) with a preview sheet and export; text share kept as a
  secondary action. Tests `CVDocumentTests` 3 (accents readable in the PDF, 80
  experience lines flow onto 2+ pages with the last line present). Preview sheet
  built, not yet opened by hand.

## BLOCKER (28 Sept, 20:30): disk full
- `/System/Volumes/Data` down to ~1.5 GB free (460 GB disk). A test build failed
  in CodeSign ("internal error in Code Signing subsystem") because of it.
- Freed only my own outputs: old scratch build copies (1.8 GB), a useless iPhone
  Release build (179 MB), and the LifeOS-CI test simulator (erased, 7.1 GB ->
  28 MB). No local snapshots hold the space; free space kept dropping afterwards,
  so something else on the Mac is writing. `~/Library/Caches` is 7.3 GB (other
  apps, not touched).
- Builds are paused until there is room (a LifeOS build + test run needs ~3 GB).

## Mac app on this machine (28 Sept, 16:30)
- Theo reported "can't click on any app on desktop". The installed copy
  `~/Applications/LifeOS.app` was an ad-hoc local build from 27 Sept 04:37 (v1.0
  build 3), made BEFORE the desktop NavigationStack fix. Replaced with today's
  Debug Catalyst build, signed ad-hoc without entitlements like the old one (no
  sandbox, so it keeps reading `~/Library/Application Support/default.store`).
  Old copy kept at `scratchpad/LifeOS-backup-2026-09-27.app`. Launched, stays up,
  no crash report. Clicking not verified by me (no computer-use access).
- Release Catalyst build fails with ad-hoc signing on this Xcode ("Ad Hoc code
  signing is not allowed with SDK iOS 27.0"); Debug with the same flags works.

## Flight comparator "Envol" (`PROMPT-CLAUDE-COMPARATEUR-VOLS-INDEPENDANT.md`), 28 Sept
- **Own engine**: `flights-api/` (Cloudflare Worker, NOT deployed). Read its
  `README.md`: source matrix, costs, what is missing and who must do it.
- **No real source is connected.** Duffel adapter is written and tested against
  its documented format; it turns on when `DUFFEL_TOKEN` exists (Theo creates the
  account). Travelport is prepared and never shown active. Amadeus self-service
  closed on 17 July 2026, Kiwi is invite-only: **no second real source without a
  contract, so the product is NOT a working multi-source comparator yet.**
- `LifeOSTests/FlightSearchTests`: 12/12 (decodes a real engine response,
  validation before any call, filters, differences, trip note, local times,
  history/favourites/alerts saved, unsubscribe). `node flights-api/test-flights.mjs`: 27/27 (grouping without merging, source
  down = partial, timeout, cache, budget, price check same/changed/unavailable,
  alerts, auth, streaming).
- App: tool **Envol** in Voyage (`LifeOS/Modules/FlightCompare.swift`,
  `LifeOS/Services/FlightSearch.swift`). Checked by hand on the iPhone 17 Pro Max
  simulator with `node flights-api/dev-server.mjs` (two fictional sources):
  search, 4 offers from 2 sources on one card, plain explanation, alert refused
  on fictional prices, detail, price confirmed, added to a new trip marked "non
  réservé". Hooks: `-flightsAPI http://127.0.0.1:8787 -shotTool Envol
  -flightsQuery LIS-CDG-30`.
- **Found on the way and fixed: the app had NO calendar permission text**
  (`NSCalendarsWriteOnlyAccessUsageDescription`). iOS kills an app that asks for
  calendar access without it, so the existing "add to calendar" on tasks crashed.
- Not done: iPad and Mac checks of Envol, push alerts (needs APNs), city and
  nearby-airport search (needs a places API), price calendar (no honest source).

## Disk (28 Sept, 21:30): the real cause
- Memory swap was **15 GB** in `/System/Volumes/VM`, on the same disk. Three
  simulators booted by me plus builds pushed it up. Shut them down. Keep ONE
  simulator booted at a time here.
- Deleted my own regenerable build outputs: `build/{Build,Index...}` (Sep 11),
  the broken half-built `DerivedData/LifeOS-*`. Tests now run with
  `-derivedDataPath build/dd-shots`.

## Audit "état actuel" (28 Sept, soir): fixes

- **Envol P1, all fixed and tested** (`flights-api/README.md`, "Rules fixed after the
  audit"): atomic budget in a Durable Object (3 simultaneous searches, budget for 1 = 1 paid
  call), limit per IP, one currency per ranking with dated ECB conversion or set aside,
  filters per offer with recalculated ranking (the app no longer filters by itself), real
  child ages, baggage per traveller, calendar dates, price check with time limit and same
  itinerary, bounded cache with shared in-flight searches, progressive results that carry
  offers, alerts refused until the cron is on, paged cron with isolated failures.
  `node flights-api/test-flights.mjs` 40/40.
- **Travelport relabelled as a skeleton** everywhere (code, `/v1/providers`, README).
- **Local mode no longer skips the questionnaire** (`AuthView.enterLocalMode` set
  `onboardingDone = true`).
- **Coach card "Compris" (Theo's report):** not reproduced on the iOS 26.5 simulator (the
  button works there). Hardened anyway: no interactive glass on that button, a tap anywhere
  on the card or a swipe down closes it, opening the Assistant closes it for good, and the
  text now points to the real "Assistant" button. Checked on the simulator: a tap on the
  card text closes it and saves the flag.
- Found while testing: on a first launch, the Health sheet and the notification prompt open
  on top of the home screen at the same moment as the coach card.
- **Suite: 625 passed, 0 failed.**

## Yuko, 29 Sept (Theo: "photos fournisseur sur fond blanc, plus de note, il manque des produits")

- **Notes dans la liste:** les resultats de recherche etaient des fiches abregees (sans
  additifs), donc "—  ouvrir" partout. Chaque page est maintenant completee: cache local
  (7 jours), puis UNE requete groupee (`api/v2/search?code=...`), puis, si Open Food Facts
  la refuse (503, limite ~10/min), les 12 premieres fiches par l'API produit (100/min).
  Mesure sur "nutella": toute la premiere page notee (47, 47, 46, 47, 42, 50...).
- **Produits:** "Tout" par defaut (aliments ET cosmetiques), France d'abord puis le monde,
  les noms contenant les mots tapes devant.
- **Photos:** photo de la MARQUE quand c'est elle qui a depose la photo de face (compte
  "org-..."; ex. Ferrero, Barilla), sinon detourage Vision sur l'appareil, pose sur blanc,
  cadre carre serre, garde en cache. Ligne sous la photo: "Photo officielle de la marque"
  ou "Photo d'un contributeur, détourée sur fond blanc".
  **Le simulateur n'a PAS le detourage Vision** (test `ProductPhotoTests`, saute la-bas);
  le meme code a tourne sur ce Mac avec de vraies photos OFF: net sur un vrai produit,
  imparfait sur une mauvaise photo (carton en magasin).
- Limite honnete: Open Food Facts n'a de packshot officiel que pour les marques qui l'y
  deposent. Les autres photos restent des photos de clients, detourees.

## Yuko, 29 Sept, second pass ("none of the products are rated on the side")

Checked on the REAL screen with `-yukoCheck "q1,q2"` (types each search in the
running app, waits up to 60 s per row, writes `Documents/yuko-check.txt`).
- **Row requests are paced** (`CatalogBudget` 60/min, `ProductEnricher` 3 at a time,
  retry after 5 s on 429 / network / 5xx). A flood of per-row requests had got this
  Mac's IP banned (429) by Open Food Facts.
- **Moved products:** the food search engine still lists shampoos whose record moved to
  Open Beauty Facts (404 food side, 200 beauty side). `complete()` now checks the other
  base before marking a row failed. Shampoo page: 0 rated -> 6 rated, 0 rows stuck.
- **Cosmetics now use the EU CosIng INCI list** (33,602 names, CC BY 4.0,
  `Resources/cosing_inci_names.txt`, credited in the Method sheet). Tokenizer: "•"
  separator, common names in parentheses removed mid-name, "/" only splits when the
  whole name is unknown, formula codes "(F.I.L. ...)" ignored. Measured on 131 real
  Open Beauty Facts lists: 35 -> 27 under 80 % recognised, and the 27 left are OCR
  junk, addresses or marketing text, so "non évalué" is the honest answer there.
- Products that can never be rated (full record, no ingredient list) are ranked after
  rateable ones at equal relevance.
- Real screen, 29 Sept: nutella 12/12, jambon 12/12, yaourt 11/12, déodorant 8/12,
  crème 7/12, shampoing 6/12, gel douche 5/12. Every unrated row left has no ingredient
  list in the base (or an unreadable one).
- Suite: 648 pass, 1 skipped (Vision cutout, simulator only), 0 fail.

## Audit after build 42 (29 Sept): lots 1 and 2 done

Brief: `~/Downloads/AUDIT-APRES-BUILD42-2026-09-29.md`. Suite 672 pass, 1 skipped, 0 fail.

**Lot 1, HabitSync loss paths (all tested, negative control done):**
- A failed SwiftData read no longer counts as "no habits": the queue is kept (`fetchOverride` for tests).
- Legacy queue: an entry is removed only once its op is written; a failed read touches nothing.
- Order: `HabitOp.order` (microseconds, strictly increasing per process). ISO 8601 kept
  only the second, so "check then uncheck" in the same second replayed in random order
  (UUID tiebreak). Proven: the old sort fails the new test. Version 1 op files still decode.
- The widget re-applies EVERY pending op of the day to the snapshot, so a lost concurrent
  write is restored on the next tap or app publish.

**Lot 2, Yuko:**
- Cosmetics: recognised (CosIng name) is separated from evaluated (33-entry watch list,
  sources: EC 1223/2009 + SCCS). The sheet says how many ingredients were NOT assessed and
  that absence from the list is not proof of safety. New confidence level (high / medium /
  low). 1 or 2 ingredient formulas, all recognised, are scored with low confidence.
- Goals (`Services/ProductFit.swift`): 7 food + 3 cosmetic goals, editable from the home
  toolbar and from every product. Verdict per goal with the value that justifies it
  (FSA traffic-light thresholds, EU protein/fibre claims, NOVA). Never mixed into the score.
- Scan history (`scans.json`) separate from "Consultés récemment"; one dated line per scan.
- Alternatives: rebuilt on search.openfoodfacts.org. Old version filtered on Nutri-Score A/B
  (excluded whole categories) AND showed "no alternative" when the search returned 503.
  Two more bugs found on screen: Nutella's last category tag is malformed ("en:Pâtes à
  tartiner") and the search index lacks the finest tags, so categories are tried precise to
  broad and candidates ranked by shared categories. Nutella now gets Jardin Bio 71,
  Nocciolata 69, Carrefour BIO 68, each with "Pourquoi : ..." reasons.
- Unknown product: camera or library photo for ingredients AND nutrition table (OCR parser
  takes the per-100 g column, never overwrites typed values), then a "Vérifier la fiche"
  screen before anything is written.
- `docs/feature-parity/render.py` writes `PARITY.md` from `ledger.json` (88 rows).

**Not done in this pass, next in order:** visit every route and sub-page of the 88 tools and
fill the ledger honestly (76 rows still "not started"); widgets (tasks, calories, photo meal,
currencies, stocks); language curriculum; investing scenarios; design light/dark matrix.

## Codex prompt "Yuko / Trilingo / détox / motion" (29 Sept evening): lot A done

Brief: `~/Documents/Codex/2026-09-25/can-x20/outputs/PROMPT-LIFEOS-YUKO-TRILINGO-DETOX-MOTION.md`.

**Yuko, scan = search (done, tested, measured):**
- `Services/Barcode.swift`: EAN-8 / UPC-A / EAN-13 / GTIN-14, check digit, canonical form and
  legitimate equivalents (never a truncation). Non-latin digits are refused, not converted.
- Scan lookup now uses the Open Food Facts **v3 universal API** (`product_type=all`): one
  request, the server redirects cosmetics to Open Beauty Facts. The old two-base path stays as
  fallback when it is down. The device cache is checked BEFORE concluding "absent" (it used to
  be skipped when both bases said absent). `LookupTrace` lists codes tried, bases, answers;
  shown on the "produit inconnu" sheet and in the log (no photo, no personal data).
- `tools/yuko-bench/bench.py`: 93 reproducible codes (popular per category and country,
  cosmetics, UPC/GTIN traps, wrong check digits, non-food controls from Wikidata).
  **100 % conform** once 429 throttling is retried. Real gap found: **7 of 21 cosmetics have
  no ingredient list in the base** -> product page now offers "Photographier la liste"
  (`IngredientPhotoSheet`, stored as `enrichments.json`, never overrides base data, labelled
  "non vérifiée"). User misses go in `tools/yuko-bench/failed_scans.txt`.

**Scores, "LifeOS Qualité 2.0" (Yuka's public method, not a Coca exception):**
- Nutrition = official Nutri-Score 2023 from Open Food Facts when present (fruit/veg
  estimate included), else LifeOS computes the 2023 algorithm (food and drink tables).
  Points by grade band: an E is worth at most 12/60 (the old linear scale gave a soda E 31/60).
- Yuka's public cap: a high-risk additive caps the score at 49, for every food method.
- E150c/E150d (4-MEI) and aspartame move to high risk (IARC 2B).
- Coca-Cola Original (5449000000996): official NS 2023 E, 12 pts, drinks table -> ~17/100
  (was ~50). Our own 2023 computation gives the same 12 points.

**Cal AI (done except a built-in engine without key):**
- Evaluated on 12 annotated Wikimedia photos (`tools/calai-bench`, licences in
  `photos/sources.json`): Apple Vision never says "soup" for a pan of vegetables here; the
  pipeline just had no mapping for "stir_fry"/"vegetable". Workers AI models: **Mistral Small
  3.1 24B: 12/12 JSON, 73 % items found, 0 false soup, soup found, 8 s median**; Qwen 3.8
  35 %; Llama 3.2 Vision needs a licence "agree" (not accepted for Theo); Kimi not on free plan.
- Results are now a list of foods with alternatives ("Plutôt : Légumes cuits"), preparation,
  confidence and a follow-up question (oil, sauce). The engine that answered is shown.
- Home-cooked foods use **Ciqual 2020 (ANSES, Licence Ouverte)**, 2 298 generic foods bundled
  (`Resources/ciqual_2020.tsv`, `Services/GenericFoods.swift`), instead of the median of
  packaged products.
- **Not done, needs Theo:** a keyless built-in engine means a server that receives meal
  photos (Worker + Mistral on Workers AI). That changes the App Privacy answer and needs a
  deploy on his Cloudflare account. Ready to build on his go.

**Pet food (Theo, 29 Sept: "la bouffe pour chat, on peut la noter"):**
- The universal lookup now also returns Open Pet Food Facts (`source .pet`) and Open Products
  Facts (`source .product`, shown, never scored: no method). Before, pet food would have been
  scored as HUMAN food.
- `Services/PetFoodScore.swift`, method "Animaux 1.0" for cats and dogs: composition /45
  (named meat first, declared meat %, cereals in the top 5, "sous-produits"), protein on dry
  matter /25 against FEDIAF minimums (cat 25 %, dog 18 %, carbohydrate estimate for cats),
  additives /30 (sugar -15, colourants, BHA/BHT/ethoxyquin, propylene glycol for cats) and a 49
  cap for species-toxic ingredients (onion, garlic; xylitol, chocolate, grapes for dogs).
  No composition = no score; no analytical constituents = score with LOW confidence, said.
- Species from categories, words in 9 languages, single-species brands (Gourmet, Felix,
  Pedigree...), else a "C'est pour qui ? Chat / Chien" choice kept per product.
- Pet food never enters the food journal and never gets personal goals.
- Real screen: Gourmet Gold mousse (3222270550673) 43/100 "Médiocre" (4 % chicken, by-products,
  sugar; protein 47.8 % of dry matter, values stored as fractions in the base and converted).
- Other animals (birds, rodents, fish) and household products: not scored yet.

**Next in order:** Trilingo (placement, mandatory setup, 180-day engine, voices, daily
notification, many languages with honest coverage), screen detox (FamilyControls: Theo must
request the distribution entitlement), night sound recording, motion system, 88-tool pass.

## Master prompt "full upgrade" (29 Sept night): lookup fix, Trilingo, night sounds

Brief: `~/Documents/Codex/2026-09-25/can-x20/outputs/PROMPT-MAITRE-LIFEOS-FULL-UPGRADE.md`
(+ annex with the 88 tools). Disk was at 630 MB: freed my own build folders, archive and raw
downloads (2.5 GB), then the simulator swap. Keep simulators shut down between screen checks.

**Yuko lookup (Codex point):** absence is established ONLY by a real "absent" on the canonical
form (universal base, or all three bases via the old path). 503 on the canonical + 404 on an
equivalent form used to end as "produit absent"; now "Recherche incomplète, réessaie". Tests
for mixed 404/429/503, cache empty/present, legacy fallback.

**Trilingo rebuilt** (`Services/Trilingo/`, `Modules/Trilingo.swift`, old 16-phrase
`Languages.swift` removed):
- Courses built offline by `tools/trilingo/build_courses.py` from **Tatoeba** (human sentences
  and translations, CC BY 2.0 FR, ids kept). Vocabulary-driven progression: ~10 new words a
  day, sentences use only introduced words, no near-duplicates; level from known words.
  **14 complete French courses (240 days, ~2 400 words by the end):** eng spa deu ita por nld
  rus cmn tur ukr hun epo ber kab. **7 partial** (small corpus < 8 000 pairs, said on screen):
  jpn (168 days) heb pol ara ron swe fin. Chinese = simplified only, with pinyin in tone
  marks; Japanese with kana reading. 6.8 MB bundled.
- Mandatory setup (language, goal, experience, minutes, reminder), adaptive placement (3
  sentences per level, stops at first failed level) or complete-beginner start.
- Daily session: intro, meaning choice, listen & choose, rebuild with tiles, dictation,
  translate (reviews), speaking (Speech framework, on-device when possible). Spaced repetition
  per skill (1-2-4-7-15-30-60-120 days), error notebook, streak. Human Tatoeba recordings
  when they exist (online), else device voice; honest message when no voice / no speech.
- Daily reminder at the chosen time for the next 7 days, skipped when today is done, one per
  day, DST-safe. Progress per language in Documents/Trilingo (backup + erase covered).
- Tests: engine, SRS intervals, placement, reminders, answer tolerance, **180 simulated days**
  (new content every day, reviews, no loop), and an honesty check of the bundled courses.
- Real screen: setup -> home "Jour 1 sur 240" -> intro, choice (wrong answer marked), tiles.
- Not done: grammar notes, unit checkpoints, other source languages, account sync.

**Night sounds** (`Services/NightSounds.swift`, `Modules/NightSoundView.swift`, tool "Nuit
sonore" in Sommeil): consent, on-device SoundAnalysis classifier (snoring, cough, speech,
crying, animals...) + loud-noise threshold, 5 s pre-roll clips in AAC, morning timeline with
playback and deletion, retention 7/14/30/90 days, interruptions recorded as gaps, storage
check. **The simulator aborts when the mic input opens** ("RPC timeout", host audio server):
a guard now refuses cleanly on the simulator. **Never run on a real iPhone yet.**

## Audit du 30 sept. (AUDIT-LIFEOS-2026-09-30.md), lot 1

Worked in the audit's priority order, skipping only what needs Theo or Apple.

| Audit point | State | Proof |
|---|---|---|
| 1. Accounts | **Not started.** Needs a decision: Sign in with Apple + iCloud (CloudKit) keeps "Data Not Collected"; Google/Facebook/email need a server and client IDs that only Theo can create. | none |
| 2. Opale | Real blocking code ready (`Services/ScreenTimeBlocker.swift`): app picker, timed block, unblock, expiry at next open. Manual tracking now labelled "Suivi manuel". **Cannot run** until Apple grants the Family Controls distribution entitlement; then add it to `LifeOS.entitlements`. Scheduled blocks need a DeviceActivity extension (next). | builds; no device |
| 3. Envol | Unchanged: needs a Duffel key (account by Theo). | |
| 4. Cal Eye | The no-key failure screen was a dead end ("add it manually", no button). It now opens the food search (Ciqual + OpenFoodFacts), same journal write. Keyless engine still waits on Theo. | code |
| 5. Yuko cosmetics | Watch list 2.0: hand-annotated entries + **CosIng annexes II and III** (`Resources/cosing_annexes.tsv`, 462 label-matchable names: 61 prohibited, 63 allergens to declare, 338 restricted), fetched by `tools/cosing/fetch_annexes.py` from the Commission's public API. Prohibited = high, allergen = sensitivity, restricted = shown without penalty (concentration is never on the label). | CosmeticAnnexTests (4) |
| 6. Gym | `Services/StrengthProgression.swift`: next load from REAL logged sets (double progression, hold at max effort, repeat after one miss, -10 % after two). "Aujourd'hui" in the programme opens `GymSessionView`: prescription per exercise, logs sets into the same journal as Hevvy, recovery warning under 48 h. Weekly hard sets per muscle vs 10 to 20. Hevvy's fixed "+2.5 kg" now uses the engine. | StrengthProgressionTests (8) |
| 7. Investing | `Services/FireProjection.swift`: returns -5 to 12 %, fees, inflation (real euros), 3 scenarios with stated assumptions, start capital = investments only unless opted in. | FireProjectionTests (4) |
| 8. Four looks | Second axis "Couleurs / Neutre" (`AppPalette`, key `appPalette`) next to Système/Clair/Sombre. Neutral = grey of the SAME relative luminance, so every contrast ratio is unchanged. Semantic palette became computed; `Color(hex:)` goes through it; 372 raw `.red/.green/.orange...` uses were routed to tokens. Changing palette rebuilds the tree (`.id`), the current tab survives (`@SceneStorage`). Photos are untouched. | ThemePaletteTests (2) |
| Requirements: second tab | Choice in Profil > Apparence: Réveil, Nutrition, Sport, Tâches, Sommeil, Argent. Réveil added to Sommeil (`WakeUpView(embedded:)`, no nested stack). | SecondTabTests (3) |
| Tracking | Ledger: Trilingo path fixed, "Nuit sonore" row 89 added, touched rows updated. PARITY.md title now counts rows. Tabata review evidence rewritten in full (`docs/lifeos-agent/jobs/2026-09-30-tabata-health-reprise/REVIEW-EVIDENCE-2.md`). | |

Not verified by hand yet: the four looks on real screens (iPhone, iPad, Mac), the second tab on iPad/Mac, the session screen. Widgets do not follow the neutral palette yet (the choice is synced to the app group as `widget_palette`, not read).

## Audit du build 48 (AUDIT-LIFEOS-BUILD48.md), lot 2

The audit's four defects, each reproduced by a test (`LifeOSTests/Build48DefectTests.swift`):

| Defect | Fix | Proof |
|---|---|---|
| Sport: the running session was mixed with finished history (prescription changed mid-workout, two sessions a day merged, partial session used as a base) | New `TrainingSession` model (active / done / cancelled); `WorkoutSet.sessionID` and `kind` (warm-up / work / drop). Starting freezes the prescription (`GymSessionService.start`, JSON in the session). Engine groups by session, not by day, and progresses only from finished sessions. Recovery excludes only the current session. Target ranges ("3×8-12"), default target for free labels, smallest weight step setting. | GymSessionIsolationTests (7). Negative control: with the build 48 grouping, the same-day test fails (82.5 instead of 62.5) and the recovery test fails. |
| Sport: save shown as a success even on failure | `GymSessionService` throws on save failure, removes the unsaved set, reverts finish/cancel; the screen shows the error and keeps the input. The button and the action use the same weight rule (`parseWeight`). | GymSessionSaveTests (4) |
| Opale: expiry only when the Opale card appeared | `ScreenTimeBlocker.appBecameActive()` called by LifeOSApp at cold launch and every return to foreground; end notification; DeviceActivity schedule set; extension prepared in `Extensions/LifeOSDeviceActivity/` (outside the build, needs Apple's permission). | ScreenBlockExpiryTests (3) |
| Palette switch rebuilt the tree (lost sub-screens and drafts) | Palette colours are dynamic UIColors that follow a custom trait (`NeutralPaletteTrait`, bridged with `.environment(\.neutralPalette)`), like dark mode. `.id(appPaletteRaw)` removed. | PaletteWithoutRebuildTests (3). **Seen on the simulator**: `-paletteFlipAfter 12` turned the category grid grey on the same screen, same tab; relaunch keeps neutral. |

Also in this lot:
- Session screen rebuilt: start / resume / finish / cancel (keep or erase sets), set type, rest timer (setting 1 to 4 min), personal record, error line. `-shotGymSession -shotGymStart` (DEBUG) opens it seeded. Seen on the simulator.
- Hevvy: correct a logged set (tap), set type in the editor, records per exercise, save and delete errors shown.
- Widgets follow the palette (`WidgetPalette`, `widget_palette` synced at launch and on change). Not seen on a real home screen.
- Kubero scenarios have distinct line patterns, readable in neutral.
- `docs/feature-parity/MATRIX.md`: per-tool matrix (tested automatically / present untested / missing / external dependency). 6 tools inventoried so far: Fitbot, Hevvy, Opale, Kubero, Accueil, Cal Eye.

Suite: 784 tests, 0 failures, 1 skipped.

## Resume here

Read the two audit lot tables above first. Next, in the audit's order:
1. **Accounts**: needs Theo's choice (Apple + iCloud without a server, or a server for Google/Facebook/email).
2. **Opale**: the day Apple grants Family Controls, add the entitlement, then build the DeviceActivity monitor extension (scheduled blocks, end of session in background).
3. **Visual pass of the four looks** on iPhone, iPad and Mac (light/dark x colour/neutral), including Tabata and charts; widgets reading `widget_palette`.
4. **Widgets matrix** per tool (audit point 9) and real journeys on device (point 10).
5. Extend MATRIX.md family by family (next: rest of Sport: TabaTime, Stepometer, GOMOB, Streakz; then Nutrition), fixing gaps as found. Depth of the other tools, one by one, with the audit's method: entry, configuration, main action, result, edit, delete, relaunch, offline, permission refused, shared data, platforms.

Test runs: use `-parallel-testing-enabled NO`. Shut simulators down between checks (disk and swap).
