# Annexe — 88 outils LifeOS : inventaire et critères de livraison

Relevé du code et du registre le 29 septembre 2026. Les statuts ci-dessous sont ceux du registre de Claude, pas une certification indépendante. `not_started` désigne le suivi de parité non commencé, pas nécessairement une fonctionnalité absente. Les chemins ont été contrôlés et les fichiers sources parcourus statiquement ; aucune visite interactive exhaustive n’est revendiquée. Le prompt maître prime sur les exigences périmées du registre.

## 1. 🩺 Santé — MediSûr
Référence à qualifier : Medisafe.
Source : LifeOS/Modules/MedicalModule.swift — 782 lignes, SHA256 f138502fd64b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build treatment schedules with multiple times, weekdays, intervals and PRN; log taken/skipped/snoozed/missed doses with undo; supply/refill tracking; adherence history/export; dependent profiles and caregiver sharing; prescription attachments. Inventory and reports must derive from dose events, not notification delivery. Evaluate interactions and medication lookup against a real drug-data service; never fabricate them.

**Critère minimum à exécuter :** Create a twice-daily treatment ending tomorrow; take one dose, skip one, edit the time, relaunch, and verify stock, history and pending reminders. Delete it and verify no orphan reminders.

**Dépendances à vérifier :** Shared treatment/dose/reminder domain with #20, stable IDs, medication dataset and caregiver backend. End dates and dose changes must reconcile pending notifications.

**Reste déclaré, à confronter au code actuel :** Build treatment schedules with multiple times, weekdays, intervals and PRN; log taken/skipped/snoozed/missed doses with undo; supply/refill tracking; adherence history/export; dependent profiles and caregiver sharing; prescription attachments. Inventory and reports must derive from dose events, not notification delivery. Evaluate interactions and medication lookup against a real drug-data service; never fabricate them.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 2. 🩺 Santé — Doctolink
Référence à qualifier : Doctolib.
Source : LifeOS/Modules/MedicalModule.swift — 782 lignes, SHA256 f138502fd64b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add practitioner directory/filtering, live slots, booking/reschedule/cancellation, booking confirmations, dependent profiles, documents and consultation history. Include waiting-list notifications, secure practitioner messaging and teleconsultation where the selected reference baseline supports them. Separate personal calendar entries from confirmed provider bookings.

**Critère minimum à exécuter :** An available slot can be booked exactly once, confirmed, rescheduled and cancelled against a sandbox provider; two clients racing for the same slot cannot both succeed. Offline entries never display provider-confirmed status.

**Dépendances à vérifier :** Real provider scheduling/messaging/video agreements or an independently operated appointment service with participating practitioners; EventKit export is not a booking API. Build manual agenda immediately, track provider-dependent flows separately.

**Reste déclaré, à confronter au code actuel :** Add practitioner directory/filtering, live slots, booking/reschedule/cancellation, booking confirmations, dependent profiles, documents and consultation history. Include waiting-list notifications, secure practitioner messaging and teleconsultation where the selected reference baseline supports them. Separate personal calendar entries from confirmed provider bookings.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 3. 🩺 Santé — Maple Health
Référence à qualifier : Apple Santé.
Source : LifeOS/Modules/MedicalModule.swift — 782 lignes, SHA256 f138502fd64b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Implement source-aware HealthKit records, supported metric categories, units, ranges, trends and historical exploration; import/export and sharing; distinguish unknown from zero and duplicate sources. Track which Apple Health capabilities are reproduced and which rely on the system app, including clinical documents, medication/cycle views and supported device data.

**Critère minimum à exécuter :** Import overlapping samples from two sources, manually correct one record, revoke access, then reopen on desktop. No double counting, stale values marked, unit conversion reversible, absence never shown as zero.

**Dépendances à vérifier :** HealthService/HealthRepository/HealthAutoSync, permission-aware adapters, shared metric schema and document vault. Desktop should display synchronized records without pretending to acquire unavailable sensors.

**Reste déclaré, à confronter au code actuel :** Implement source-aware HealthKit records, supported metric categories, units, ranges, trends and historical exploration; import/export and sharing; distinguish unknown from zero and duplicate sources. Track which Apple Health capabilities are reproduced and which rely on the system app, including clinical documents, medication/cycle views and supported device data.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 4. 🩺 Santé — Mon Espace Vaccin
Référence à qualifier : Mon espace santé.
Source : LifeOS/Modules/MedicalModule.swift — 782 lignes, SHA256 f138502fd64b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add multi-person vaccination histories, product/dose/practitioner/lot/document provenance, schedule versioning, catch-up review and exports. Full reference scope additionally requires a health document repository, care profile, secure communications and authorized interoperability, not merely another vaccine form.

**Critère minimum à exécuter :** Import a vaccination certificate, link it to a dose, edit a future booster and verify reminder replacement. Show exactly which schedule/version suggested the due date and allow corrections.

**Dépendances à vérifier :** Use shared medical profiles and vault; versioned jurisdiction/age-specific schedule data. Actual Mon espace santé access requires a supported integration route; don't infer access from the app's existence.

**Reste déclaré, à confronter au code actuel :** Add multi-person vaccination histories, product/dose/practitioner/lot/document provenance, schedule versioning, catch-up review and exports. Full reference scope additionally requires a health document repository, care profile, secure communications and authorized interoperability, not merely another vaccine form.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 5. 🌸 Cycle — Floé
Référence à qualifier : Flo.
Source : LifeOS/Modules/CycleModule.swift — 479 lignes, SHA256 4959614dc00d.
Statut déclaré iPhone : partial: navigation bug fixed and verified (Floé); product depth not verified. Mac : not_started.

**Périmètre cible du registre :** Build calendar editing for historical periods, variable-cycle predictions with uncertainty, explicit period boundaries, goals and relevant life-stage modes. Add symptom insights, reminders, educational material and user-controlled sharing. Pregnancy/fertility/perimenopause feature families must be inventoried separately instead of claiming full Flo parity from period arithmetic.

**Critère minimum à exécuter :** Enter three irregular periods, correct one retrospectively and confirm predictions/history update together. Missing history shows uncertainty; a predicted fertile date is never presented as confirmed ovulation.

**Dépendances à vérifier :** One cycle domain for #5–7; historical inputs, prediction version and provenance; optional HealthKit integration; curated content. User-entered and predicted events must remain distinct.

**Reste déclaré, à confronter au code actuel :** Build calendar editing for historical periods, variable-cycle predictions with uncertainty, explicit period boundaries, goals and relevant life-stage modes. Add symptom insights, reminders, educational material and user-controlled sharing. Pregnancy/fertility/perimenopause feature families must be inventoried separately instead of claiming full Flo parity from period arithmetic.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 6. 🌸 Cycle — Klue
Référence à qualifier : Clue.
Source : LifeOS/Modules/CycleModule.swift — 479 lignes, SHA256 4959614dc00d.
Statut déclaré iPhone : partial: navigation bug fixed and verified (Floé); product depth not verified. Mac : not_started.

**Périmètre cible du registre :** Support configurable symptom/intensity/duration logs, mood, pain, discharge and other reference categories; custom tags, searchable daily entries, cycle-phase correlations and trend/export views. Add stage-specific categories without forcing irrelevant questions. Clarify associations rather than presenting causal conclusions.

**Critère minimum à exécuter :** Log multiple symptoms with severity, edit an old day and inspect filtered history and phase comparisons. Deleted entries disappear from every aggregate and export.

**Dépendances à vérifier :** Reuse CycleEntry through a richer versioned schema, shared calendar, stable symptom identifiers and optional attachments; migrate existing eight-category entries.

**Reste déclaré, à confronter au code actuel :** Support configurable symptom/intensity/duration logs, mood, pain, discharge and other reference categories; custom tags, searchable daily entries, cycle-phase correlations and trend/export views. Add stage-specific categories without forcing irrelevant questions. Clarify associations rather than presenting causal conclusions.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 7. 🌸 Cycle — Floé Stats
Référence à qualifier : Flo / Clue.
Source : LifeOS/Modules/CycleModule.swift — 479 lignes, SHA256 4959614dc00d.
Statut déclaré iPhone : partial: navigation bug fixed and verified (Floé); product depth not verified. Mac : not_started.

**Périmètre cible du registre :** Add period duration, cycle-length distribution, irregularity, symptom trend overlays, date-range filters, corrections, report export and meaningful insufficient-data states. Reconcile all cycle screens and coach context with the same calculations; include the wider Flo/Clue reporting baseline in the parity ledger.

**Critère minimum à exécuter :** A fixture with incomplete and unusually long cycles produces explainable statistics, excludes incomplete cycles appropriately and yields identical results in history, tracker and exported report.

**Dépendances à vérifier :** Shared cycle analytics service, timezone-aware day boundaries, tested fixtures including incomplete cycles and lifecycle changes.

**Reste déclaré, à confronter au code actuel :** Add period duration, cycle-length distribution, irregularity, symptom trend overlays, date-range filters, corrections, report export and meaningful insufficient-data states. Reconcile all cycle screens and coach context with the same calculations; include the wider Flo/Clue reporting baseline in the parity ledger.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 8. 😴 Sommeil — Sleep Circle
Référence à qualifier : Sleep Cycle.
Source : LifeOS/Modules/SleepModule.swift — 424 lignes, SHA256 c7463ee2a0bf.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add actual overnight session recording, supported microphone/motion or HealthKit acquisition, sleep timeline and quality trends, sleep notes/audio events, smart wake window, history and exports. Keep the calculator as a secondary feature. A phone-based route is possible; an Apple Watch is not universally required for Sleep Cycle-style tracking.

**Critère minimum à exécuter :** Run an overnight real-device session, interrupt audio, relaunch and verify retained samples, timeline and alarm delivery. Test absent/denied sensors and never generate a plausible-looking night from no data.

**Dépendances à vérifier :** Choose and validate acquisition/analysis technology, recording permission, storage/retention, background operation and alarm adapter. Sleep-stage claims need validated evidence; audio event detection is not automatically sleep staging.

**Reste déclaré, à confronter au code actuel :** Add actual overnight session recording, supported microphone/motion or HealthKit acquisition, sleep timeline and quality trends, sleep notes/audio events, smart wake window, history and exports. Keep the calculator as a secondary feature. A phone-based route is possible; an Apple Watch is not universally required for Sleep Cycle-style tracking.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 9. 😴 Sommeil — Pzazz
Référence à qualifier : Pzizz.
Source : LifeOS/Modules/SleepModule.swift — 424 lignes, SHA256 c7463ee2a0bf.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build persisted nap sessions, configurable duration, narrated/soundscape programmes, sound/voice mixing, fade-in/out, wake alarm and history. Include sleep/focus modes if retaining full Pzizz scope, not only nap timing.

**Critère minimum à exécuter :** Start a nap, lock the phone and background/terminate as supported by the chosen alarm API; completion uses the original deadline. Pause/resume and headphones removal behave predictably; no duplicate completion record.

**Dépendances à vérifier :** Shared durable timer, audio session/player and supported alarm delivery; original or licensed audio library with offline downloads.

**Reste déclaré, à confronter au code actuel :** Build persisted nap sessions, configurable duration, narrated/soundscape programmes, sound/voice mixing, fade-in/out, wake alarm and history. Include sleep/focus modes if retaining full Pzizz scope, not only nap timing.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 10. 😴 Sommeil — Rize
Référence à qualifier : Rise.
Source : LifeOS/Modules/SleepModule.swift — 424 lignes, SHA256 c7463ee2a0bf.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add sleep debt/history, personalized wind-down schedule, energy-window presentation, routine checklist, reminders and calendar integration. Label predictions and input coverage. Provide supported shortcuts/settings guidance for system modes instead of a switch that claims to change unsupported OS settings.

**Critère minimum à exécuter :** Change wake time and enter a short night; recompute schedule consistently. Verify cross-midnight reminders, travel timezone changes and missing sleep data without inventing recovery.

**Dépendances à vérifier :** Shared sleep history, circadian model with explicit assumptions, routine engine and calendar adapter. RISE-style debt and energy forecasting require more than a fixed reminder.

**Reste déclaré, à confronter au code actuel :** Add sleep debt/history, personalized wind-down schedule, energy-window presentation, routine checklist, reminders and calendar integration. Label predictions and input coverage. Provide supported shortcuts/settings guidance for system modes instead of a switch that claims to change unsupported OS settings.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 11. 😴 Sommeil — Awaken
Référence à qualifier : Awoken.
Source : LifeOS/Modules/SleepModule.swift — 424 lignes, SHA256 c7463ee2a0bf.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add transcription when available, search/tags, playback management, reality-check reminders, lucid-dream exercises and progress, attachments/export/backup. Manage recording files transactionally on save/delete. Resolve the exact Awoken identity: a verified Android listing exists, while the iOS search returned a different product.

**Critère minimum à exécuter :** Record, save, transcribe, search, play and delete a dream; cancelling an entry leaves no orphan recording. Reality reminders respect quiet hours and notification denial.

**Dépendances à vérifier :** Speech/audio adapters and shared attachment store. Baseline identity remains a research item; do not substitute Shape as Awoken.

**Reste déclaré, à confronter au code actuel :** Add transcription when available, search/tags, playback management, reality-check reminders, lucid-dream exercises and progress, attachments/export/backup. Manage recording files transactionally on save/delete. Resolve the exact Awoken identity: a verified Android listing exists, while the iOS search returned a different product.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 12. 😴 Sommeil — Whoosh
Référence à qualifier : Whoop / AutoSleep.
Source : LifeOS/Modules/SleepModule.swift — 424 lignes, SHA256 c7463ee2a0bf.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build personalized longitudinal baselines, sleep/recovery/strain/stress views, trends, input coverage and transparent contribution explanations. Add sleep debt, workouts and journal correlations; map wearable-dependent features explicitly. Separate the LifeOS model from proprietary reference scores.

**Critère minimum à exécuter :** Missing HRV or a stale heart-rate sample suppresses/qualifies the score. New users have a calibration state. Same fixture gives the same result and removing a sample recomputes dependent charts.

**Dépendances à vérifier :** HealthKit/wearable adapters, source de-duplication and longitudinal aggregates. WHOOP-specific acquisition requires supported device/service access; AutoSleep-style watch acquisition is a different path.

**Reste déclaré, à confronter au code actuel :** Build personalized longitudinal baselines, sleep/recovery/strain/stress views, trends, input coverage and transparent contribution explanations. Add sleep debt, workouts and journal correlations; map wearable-dependent features explicitly. Separate the LifeOS model from proprietary reference scores.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 13. 🥗 Nutrition — Zerø
Référence à qualifier : Zero.
Source : LifeOS/Modules/NutritionModule.swift — 754 lignes, SHA256 b31721377093.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add edit/backfill, custom protocols, schedule reminders, history/streaks, progress charts, notes and goal integration. Cover the current reference's food/protein/hydration features through shared nutrition screens rather than duplicate stores.

**Critère minimum à exécuter :** Begin a fast before midnight, relaunch after the target, edit start/end and verify duration, streak and report. Prevent overlapping active fasts and duplicate completion events.

**Dépendances à vérifier :** Durable timestamp-based sessions, nutrition links and shared reminder system; versioned goals.

**Reste déclaré, à confronter au code actuel :** Add edit/backfill, custom protocols, schedule reminders, history/streaks, progress charts, notes and goal integration. Cover the current reference's food/protein/hydration features through shared nutrition screens rather than duplicate stores.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 14. 🥗 Nutrition — Yumzio
Référence à qualifier : Yazio / MyFitnessPal.
Source : LifeOS/Modules/CalAIView.swift — 502 lignes, SHA256 219ecbf4d30f.
Statut déclaré iPhone : partial: log/edit/delete journey verified on device. Mac : not_started.

**Périmètre cible du registre :** Add recipes/custom foods, portions and units, saved meals/copy day, micronutrients, meal planning, weight/activity-adjusted goals and trends. Audit barcode/search coverage and nutrition provenance. Ensure coach/widget totals refresh after edits as well as insertions; current synchronization watches foods.count.

**Critère minimum à exécuter :** Log a recipe, halve its portion, edit without changing row count and delete it. Calories/macros agree across diary, day ring, coach and widget; selecting a past day must not overwrite today's context.

**Dépendances à vérifier :** Canonical FoodProduct, FoodEntry, Recipe and Goal services shared with #15–21/#64–65; robust nutrition provider/cache and HealthKit links.

**Reste déclaré, à confronter au code actuel :** Add recipes/custom foods, portions and units, saved meals/copy day, micronutrients, meal planning, weight/activity-adjusted goals and trends. Audit barcode/search coverage and nutrition provenance. Ensure coach/widget totals refresh after edits as well as insertions; current synchronization watches foods.count.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 15. 🥗 Nutrition — Cal Eye
Référence à qualifier : Cal AI.
Source : LifeOS/Modules/PhotoCalorie.swift — 656 lignes, SHA256 2e5617fa5d7b.
Statut déclaré iPhone : partial: save integrity fixed and unit-tested; photo journey not run on device. Mac : not_started.

**Périmètre cible du registre :** Implement multi-item recognition, editable bounding/item suggestions, confidence/unknown states, portion correction, preparation/oil/sauce handling, rescan, meal confirmation and saved history. Connect corrected output to the shared diary exactly once. Benchmark common, mixed and unfamiliar dishes.

**Critère minimum à exécuter :** Test a mixed plate, a non-food image and an unfamiliar dish. User correction updates nutrients proportionally; low-confidence detection asks for review and never silently invents precise grams.

**Dépendances à vérifier :** Image/model provider with capabilities declared, nutrition source attribution, image lifecycle and a labeled evaluation dataset. Keep useful offline suggestions without implying provider-equivalent recognition accuracy.

**Reste déclaré, à confronter au code actuel :** Deploy a keyless engine (needs Theo: server + App Privacy); real photos on device; portion estimation stays a hypothesis.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 16. 🥗 Nutrition — Yuko
Référence à qualifier : Yuka.
Source : LifeOS/Modules/Yuko.swift — 1363 lignes, SHA256 120c6dda898b.
Statut déclaré iPhone : partial: verified on simulator with live data (29 Sept): scores in lists, goals fit, alternatives with reasons, scan history; camera scan and camera OCR not run on a real iPhone. Mac : partial: navigation verified, product depth not verified.

**Périmètre cible du registre :** Add food/cosmetic product types, ingredient detail, transparent scoring methodology, allergen links, scan history/favourites, search and evidence-backed alternatives. Display prices only with an actual location/store/date source. Missing product data must remain unknown.

**Critère minimum à exécuter :** Scan known, unknown and incomplete products. No fabricated score/price; alternatives share the relevant category and dietary constraints. Offline cached records visibly show their age.

**Dépendances à vérifier :** Food and cosmetic datasets, published LifeOS scoring rules, ingredient normalization, alternatives/category service and optional verified price feed.

**Reste déclaré, à confronter au code actuel :** Real-iPhone camera scan and label photos; cosmetics: 33-entry watch list only (no full ingredient safety dataset); 7/21 benchmark cosmetics lack ingredient lists in the base (photo enrichment is local only, no upload to Open Beauty Facts); coverage of products missing from all bases still unmeasured until failed_scans.txt is filled.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 17. 🥗 Nutrition — Fridgy
Référence à qualifier : Fridgely.
Source : LifeOS/Modules/NutritionModule.swift — 754 lignes, SHA256 b31721377093.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build structured units/quantities, barcode/receipt capture, batches with separate expiry dates, consume/discard/transfer actions, alerts, multiple storage areas, shared household inventory and recipe matching. Keep an auditable stock history.

**Critère minimum à exécuter :** Add two milk batches, consume one partially, move the remainder and verify expiry warnings and recipe availability on a second device. Undo waste/consumption restores the correct batch.

**Dépendances à vérifier :** Shared pantry domain with #18/#64/#65; household sync/roles, product lookup and unit conversion. Confirm Fridgely publisher: use original fridge-inventory product, not unrelated same-name AI app.

**Reste déclaré, à confronter au code actuel :** Build structured units/quantities, barcode/receipt capture, batches with separate expiry dates, consume/discard/transfer actions, alerts, multiple storage areas, shared household inventory and recipe matching. Keep an auditable stock history.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 18. 🥗 Nutrition — Bringo
Référence à qualifier : Bring!.
Source : LifeOS/Modules/NutritionModule.swift — 754 lignes, SHA256 b31721377093.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add multiple named/shared lists, real-time household edits, quantities/units, custom aisles, reorder, favourites, recipe-to-list additions, bought history and store grouping. Merge duplicate ingredients by compatible unit while preserving user intent.

**Critère minimum à exécuter :** Two people edit offline and reconnect without lost items. Recipe additions consolidate compatible quantities; checking purchased items updates pantry only through an explicit supported workflow.

**Dépendances à vérifier :** Household collaboration, offline change queue, canonical product/recipe links and stable list/member IDs.

**Reste déclaré, à confronter au code actuel :** Add multiple named/shared lists, real-time household edits, quantities/units, custom aisles, reorder, favourites, recipe-to-list additions, bought history and store grouping. Merge duplicate ingredients by compatible unit while preserving user intent.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 19. 🥗 Nutrition — WaterMind
Référence à qualifier : WaterMinder.
Source : LifeOS/Modules/NutritionModule.swift — 754 lignes, SHA256 b31721377093.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add beverage types and serving presets, unit preferences, custom/goal-based reminder schedules, history/trends, configurable goals, widgets/shortcuts/watch support where targeted and HealthKit synchronization. Reconcile deletions and edits across all surfaces.

**Critère minimum à exécuter :** Log 250 ml through a widget, edit to 300 ml, delete on another surface and verify all totals. Midnight/timezone changes and notification denial do not lose history or double-log water.

**Dépendances à vérifier :** Shared intake service and reminders; health write deduplication, local-day rules and widget intents.

**Reste déclaré, à confronter au code actuel :** Add beverage types and serving presets, unit preferences, custom/goal-based reminder schedules, history/trends, configurable goals, widgets/shortcuts/watch support where targeted and HealthKit synchronization. Reconcile deletions and edits across all surfaces.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 20. 🥗 Nutrition — SuppSafe
Référence à qualifier : Medisafe.
Source : LifeOS/Modules/NutritionModule.swift — 754 lignes, SHA256 b31721377093.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Use the medication engine for dose events, taken/skipped history, schedule variations, stock/refills, start/end dates and adherence export, while keeping supplement-specific fields and grouping. Do not build a second inconsistent reminder system.

**Critère minimum à exécuter :** Edit a supplement name and dosing schedule, relaunch and delete; one reminder per intended dose, no old-name reminders, and historical taken events retain their identity.

**Dépendances à vérifier :** Shared #1 Treatment/DoseEvent service and inventory; ingredient information from a real dataset if offered.

**Reste déclaré, à confronter au code actuel :** Use the medication engine for dose events, taken/skipped history, schedule variations, stock/refills, start/end dates and adherence export, while keeping supplement-specific fields and grouping. Do not build a second inconsistent reminder system.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 21. 🥗 Nutrition — Figue
Référence à qualifier : Fig.
Source : LifeOS/Modules/NutritionModule.swift — 754 lignes, SHA256 b31721377093.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add detailed profiles and ingredient explanations, synonyms/derivatives, cross-contact and missing-label states, barcode/search integration, user overrides and supported restaurant/product discovery. Separate confirmed label evidence, inferred incompatibility and unknown. A substring miss must not mean safe.

**Critère minimum à exécuter :** Test synonyms, compound ingredients, missing ingredients and explicit may-contain labels. Unknown products never receive an unconditional compatible badge; a profile change re-evaluates saved products.

**Dépendances à vérifier :** Versioned allergen/ingredient ontology, authoritative product labels and dietary rules; connect scan, recipes, pantry and shopping.

**Reste déclaré, à confronter au code actuel :** Add detailed profiles and ingredient explanations, synonyms/derivatives, cross-contact and missing-label states, barcode/search integration, user overrides and supported restaurant/product discovery. Separate confirmed label evidence, inferred incompatibility and unknown. A substring miss must not mean safe.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 22. 💪 Sport — Fitbot
Référence à qualifier : Fitbod.
Source : LifeOS/Modules/GymProgram.swift — 241 lignes, SHA256 74c70a18da4b.
Statut déclaré iPhone : not_started. Mac : partial: navigation verified, product depth not verified.

**Périmètre cible du registre :** Add exercise catalogue/demonstrations, experience/equipment/goals, progression based on completed sets, recovery/volume balancing, substitutions and editable generated sessions. Support warmups, rest, supersets and programme history; share sessions with #24.

**Critère minimum à exécuter :** Generate with restricted equipment, complete a workout and verify the next prescription changes from actual history. Excluded exercises never reappear; editing a plan preserves past workouts.

**Dépendances à vérifier :** Structured exercise IDs, workout/set domain, progression engine and content library. AI suggestions must resolve to valid exercises and loads and remain editable.

**Reste déclaré, à confronter au code actuel :** Add exercise catalogue/demonstrations, experience/equipment/goals, progression based on completed sets, recovery/volume balancing, substitutions and editable generated sessions. Support warmups, rest, supersets and programme history; share sessions with #24.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 23. 💪 Sport — Stepometer
Référence à qualifier : Pedometer++.
Source : LifeOS/Modules/FitnessModule.swift — 401 lignes, SHA256 436beeaeb6fa.
Statut déclaré iPhone : not_started. Mac : partial: navigation verified, product depth not verified.

**Périmètre cible du registre :** Add distance/floors where available, goals, longer history/trends, achievements, walking sessions/routes, widgets and supported watch workflows. Distinguish live phone acquisition from imported health summaries.

**Critère minimum à exécuter :** Verify phone/watch overlap, denied permissions, timezone changes and a full day with zero activity. A desktop sees real synchronized history and never pretends its own step sensor exists.

**Dépendances à vérifier :** HealthKit/CoreMotion adapters and source rules; platform capability-aware desktop history.

**Reste déclaré, à confronter au code actuel :** Add distance/floors where available, goals, longer history/trends, achievements, walking sessions/routes, widgets and supported watch workflows. Distinguish live phone acquisition from imported health summaries.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 24. 💪 Sport — Hevvy
Référence à qualifier : Strong / Hevy.
Source : LifeOS/Modules/FitnessModule.swift — 401 lignes, SHA256 436beeaeb6fa.
Statut déclaré iPhone : not_started. Mac : partial: navigation verified, product depth not verified.

**Périmètre cible du registre :** Add reusable routines, exercise library/custom exercises, full sessions, warmup/drop/superset types, rest timers, notes, personal records, history editing, body measurements and sharing/export. Include Hevy-style social workflows in a separate explicit backlog if pursuing the whole reference union.

**Critère minimum à exécuter :** Complete a superset with a paused rest timer, edit a historical set and verify volume/PR recalculation. kg/lb conversion preserves underlying values; deletion doesn't leave phantom records.

**Dépendances à vérifier :** One workout schema with #22/#25/#26; community/sharing service for social features, units and evidence-based formula labels.

**Reste déclaré, à confronter au code actuel :** Add reusable routines, exercise library/custom exercises, full sessions, warmup/drop/superset types, rest timers, notes, personal records, history editing, body measurements and sharing/export. Include Hevy-style social workflows in a separate explicit backlog if pursuing the whole reference union.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 25. 💪 Sport — TabaTime
Référence à qualifier : Tabata Timer.
Source : LifeOS/Modules/TabataView.swift — 1560 lignes, SHA256 6a90c15fe158.
Statut déclaré iPhone : partial: light/dark theme verified on ready, running, pause, settings; completion not screenshot. Mac : partial: opens (full screen); theme verified.

**Périmètre cible du registre :** Verify and complete custom work/rest/prep/cooldown, rounds/sets, presets, sound/haptic/voice cues, pause/resume/skip, session history and accessible full-screen operation. Resolve the exact Tabata Timer publisher before declaring app parity.

**Critère minimum à exécuter :** Run multiple intervals while backgrounded, resume after several phase boundaries and verify correct phase and exactly one workout record. Test interrupted audio, zero rest and edited presets.

**Dépendances à vérifier :** Existing Tabata engine plus persistent preset/session domain and health writer; desktop audio/keyboard controls.

**Reste déclaré, à confronter au code actuel :** Verify and complete custom work/rest/prep/cooldown, rounds/sets, presets, sound/haptic/voice cues, pause/resume/skip, session history and accessible full-screen operation. Resolve the exact Tabata Timer publisher before declaring app parity. Screenshot the completion summary in both themes.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 26. 💪 Sport — GOMOB
Référence à qualifier : GOWOD / Pliability.
Source : LifeOS/Modules/FitnessModule.swift — 401 lignes, SHA256 436beeaeb6fa.
Statut déclaré iPhone : not_started. Mac : partial: navigation verified, product depth not verified.

**Périmètre cible du registre :** Add assessments, target-area recommendations, pre/post-workout routines, difficulty/duration filters, demonstrations, programme progression, completion history and reassessment trends. Include breathing/recovery content where the selected baseline includes it.

**Critère minimum à exécuter :** Complete an assessment, follow a targeted routine, pause/relaunch and record completion once. Reassessment changes recommendations based on actual results; unavailable videos have usable text guidance.

**Dépendances à vérifier :** Structured movement library, original/licensed video/audio and durable session timing; reuse fitness history.

**Reste déclaré, à confronter au code actuel :** Add assessments, target-area recommendations, pre/post-workout routines, difficulty/duration filters, demonstrations, programme progression, completion history and reassessment trends. Include breathing/recovery content where the selected baseline includes it.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 27. 💪 Sport — Streakz
Référence à qualifier : Streaks.
Source : LifeOS/Modules/FitnessModule.swift — 401 lignes, SHA256 436beeaeb6fa.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add positive/negative habits, count/duration targets, weekly frequencies, skip/pause/backfill, reminders, history/statistics and widgets, sharing the Habitly engine. Preserve a focused training view rather than maintaining separate completion semantics.

**Critère minimum à exécuter :** A habit scheduled three days/week retains its streak over unscheduled days; skip and correction update reports consistently in both Streakz and Habitly.

**Dépendances à vérifier :** Canonical habit schedule/completion engine with #41; HealthKit automatic goals only for available data.

**Reste déclaré, à confronter au code actuel :** Add positive/negative habits, count/duration targets, weekly frequencies, skip/pause/backfill, reminders, history/statistics and widgets, sharing the Habitly engine. Preserve a focused training view rather than maintaining separate completion semantics.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 28. ✨ Apparence — Umaxx
Référence à qualifier : Umax.
Source : LifeOS/Modules/FaceAnalysis.swift — 265 lignes, SHA256 70efcbd794e3.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add consistent capture guidance, face/pose/lighting quality checks, retake/correction, clearly explained measurements, saved dated comparisons and user-controlled exports/deletion. Inventory the actual Umax plans/progress features separately. Do not present a homemade ratio score as the competitor's validated model.

**Critère minimum à exécuter :** Reject no-face/multiple-face/strongly rotated images; repeat a fixture deterministically and explain changes after algorithm updates. Deleting an analysis removes its images and derived data.

**Dépendances à vérifier :** Vision capability checks, documented geometry algorithm, private attachment storage and versioned results. Keep recommendations separate from raw measurements.

**Reste déclaré, à confronter au code actuel :** Not seen on a real portrait; capture guidance and quality checks still missing.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 29. ✨ Apparence — TrueSkin
Référence à qualifier : TroveSkin.
Source : LifeOS/Modules/LooksModule.swift — 503 lignes, SHA256 4f5246d399db.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build structured products/ingredients, routine steps/order, schedules, product usage/expiry, skin diary and consistent photo comparison, progress and possible trigger tracking. Product compatibility needs a sourced rule set. Exact current TroveSkin listing/publisher remains unresolved.

**Critère minimum à exécuter :** Edit a routine without erasing history, log a product reaction and compare dated photos. Unknown product composition stays unknown; archived products remain attached to old entries.

**Dépendances à vérifier :** Product catalogue, ingredient service, skin journal and photo store. Confirm official baseline before attributing obscure features to TroveSkin.

**Reste déclaré, à confronter au code actuel :** Build structured products/ingredients, routine steps/order, schedules, product usage/expiry, skin diary and consistent photo comparison, progress and possible trigger tracking. Product compatibility needs a sourced rule set. Exact current TroveSkin listing/publisher remains unresolved.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 30. ✨ Apparence — Progrez
Référence à qualifier : Progress.
Source : LifeOS/Modules/LooksModule.swift — 503 lignes, SHA256 4f5246d399db.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add aligned side-by-side/slider comparison, body/measurement tags, progress timelines, pose guides, private albums, export and backup. Resolve which Progress app is intended; its generic name matches multiple products.

**Critère minimum à exécuter :** Compare two selected dates, rotate/import a large image, export the comparison and delete the original. No orphan thumbnail; cancelled import adds nothing.

**Dépendances à vérifier :** Shared attachment/measurement domain, import metadata, secure thumbnails and explicit comparison dates.

**Reste déclaré, à confronter au code actuel :** Add aligned side-by-side/slider comparison, body/measurement tags, progress timelines, pose guides, private albums, export and backup. Resolve which Progress app is intended; its generic name matches multiple products.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 31. ✨ Apparence — Mewing Klub
Référence à qualifier : Mewing Club.
Source : LifeOS/Modules/LooksModule.swift — 503 lignes, SHA256 4f5246d399db.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build structured guided sessions, exercise instruction, progression/history, reminder schedule and completion analytics. Resolve Mewing Club's exact publisher and feature list before claiming parity; do not assume measurable facial change from completing a timer.

**Critère minimum à exécuter :** A session can be paused, resumed, completed and revisited; editing reminders replaces old schedules. Progress means recorded practice, not a fabricated physical-change score.

**Dépendances à vérifier :** Content programme and durable session engine; avoid auto-generated outcome guarantees in product copy.

**Reste déclaré, à confronter au code actuel :** Build structured guided sessions, exercise instruction, progression/history, reminder schedule and completion analytics. Resolve Mewing Club's exact publisher and feature list before claiming parity; do not assume measurable facial change from completing a timer.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 32. ✨ Apparence — Wearing
Référence à qualifier : Whering / Acloset.
Source : LifeOS/Modules/LooksModule.swift — 503 lignes, SHA256 4f5246d399db.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add background removal, wardrobe search/tags, outfits and calendar, wear history/cost per wear, packing/capsule collections, actual weather/location integration and editable recommendations. Include inspiration/sharing features as explicit service work.

**Critère minimum à exécuter :** Import a garment, build an outfit, schedule and log wearing it, then generate a travel packing list. Weather failure shows manual selection instead of made-up conditions.

**Dépendances à vérifier :** Image segmentation, weather adapter, outfit graph and trip linkage; shared/private wardrobe data ownership.

**Reste déclaré, à confronter au code actuel :** Add background removal, wardrobe search/tags, outfits and calendar, wear history/cost per wear, packing/capsule collections, actual weather/location integration and editable recommendations. Include inspiration/sharing features as explicit service work.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 33. 🧠 Mental — Breathwerk
Référence à qualifier : Breathwrk.
Source : LifeOS/Modules/MindModule.swift — 291 lignes, SHA256 6afe2e2aabc4.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add a searchable exercise programme library, configurable phases/rounds, narrated/audio/haptic guidance, session history, reminders, favourites and progress. Respect reduce-motion settings while preserving phase cues.

**Critère minimum à exécuter :** Complete 4-7-8 and box sessions with VoiceOver and reduced motion; pause/resume does not skip phases, and one completion updates history exactly once.

**Dépendances à vérifier :** Shared session/audio/reminder engines and sourced/original instructional content.

**Reste déclaré, à confronter au code actuel :** Add a searchable exercise programme library, configurable phases/rounds, narrated/audio/haptic guidance, session history, reminders, favourites and progress. Respect reduce-motion settings while preserving phase cues.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 34. 🧠 Mental — Headplace
Référence à qualifier : Headspace / Calm.
Source : LifeOS/Modules/MindModule.swift — 291 lignes, SHA256 6afe2e2aabc4.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build guided programmes, sleep stories, music, topic/level/duration search, narrator/language metadata, favourites, downloads, playback resume, daily recommendations and progress. Catalogue availability is a product dependency, not a UI TODO.

**Critère minimum à exécuter :** Download a guided lesson, play offline/locked, interrupt with a call and resume at the same point. Completion/progress persists across phone and desktop; unavailable content is not replaced with a silent timer.

**Dépendances à vérifier :** Original/licensed audio/video and editorial pipeline; media CDN/download management, now-playing and background audio; shared session history.

**Reste déclaré, à confronter au code actuel :** Build guided programmes, sleep stories, music, topic/level/duration search, narrator/language metadata, favourites, downloads, playback resume, daily recommendations and progress. Catalogue availability is a product dependency, not a UI TODO.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 35. 🧠 Mental — Endlo
Référence à qualifier : Endel.
Source : LifeOS/Modules/Soundscape.swift — 300 lignes, SHA256 4c499187fe7d.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build persistent background playback, mode-specific mixes, levels/fades, session scheduling, offline presets and optional adaptive inputs such as time/activity. Add now-playing controls and consistent audio interruption handling.

**Critère minimum à exécuter :** Start a focus sound, navigate to tasks and lock the phone; audio continues as intended. Stop from lock-screen controls, detach headphones and reopen without a duplicated engine.

**Dépendances à vérifier :** Long-lived audio service outside view lifecycle, original sound assets/DSP and explicit contextual input permissions. Don't claim Endel's proprietary generation engine.

**Reste déclaré, à confronter au code actuel :** Build persistent background playback, mode-specific mixes, levels/fades, session scheduling, offline presets and optional adaptive inputs such as time/activity. Add now-playing controls and consistent audio interruption handling.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 36. 🧠 Mental — Daylia
Référence à qualifier : Daylio.
Source : LifeOS/Modules/MindModule.swift — 291 lignes, SHA256 6afe2e2aabc4.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add custom moods/activities, multiple daily entries, tags/photos, reminders, calendar/year views, filters, activity correlations, goals and export/backup. Historical edits must update analytics.

**Critère minimum à exécuter :** Backfill two moods on one day with activities, filter by activity, export and delete one. Counts and correlations update correctly without implying causation from sparse data.

**Dépendances à vérifier :** Journal domain, attachments, timezone-aware aggregation and user-controlled sharing.

**Reste déclaré, à confronter au code actuel :** Add custom moods/activities, multiple daily entries, tags/photos, reminders, calendar/year views, filters, activity correlations, goals and export/backup. Historical edits must update analytics.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 37. 🧠 Mental — Opale
Référence à qualifier : Opal / one sec.
Source : LifeOS/Modules/MindModule.swift — 291 lignes, SHA256 6afe2e2aabc4.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Implement actual app/category selection, authorized usage reports, scheduled/focus blocking, limits, intervention/breathing delays, session analytics and controlled overrides. Replace manual counts with explicit manual mode until real reports are available.

**Critère minimum à exécuter :** On an authorized physical device block chosen apps during a session, test expiry and revoke permission. Device restart/timezone changes do not strand a shield. Reports never label manually entered minutes as measured.

**Dépendances à vérifier :** FamilyControls/DeviceActivity/ManagedSettings with distribution entitlement and extensions where supported; separate desktop capability plan. Apple authorization is an implementation dependency, not a blanket impossibility.

**Reste déclaré, à confronter au code actuel :** Implement actual app/category selection, authorized usage reports, scheduled/focus blocking, limits, intervention/breathing delays, session analytics and controlled overrides. Replace manual counts with explicit manual mode until real reports are available.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 38. 🧠 Mental — Fabuleux
Référence à qualifier : Fabulous.
Source : LifeOS/Modules/MindModule.swift — 291 lignes, SHA256 6afe2e2aabc4.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Unify the two briefing paths; add structured routines, onboarding/journeys, habit stacking, coached programmes, reflection and progress. Generate today's briefing from real shared records, with editable preferences and reliable audio.

**Critère minimum à exécuter :** Change a task and sleep check-in, then open both briefing entry points. They agree on date/context; offline operation still offers a coherent routine and never invents appointments.

**Dépendances à vérifier :** Routine/habit domain, curated coaching content, shared day-context service and optional AI; no duplicate independent morning state.

**Reste déclaré, à confronter au code actuel :** Unify the two briefing paths; add structured routines, onboarding/journeys, habit stacking, coached programmes, reflection and progress. Generate today's briefing from real shared records, with editable preferences and reliable audio.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 39. ✅ Productivité — Todoo
Référence à qualifier : Todoist / Things.
Source : LifeOS/Modules/ProductivityModule.swift — 1078 lignes, SHA256 042f723c93a1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add nested projects/sections, subtasks/checklists, tags/filters/search, inbox/today/upcoming, natural-language capture, robust recurrence, reminders, dependencies and collaboration where required by the Todoist/Things union. Audit same-priority due-date sorting and calendar duplicates.

**Critère minimum à exécuter :** Complete a recurring task late across DST, undo it, move projects and export twice to calendar. Exactly one intended next occurrence and one linked event; upcoming tasks sort chronologically.

**Dépendances à vérifier :** Task/project domain with stable IDs, recurring occurrence model, shared reminder/calendar and collaboration services.

**Reste déclaré, à confronter au code actuel :** Add nested projects/sections, subtasks/checklists, tags/filters/search, inbox/today/upcoming, natural-language capture, robust recurrence, reminders, dependencies and collaboration where required by the Todoist/Things union. Audit same-priority due-date sorting and calendar duplicates.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 40. ✅ Productivité — Structurd
Référence à qualifier : Structured.
Source : LifeOS/Modules/ProductivityModule.swift — 1078 lignes, SHA256 042f723c93a1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add estimated duration, deadlines/priorities, calendar busy-time import, breaks/travel buffers, drag/drop timeline, split tasks, rescheduling, recurring tasks and explicit unscheduled overflow. Show plan previews and avoid overwriting user-locked blocks.

**Critère minimum à exécuter :** With a 30-minute task, 90-minute task and a fixed meeting, produce no overlaps, respect working hours and explain anything unscheduled. Moving a meeting updates only affected unlocked blocks.

**Dépendances à vérifier :** Shared task/calendar domain, deterministic scheduling engine and EventKit reconciliation; desktop keyboard/drag controls.

**Reste déclaré, à confronter au code actuel :** Add estimated duration, deadlines/priorities, calendar busy-time import, breaks/travel buffers, drag/drop timeline, split tasks, rescheduling, recurring tasks and explicit unscheduled overflow. Show plan previews and avoid overwriting user-locked blocks.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 41. ✅ Productivité — Habitly
Référence à qualifier : Habitify.
Source : LifeOS/Modules/ProductivityModule.swift — 1078 lignes, SHA256 042f723c93a1.
Statut déclaré iPhone : partial: sync layer unit-tested (16 tests incl. fetch failure, failed migration write, same-second opposite taps, concurrent snapshot); widget taps not run on a real home screen. Mac : not_started.

**Périmètre cible du registre :** Add quantity/duration targets, flexible frequencies, skips/pauses, habit areas, streak/calendar analytics, reminders, HealthKit automatic completion and backup/sync. Audit widget average-streak calculation: completion count is not a streak.

**Critère minimum à exécuter :** Test a twice-weekly habit, retroactive correction and archived habit with past history. App/widget/coach report the same streak and today's due set; no accidental completions on unscheduled dates.

**Dépendances à vérifier :** Shared habit engine with #27/#38, occurrence IDs and domain events for widgets/coach.

**Reste déclaré, à confronter au code actuel :** Tap the interactive widget on a real device and on Mac; habit editor depth vs Habitify (schedules, reminders per habit, streak freeze, stats); widgets for tasks still missing.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 42. ✅ Productivité — Forêt
Référence à qualifier : Forest.
Source : LifeOS/Modules/ProductivityModule.swift — 1078 lignes, SHA256 042f723c93a1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add durable focus/break sessions, configurable cycles, interruption rules, tags/history, visual growth/collection rewards and statistics. Implement supported distraction blocking via #37; multiplayer/real-tree programmes need separate services if retained in full parity scope.

**Critère minimum à exécuter :** Background a session, interrupt it and complete another. Rewards follow the documented policy and cannot be duplicated by relaunch; blocked-app behavior respects user authorization.

**Dépendances à vérifier :** Shared timer and blocking adapter, gamification domain, optional community/partner service. A Pomodoro timer alone is not Forest parity.

**Reste déclaré, à confronter au code actuel :** Add durable focus/break sessions, configurable cycles, interruption rules, tags/history, visual growth/collection rewards and statistics. Implement supported distraction blocking via #37; multiplayer/real-tree programmes need separate services if retained in full parity scope.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 43. ✅ Productivité — Notio
Référence à qualifier : Notion / Bear.
Source : LifeOS/Modules/ProductivityModule.swift — 1078 lignes, SHA256 042f723c93a1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add rich/Markdown editing, attachments, nested organization, backlinks, full-text search, export formats and version recovery. Full Notion scope additionally includes typed databases/views, relations/formulas, templates, collaborative pages/permissions and task links. Maintain an explicit backlog for each rather than relabelling plain text as a second brain.

**Critère minimum à exécuter :** Create linked notes and a database with two views, attach a PDF, edit offline on two devices and resolve conflicts. Export/reimport preserves structure and attachments; keyboard editing works on desktop.

**Dépendances à vérifier :** Document/block model, attachment index, search, sync/version conflicts, collaboration backend and import/export formats.

**Reste déclaré, à confronter au code actuel :** Add rich/Markdown editing, attachments, nested organization, backlinks, full-text search, export formats and version recovery. Full Notion scope additionally includes typed databases/views, relations/formulas, templates, collaborative pages/permissions and task links. Maintain an explicit backlog for each rather than relabelling plain text as a second brain.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 44. 💶 Argent — Bankino
Référence à qualifier : Bankin.
Source : LifeOS/Modules/FinanceModule.swift — 659 lignes, SHA256 d75f30cbf752.
Statut déclaré iPhone : defect_repaired. Mac : not_started.

**Périmètre cible du registre :** Fix ledger invariants first. Add transaction editing/reversal, account IDs rather than names, transfers, reconciliation, categories/rules, recurring payments, imports, search/history and real bank connection. Never infer connection from local accounts.

**Critère minimum à exécuter :** Account opens at 100; add −20, edit to −30, delete: balances 80,70,100. Same imported transaction delivered twice is counted once; renaming an account preserves all links.

**Dépendances à vérifier :** Canonical money/ledger service with Decimal/minor units and currency; authorized aggregation provider, consent/webhooks and deduplication shared with #45–53/#76.

**Reste déclaré, à confronter au code actuel :** Fix ledger invariants first. Add transaction editing/reversal, account IDs rather than names, transfers, reconciliation, categories/rules, recurring payments, imports, search/history and real bank connection. Never infer connection from local accounts.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 45. 💶 Argent — Ynabi
Référence à qualifier : YNAB.
Source : LifeOS/Modules/FinanceModule.swift — 659 lignes, SHA256 d75f30cbf752.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Implement funded assignments, available balances, transactions linked to categories, rollover/overspending handling, targets, credit-card/debt behavior, future months, reconciliation and reports. Preserve previous months and every transfer/reallocation.

**Critère minimum à exécuter :** Budget 100, spend 30, move 20 to another category and roll over with the selected policy. Earlier reports remain unchanged; refunds and transfer transactions don't inflate income/spending.

**Dépendances à vérifier :** Shared #44 ledger and budget periods; category assignment history, currencies and household sharing.

**Reste déclaré, à confronter au code actuel :** Implement funded assignments, available balances, transactions linked to categories, rollover/overspending handling, targets, credit-card/debt behavior, future months, reconciliation and reports. Preserve previous months and every transfer/reallocation.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 46. 💶 Argent — Pocket Money
Référence à qualifier : Rocket Money.
Source : LifeOS/Modules/FinanceModule.swift — 659 lignes, SHA256 d75f30cbf752.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Detect recurring merchants from connected/imported transactions, support trials/price changes, reminders, forecast and actual charge history. Track cancellation request/evidence/status. Full Rocket Money scope also includes budgeting and assisted bill/cancellation services through real providers.

**Critère minimum à exécuter :** Detect a monthly series and annual renewal, reject a coincidental one-off, notify a price increase and record confirmed cancellation. Bank disconnect shows stale detection data explicitly.

**Dépendances à vérifier :** Bank transaction stream, recurring-series detector and optional cancellation/negotiation operations. Never present a web search as a service completion.

**Reste déclaré, à confronter au code actuel :** Detect recurring merchants from connected/imported transactions, support trials/price changes, reminders, forecast and actual charge history. Track cancellation request/evidence/status. Full Rocket Money scope also includes budgeting and assisted bill/cancellation services through real providers.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 47. 💶 Argent — Quadricount
Référence à qualifier : Tricount.
Source : LifeOS/Modules/FinanceModule.swift — 659 lignes, SHA256 d75f30cbf752.
Statut déclaré iPhone : defect_repaired. Mac : not_started.

**Périmètre cible du registre :** Add stable groups/members, exact-cent accounting, unequal shares/percentages, multi-currency expenses, reimbursements, receipt attachments, complete settlement algorithm and collaborative edits/history.

**Critère minimum à exécuter :** For balances −100,+60,+40, suggest payments 60 and 40, never 100 to the first creditor. Test €10/3 rounding, partial repayments and a deleted shared expense on two devices.

**Dépendances à vérifier :** Shared finance primitives and group sync; settlement records distinct from expenses. Fix largest-debtor/creditor overpayment and truncation of cents.

**Reste déclaré, à confronter au code actuel :** Add stable groups/members, exact-cent accounting, unequal shares/percentages, multi-currency expenses, reimbursements, receipt attachments, complete settlement algorithm and collaborative edits/history.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 48. 💶 Argent — Kapital
Référence à qualifier : Qapital.
Source : LifeOS/Modules/FinanceModule.swift — 659 lignes, SHA256 d75f30cbf752.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add linked funding accounts, contribution/withdrawal history, scheduled/rule-based savings, shared goals and forecast scenarios. Automated deposits require actual payment/account service integration; a UI increment is not a transfer.

**Critère minimum à exécuter :** A simulated rule produces a preview, a confirmed provider transfer updates the goal once, and a failed transfer leaves balance unchanged. Manual mode is clearly distinct.

**Dépendances à vérifier :** Ledger/goal service, savings-rule evaluator and authorized money-movement provider if full Qapital behavior is retained.

**Reste déclaré, à confronter au code actuel :** Add linked funding accounts, contribution/withdrawal history, scheduled/rule-based savings, shared goals and forecast scenarios. Automated deposits require actual payment/account service integration; a UI increment is not a transfer.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 49. 💶 Argent — Linxa
Référence à qualifier : Linxo.
Source : LifeOS/Modules/FinanceModule.swift — 659 lignes, SHA256 d75f30cbf752.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Implement institution connection, consent lifecycle, initial/history sync, transaction deduplication, pending-to-booked reconciliation, balance freshness, reauthentication, connection health and deletion. Reuse this connection layer across finance modules.

**Critère minimum à exécuter :** Connect a sandbox bank, sync twice, expire/regrant consent and verify no duplicate transactions. Partial provider failure preserves good accounts and shows exactly which balance is stale.

**Dépendances à vérifier :** Commercial/authorized bank-data provider such as Powens with credentials and supported institutions. Evaluate requirements with the provider; don't mark the entire feature impossible because direct regulated access would be complex.

**Reste déclaré, à confronter au code actuel :** Implement institution connection, consent lifecycle, initial/history sync, transaction deduplication, pending-to-booked reconciliation, balance freshness, reauthentication, connection health and deletion. Reuse this connection layer across finance modules.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 50. 📈 Investissement — Finario
Référence à qualifier : Finary.
Source : LifeOS/Modules/InvestModule.swift — 571 lignes, SHA256 b2dcb92cf655.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add transaction lots, purchases/sales/dividends/fees, realized/unrealized returns, allocation, benchmarks, historical value, multiple asset classes and broker imports/connections. Audit source permissions, rate limits and market availability; latest price is not a performance history.

**Critère minimum à exécuter :** Buy, partially sell, receive a dividend and change currency. Returns reconcile to cashflows and fees; a failed quote retains a timestamped last value, not zero.

**Dépendances à vérifier :** Shared asset/ledger/FX providers, quote cache with timestamps and portfolio analytics; no implicit reliability promise for undocumented endpoints.

**Reste déclaré, à confronter au code actuel :** Add transaction lots, purchases/sales/dividends/fees, realized/unrealized returns, allocation, benchmarks, historical value, multiple asset classes and broker imports/connections. Audit source permissions, rate limits and market availability; latest price is not a performance history.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 51. 📈 Investissement — Kubero
Référence à qualifier : Kubera.
Source : LifeOS/Modules/InvestModule.swift — 571 lignes, SHA256 b2dcb92cf655.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Unify accounts, investments, properties and liabilities without double counting; add historical snapshots, currencies, debt amortization and editable scenarios. Full Kubera scope includes broader aggregation, sharing/access and continuity features that need explicit implementation.

**Critère minimum à exécuter :** Link an already-tracked account and property without counting either twice. A loan payment changes cash and liability consistently. Scenario assumptions are editable and projections are labeled projections.

**Dépendances à vérifier :** Canonical asset ownership graph, valuation dates, FX history, shared connection layer and access controls.

**Reste déclaré, à confronter au code actuel :** Unify accounts, investments, properties and liabilities without double counting; add historical snapshots, currencies, debt amortization and editable scenarios. Full Kubera scope includes broader aggregation, sharing/access and continuity features that need explicit implementation.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 52. 📈 Investissement — Horizo
Référence à qualifier : Horiz.io.
Source : LifeOS/Modules/InvestModule.swift — 571 lignes, SHA256 b2dcb92cf655.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add acquisition costs, financing/amortization, vacancy, repairs, taxes, cashflow/yield scenarios, comparable assumptions, tenancy/lease records, rent collection status, receipts and maintenance documents. Separate copied listing extraction from an actual authenticated listing feed.

**Critère minimum à exécuter :** Import a listing with missing rent, correct it and compare financed/unfinanced scenarios. Missing numbers remain blank; annual cashflow reconciles to monthly entries and generated receipts.

**Dépendances à vérifier :** Property/lease/cashflow domain, versioned tax assumptions, parser validation and document service; provider agreement if automatic listing ingestion is required.

**Reste déclaré, à confronter au code actuel :** Add acquisition costs, financing/amortization, vacancy, repairs, taxes, cashflow/yield scenarios, comparable assumptions, tenancy/lease records, rent collection status, receipts and maintenance documents. Separate copied listing extraction from an actual authenticated listing feed.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 53. 📈 Investissement — Impôts+
Référence à qualifier : Simulateur impots.gouv.
Source : LifeOS/Modules/InvestModule.swift — 571 lignes, SHA256 b2dcb92cf655.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Implement versioned tax-year forms and supported household cases, income classes, allowances/expenses, rental/capital income, deductions/credits, special cases and result breakdown/export. Explicitly distinguish simplified supported cases from full simulator parity.

**Critère minimum à exécuter :** Compare supported fixtures against the official 2026-on-2025 simulator at thresholds and family cases. Unsupported fields must be identified, not ignored while presenting a complete tax estimate.

**Dépendances à vérifier :** Official annual simulator/reference rules and golden fixtures, including rounding and household exceptions. Do not silently reuse one year's constants for the next.

**Reste déclaré, à confronter au code actuel :** Implement versioned tax-year forms and supported household cases, income classes, allowances/expenses, rental/capital income, deductions/credits, special cases and result breakdown/export. Explicitly distinguish simplified supported cases from full simulator parity.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 54. 💼 Carrière — Huntly
Référence à qualifier : Huntr.
Source : LifeOS/Modules/CareerModule.swift — 730 lignes, SHA256 36ff1db1ae4d.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add board/list views, job description snapshots, contacts, application dates/deadlines, tasks/reminders, attached resume variants, interviews and outcome analytics. Add browser/share-sheet capture and deduplication; preserve deleted listing details.

**Critère minimum à exécuter :** Capture the same job twice, move it through interview stages and link a resume. One application remains; stage history and next follow-up survive relaunch and export.

**Dépendances à vérifier :** Career job/application domain linked to #55/#57/#58, attachments, calendar and import adapters.

**Reste déclaré, à confronter au code actuel :** Add board/list views, job description snapshots, contacts, application dates/deadlines, tasks/reminders, attached resume variants, interviews and outcome analytics. Add browser/share-sheet capture and deduplication; preserve deleted listing details.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 55. 💼 Carrière — Zetty
Référence à qualifier : Zety / Canva.
Source : LifeOS/Modules/CareerModule.swift — 730 lignes, SHA256 36ff1db1ae4d.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build multiple resumes, structured sections/reorder, real page preview, templates, PDF/DOCX exports, import, versions, cover letters and job-specific tailoring with user review. Canva's wider design suite is a separate large scope: explicitly inventory editor/assets/collaboration beyond CVs rather than claiming Canva parity from resume templates.

**Critère minimum à exécuter :** Export a two-page French CV with accents and long entries to PDF/DOCX, reopen it and inspect pagination/text selection. Save an offer-specific variant without overwriting the master.

**Dépendances à vérifier :** Document layout/rendering engine, fonts/assets, attachment/version store and AI provider. Never invent qualifications while tailoring.

**Reste déclaré, à confronter au code actuel :** Build multiple resumes, structured sections/reorder, real page preview, templates, PDF/DOCX exports, import, versions, cover letters and job-specific tailoring with user review. Canva's wider design suite is a separate large scope: explicitly inventory editor/assets/collaboration beyond CVs rather than claiming Canva parity from resume templates.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 56. 💼 Carrière — LinkedUp
Référence à qualifier : LinkedIn Learning.
Source : LifeOS/Modules/CareerModule.swift — 730 lignes, SHA256 36ff1db1ae4d.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add role/skill assessment, searchable courses/learning paths, lessons/media playback, quizzes/practice, notes, progress and completion credentials. Connect a job's skill gaps to actual available lessons. Distinguish LifeOS completion records from third-party certificates.

**Critère minimum à exécuter :** Choose a missing skill, enroll in a real course, complete/resume a lesson offline and record an assessment. A link to a course is not shown as completion or a certificate.

**Dépendances à vérifier :** Original/licensed course content or a provider integration with verified access; media downloads, learning records and assessment engine.

**Reste déclaré, à confronter au code actuel :** Add role/skill assessment, searchable courses/learning paths, lessons/media playback, quizzes/practice, notes, progress and completion credentials. Connect a job's skill gaps to actual available lessons. Distinguish LifeOS completion records from third-party certificates.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 57. 💼 Carrière — Yoodly
Référence à qualifier : Yoodli.
Source : LifeOS/Modules/CareerModule.swift — 730 lignes, SHA256 36ff1db1ae4d.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add role/company/scenario configuration, follow-up conversations, recording/transcription, playback, delivery metrics, structured rubrics, practice history and improvement comparisons. Retain text-only mode without pretending it measures speech delivery.

**Critère minimum à exécuter :** Record an answer with a pause, inspect aligned transcript/feedback, retry and compare. Provider failure retains the draft; no invented pace/filler measurements for typed answers.

**Dépendances à vérifier :** Speech/audio and AI providers with capability checks; recording retention and rubric versioning. Yoodli-style delivery metrics must come from actual audio/transcript data.

**Reste déclaré, à confronter au code actuel :** Add role/company/scenario configuration, follow-up conversations, recording/transcription, playback, delivery metrics, structured rubrics, practice history and improvement comparisons. Retain text-only mode without pretending it measures speech delivery.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 58. 💼 Carrière — Welcome to the Djob
Référence à qualifier : Welcome to the Jungle.
Source : LifeOS/Modules/CareerModule.swift — 730 lignes, SHA256 36ff1db1ae4d.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add location/remote/type/salary/company filters, relevance explanations, saved searches/alerts, deduplication, pagination, expired-job handling, company profiles and application handoff/status. A different public feed is not Welcome to the Jungle catalogue parity.

**Critère minimum à exécuter :** Search with two filters, save and apply to a result, then expire it at the provider. Saved history remains while the listing is visibly closed; matching never claims skills absent from the user's profile.

**Dépendances à vérifier :** Supported job-data provider/partner access or an independent employer catalogue; normalized jobs and #54 integration.

**Reste déclaré, à confronter au code actuel :** Add location/remote/type/salary/company filters, relevance explanations, saved searches/alerts, deduplication, pagination, expired-job handling, company profiles and application handoff/status. A different public feed is not Welcome to the Jungle catalogue parity.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 59. 📚 Apprentissage — Trilingo
Référence à qualifier : Duolingo.
Source : LifeOS/Modules/Languages.swift — 207 lignes, SHA256 b06fa3ab7402.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build level placement, structured courses, vocabulary plus grammar, listening/reading/writing/speaking exercises, pronunciation feedback, adaptive practice, checkpoints and progress. Explicitly inventory the reference's non-language subjects and social/game systems if 'all Duolingo features' remains literal.

**Critère minimum à exécuter :** Complete a lesson containing all four language skills, make mistakes and receive targeted review. Resume on desktop at the same checkpoint; passing depends on answers, not opening the screen.

**Dépendances à vérifier :** Curriculum and exercise-authoring pipeline, language audio/TTS/STT, assessment/scheduling engine and content QA; shared flashcards as a component, not the whole course.

**Reste déclaré, à confronter au code actuel :** Build level placement, structured courses, vocabulary plus grammar, listening/reading/writing/speaking exercises, pronunciation feedback, adaptive practice, checkpoints and progress. Explicitly inventory the reference's non-language subjects and social/game systems if 'all Duolingo features' remains literal.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 60. 📚 Apprentissage — Anko
Référence à qualifier : Anki.
Source : LifeOS/Modules/LearningModule.swift — 367 lignes, SHA256 ff36a9c62ba1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add note/card types, cloze/reversed cards, images/audio, tags/search, deck hierarchy, import/export, scheduling controls, suspend/bury/undo, statistics and sync. Evaluate modern Anki scheduling compatibility and record exact supported formats rather than claiming full .apkg fidelity untested.

**Critère minimum à exécuter :** Import a deck with media/cloze, review offline, undo, change timezone and sync. Due dates and intervals remain deterministic; export/reimport retains card types, media and review history.

**Dépendances à vérifier :** Card/note/media schema, review event log and deterministic scheduler with migration policy.

**Reste déclaré, à confronter au code actuel :** Add note/card types, cloze/reversed cards, images/audio, tags/search, deck hierarchy, import/export, scheduling controls, suspend/bury/undo, statistics and sync. Evaluate modern Anki scheduling compatibility and record exact supported formats rather than claiming full .apkg fidelity untested.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 61. 📚 Apprentissage — Headwave
Référence à qualifier : Headway.
Source : LifeOS/Modules/LearningModule.swift — 367 lignes, SHA256 ff36a9c62ba1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build a genuine searchable micro-learning catalogue, structured programmes, read/listen modes, saved highlights, quizzes/recaps, spaced practice, recommendations and downloads. Content depth and editorial quality are required, not only an endless generated quote feed.

**Critère minimum à exécuter :** Read/listen to a complete lesson, save an excerpt, answer a quiz and revisit it offline. Progress records the actual lesson version; corrections propagate without losing notes.

**Dépendances à vérifier :** Original/licensed editorial content, audio production and shared learning/content services; connect #62/#63 without duplicate progress.

**Reste déclaré, à confronter au code actuel :** Build a genuine searchable micro-learning catalogue, structured programmes, read/listen modes, saved highlights, quizzes/recaps, spaced practice, recommendations and downloads. Content depth and editorial quality are required, not only an endless generated quote feed.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 62. 📚 Apprentissage — Blinklist
Référence à qualifier : Blinkist.
Source : LifeOS/Modules/LearningModule.swift — 367 lignes, SHA256 ff36a9c62ba1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add sourced book metadata, substantive edited summaries/audio, chapter/key-idea navigation, discovery, collections, highlights, downloads and personal-content summarization where supported. An ungrounded generated summary must not impersonate a verified book synopsis.

**Critère minimum à exécuter :** Find a book, read/listen offline, highlight and resume on desktop. An unknown title offers an honest unavailable state; generated output identifies its source material and cannot invent quotations.

**Dépendances à vérifier :** Original/licensed summary catalogue, grounding inputs, audio/CDN and editorial review; user notes remain distinct from catalogue content.

**Reste déclaré, à confronter au code actuel :** Add sourced book metadata, substantive edited summaries/audio, chapter/key-idea navigation, discovery, collections, highlights, downloads and personal-content summarization where supported. An ungrounded generated summary must not impersonate a verified book synopsis.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 63. 📚 Apprentissage — Coursia
Référence à qualifier : Coursera.
Source : LifeOS/Modules/LearningModule.swift — 367 lignes, SHA256 ff36a9c62ba1.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build multiple programmes, course/module/lesson hierarchy, enrollment, media playback, assessments/projects, deadlines, progress, discussion/feedback and credential verification. Coursera degree/professional programme services are not reproduced by a checklist; keep their delivery/partner dependencies explicit.

**Critère minimum à exécuter :** Enroll in a course, resume a lesson, submit a project, receive recorded feedback and finish all required assessments. A credential is issued only by its actual issuer and verified criteria.

**Dépendances à vérifier :** Learning-management backend, content authoring/licensing, assessment/grading, user roles and certification authority where applicable.

**Reste déclaré, à confronter au code actuel :** Build multiple programmes, course/module/lesson hierarchy, enrollment, media playback, assessments/projects, deadlines, progress, discussion/feedback and credential verification. Coursera degree/professional programme services are not reproduced by a checklist; keep their delivery/partner dependencies explicit.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 64. 🏠 Maison — NoGaspi
Référence à qualifier : NoWaste.
Source : LifeOS/Modules/HomeModule.swift — 288 lignes, SHA256 60d5a117482c.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Complete waste/consumption ledger, inventory entry/scanning, storage/batch management, reminders, waste/cost analytics and household sync by extending #17's canonical pantry. Avoid a second independent fridge database.

**Critère minimum à exécuter :** Consume, discard and correct a batch from either entry point; both modules and shopping quantities update. Waste reports distinguish consumed food from discarded stock.

**Dépendances à vérifier :** Shared pantry, shopping and recipe engines; receipt/barcode import and expiry notification scheduling.

**Reste déclaré, à confronter au code actuel :** Complete waste/consumption ledger, inventory entry/scanning, storage/batch management, reminders, waste/cost analytics and household sync by extending #17's canonical pantry. Avoid a second independent fridge database.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 65. 🏠 Maison — SuperCuisto
Référence à qualifier : SuperCook.
Source : LifeOS/Modules/HomeModule.swift — 288 lignes, SHA256 60d5a117482c.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Provide a substantial ingredient-indexed recipe catalogue, missing-ingredient logic, diet/allergen/time/skill filters, substitutions, serving scaling, instructions, favourites and meal-plan/shopping integration. Verify source links and recipe quality.

**Critère minimum à exécuter :** Given eggs/rice and a nut allergy, show genuinely feasible recipes, disclose missing items, scale servings and add only missing compatible ingredients to the shopping list.

**Dépendances à vérifier :** Original/licensed/search-provider recipe data, normalized ingredient quantities and dietary rules shared with #21.

**Reste déclaré, à confronter au code actuel :** Provide a substantial ingredient-indexed recipe catalogue, missing-ingredient logic, diet/allergen/time/skill filters, substitutions, serving scaling, instructions, favourites and meal-plan/shopping integration. Verify source links and recipe quality.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 66. 🏠 Maison — Sweepo
Référence à qualifier : Sweepy.
Source : LifeOS/Modules/HomeModule.swift — 288 lignes, SHA256 60d5a117482c.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add rooms, cleanliness/urgency, effort, schedules/rotation, household members, invitations, assigned notifications, completion history, points and shared activity. Support skip/reschedule and vacation modes.

**Critère minimum à exécuter :** Two household members complete the same chore offline; reconciliation records one occurrence and consistent credit. Reassignment updates reminders and removal of a member preserves history.

**Dépendances à vérifier :** Household identity/roles/sync, recurrence and audit events; integrate chores into common tasks without duplicate completions.

**Reste déclaré, à confronter au code actuel :** Add rooms, cleanliness/urgency, effort, schedules/rotation, household members, invitations, assigned notifications, completion history, points and shared activity. Support skip/reschedule and vacation modes.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 67. 🏠 Maison — 12pets
Référence à qualifier : 11pets.
Source : LifeOS/Modules/HomeModule.swift — 288 lignes, SHA256 60d5a117482c.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add multi-pet profiles, medical/vaccination/medication history, feeding/grooming/measurements, records/photos, recurring care plans, shared caregivers and vet-ready exports.

**Critère minimum à exécuter :** Schedule a recurring treatment, record a dose and export the pet's care record. Delete/archive the pet and verify reminders and attachments follow the documented policy.

**Dépendances à vérifier :** Pet subject type within shared treatment/reminder/document engines; caregiver access distinct from owner account.

**Reste déclaré, à confronter au code actuel :** Add multi-pet profiles, medical/vaccination/medication history, feeding/grooming/measurements, records/photos, recurring care plans, shared caregivers and vet-ready exports.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 68. 🏠 Maison — HomeZen
Référence à qualifier : HomeZada.
Source : LifeOS/Modules/HomeModule.swift — 288 lignes, SHA256 60d5a117482c.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add properties/rooms/assets, serial numbers/warranties/manuals, recurring schedule/reminders, service records/vendors, receipts, home inventory/photos, projects/budgets and valuation/expense reporting for wider HomeZada scope.

**Critère minimum à exécuter :** Register an appliance with warranty and filter schedule, mark serviced and attach receipt. Next due date recalculates, warning fires once, and an insurance inventory export includes the asset.

**Dépendances à vérifier :** Shared property/asset/vault domains, recurrence and household access.

**Reste déclaré, à confronter au code actuel :** Add properties/rooms/assets, serial numbers/warranties/manuals, recurring schedule/reminders, service records/vendors, receipts, home inventory/photos, projects/budgets and valuation/expense reporting for wider HomeZada scope.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 69. 🚗 Mobilité — Fuelo
Référence à qualifier : Fuelio.
Source : LifeOS/Modules/MobilityModule.swift — 165 lignes, SHA256 711faaa71deb.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add multiple fuel/charging types, fill-to-fill correctness, partial fills, odometer validation, expense categories, maintenance history, trip/mileage tracking, imports/exports and station prices where available.

**Critère minimum à exécuter :** Test partial fills, an odometer typo and a missed fill before accepting consumption. A business trip contributes mileage once; deleting a vehicle cancels its reminders.

**Dépendances à vérifier :** Vehicle/trip ledger, CoreLocation route capture and verified fuel-price provider; shared reminder/vault services.

**Reste déclaré, à confronter au code actuel :** Add multiple fuel/charging types, fill-to-fill correctness, partial fills, odometer validation, expense categories, maintenance history, trip/mileage tracking, imports/exports and station prices where available.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 70. 🚗 Mobilité — CityMappr
Référence à qualifier : Citymapper.
Source : LifeOS/Modules/MobilityTools.swift — 349 lignes, SHA256 d30693edc758.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add place search, multimodal routes, maps, departure/arrival times, live transit departures/disruptions, step guidance, saved commutes, accessibility preferences and real fares where sourced. Retain CO₂ as an explained estimate layered on real routes.

**Critère minimum à exécuter :** Plan an accessible route with a disrupted line; show realistic alternatives and data timestamp. Unsupported cities/feeds produce an honest limitation, not fabricated departures.

**Dépendances à vérifier :** Routing/geocoding and transit providers, GTFS/GTFS-RT coverage where supported, location and cache. City coverage must be explicit.

**Reste déclaré, à confronter au code actuel :** Add place search, multimodal routes, maps, departure/arrival times, live transit departures/disruptions, step guidance, saved commutes, accessibility preferences and real fares where sourced. Retain CO₂ as an explained estimate layered on real routes.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 71. 🚗 Mobilité — Park Maps
Référence à qualifier : Google Maps.
Source : LifeOS/Modules/MobilityTools.swift — 349 lignes, SHA256 d30693edc758.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Complete parking photo/floor/meter reminders and saved-location history. Literal Google Maps parity additionally requires place search/details, map browsing, route modes, navigation/traffic, saved lists, offline data and reviews; represent this as a substantial maps subsystem, not completed by the parking shortcut.

**Critère minimum à exécuter :** Save a parking spot with poor GPS, correct the pin and navigate back. Map search and route planning work independently of parking; offline/unavailable routes are clearly identified.

**Dépendances à vérifier :** Map SDK/routing/place/traffic providers and usage agreements; shared route service with #70. Provider-rendered functionality must remain usable inside LifeOS where technically supported.

**Reste déclaré, à confronter au code actuel :** Complete parking photo/floor/meter reminders and saved-location history. Literal Google Maps parity additionally requires place search/details, map browsing, route modes, navigation/traffic, saved lists, offline data and reviews; represent this as a substantial maps subsystem, not completed by the parking shortcut.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 72. 👥 Social — Dexo
Référence à qualifier : Dex.
Source : LifeOS/Modules/SocialModule.swift — 352 lignes, SHA256 27fe47b0602b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add stable source contact IDs, merge/conflict handling, groups/tags, interactions/notes, reminders, relationship history, search and supported email/calendar/contact integrations. Desktop/browser capture is separate work.

**Critère minimum à exécuter :** Import two different people with the same name and one renamed person twice; preserve correct identities. Logging an interaction updates the next reminder and connected history exactly once.

**Dépendances à vérifier :** Contacts/event adapters, CRM identity model and optional authorized communication sync.

**Reste déclaré, à confronter au code actuel :** Add stable source contact IDs, merge/conflict handling, groups/tags, interactions/notes, reminders, relationship history, search and supported email/calendar/contact integrations. Desktop/browser capture is separate work.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 73. 👥 Social — Hipp
Référence à qualifier : hip.
Source : LifeOS/Modules/SocialModule.swift — 352 lignes, SHA256 27fe47b0602b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add contact/calendar import, custom occasions, configurable advance reminders, leap-day rules, gift ideas/history/budget, cards/messages and shared family calendars where supported. Prefer stable event IDs over names.

**Critère minimum à exécuter :** Rename a person, change their birthday and delete the occasion; no orphan reminders. Test 29 February in leap/non-leap years and delivery at local time after travel.

**Dépendances à vérifier :** Shared contacts/occasion/reminder service and optional card/message delivery provider.

**Reste déclaré, à confronter au code actuel :** Add contact/calendar import, custom occasions, configurable advance reminders, leap-day rules, gift ideas/history/budget, cards/messages and shared family calendars where supported. Prefer stable event IDs over names.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 74. 👥 Social — Partyful
Référence à qualifier : Partiful / Luma.
Source : LifeOS/Modules/SocialModule.swift — 352 lignes, SHA256 27fe47b0602b.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add invitation pages/links, guest identities, RSVP/maybe/waitlist, plus-ones, polls, comments/updates, reminders, guest permissions and calendar integration. Luma-style ticketing/check-in/refunds require a real commerce layer.

**Critère minimum à exécuter :** Create a private event, invite test guests, receive an RSVP and update the time. Unauthorized guests cannot see private details; cancelled tickets/RSVPs update capacity and reminders.

**Dépendances à vérifier :** Hosted invitation/RSVP backend, notifications, access controls and optional payments/ticketing provider. Do not send invitations without the user's action.

**Reste déclaré, à confronter au code actuel :** Add invitation pages/links, guest identities, RSVP/maybe/waitlist, plus-ones, polls, comments/updates, reminders, guest permissions and calendar integration. Luma-style ticketing/check-in/refunds require a real commerce layer.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 75. 📁 Admin — Digicoffre
Référence à qualifier : Digiposte.
Source : LifeOS/Modules/AdminModule.swift — 385 lignes, SHA256 d8572055ee9f.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add original multi-page PDFs/files, OCR search, metadata/tags, versioning, access lock, secure backup/sync, import/export, controlled share links and account/document connectors. Preserve originals and attachment integrity across devices.

**Critère minimum à exécuter :** Import a multi-page contract, search a phrase on its last page, share with expiry and revoke access. Export/restore reproduces every original byte and metadata link.

**Dépendances à vérifier :** Document/attachment storage with encryption/access controls, OCR index, sharing service and supported issuer connectors. Separate personal storage from any certified archival claim.

**Reste déclaré, à confronter au code actuel :** Add original multi-page PDFs/files, OCR search, metadata/tags, versioning, access lock, secure backup/sync, import/export, controlled share links and account/document connectors. Preserve originals and attachment integrity across devices.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 76. 📁 Admin — Papernid
Référence à qualifier : Papernest.
Source : LifeOS/Modules/AdminModule.swift — 385 lignes, SHA256 d8572055ee9f.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Link contracts/subscriptions, detect renewals from real records, import bills, show forecasts, compare sourced offers and track provider switching/cancellation through confirmations. Include moving-house workflows and energy information where the verified baseline applies.

**Critère minimum à exécuter :** Import a contract renewal, schedule notice and initiate a sandbox provider change. Status only advances on a real confirmation; no fabricated savings or cancellation completion.

**Dépendances à vérifier :** Shared #44/#46 bank/contract domains plus commercial provider integrations for switching. Keep manual deadlines useful while externally executed operations remain pending.

**Reste déclaré, à confronter au code actuel :** Link contracts/subscriptions, detect renewals from real records, import bills, show forecasts, compare sourced offers and track provider switching/cancellation through confirmations. Include moving-house workflows and energy information where the verified baseline applies.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 77. 📁 Admin — Lettre-Public
Référence à qualifier : Modèles Service-Public.
Source : LifeOS/Modules/AdminModule.swift — 385 lignes, SHA256 d8572055ee9f.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build a searchable, versioned template catalogue with source/date/jurisdiction, conditional questionnaires, required-field validation, attachments, editable preview, PDF/DOCX export and delivery tracking if a delivery service is added.

**Critère minimum à exécuter :** Generate a cancellation letter with accents/address/date, inspect exported pages and verify required notice fields. Outdated/unavailable templates are flagged rather than silently reused.

**Dépendances à vérifier :** Official Service-Public template references, document renderer and deadline/contract linkage. The official template library is a source, not an embedded execution service.

**Reste déclaré, à confronter au code actuel :** Build a searchable, versioned template catalogue with source/date/jurisdiction, conditional questionnaires, required-field validation, attachments, editable preview, PDF/DOCX export and delivery tracking if a delivery service is added.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 78. 📁 Admin — Adobo Scan
Référence à qualifier : Adobe Scan.
Source : LifeOS/Modules/DocScan.swift — 430 lignes, SHA256 d68c319730c6.
Statut déclaré iPhone : partial: verified on simulator (2-page invoice, reorder, save, relaunch, PDF share). Mac : partial.

**Périmètre cible du registre :** Preserve all pages/original PDFs; crop/rotate/reorder/delete pages, perspective cleanup, searchable PDF OCR, classification confidence/manual correction, search/share and vault integration. Audit desktop PDF import so it does not merely rasterize page one.

**Critère minimum à exécuter :** Scan/import a five-page document, reorder pages and search text from page five. Export/reopen PDF preserves five pages and selectable text; cancellation/failure never reports a saved document falsely.

**Dépendances à vérifier :** Multi-page Document/Page/Attachment schema, Vision/PDFKit OCR pipeline and transactional file storage; phone camera plus desktop file/drag input.

**Reste déclaré, à confronter au code actuel :** Perspective cleanup/crop; searchable (text layer) PDF; real camera scan on device; 5-page journey.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 79. ✈️ Voyage — TripUp
Référence à qualifier : TripIt.
Source : LifeOS/Modules/TravelModule.swift — 306 lignes, SHA256 82d646edba8f.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add structured reservations/segments for flights/hotels/rail/car, confirmation import/parsing, timezone-aware itinerary, documents/maps, sharing, expenses, packing and alerts. TripIt Pro-style status and disruption features depend on live feeds.

**Critère minimum à exécuter :** Import a multi-city confirmation with local timezones, correct one segment and share with a companion. Duplicate emails do not duplicate reservations; changed flights propagate without losing user notes.

**Dépendances à vérifier :** Travel itinerary schema, email/file import with explicit access, parser review and #80/#83 services.

**Reste déclaré, à confronter au code actuel :** Add structured reservations/segments for flights/hotels/rail/car, confirmation import/parsing, timezone-aware itinerary, documents/maps, sharing, expenses, packing and alerts. TripIt Pro-style status and disruption features depend on live feeds.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 80. ✈️ Voyage — Xchange
Référence à qualifier : XE Currency.
Source : LifeOS/Modules/TravelTools.swift — 355 lignes, SHA256 f6161bb5da45.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add timestamped live rates, refresh/cache/failure behavior, broader currencies, historical charts, favourites and rate alerts. Full XE transfer functionality requires a real payments service; conversion estimates must be distinct from executable quotes and fees.

**Critère minimum à exécuter :** Fetch a rate, go offline, convert a cross pair and display the original timestamp. Stale data is explicit; transfer failure cannot appear completed or debit a local balance fictitiously.

**Dépendances à vérifier :** FX data provider, currency precision rules and shared finance/travel cache; optional transfer provider with complete status lifecycle.

**Reste déclaré, à confronter au code actuel :** Add timestamped live rates, refresh/cache/failure behavior, broader currencies, historical charts, favourites and rate alerts. Full XE transfer functionality requires a real payments service; conversion estimates must be distinct from executable quotes and fees.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 81. ✈️ Voyage — iTraduis
Référence à qualifier : iTranslate.
Source : LifeOS/Modules/TravelTools.swift — 355 lignes, SHA256 f6161bb5da45.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add searchable categories, favourites/custom phrases, pronunciation controls, offline language assets and destination collections. Literal iTranslate parity includes arbitrary text/voice/camera translation and conversation modes, which should reuse #82 instead of stopping at canned phrases.

**Critère minimum à exécuter :** Find and play a phrase offline, save a custom translation and reopen on desktop. Unsupported pronunciation/translation languages are visible before the user starts.

**Dépendances à vérifier :** Shared translation/TTS/STT and language-capability registry; content translations reviewed per language.

**Reste déclaré, à confronter au code actuel :** Add searchable categories, favourites/custom phrases, pronunciation controls, offline language assets and destination collections. Literal iTranslate parity includes arbitrary text/voice/camera translation and conversation modes, which should reuse #82 instead of stopping at canned phrases.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 82. ✈️ Voyage — Goggle Traduction
Référence à qualifier : Google Traduction.
Source : LifeOS/Modules/Translator.swift — 208 lignes, SHA256 ec319e0b62fb.
Statut déclaré iPhone : not_started. Mac : partial: real Mac Catalyst build translated 'Bonjour, où est la gare ?' -> 'Hello, where is the train station?' (DEBUG probe).

**Périmètre cible du registre :** Add dynamic capability checks, download management, language detection, history/favourites, speech input/output, conversation mode, camera/image OCR and document translation. Match supported reference workflows explicitly; do not assume Apple's language coverage equals Google's.

**Critère minimum à exécuter :** Translate typed text, a photographed menu and a two-person exchange. Test uninstalled offline assets and unsupported pairs. Keep original formatting/context and never show untranslated text as a successful translation.

**Dépendances à vérifier :** Translation provider abstraction, Vision OCR, speech adapters and offline asset lifecycle; desktop capability checks.

**Reste déclaré, à confronter au code actuel :** Language detection, history/favourites, download management UI, speech.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 83. ✈️ Voyage — Flighto
Référence à qualifier : Flighty.
Source : LifeOS/Modules/TravelModule.swift — 306 lignes, SHA256 82d646edba8f.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Add flight/date/airport lookup, live departure/arrival/gate/terminal/status, disruption alerts, incoming aircraft where supplied, timezone correctness, calendar/email import, sharing and travel history. Mark unknown status unknown until a provider confirms it.

**Critère minimum à exécuter :** Simulate delayed, cancelled, diverted and gate-changed flights. Alerts update once; a disconnected feed never reverts to on-time. Date-line crossings and codeshares resolve the correct flight.

**Dépendances à vérifier :** Flight-data provider with commercial access/coverage, backend polling/push and itinerary links. Preserve provider timestamp and confidence.

**Reste déclaré, à confronter au code actuel :** Add flight/date/airport lookup, live departure/arrival/gate/terminal/status, disruption alerts, incoming aircraft where supplied, timezone correctness, calendar/email import, sharing and travel history. Mark unknown status unknown until a provider confirms it.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 88. ✈️ Voyage — Envol
Référence à qualifier : Skyscanner (functional reference only, never a provider).
Source : LifeOS/Modules/FlightCompare.swift — 729 lignes, SHA256 30c040f6dbd9 ; flights-api/ — dossier présent.
Statut déclaré iPhone : partial. Mac : not_verified.

**Périmètre cible du registre :** Independent multi-source engine (FlightSearchProvider adapters, capability registry, backend-held keys, parallel bounded search, partial results, dated cache, budget), normalized offers, grouping without merging, cheapest/fastest/best explained, refresh before handoff, filters, favourites, server alerts with unsubscribe, link to trip/calendar without marking booked.

**Critère minimum à exécuter :** Two real distinct sources: same route/passengers/currency, grouping, different fares, source down, price changed, expired offer, seller handoff, filters, alerts, add to trip.

**Dépendances à vérifier :** Duffel account + test key (Theo); second real source needs a contract (Travelport or airline NDC); APNs for push alerts; places API for city/nearby airports.

**Reste déclaré, à confronter au code actuel :** Connect Duffel test key and measure coverage; seller handoff model; second real source; push alerts; places lookup; iPad/Mac checks.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 84. 🏡 En dehors des catégories — Réveil
Référence à qualifier : Alarmy.
Source : LifeOS/Core/AlarmManager.swift — 391 lignes, SHA256 befc37e873b3.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Build multiple persistent alarms, repeat rules, labels/sounds, reliable supported system delivery, missions (math/photo/barcode/steps as selected), snooze policy, wake checks and history. Keep the briefing integration. Inventory Alarmy sleep-related features separately.

**Critère minimum à exécuter :** Test locked phone, silent/Focus modes under the chosen API contract, relaunch/reboot, DST and disabled authorization. A mission must be completed before the chosen dismiss policy advances; don't auto-dismiss after ten seconds.

**Dépendances à vérifier :** Evaluate AlarmKit on supported OS, authorization and actual background/terminated behavior; fallback notifications must be named honestly. Camera/motion missions need device adapters; desktop requires its own delivery tests.

**Reste déclaré, à confronter au code actuel :** Build multiple persistent alarms, repeat rules, labels/sounds, reliable supported system delivery, missions (math/photo/barcode/steps as selected), snooze policy, wake checks and history. Keep the briefing integration. Inventory Alarmy sleep-related features separately.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 85. 🏡 En dehors des catégories — Ton coach
Référence à qualifier : ChatGPT.
Source : LifeOS/Shared/AIAssistantView.swift — 2066 lignes, SHA256 3ea800ba6295.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Audit actual capability end-to-end, then add missing reference workflows: robust conversation/project organization, file/document analysis, grounded web research/citations, richer voice, image generation where provided, searchable history and reliable artifacts. Full ChatGPT capability inventory is separate from simply calling a text model; current image-only importer is not general file analysis.

**Critère minimum à exécuter :** Run a scenario using real LifeOS data, attach a PDF, cite a retrieved source and preview/apply a task change. Cancel mid-stream and retry without duplicate mutations; unavailable providers show an actionable state and retain the draft.

**Dépendances à vérifier :** Reuse AICore/router/tools/memory rather than rewrite. Provider capability matrix, server-backed credentials where appropriate, file processing, citation provenance, budgets/cancellation and idempotent tool actions.

**Reste déclaré, à confronter au code actuel :** Audit actual capability end-to-end, then add missing reference workflows: robust conversation/project organization, file/document analysis, grounded web research/citations, richer voice, image generation where provided, searchable history and reliable artifacts. Full ChatGPT capability inventory is separate from simply calling a text model; current image-only importer is not general file analysis.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 86. 🏡 En dehors des catégories — Score du jour & bilan
Référence à qualifier : Bevel.
Source : LifeOS/Services/EnergyScore.swift — 134 lignes, SHA256 97ee80a18706.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Keep a transparent LifeOS daily-goal score while adding separately labeled recovery/sleep/strain/stress/nutrition trends and coaching where supported. Personal baselines, journal correlations and input coverage are essential. Inventory Bevel's current modules and map shared nutrition/workout services rather than duplicating them.

**Critère minimum à exécuter :** Withhold unavailable data, update a corrected sleep entry and compare all score displays. Explain each contribution and coverage; goal completion must not be mislabeled as measured physiological recovery.

**Dépendances à vérifier :** Shared health/workout/nutrition/journal analytics and historical snapshots; validated definitions and no invented biometric inputs.

**Reste déclaré, à confronter au code actuel :** Keep a transparent LifeOS daily-goal score while adding separately labeled recovery/sleep/strain/stress/nutrition trends and coaching where supported. Personal baselines, journal correlations and input coverage are essential. Inventory Bevel's current modules and map shared nutrition/workout services rather than duplicating them.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.

## 87. 🏡 En dehors des catégories — Accueil personnalisable
Référence à qualifier : Widgets iOS.
Source : LifeOS/Core/HomeWidgetEditing.swift — 217 lignes, SHA256 edbcd449f2c5.
Statut déclaré iPhone : not_started. Mac : not_started.

**Périmètre cible du registre :** Complete add/remove/reorder/resize/configure of supported dashboard cards; phone/tablet/desktop layouts; widget families, deep links and actions; persistent preferences and synchronized data. Distinguish in-app cards from actual OS widgets and Live Activities.

**Critère minimum à exécuter :** Reorder on phone, reopen desktop, invoke a widget action while the app is closed and verify exactly one domain update. Removed/archived modules never leave dead links or stale private data in snapshots.

**Dépendances à vérifier :** Stable widget/tool IDs, shared read models/intents, capability registry and accessibility/keyboard reorder; preserve the separate Liquid Glass design system.

**Reste déclaré, à confronter au code actuel :** Complete add/remove/reorder/resize/configure of supported dashboard cards; phone/tablet/desktop layouts; widget families, deep links and actions; persistent preferences and synchronized data. Distinguish in-app cards from actual OS widgets and Live Activities.

**Preuve exigée pour clore :** création/utilisation réelle, modification, suppression/annulation, relance et effets intermodules ; captures clair/sombre iPhone/Mac ; états vide, hors-ligne, permission refusée et fournisseur indisponible. Marquer individuellement tout parcours non testé.
