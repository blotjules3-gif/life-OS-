# LifeOS — audit of all 87 tools

Source audit dated 26 September 2026. Repository reference `20db360eb`; inspected feature code derives from `4959958b4` with intervening UI-only changes. This annex is a source-level implementation backlog, not proof of runtime completion or exhaustive paid-reference parity. Read the accompanying prompt for common acceptance gates, platform requirements and exact-baseline closure.

**Progress labels are qualitative.** They identify the dominant remaining work, not a percentage or a passed release state. The original Notion checks are retained as claims for comparison. Every requirement below also needs the common mobile/desktop, persistence, failure-state and cross-module tests.

## 🩺 Santé

### 01. MediSûr — Médicaments

**Reference:** Medisafe. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Traitements en cours et rappels de prise. **Original status claim:** ✅ Rappels chaque jour, 2 ou 3 prises, date de fin, rien pour « au besoin ».

**Source evidence:** [`MedicationView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MedicalModule.swift:9) in `LifeOS/Modules/MedicalModule.swift`. Medication CRUD, active/inactive treatments, dosage, start/end dates and scheduled reminders exist. A dose-by-dose adherence ledger is not present in this view.

**Work to deliver:** Build treatment schedules with multiple times, weekdays, intervals and PRN; log taken/skipped/snoozed/missed doses with undo; supply/refill tracking; adherence history/export; dependent profiles and caregiver sharing; prescription attachments. Inventory and reports must derive from dose events, not notification delivery. Evaluate interactions and medication lookup against a real drug-data service; never fabricate them.

**Integration/dependencies:** Shared treatment/dose/reminder domain with #20, stable IDs, medication dataset and caregiver backend. End dates and dose changes must reconcile pending notifications.

**Minimum acceptance scenario:** Create a twice-daily treatment ending tomorrow; take one dose, skip one, edit the time, relaunch, and verify stock, history and pending reminders. Delete it and verify no orphan reminders.

**Public baseline references:** [Medisafe](https://apps.apple.com/us/app/medisafe-medication-management/id573916946). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 02. Doctolink — Rendez-vous

**Reference:** Doctolib. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Agenda médical, rappel la veille. **Original status claim:** ✅ Rappel annulé si le rendez-vous est supprimé.

**Source evidence:** [`AppointmentsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MedicalModule.swift:233) in `LifeOS/Modules/MedicalModule.swift`. Manual medical appointments, practitioner/specialty/location/notes and reminders exist. No practitioner search, availability or actual appointment booking was found in the routed module.

**Work to deliver:** Add practitioner directory/filtering, live slots, booking/reschedule/cancellation, booking confirmations, dependent profiles, documents and consultation history. Include waiting-list notifications, secure practitioner messaging and teleconsultation where the selected reference baseline supports them. Separate personal calendar entries from confirmed provider bookings.

**Integration/dependencies:** Real provider scheduling/messaging/video agreements or an independently operated appointment service with participating practitioners; EventKit export is not a booking API. Build manual agenda immediately, track provider-dependent flows separately.

**Minimum acceptance scenario:** An available slot can be booked exactly once, confirmed, rescheduled and cancelled against a sandbox provider; two clients racing for the same slot cannot both succeed. Offline entries never display provider-confirmed status.

**Public baseline references:** [Doctolib](https://apps.apple.com/fr/app/doctolib-compagnon-de-sant%C3%A9/id925339063). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 03. Maple Health — Carnet de santé

**Reference:** Apple Santé. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Poids, tension, glycémie. **Original status claim:** ✅.

**Source evidence:** [`VitalsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MedicalModule.swift:358) in `LifeOS/Modules/MedicalModule.swift`. Manual weight, blood pressure, glucose and pulse records/charts exist. HealthAutoSync additionally imports newer weight samples and sleep context; this is more than a purely manual journal.

**Work to deliver:** Implement source-aware HealthKit records, supported metric categories, units, ranges, trends and historical exploration; import/export and sharing; distinguish unknown from zero and duplicate sources. Track which Apple Health capabilities are reproduced and which rely on the system app, including clinical documents, medication/cycle views and supported device data.

**Integration/dependencies:** HealthService/HealthRepository/HealthAutoSync, permission-aware adapters, shared metric schema and document vault. Desktop should display synchronized records without pretending to acquire unavailable sensors.

**Minimum acceptance scenario:** Import overlapping samples from two sources, manually correct one record, revoke access, then reopen on desktop. No double counting, stale values marked, unit conversion reversible, absence never shown as zero.

**Public baseline references:** [Apple Santé](https://www.apple.com/health/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 04. Mon Espace Vaccin — Vaccinations

**Reference:** Mon espace santé. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Historique et rappel avant l'échéance. **Original status claim:** ✅ Rappel 30 jours avant.

**Source evidence:** [`VaccinationView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MedicalModule.swift:564) in `LifeOS/Modules/MedicalModule.swift`. Local vaccination records, lot numbers, next-due dates and reminders exist. This covers a small vaccination notebook, not Mon espace santé.

**Work to deliver:** Add multi-person vaccination histories, product/dose/practitioner/lot/document provenance, schedule versioning, catch-up review and exports. Full reference scope additionally requires a health document repository, care profile, secure communications and authorized interoperability, not merely another vaccine form.

**Integration/dependencies:** Use shared medical profiles and vault; versioned jurisdiction/age-specific schedule data. Actual Mon espace santé access requires a supported integration route; don't infer access from the app's existence.

**Minimum acceptance scenario:** Import a vaccination certificate, link it to a dose, edit a future booster and verify reminder replacement. Show exactly which schedule/version suggested the due date and allow corrections.

**Public baseline references:** [Mon espace santé](https://apps.apple.com/fr/app/mon-espace-sant%C3%A9/id1589255019). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 🌸 Cycle

### 05. Floé — Suivi du cycle

**Reference:** Flo. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Règles, durée, prédiction. **Original status claim:** ✅.

**Source evidence:** [`CycleTrackerView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CycleModule.swift:30) in `LifeOS/Modules/CycleModule.swift`. Cycle start/length settings and daily flow/symptom/mood entries exist. Prediction relies on simple stored-cycle assumptions.

**Work to deliver:** Build calendar editing for historical periods, variable-cycle predictions with uncertainty, explicit period boundaries, goals and relevant life-stage modes. Add symptom insights, reminders, educational material and user-controlled sharing. Pregnancy/fertility/perimenopause feature families must be inventoried separately instead of claiming full Flo parity from period arithmetic.

**Integration/dependencies:** One cycle domain for #5–7; historical inputs, prediction version and provenance; optional HealthKit integration; curated content. User-entered and predicted events must remain distinct.

**Minimum acceptance scenario:** Enter three irregular periods, correct one retrospectively and confirm predictions/history update together. Missing history shows uncertainty; a predicted fertile date is never presented as confirmed ovulation.

**Public baseline references:** [Flo](https://apps.apple.com/us/app/flo-cycle-period-tracker/id1038369065). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 06. Klue — Symptômes

**Reference:** Clue. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Crampes, humeur, énergie, peau. **Original status claim:** ✅.

**Source evidence:** [`CycleSymptomsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CycleModule.swift:367) in `LifeOS/Modules/CycleModule.swift`. A small fixed symptom vocabulary and recent symptom counts are present.

**Work to deliver:** Support configurable symptom/intensity/duration logs, mood, pain, discharge and other reference categories; custom tags, searchable daily entries, cycle-phase correlations and trend/export views. Add stage-specific categories without forcing irrelevant questions. Clarify associations rather than presenting causal conclusions.

**Integration/dependencies:** Reuse CycleEntry through a richer versioned schema, shared calendar, stable symptom identifiers and optional attachments; migrate existing eight-category entries.

**Minimum acceptance scenario:** Log multiple symptoms with severity, edit an old day and inspect filtered history and phase comparisons. Deleted entries disappear from every aggregate and export.

**Public baseline references:** [Clue](https://apps.apple.com/us/app/clue-period-cycle-tracker/id657189652). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 07. Floé Stats — Historique

**Reference:** Flo / Clue. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Régularité, durée moyenne, plus court et plus long. **Original status claim:** ✅ Corrigé : ne s'affichait jamais si on note tous les jours.

**Source evidence:** [`CycleHistoryView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CycleModule.swift:404) in `LifeOS/Modules/CycleModule.swift`. Cycle history/statistics views exist and have dedicated CycleStats tests in the repository.

**Work to deliver:** Add period duration, cycle-length distribution, irregularity, symptom trend overlays, date-range filters, corrections, report export and meaningful insufficient-data states. Reconcile all cycle screens and coach context with the same calculations; include the wider Flo/Clue reporting baseline in the parity ledger.

**Integration/dependencies:** Shared cycle analytics service, timezone-aware day boundaries, tested fixtures including incomplete cycles and lifecycle changes.

**Minimum acceptance scenario:** A fixture with incomplete and unusually long cycles produces explainable statistics, excludes incomplete cycles appropriately and yields identical results in history, tracker and exported report.

**Public baseline references:** [Flo](https://apps.apple.com/us/app/flo-cycle-period-tracker/id1038369065); [Clue](https://apps.apple.com/us/app/clue-period-cycle-tracker/id657189652). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 😴 Sommeil

### 08. Sleep Circle — Heure de coucher optimale

**Reference:** Sleep Cycle. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Cycles de 90 min. **Original status claim:** 🟡 Réveil en sommeil léger : demande une Apple Watch.

**Source evidence:** [`BedtimeCalculatorView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SleepModule.swift:12) in `LifeOS/Modules/SleepModule.swift`. The routed Sleep Circle tool is a bedtime calculator based on 90-minute cycles plus a sleep-onset allowance. Health sleep import elsewhere does not make this a Sleep Cycle tracker.

**Work to deliver:** Add actual overnight session recording, supported microphone/motion or HealthKit acquisition, sleep timeline and quality trends, sleep notes/audio events, smart wake window, history and exports. Keep the calculator as a secondary feature. A phone-based route is possible; an Apple Watch is not universally required for Sleep Cycle-style tracking.

**Integration/dependencies:** Choose and validate acquisition/analysis technology, recording permission, storage/retention, background operation and alarm adapter. Sleep-stage claims need validated evidence; audio event detection is not automatically sleep staging.

**Minimum acceptance scenario:** Run an overnight real-device session, interrupt audio, relaunch and verify retained samples, timeline and alarm delivery. Test absent/denied sensors and never generate a plausible-looking night from no data.

**Public baseline references:** [Sleep Cycle](https://apps.apple.com/us/app/sleep-cycle-tracker-sounds/id320606217). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 09. Pzazz — Power nap

**Reference:** Pzizz. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Sieste de 20 ou 90 min. **Original status claim:** ✅.

**Source evidence:** [`PowerNapView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SleepModule.swift:90) in `LifeOS/Modules/SleepModule.swift`. 20/90-minute nap presets use CountdownEngine. Completion notification is scheduled after the in-app countdown finishes, so it cannot establish reliable suspended-app completion.

**Work to deliver:** Build persisted nap sessions, configurable duration, narrated/soundscape programmes, sound/voice mixing, fade-in/out, wake alarm and history. Include sleep/focus modes if retaining full Pzizz scope, not only nap timing.

**Integration/dependencies:** Shared durable timer, audio session/player and supported alarm delivery; original or licensed audio library with offline downloads.

**Minimum acceptance scenario:** Start a nap, lock the phone and background/terminate as supported by the chosen alarm API; completion uses the original deadline. Pause/resume and headphones removal behave predictably; no duplicate completion record.

**Public baseline references:** [Pzizz](https://apps.apple.com/us/app/pzizz-sleep-nap-focus/id915664862). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 10. Rize — Coucher progressif

**Reference:** Rise. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Rappel, lumière bleue, mode nuit. **Original status claim:** ✅.

**Source evidence:** [`WindDownView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SleepModule.swift:143) in `LifeOS/Modules/SleepModule.swift`. A bedtime reminder and advice are present. The UI does not actually control system blue-light/night-mode settings.

**Work to deliver:** Add sleep debt/history, personalized wind-down schedule, energy-window presentation, routine checklist, reminders and calendar integration. Label predictions and input coverage. Provide supported shortcuts/settings guidance for system modes instead of a switch that claims to change unsupported OS settings.

**Integration/dependencies:** Shared sleep history, circadian model with explicit assumptions, routine engine and calendar adapter. RISE-style debt and energy forecasting require more than a fixed reminder.

**Minimum acceptance scenario:** Change wake time and enter a short night; recompute schedule consistently. Verify cross-midnight reminders, travel timezone changes and missing sleep data without inventing recovery.

**Public baseline references:** [Rise](https://apps.apple.com/us/app/rise-sleep-tracker/id1453884781). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 11. Awaken — Journal de rêves

**Reference:** Awoken. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Note vocale, texte, humeur. **Original status claim:** ✅.

**Source evidence:** [`DreamJournalView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SleepModule.swift:198) in `LifeOS/Modules/SleepModule.swift`. Text, mood and recorded-audio dream entries exist.

**Work to deliver:** Add transcription when available, search/tags, playback management, reality-check reminders, lucid-dream exercises and progress, attachments/export/backup. Manage recording files transactionally on save/delete. Resolve the exact Awoken identity: a verified Android listing exists, while the iOS search returned a different product.

**Integration/dependencies:** Speech/audio adapters and shared attachment store. Baseline identity remains a research item; do not substitute Shape as Awoken.

**Minimum acceptance scenario:** Record, save, transcribe, search, play and delete a dream; cancelling an entry leaves no orphan recording. Reality reminders respect quiet hours and notification denial.

**Public baseline references:** [Awoken](https://play.google.com/store/apps/details?id=com.lucid_dreaming.awoken&hl=en_GB). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 12. Whoosh — Score de récupération

**Reference:** Whoop / AutoSleep. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** HRV et fréquence cardiaque au repos (Apple Santé). **Original status claim:** ✅ Sur un vrai iPhone.

**Source evidence:** [`RecoveryScoreView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SleepModule.swift:338) in `LifeOS/Modules/SleepModule.swift`. Reads HRV/resting heart rate and computes a fixed weighted formula. WHOOP/AutoSleep-level baseline, strain and detailed sleep analysis are not established by that formula.

**Work to deliver:** Build personalized longitudinal baselines, sleep/recovery/strain/stress views, trends, input coverage and transparent contribution explanations. Add sleep debt, workouts and journal correlations; map wearable-dependent features explicitly. Separate the LifeOS model from proprietary reference scores.

**Integration/dependencies:** HealthKit/wearable adapters, source de-duplication and longitudinal aggregates. WHOOP-specific acquisition requires supported device/service access; AutoSleep-style watch acquisition is a different path.

**Minimum acceptance scenario:** Missing HRV or a stale heart-rate sample suppresses/qualifies the score. New users have a calibration state. Same fixture gives the same result and removing a sample recomputes dependent charts.

**Public baseline references:** [Whoop](https://apps.apple.com/us/app/whoop/id933944389); [AutoSleep](https://apps.apple.com/us/app/autosleep-watch-sleep-tracker/id1164801111). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 🥗 Nutrition

### 13. Zerø — Jeûne intermittent

**Reference:** Zero. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** 16:8, 18:6, OMAD. **Original status claim:** ✅.

**Source evidence:** [`FastingView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/NutritionModule.swift:11) in `LifeOS/Modules/NutritionModule.swift`. Persisted fasting sessions, protocol targets and start/stop controls exist.

**Work to deliver:** Add edit/backfill, custom protocols, schedule reminders, history/streaks, progress charts, notes and goal integration. Cover the current reference's food/protein/hydration features through shared nutrition screens rather than duplicate stores.

**Integration/dependencies:** Durable timestamp-based sessions, nutrition links and shared reminder system; versioned goals.

**Minimum acceptance scenario:** Begin a fast before midnight, relaunch after the target, edit start/end and verify duration, streak and report. Prevent overlapping active fasts and duplicate completion events.

**Public baseline references:** [Zero](https://apps.apple.com/us/app/zero-fasting-food-tracker/id1168348542). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 14. Yumzio — Calories & macros

**Reference:** Yazio / MyFitnessPal. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Journal du jour, calories restantes, objectifs. **Original status claim:** ✅.

**Source evidence:** [`CalAIView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CalAIView.swift:6) in `LifeOS/Modules/CalAIView.swift`. The actual route uses CalAIView, with date selection, calorie/macro goals, meals/history, barcode addition and FoodEditor/OpenFoodFacts search. It is not just the older NutritionModule screen.

**Work to deliver:** Add recipes/custom foods, portions and units, saved meals/copy day, micronutrients, meal planning, weight/activity-adjusted goals and trends. Audit barcode/search coverage and nutrition provenance. Ensure coach/widget totals refresh after edits as well as insertions; current synchronization watches foods.count.

**Integration/dependencies:** Canonical FoodProduct, FoodEntry, Recipe and Goal services shared with #15–21/#64–65; robust nutrition provider/cache and HealthKit links.

**Minimum acceptance scenario:** Log a recipe, halve its portion, edit without changing row count and delete it. Calories/macros agree across diary, day ring, coach and widget; selecting a past day must not overwrite today's context.

**Public baseline references:** [Yazio](https://apps.apple.com/us/app/ai-calorie-tracker-by-yazio/id946099227); [MyFitnessPal](https://apps.apple.com/us/app/myfitnesspal-calorie-counter/id341232718). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 15. Cal Eye — Calories par photo

**Reference:** Cal AI. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Photo de l'assiette → aliments, grammes, calories. **Original status claim:** ✅ Sans clé : Vision sur l'iPhone + OpenFoodFacts, portion modifiable.

**Source evidence:** [`PhotoCalorieView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/PhotoCalorie.swift:85) in `LifeOS/Modules/PhotoCalorie.swift`. Vision-based food recognition plus OpenFoodFacts/macronutrient lookup and editable portions exists; this is an estimate pipeline, not measurement of food mass.

**Work to deliver:** Implement multi-item recognition, editable bounding/item suggestions, confidence/unknown states, portion correction, preparation/oil/sauce handling, rescan, meal confirmation and saved history. Connect corrected output to the shared diary exactly once. Benchmark common, mixed and unfamiliar dishes.

**Integration/dependencies:** Image/model provider with capabilities declared, nutrition source attribution, image lifecycle and a labeled evaluation dataset. Keep useful offline suggestions without implying provider-equivalent recognition accuracy.

**Minimum acceptance scenario:** Test a mixed plate, a non-food image and an unfamiliar dish. User correction updates nutrients proportionally; low-confidence detection asks for review and never silently invents precise grams.

**Public baseline references:** [Cal AI](https://apps.apple.com/us/app/cal-ai-calorie-tracker/id6480417616). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 16. Yuko — Scan code-barres santé

**Reference:** Yuka. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Note santé, prix, alternative. **Original status claim:** ✅ OpenFoodFacts gratuit.

**Source evidence:** [`ScanProductView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FoodSearch.swift:321) in `LifeOS/Modules/FoodSearch.swift`. Barcode/OpenFoodFacts product lookup exists. OpenFoodFacts nutrition grades are not proof of Yuka's food-and-cosmetic analysis or its alternative catalogue.

**Work to deliver:** Add food/cosmetic product types, ingredient detail, transparent scoring methodology, allergen links, scan history/favourites, search and evidence-backed alternatives. Display prices only with an actual location/store/date source. Missing product data must remain unknown.

**Integration/dependencies:** Food and cosmetic datasets, published LifeOS scoring rules, ingredient normalization, alternatives/category service and optional verified price feed.

**Minimum acceptance scenario:** Scan known, unknown and incomplete products. No fabricated score/price; alternatives share the relevant category and dietary constraints. Offline cached records visibly show their age.

**Public baseline references:** [Yuka](https://apps.apple.com/us/app/yuka-food-cosmetic-scanner/id1092799236). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 17. Fridgy — Mon frigo

**Reference:** Fridgely. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Inventaire et idées repas. **Original status claim:** ✅.

**Source evidence:** [`FridgeView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/NutritionModule.swift:215) in `LifeOS/Modules/NutritionModule.swift`. Local pantry items, string quantities, storage location, expiry and a small recipe engine exist.

**Work to deliver:** Build structured units/quantities, barcode/receipt capture, batches with separate expiry dates, consume/discard/transfer actions, alerts, multiple storage areas, shared household inventory and recipe matching. Keep an auditable stock history.

**Integration/dependencies:** Shared pantry domain with #18/#64/#65; household sync/roles, product lookup and unit conversion. Confirm Fridgely publisher: use original fridge-inventory product, not unrelated same-name AI app.

**Minimum acceptance scenario:** Add two milk batches, consume one partially, move the remainder and verify expiry warnings and recipe availability on a second device. Undo waste/consumption restores the correct batch.

**Public baseline references:** [Fridgely](https://www.fridgelyapp.com/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 18. Bringo — Liste de courses

**Reference:** Bring!. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Par rayon, cochable. **Original status claim:** ✅.

**Source evidence:** [`ShoppingListView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/NutritionModule.swift:337) in `LifeOS/Modules/NutritionModule.swift`. One local list with checkbox state and guessed aisles exists.

**Work to deliver:** Add multiple named/shared lists, real-time household edits, quantities/units, custom aisles, reorder, favourites, recipe-to-list additions, bought history and store grouping. Merge duplicate ingredients by compatible unit while preserving user intent.

**Integration/dependencies:** Household collaboration, offline change queue, canonical product/recipe links and stable list/member IDs.

**Minimum acceptance scenario:** Two people edit offline and reconnect without lost items. Recipe additions consolidate compatible quantities; checking purchased items updates pantry only through an explicit supported workflow.

**Public baseline references:** [Bring!](https://apps.apple.com/us/app/bring-grocery-shopping-list/id580669177). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 19. WaterMind — Hydratation

**Reference:** WaterMinder. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Suivi et rappels. **Original status claim:** ✅ Une prise d'eau peut enfin se retirer.

**Source evidence:** [`HydrationView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/NutritionModule.swift:407) in `LifeOS/Modules/NutritionModule.swift`. Water logging, deletion, goal, app-group publication and fixed daytime reminders exist.

**Work to deliver:** Add beverage types and serving presets, unit preferences, custom/goal-based reminder schedules, history/trends, configurable goals, widgets/shortcuts/watch support where targeted and HealthKit synchronization. Reconcile deletions and edits across all surfaces.

**Integration/dependencies:** Shared intake service and reminders; health write deduplication, local-day rules and widget intents.

**Minimum acceptance scenario:** Log 250 ml through a widget, edit to 300 ml, delete on another surface and verify all totals. Midnight/timezone changes and notification denial do not lose history or double-log water.

**Public baseline references:** [WaterMinder](https://apps.apple.com/us/app/water-tracker-by-waterminder/id653031147). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 20. SuppSafe — Compléments

**Reference:** Medisafe. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Rappels personnalisés. **Original status claim:** ✅ Rappels stables entre deux lancements.

**Source evidence:** [`SupplementsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/NutritionModule.swift:515) in `LifeOS/Modules/NutritionModule.swift`. Supplement records and stable reminder identifiers are implemented.

**Work to deliver:** Use the medication engine for dose events, taken/skipped history, schedule variations, stock/refills, start/end dates and adherence export, while keeping supplement-specific fields and grouping. Do not build a second inconsistent reminder system.

**Integration/dependencies:** Shared #1 Treatment/DoseEvent service and inventory; ingredient information from a real dataset if offered.

**Minimum acceptance scenario:** Edit a supplement name and dosing schedule, relaunch and delete; one reminder per intended dose, no old-name reminders, and historical taken events retain their identity.

**Public baseline references:** [Medisafe](https://apps.apple.com/us/app/medisafe-medication-management/id573916946). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 21. Figue — Allergènes & régimes

**Reference:** Fig. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Halal, vegan, sans gluten…. **Original status claim:** ✅.

**Source evidence:** [`DietProfileView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/NutritionModule.swift:677) in `LifeOS/Modules/NutritionModule.swift`. Dietary preferences and a simple ingredient-checking helper exist.

**Work to deliver:** Add detailed profiles and ingredient explanations, synonyms/derivatives, cross-contact and missing-label states, barcode/search integration, user overrides and supported restaurant/product discovery. Separate confirmed label evidence, inferred incompatibility and unknown. A substring miss must not mean safe.

**Integration/dependencies:** Versioned allergen/ingredient ontology, authoritative product labels and dietary rules; connect scan, recipes, pantry and shopping.

**Minimum acceptance scenario:** Test synonyms, compound ingredients, missing ingredients and explicit may-contain labels. Unknown products never receive an unconditional compatible badge; a profile change re-evaluates saved products.

**Public baseline references:** [Fig](https://apps.apple.com/us/app/fig-food-scanner-recipes/id1564434726). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 💪 Sport

### 22. Fitbot — Programme de sport

**Reference:** Fitbod. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Ta semaine + rappels muscu. **Original status claim:** ✅.

**Source evidence:** [`GymProgramView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/GymProgram.swift:12) in `LifeOS/Modules/GymProgram.swift`. Weekday programmes, reminders, templates, guided workouts and equipment substitutions exist. A keyword replacement helper is not adaptive training intelligence.

**Work to deliver:** Add exercise catalogue/demonstrations, experience/equipment/goals, progression based on completed sets, recovery/volume balancing, substitutions and editable generated sessions. Support warmups, rest, supersets and programme history; share sessions with #24.

**Integration/dependencies:** Structured exercise IDs, workout/set domain, progression engine and content library. AI suggestions must resolve to valid exercises and loads and remain editable.

**Minimum acceptance scenario:** Generate with restricted equipment, complete a workout and verify the next prescription changes from actual history. Excluded exercises never reappear; editing a plan preserves past workouts.

**Public baseline references:** [Fitbod](https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 23. Stepometer — Compteur de pas

**Reference:** Pedometer++. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Aujourd'hui + 7 jours (Apple Santé). **Original status claim:** ✅.

**Source evidence:** [`StepsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FitnessModule.swift:14) in `LifeOS/Modules/FitnessModule.swift`. Today's steps and a seven-day view use HealthService with a permission UI.

**Work to deliver:** Add distance/floors where available, goals, longer history/trends, achievements, walking sessions/routes, widgets and supported watch workflows. Distinguish live phone acquisition from imported health summaries.

**Integration/dependencies:** HealthKit/CoreMotion adapters and source rules; platform capability-aware desktop history.

**Minimum acceptance scenario:** Verify phone/watch overlap, denied permissions, timezone changes and a full day with zero activity. A desktop sees real synchronized history and never pretends its own step sensor exists.

**Public baseline references:** [Pedometer++](https://apps.apple.com/us/app/pedometer/id712286167). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 24. Hevvy — Muscu & progression

**Reference:** Strong / Hevy. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Charges, volume, 1RM, courbe. **Original status claim:** ✅.

**Source evidence:** [`StrengthView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FitnessModule.swift:82) in `LifeOS/Modules/FitnessModule.swift`. WorkoutSet entries, volume, estimated 1RM, charts and basic load progression exist; guided training is elsewhere.

**Work to deliver:** Add reusable routines, exercise library/custom exercises, full sessions, warmup/drop/superset types, rest timers, notes, personal records, history editing, body measurements and sharing/export. Include Hevy-style social workflows in a separate explicit backlog if pursuing the whole reference union.

**Integration/dependencies:** One workout schema with #22/#25/#26; community/sharing service for social features, units and evidence-based formula labels.

**Minimum acceptance scenario:** Complete a superset with a paused rest timer, edit a historical set and verify volume/PR recalculation. kg/lb conversion preserves underlying values; deletion doesn't leave phantom records.

**Public baseline references:** [Strong](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577); [Hevy](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 25. TabaTime — HIIT / Tabata

**Reference:** Tabata Timer. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Minuteur plein écran. **Original status claim:** ✅ Tient en arrière-plan, la séance part dans Apple Santé.

**Source evidence:** [`TabataView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/TabataView.swift:449) in `LifeOS/Modules/TabataView.swift`. The routed TabataView has a substantial interval engine, background catch-up logic, tests and HealthKit workout writing. Do not replace it with the weaker generic CountdownEngine.

**Work to deliver:** Verify and complete custom work/rest/prep/cooldown, rounds/sets, presets, sound/haptic/voice cues, pause/resume/skip, session history and accessible full-screen operation. Resolve the exact Tabata Timer publisher before declaring app parity.

**Integration/dependencies:** Existing Tabata engine plus persistent preset/session domain and health writer; desktop audio/keyboard controls.

**Minimum acceptance scenario:** Run multiple intervals while backgrounded, resume after several phase boundaries and verify correct phase and exactly one workout record. Test interrupted audio, zero rest and edited presets.

**Public baseline references:** [Tabata Timer](https://apps.apple.com/us/app/id664563975). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 26. GOMOB — Mobilité & stretching

**Reference:** GOWOD / Pliability. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Routines guidées. **Original status claim:** ✅.

**Source evidence:** [`MobilityRoutineView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FitnessModule.swift:270) in `LifeOS/Modules/FitnessModule.swift`. A small static routine library and guided countdown stretches exist.

**Work to deliver:** Add assessments, target-area recommendations, pre/post-workout routines, difficulty/duration filters, demonstrations, programme progression, completion history and reassessment trends. Include breathing/recovery content where the selected baseline includes it.

**Integration/dependencies:** Structured movement library, original/licensed video/audio and durable session timing; reuse fitness history.

**Minimum acceptance scenario:** Complete an assessment, follow a targeted routine, pause/relaunch and record completion once. Reassessment changes recommendations based on actual results; unavailable videos have usable text guidance.

**Public baseline references:** [GOWOD](https://apps.apple.com/us/app/gowod-mobility-stretching/id1227834875); [Pliability](https://apps.apple.com/us/app/pliability-stretch-mobility/id1175346453). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 27. Streakz — Streaks & habitudes

**Reference:** Streaks. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Régularité d'entraînement. **Original status claim:** ✅.

**Source evidence:** [`StreaksView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FitnessModule.swift:349) in `LifeOS/Modules/FitnessModule.swift`. The screen derives training streaks from workout dates. It is not the general-purpose Streaks product.

**Work to deliver:** Add positive/negative habits, count/duration targets, weekly frequencies, skip/pause/backfill, reminders, history/statistics and widgets, sharing the Habitly engine. Preserve a focused training view rather than maintaining separate completion semantics.

**Integration/dependencies:** Canonical habit schedule/completion engine with #41; HealthKit automatic goals only for available data.

**Minimum acceptance scenario:** A habit scheduled three days/week retains its streak over unscheduled days; skip and correction update reports consistently in both Streakz and Habitly.

**Public baseline references:** [Streaks](https://apps.apple.com/us/app/streaks/id963034692). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## ✨ Apparence

### 28. Umaxx — Analyse faciale

**Reference:** Umax. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Symétrie, tiers, ratios. **Original status claim:** ✅ Vision sur l'iPhone, gratuit.

**Source evidence:** [`FaceAnalysisView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FaceAnalysis.swift:142) in `LifeOS/Modules/FaceAnalysis.swift`. On-device Vision landmarks feed locally defined symmetry/proportion scores.

**Work to deliver:** Add consistent capture guidance, face/pose/lighting quality checks, retake/correction, clearly explained measurements, saved dated comparisons and user-controlled exports/deletion. Inventory the actual Umax plans/progress features separately. Do not present a homemade ratio score as the competitor's validated model.

**Integration/dependencies:** Vision capability checks, documented geometry algorithm, private attachment storage and versioned results. Keep recommendations separate from raw measurements.

**Minimum acceptance scenario:** Reject no-face/multiple-face/strongly rotated images; repeat a fixture deterministically and explain changes after algorithm updates. Deleting an analysis removes its images and derived data.

**Public baseline references:** [Umax](https://apps.apple.com/us/app/umax-become-hot/id6471026798). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 29. TrueSkin — Routine skincare

**Reference:** TroveSkin. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Matin et soir + rappels. **Original status claim:** ✅.

**Source evidence:** [`SkincareView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LooksModule.swift:11) in `LifeOS/Modules/LooksModule.swift`. AM/PM routine strings, daily completion flags, reminders and a rules-based setup exist.

**Work to deliver:** Build structured products/ingredients, routine steps/order, schedules, product usage/expiry, skin diary and consistent photo comparison, progress and possible trigger tracking. Product compatibility needs a sourced rule set. Exact current TroveSkin listing/publisher remains unresolved.

**Integration/dependencies:** Product catalogue, ingredient service, skin journal and photo store. Confirm official baseline before attributing obscure features to TroveSkin.

**Minimum acceptance scenario:** Edit a routine without erasing history, log a product reaction and compare dated photos. Unknown product composition stays unknown; archived products remain attached to old entries.

**Public baseline references:** TroveSkin — exact baseline unresolved. These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 30. Progrez — Photos avant / après

**Reference:** Progress. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Suivi visuel daté. **Original status claim:** ✅.

**Source evidence:** [`ProgressPhotoGalleryView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LooksModule.swift:320) in `LifeOS/Modules/LooksModule.swift`. Dated photo import, display and deletion exist.

**Work to deliver:** Add aligned side-by-side/slider comparison, body/measurement tags, progress timelines, pose guides, private albums, export and backup. Resolve which Progress app is intended; its generic name matches multiple products.

**Integration/dependencies:** Shared attachment/measurement domain, import metadata, secure thumbnails and explicit comparison dates.

**Minimum acceptance scenario:** Compare two selected dates, rotate/import a large image, export the comparison and delete the original. No orphan thumbnail; cancelled import adds nothing.

**Public baseline references:** Progress — exact baseline unresolved. These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 31. Mewing Klub — Mewing & posture

**Reference:** Mewing Club. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Rappels + minuteur. **Original status claim:** ✅.

**Source evidence:** [`MewingPostureView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LooksModule.swift:359) in `LifeOS/Modules/LooksModule.swift`. Posture/mewing reminder and timer functionality exists; verify the exact routed type if renamed.

**Work to deliver:** Build structured guided sessions, exercise instruction, progression/history, reminder schedule and completion analytics. Resolve Mewing Club's exact publisher and feature list before claiming parity; do not assume measurable facial change from completing a timer.

**Integration/dependencies:** Content programme and durable session engine; avoid auto-generated outcome guarantees in product copy.

**Minimum acceptance scenario:** A session can be paused, resumed, completed and revisited; editing reminders replaces old schedules. Progress means recorded practice, not a fabricated physical-change score.

**Public baseline references:** Mewing Club — exact baseline unresolved. These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 32. Wearing — Garde-robe & outfits

**Reference:** Whering / Acloset. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Tenue selon la météo. **Original status claim:** ✅.

**Source evidence:** [`WardrobeView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LooksModule.swift:401) in `LifeOS/Modules/LooksModule.swift`. Manual clothing category/colour/warmth/image entries and a warmth-based outfit selector exist. Weather is selected manually in the view.

**Work to deliver:** Add background removal, wardrobe search/tags, outfits and calendar, wear history/cost per wear, packing/capsule collections, actual weather/location integration and editable recommendations. Include inspiration/sharing features as explicit service work.

**Integration/dependencies:** Image segmentation, weather adapter, outfit graph and trip linkage; shared/private wardrobe data ownership.

**Minimum acceptance scenario:** Import a garment, build an outfit, schedule and log wearing it, then generate a travel packing list. Weather failure shows manual selection instead of made-up conditions.

**Public baseline references:** [Whering](https://apps.apple.com/us/app/whering-your-digital-closet/id1519461680); [Acloset](https://apps.apple.com/us/app/acloset-ai-fashion-assistant/id1542311809). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 🧠 Mental

### 33. Breathwerk — Respiration & cohérence

**Reference:** Breathwrk. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Box breathing, 365…. **Original status claim:** ✅.

**Source evidence:** [`BreathingView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MindModule.swift:11) in `LifeOS/Modules/MindModule.swift`. Three animated breath patterns are implemented.

**Work to deliver:** Add a searchable exercise programme library, configurable phases/rounds, narrated/audio/haptic guidance, session history, reminders, favourites and progress. Respect reduce-motion settings while preserving phase cues.

**Integration/dependencies:** Shared session/audio/reminder engines and sourced/original instructional content.

**Minimum acceptance scenario:** Complete 4-7-8 and box sessions with VoiceOver and reduced motion; pause/resume does not skip phases, and one completion updates history exactly once.

**Public baseline references:** [Breathwrk](https://apps.apple.com/us/app/breathwrk-breathing-exercises/id1481804500). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 34. Headplace — Méditation

**Reference:** Headspace / Calm. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Minuteur guidé. **Original status claim:** ✅.

**Source evidence:** [`MeditationView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MindModule.swift:89) in `LifeOS/Modules/MindModule.swift`. The routed view is a duration selector and timer. It has no equivalent Headspace/Calm course catalogue.

**Work to deliver:** Build guided programmes, sleep stories, music, topic/level/duration search, narrator/language metadata, favourites, downloads, playback resume, daily recommendations and progress. Catalogue availability is a product dependency, not a UI TODO.

**Integration/dependencies:** Original/licensed audio/video and editorial pipeline; media CDN/download management, now-playing and background audio; shared session history.

**Minimum acceptance scenario:** Download a guided lesson, play offline/locked, interrupt with a call and resume at the same point. Completion/progress persists across phone and desktop; unavailable content is not replaced with a silent timer.

**Public baseline references:** [Headspace](https://apps.apple.com/us/app/headspace-sleep-meditation/id493145008); [Calm](https://apps.apple.com/us/app/calm/id571800810). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 35. Endlo — Sons relaxants

**Reference:** Endel. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Bruit blanc, rose, brun + minuteur. **Original status claim:** ✅.

**Source evidence:** [`SoundscapeView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/Soundscape.swift:142) in `LifeOS/Modules/Soundscape.swift`. White/pink/brown/ocean audio synthesis exists. onDisappear stops playback and cancels its timer.

**Work to deliver:** Build persistent background playback, mode-specific mixes, levels/fades, session scheduling, offline presets and optional adaptive inputs such as time/activity. Add now-playing controls and consistent audio interruption handling.

**Integration/dependencies:** Long-lived audio service outside view lifecycle, original sound assets/DSP and explicit contextual input permissions. Don't claim Endel's proprietary generation engine.

**Minimum acceptance scenario:** Start a focus sound, navigate to tasks and lock the phone; audio continues as intended. Stop from lock-screen controls, detach headphones and reopen without a duplicated engine.

**Public baseline references:** [Endel](https://apps.apple.com/us/app/endel-focus-sleep-sounds/id1346247457). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 36. Daylia — Humeur & gratitude

**Reference:** Daylio. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Journal quotidien. **Original status claim:** ✅.

**Source evidence:** [`MoodJournalView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MindModule.swift:120) in `LifeOS/Modules/MindModule.swift`. Mood score, note, gratitude, history and average exist.

**Work to deliver:** Add custom moods/activities, multiple daily entries, tags/photos, reminders, calendar/year views, filters, activity correlations, goals and export/backup. Historical edits must update analytics.

**Integration/dependencies:** Journal domain, attachments, timezone-aware aggregation and user-controlled sharing.

**Minimum acceptance scenario:** Backfill two moods on one day with activities, filter by activity, export and delete one. Counts and correlations update correctly without implying causation from sparse data.

**Public baseline references:** [Daylio](https://apps.apple.com/us/app/daylio-journal-mood-tracker/id1194023242). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 37. Opale — Détox écran

**Reference:** Opal / one sec. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Usage et objectifs. **Original status claim:** ⛔ Blocage des apps interdit sans autorisation Apple spéciale.

**Source evidence:** [`ScreenDetoxView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MindModule.swift:199) in `LifeOS/Modules/MindModule.swift`. Screen usage is manually incremented/decremented in AppStorage. No FamilyControls implementation was found in this module or current entitlements.

**Work to deliver:** Implement actual app/category selection, authorized usage reports, scheduled/focus blocking, limits, intervention/breathing delays, session analytics and controlled overrides. Replace manual counts with explicit manual mode until real reports are available.

**Integration/dependencies:** FamilyControls/DeviceActivity/ManagedSettings with distribution entitlement and extensions where supported; separate desktop capability plan. Apple authorization is an implementation dependency, not a blanket impossibility.

**Minimum acceptance scenario:** On an authorized physical device block chosen apps during a session, test expiry and revoke permission. Device restart/timezone changes do not strand a shield. Reports never label manually entered minutes as measured.

**Public baseline references:** [Opal](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230); [one sec](https://apps.apple.com/us/app/one-sec-screen-time-focus/id1532875441). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 38. Fabuleux — Briefing du matin

**Reference:** Fabulous. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Motivation + ta journée. **Original status claim:** ✅.

**Source evidence:** [`MorningBriefingView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MindModule.swift:250) in `LifeOS/Modules/MindModule.swift`. Static rotating quotes and today's tasks/events are present; DailyBriefingView elsewhere offers a richer wake-up flow.

**Work to deliver:** Unify the two briefing paths; add structured routines, onboarding/journeys, habit stacking, coached programmes, reflection and progress. Generate today's briefing from real shared records, with editable preferences and reliable audio.

**Integration/dependencies:** Routine/habit domain, curated coaching content, shared day-context service and optional AI; no duplicate independent morning state.

**Minimum acceptance scenario:** Change a task and sleep check-in, then open both briefing entry points. They agree on date/context; offline operation still offers a coherent routine and never invents appointments.

**Public baseline references:** [Fabulous](https://apps.apple.com/us/app/fabulous-daily-habit-tracker/id1203637303). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## ✅ Productivité

### 39. Todoo — To-do intelligente

**Reference:** Todoist / Things. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Priorités, projets, échéances. **Original status claim:** ✅.

**Source evidence:** [`TodoView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/ProductivityModule.swift:13) in `LifeOS/Modules/ProductivityModule.swift`. Tasks, priority, project strings, due dates, simple recurrence and one-way calendar creation exist; verify the routed name in CategoryHub.

**Work to deliver:** Add nested projects/sections, subtasks/checklists, tags/filters/search, inbox/today/upcoming, natural-language capture, robust recurrence, reminders, dependencies and collaboration where required by the Todoist/Things union. Audit same-priority due-date sorting and calendar duplicates.

**Integration/dependencies:** Task/project domain with stable IDs, recurring occurrence model, shared reminder/calendar and collaboration services.

**Minimum acceptance scenario:** Complete a recurring task late across DST, undo it, move projects and export twice to calendar. Exactly one intended next occurrence and one linked event; upcoming tasks sort chronologically.

**Public baseline references:** [Todoist](https://apps.apple.com/us/app/todoist-to-do-list-calendar/id572688855); [Things](https://apps.apple.com/us/app/things-3/id904237743). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 40. Structurd — Time-blocking auto

**Reference:** Structured. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** L'app remplit ta journée. **Original status claim:** ✅.

**Source evidence:** [`TimeBlockView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/ProductivityModule.swift:217) in `LifeOS/Modules/ProductivityModule.swift`. Auto-planning currently allocates successive one-hour slots within day bounds and persists block times.

**Work to deliver:** Add estimated duration, deadlines/priorities, calendar busy-time import, breaks/travel buffers, drag/drop timeline, split tasks, rescheduling, recurring tasks and explicit unscheduled overflow. Show plan previews and avoid overwriting user-locked blocks.

**Integration/dependencies:** Shared task/calendar domain, deterministic scheduling engine and EventKit reconciliation; desktop keyboard/drag controls.

**Minimum acceptance scenario:** With a 30-minute task, 90-minute task and a fixed meeting, produce no overlaps, respect working hours and explain anything unscheduled. Moving a meeting updates only affected unlocked blocks.

**Public baseline references:** [Structured](https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 41. Habitly — Habit tracker

**Reference:** Habitify. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Séries et régularité. **Original status claim:** ✅.

**Source evidence:** [`HabitTrackerView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/ProductivityModule.swift:359) in `LifeOS/Modules/ProductivityModule.swift`. CRUD, active/pending/archive flows, schedules, completions and widget integration exist.

**Work to deliver:** Add quantity/duration targets, flexible frequencies, skips/pauses, habit areas, streak/calendar analytics, reminders, HealthKit automatic completion and backup/sync. Audit widget average-streak calculation: completion count is not a streak.

**Integration/dependencies:** Shared habit engine with #27/#38, occurrence IDs and domain events for widgets/coach.

**Minimum acceptance scenario:** Test a twice-weekly habit, retroactive correction and archived habit with past history. App/widget/coach report the same streak and today's due set; no accidental completions on unscheduled dates.

**Public baseline references:** [Habitify](https://apps.apple.com/us/app/habitify-habit-tracker/id1111447047). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 42. Forêt — Focus / Pomodoro

**Reference:** Forest. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** 25 min de concentration. **Original status claim:** 🟡 Minuteur OK, blocage des apps bloqué par Apple.

**Source evidence:** [`FocusTimerView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/ProductivityModule.swift:756) in `LifeOS/Modules/ProductivityModule.swift`. Focus/break countdown exists; no Forest-style growth system or app blocking is established.

**Work to deliver:** Add durable focus/break sessions, configurable cycles, interruption rules, tags/history, visual growth/collection rewards and statistics. Implement supported distraction blocking via #37; multiplayer/real-tree programmes need separate services if retained in full parity scope.

**Integration/dependencies:** Shared timer and blocking adapter, gamification domain, optional community/partner service. A Pomodoro timer alone is not Forest parity.

**Minimum acceptance scenario:** Background a session, interrupt it and complete another. Rewards follow the documented policy and cannot be duplicated by relaunch; blocked-app behavior respects user authorization.

**Public baseline references:** [Forest](https://apps.apple.com/us/app/forest-focus-for-productivity/id866450515). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 43. Notio — Notes & second cerveau

**Reference:** Notion / Bear. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Capture rapide + tags. **Original status claim:** ✅.

**Source evidence:** [`NotesView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/ProductivityModule.swift:802) in `LifeOS/Modules/ProductivityModule.swift`. Title/body/tag notes and search exist. This is a useful local notebook, not Notion/Bear parity.

**Work to deliver:** Add rich/Markdown editing, attachments, nested organization, backlinks, full-text search, export formats and version recovery. Full Notion scope additionally includes typed databases/views, relations/formulas, templates, collaborative pages/permissions and task links. Maintain an explicit backlog for each rather than relabelling plain text as a second brain.

**Integration/dependencies:** Document/block model, attachment index, search, sync/version conflicts, collaboration backend and import/export formats.

**Minimum acceptance scenario:** Create linked notes and a database with two views, attach a PDF, edit offline on two devices and resolve conflicts. Export/reimport preserves structure and attachments; keyboard editing works on desktop.

**Public baseline references:** [Notion](https://apps.apple.com/us/app/notion-notes-tasks-ai/id1232780281); [Bear](https://apps.apple.com/us/app/bear-markdown-notes/id1016366447). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 💶 Argent

### 44. Bankino — Comptes & dépenses

**Reference:** Bankin. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Solde, transactions, alertes. **Original status claim:** 🟡 Saisie manuelle.

**Source evidence:** [`AccountsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FinanceModule.swift:12) in `LifeOS/Modules/FinanceModule.swift`. Manual accounts/transactions and basic alerts exist. Inserting a transaction mutates account balance, while deletion only deletes the transaction: balances can drift.

**Work to deliver:** Fix ledger invariants first. Add transaction editing/reversal, account IDs rather than names, transfers, reconciliation, categories/rules, recurring payments, imports, search/history and real bank connection. Never infer connection from local accounts.

**Integration/dependencies:** Canonical money/ledger service with Decimal/minor units and currency; authorized aggregation provider, consent/webhooks and deduplication shared with #45–53/#76.

**Minimum acceptance scenario:** Account opens at 100; add −20, edit to −30, delete: balances 80,70,100. Same imported transaction delivered twice is counted once; renaming an account preserves all links.

**Public baseline references:** [Bankin](https://apps.apple.com/fr/app/id447040033). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 45. Ynabi — Budget par enveloppes

**Reference:** YNAB. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Catégorise et plafonne. **Original status claim:** ✅ Remise à zéro chaque mois.

**Source evidence:** [`BudgetView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FinanceModule.swift:137) in `LifeOS/Modules/FinanceModule.swift`. Envelope limits and manually tracked spending with monthly rollover exist. Resetting a number monthly is not a full YNAB budget ledger.

**Work to deliver:** Implement funded assignments, available balances, transactions linked to categories, rollover/overspending handling, targets, credit-card/debt behavior, future months, reconciliation and reports. Preserve previous months and every transfer/reallocation.

**Integration/dependencies:** Shared #44 ledger and budget periods; category assignment history, currencies and household sharing.

**Minimum acceptance scenario:** Budget 100, spend 30, move 20 to another category and roll over with the selected policy. Earlier reports remain unchanged; refunds and transfer transactions don't inflate income/spending.

**Public baseline references:** [YNAB](https://apps.apple.com/us/app/ynab/id1010865877). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 46. Pocket Money — Abonnements

**Reference:** Rocket Money. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Abonnements oubliés + résiliation. **Original status claim:** 🟡 Pas de détection auto (demande la banque).

**Source evidence:** [`SubscriptionsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FinanceModule.swift:224) in `LifeOS/Modules/FinanceModule.swift`. Manual subscriptions/costs/renewal dates exist; forgotten status uses age heuristics. Cancellation opens a search URL, not a completed cancellation.

**Work to deliver:** Detect recurring merchants from connected/imported transactions, support trials/price changes, reminders, forecast and actual charge history. Track cancellation request/evidence/status. Full Rocket Money scope also includes budgeting and assisted bill/cancellation services through real providers.

**Integration/dependencies:** Bank transaction stream, recurring-series detector and optional cancellation/negotiation operations. Never present a web search as a service completion.

**Minimum acceptance scenario:** Detect a monthly series and annual renewal, reject a coincidental one-off, notify a price increase and record confirmed cancellation. Bank disconnect shows stale detection data explicitly.

**Public baseline references:** [Rocket Money](https://apps.apple.com/us/app/rocket-money-bills-budgets/id1130616675). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 47. Quadricount — Split entre potes

**Reference:** Tricount. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Qui doit quoi à qui. **Original status claim:** ✅.

**Source evidence:** [`SplitView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FinanceModule.swift:311) in `LifeOS/Modules/FinanceModule.swift`. One string-based group, equal expense splits and balance hints exist. The settlement hint can allocate an entire debtor balance to one creditor even when that creditor is owed less.

**Work to deliver:** Add stable groups/members, exact-cent accounting, unequal shares/percentages, multi-currency expenses, reimbursements, receipt attachments, complete settlement algorithm and collaborative edits/history.

**Integration/dependencies:** Shared finance primitives and group sync; settlement records distinct from expenses. Fix largest-debtor/creditor overpayment and truncation of cents.

**Minimum acceptance scenario:** For balances −100,+60,+40, suggest payments 60 and 40, never 100 to the first creditor. Test €10/3 rounding, partial repayments and a deleted shared expense on two devices.

**Public baseline references:** [Tricount](https://apps.apple.com/us/app/tricount-split-settle-bills/id349866256). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 48. Kapital — Objectifs d'épargne

**Reference:** Qapital. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Projection du temps restant. **Original status claim:** ✅.

**Source evidence:** [`SavingsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FinanceModule.swift:410) in `LifeOS/Modules/FinanceModule.swift`. Manual goal amount, current savings, monthly contribution and time projection exist.

**Work to deliver:** Add linked funding accounts, contribution/withdrawal history, scheduled/rule-based savings, shared goals and forecast scenarios. Automated deposits require actual payment/account service integration; a UI increment is not a transfer.

**Integration/dependencies:** Ledger/goal service, savings-rule evaluator and authorized money-movement provider if full Qapital behavior is retained.

**Minimum acceptance scenario:** A simulated rule produces a preview, a confirmed provider transfer updates the goal once, and a failed transfer leaves balance unchanged. Manual mode is clearly distinct.

**Public baseline references:** [Qapital](https://www.qapital.com/saving/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 49. Linxa — Solde global

**Reference:** Linxo. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Tous les comptes agrégés. **Original status claim:** ⛔ Demande un agrément bancaire (DSP2).

**Source evidence:** [`BankOverviewView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/FinanceModule.swift:474) in `LifeOS/Modules/FinanceModule.swift`. Aggregates the same local manual accounts; there is no real bank aggregation in this routed screen.

**Work to deliver:** Implement institution connection, consent lifecycle, initial/history sync, transaction deduplication, pending-to-booked reconciliation, balance freshness, reauthentication, connection health and deletion. Reuse this connection layer across finance modules.

**Integration/dependencies:** Commercial/authorized bank-data provider such as Powens with credentials and supported institutions. Evaluate requirements with the provider; don't mark the entire feature impossible because direct regulated access would be complex.

**Minimum acceptance scenario:** Connect a sandbox bank, sync twice, expire/regrant consent and verify no duplicate transactions. Partial provider failure preserves good accounts and shows exactly which balance is stale.

**Public baseline references:** [Linxo](https://apps.apple.com/fr/app/linxo-lapp-n-1-de-budget/id440509306). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 📈 Investissement

### 50. Finario — Portefeuille

**Reference:** Finary. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Actions + crypto. **Original status claim:** ✅ Cours en direct (CoinGecko, Yahoo), en euros.

**Source evidence:** [`PortfolioView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/InvestModule.swift:12) in `LifeOS/Modules/InvestModule.swift`. Manual holdings plus CoinGecko/Yahoo price retrieval, conversion and some freshness/error handling exist.

**Work to deliver:** Add transaction lots, purchases/sales/dividends/fees, realized/unrealized returns, allocation, benchmarks, historical value, multiple asset classes and broker imports/connections. Audit source permissions, rate limits and market availability; latest price is not a performance history.

**Integration/dependencies:** Shared asset/ledger/FX providers, quote cache with timestamps and portfolio analytics; no implicit reliability promise for undocumented endpoints.

**Minimum acceptance scenario:** Buy, partially sell, receive a dividend and change currency. Returns reconcile to cashflows and fees; a failed quote retains a timestamped last value, not zero.

**Public baseline references:** [Finary](https://apps.apple.com/fr/app/finary-patrimoine-budget/id1569413444). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 51. Kubero — Net worth & FIRE

**Reference:** Kubera. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Patrimoine + projection. **Original status claim:** ✅.

**Source evidence:** [`NetWorthView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/InvestModule.swift:180) in `LifeOS/Modules/InvestModule.swift`. Manual assets/liabilities and holdings feed a net-worth view; FIRE assumes a fixed return projection.

**Work to deliver:** Unify accounts, investments, properties and liabilities without double counting; add historical snapshots, currencies, debt amortization and editable scenarios. Full Kubera scope includes broader aggregation, sharing/access and continuity features that need explicit implementation.

**Integration/dependencies:** Canonical asset ownership graph, valuation dates, FX history, shared connection layer and access controls.

**Minimum acceptance scenario:** Link an already-tracked account and property without counting either twice. A loan payment changes cash and liability consistently. Scenario assumptions are editable and projections are labeled projections.

**Public baseline references:** [Kubera](https://www.kubera.com/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 52. Horizo — Immobilier

**Reference:** Horiz.io. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Biens, loyers, cashflow. **Original status claim:** ✅ Colle une annonce, la fiche se remplit (clé coach).

**Source evidence:** [`RealEstateView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/InvestModule.swift:279) in `LifeOS/Modules/InvestModule.swift`. Manual property value/rent/charges/loan/payment and an AI-assisted pasted-listing parser exist.

**Work to deliver:** Add acquisition costs, financing/amortization, vacancy, repairs, taxes, cashflow/yield scenarios, comparable assumptions, tenancy/lease records, rent collection status, receipts and maintenance documents. Separate copied listing extraction from an actual authenticated listing feed.

**Integration/dependencies:** Property/lease/cashflow domain, versioned tax assumptions, parser validation and document service; provider agreement if automatic listing ingestion is required.

**Minimum acceptance scenario:** Import a listing with missing rent, correct it and compare financed/unfinanced scenarios. Missing numbers remain blank; annual cashflow reconciles to monthly entries and generated receipts.

**Public baseline references:** [Horiz.io](https://support.horiz.io/hc/fr/articles/360019832180-Comprendre-les-principales-fonctionnalit%C3%A9s-de-l-interface-de-Gestion-Locative). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 53. Impôts+ — Simulateur fiscalité

**Reference:** Simulateur impots.gouv. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Impôt sur le revenu. **Original status claim:** ✅ Barème 2026, plafond du quotient familial, décote.

**Source evidence:** [`TaxSimulatorView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/InvestModule.swift:469) in `LifeOS/Modules/InvestModule.swift`. FrenchTax has bracket, family-quotient cap and décote logic with tests. Inputs are much narrower than the full official income-tax simulator.

**Work to deliver:** Implement versioned tax-year forms and supported household cases, income classes, allowances/expenses, rental/capital income, deductions/credits, special cases and result breakdown/export. Explicitly distinguish simplified supported cases from full simulator parity.

**Integration/dependencies:** Official annual simulator/reference rules and golden fixtures, including rounding and household exceptions. Do not silently reuse one year's constants for the next.

**Minimum acceptance scenario:** Compare supported fixtures against the official 2026-on-2025 simulator at thresholds and family cases. Unsupported fields must be identified, not ignored while presenting a complete tax estimate.

**Public baseline references:** [Simulateur impots.gouv](https://simulateur-ir-ifi.impots.gouv.fr/calcul_impot/2026/complet/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 💼 Carrière

### 54. Huntly — Suivi des candidatures

**Reference:** Huntr. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Pipeline par statut. **Original status claim:** ✅.

**Source evidence:** [`ApplicationsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CareerModule.swift:11) in `LifeOS/Modules/CareerModule.swift`. Local company/role/link/notes/status tracking exists.

**Work to deliver:** Add board/list views, job description snapshots, contacts, application dates/deadlines, tasks/reminders, attached resume variants, interviews and outcome analytics. Add browser/share-sheet capture and deduplication; preserve deleted listing details.

**Integration/dependencies:** Career job/application domain linked to #55/#57/#58, attachments, calendar and import adapters.

**Minimum acceptance scenario:** Capture the same job twice, move it through interview stages and link a resume. One application remains; stage history and next follow-up survive relaunch and export.

**Public baseline references:** [Huntr](https://apps.apple.com/us/app/huntr-job-search-browser/id1372389812). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 55. Zetty — Générateur de CV

**Reference:** Zety / Canva. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Remplis → exporte, adapté à une offre. **Original status claim:** ✅.

**Source evidence:** [`CVBuilderView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CareerModule.swift:85) in `LifeOS/Modules/CareerModule.swift`. Form-based CV text generation and ShareLink text export exist; an AI optimizer can adapt wording.

**Work to deliver:** Build multiple resumes, structured sections/reorder, real page preview, templates, PDF/DOCX exports, import, versions, cover letters and job-specific tailoring with user review. Canva's wider design suite is a separate large scope: explicitly inventory editor/assets/collaboration beyond CVs rather than claiming Canva parity from resume templates.

**Integration/dependencies:** Document layout/rendering engine, fonts/assets, attachment/version store and AI provider. Never invent qualifications while tailoring.

**Minimum acceptance scenario:** Export a two-page French CV with accents and long entries to PDF/DOCX, reopen it and inspect pagination/text selection. Save an offer-specific variant without overwriting the master.

**Public baseline references:** [Zety](https://zety.com/about); [Canva](https://www.canva.com/create/resumes/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 56. LinkedUp — Compétences manquantes

**Reference:** LinkedIn Learning. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Écart + plan pour combler. **Original status claim:** ✅.

**Source evidence:** [`SkillGapView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CareerModule.swift:248) in `LifeOS/Modules/CareerModule.swift`. Manually entered skill gaps and plans exist. No LinkedIn Learning-equivalent course catalogue is present.

**Work to deliver:** Add role/skill assessment, searchable courses/learning paths, lessons/media playback, quizzes/practice, notes, progress and completion credentials. Connect a job's skill gaps to actual available lessons. Distinguish LifeOS completion records from third-party certificates.

**Integration/dependencies:** Original/licensed course content or a provider integration with verified access; media downloads, learning records and assessment engine.

**Minimum acceptance scenario:** Choose a missing skill, enroll in a real course, complete/resume a lesson offline and record an assessment. A link to a course is not shown as completion or a certificate.

**Public baseline references:** [LinkedIn Learning](https://apps.apple.com/us/app/linkedin-learning/id1084807225). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 57. Yoodly — Mock interview

**Reference:** Yoodli. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Questions + retour sur ta réponse. **Original status claim:** 🟡 Le retour demande une clé coach.

**Source evidence:** [`MockInterviewView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CareerModule.swift:327) in `LifeOS/Modules/CareerModule.swift`. Fixed questions/tips and provider-backed critique of typed answers exist.

**Work to deliver:** Add role/company/scenario configuration, follow-up conversations, recording/transcription, playback, delivery metrics, structured rubrics, practice history and improvement comparisons. Retain text-only mode without pretending it measures speech delivery.

**Integration/dependencies:** Speech/audio and AI providers with capability checks; recording retention and rubric versioning. Yoodli-style delivery metrics must come from actual audio/transcript data.

**Minimum acceptance scenario:** Record an answer with a pause, inspect aligned transcript/feedback, retry and compare. Provider failure retains the draft; no invented pace/filler measurements for typed answers.

**Public baseline references:** [Yoodli](https://support.yoodli.ai/en/articles/9550461-yoodli-overview). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 58. Welcome to the Djob — Matching d'offres

**Reference:** Welcome to the Jungle. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Offres réelles selon tes compétences. **Original status claim:** ✅ Flux public gratuit (Arbeitnow).

**Source evidence:** [`JobMatchView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/CareerModule.swift:527) in `LifeOS/Modules/CareerModule.swift`. Arbeitnow jobs and keyword-based skill matching with application tracking exist.

**Work to deliver:** Add location/remote/type/salary/company filters, relevance explanations, saved searches/alerts, deduplication, pagination, expired-job handling, company profiles and application handoff/status. A different public feed is not Welcome to the Jungle catalogue parity.

**Integration/dependencies:** Supported job-data provider/partner access or an independent employer catalogue; normalized jobs and #54 integration.

**Minimum acceptance scenario:** Search with two filters, save and apply to a result, then expire it at the provider. Saved history remains while the listing is visibly closed; matching never claims skills absent from the user's profile.

**Public baseline references:** [Welcome to the Jungle](https://help.welcometothejungle.com/en/filter-your-job-search-on-welcome-to-the-jungle). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 📚 Apprentissage

### 59. Trilingo — Langues

**Reference:** Duolingo. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Vocabulaire en répétition espacée. **Original status claim:** ✅.

**Source evidence:** [`LanguagesView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/Languages.swift:46) in `LifeOS/Modules/Languages.swift`. Static vocabulary packs, spaced-review intervals, scores and streaks exist.

**Work to deliver:** Build level placement, structured courses, vocabulary plus grammar, listening/reading/writing/speaking exercises, pronunciation feedback, adaptive practice, checkpoints and progress. Explicitly inventory the reference's non-language subjects and social/game systems if 'all Duolingo features' remains literal.

**Integration/dependencies:** Curriculum and exercise-authoring pipeline, language audio/TTS/STT, assessment/scheduling engine and content QA; shared flashcards as a component, not the whole course.

**Minimum acceptance scenario:** Complete a lesson containing all four language skills, make mistakes and receive targeted review. Resume on desktop at the same checkpoint; passing depends on answers, not opening the screen.

**Public baseline references:** [Duolingo](https://apps.apple.com/us/app/duolingo-language-lessons/id570060128). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 60. Anko — Flashcards

**Reference:** Anki. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Répétition espacée SM-2. **Original status claim:** ✅.

**Source evidence:** [`FlashcardsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LearningModule.swift:11) in `LifeOS/Modules/LearningModule.swift`. Text decks and SM-2 review scheduling exist.

**Work to deliver:** Add note/card types, cloze/reversed cards, images/audio, tags/search, deck hierarchy, import/export, scheduling controls, suspend/bury/undo, statistics and sync. Evaluate modern Anki scheduling compatibility and record exact supported formats rather than claiming full .apkg fidelity untested.

**Integration/dependencies:** Card/note/media schema, review event log and deterministic scheduler with migration policy.

**Minimum acceptance scenario:** Import a deck with media/cloze, review offline, undo, change timezone and sync. Due dates and intervals remain deterministic; export/reimport retains card types, media and review history.

**Public baseline references:** [Anki](https://apps.ankiweb.net/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 61. Headwave — Micro-learning du jour

**Reference:** Headway. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Une pépite par jour. **Original status claim:** ✅.

**Source evidence:** [`MicroLearningView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LearningModule.swift:141) in `LifeOS/Modules/LearningModule.swift`. A small static rotating fact collection provides daily content.

**Work to deliver:** Build a genuine searchable micro-learning catalogue, structured programmes, read/listen modes, saved highlights, quizzes/recaps, spaced practice, recommendations and downloads. Content depth and editorial quality are required, not only an endless generated quote feed.

**Integration/dependencies:** Original/licensed editorial content, audio production and shared learning/content services; connect #62/#63 without duplicate progress.

**Minimum acceptance scenario:** Read/listen to a complete lesson, save an excerpt, answer a quiz and revisit it offline. Progress records the actual lesson version; corrections propagate without losing notes.

**Public baseline references:** [Headway](https://makeheadway.com/faq/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 62. Blinklist — Résumés de livres

**Reference:** Blinkist. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Tes idées clés. **Original status claim:** ✅ Tes notes, pas de catalogue.

**Source evidence:** [`BookSummariesView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LearningModule.swift:173) in `LifeOS/Modules/LearningModule.swift`. User-entered book notes/ratings and an AI title/author summary helper exist. There is no curated Blinkist-equivalent library.

**Work to deliver:** Add sourced book metadata, substantive edited summaries/audio, chapter/key-idea navigation, discovery, collections, highlights, downloads and personal-content summarization where supported. An ungrounded generated summary must not impersonate a verified book synopsis.

**Integration/dependencies:** Original/licensed summary catalogue, grounding inputs, audio/CDN and editorial review; user notes remain distinct from catalogue content.

**Minimum acceptance scenario:** Find a book, read/listen offline, highlight and resume on desktop. An unknown title offers an honest unavailable state; generated output identifies its source material and cannot invent quotations.

**Public baseline references:** [Blinkist](https://www.blinkist.com/learn/what-is-blinkist). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 63. Coursia — Plan de montée en compétence

**Reference:** Coursera. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Compétence → jalons. **Original status claim:** ✅.

**Source evidence:** [`SkillPlanView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/LearningModule.swift:322) in `LifeOS/Modules/LearningModule.swift`. One AppStorage skill plan with text milestones/checkmarks exists.

**Work to deliver:** Build multiple programmes, course/module/lesson hierarchy, enrollment, media playback, assessments/projects, deadlines, progress, discussion/feedback and credential verification. Coursera degree/professional programme services are not reproduced by a checklist; keep their delivery/partner dependencies explicit.

**Integration/dependencies:** Learning-management backend, content authoring/licensing, assessment/grading, user roles and certification authority where applicable.

**Minimum acceptance scenario:** Enroll in a course, resume a lesson, submit a project, receive recorded feedback and finish all required assessments. A credential is issued only by its actual issuer and verified criteria.

**Public baseline references:** [Coursera](https://apps.apple.com/us/app/coursera-grow-your-career/id736535961). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 🏠 Maison

### 64. NoGaspi — Anti-gaspi & péremption

**Reference:** NoWaste. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Ce qui périme bientôt. **Original status claim:** ✅.

**Source evidence:** [`AntiWasteView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/HomeModule.swift:11) in `LifeOS/Modules/HomeModule.swift`. A view filters PantryItem records by approaching expiry.

**Work to deliver:** Complete waste/consumption ledger, inventory entry/scanning, storage/batch management, reminders, waste/cost analytics and household sync by extending #17's canonical pantry. Avoid a second independent fridge database.

**Integration/dependencies:** Shared pantry, shopping and recipe engines; receipt/barcode import and expiry notification scheduling.

**Minimum acceptance scenario:** Consume, discard and correct a batch from either entry point; both modules and shopping quantities update. Waste reports distinguish consumed food from discarded stock.

**Public baseline references:** [NoWaste](https://apps.apple.com/us/app/nowaste-food-inventory-list/id926211004). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 65. SuperCuisto — Recettes avec les restes

**Reference:** SuperCook. **Progress:** Partial foundation; content/product-depth gap.

**Original table scope:** Cuisine ce que tu as. **Original status claim:** ✅.

**Source evidence:** [`LeftoverRecipesView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/HomeModule.swift:41) in `LifeOS/Modules/HomeModule.swift`. Uses the same small static RecipeEngine as FridgeView.

**Work to deliver:** Provide a substantial ingredient-indexed recipe catalogue, missing-ingredient logic, diet/allergen/time/skill filters, substitutions, serving scaling, instructions, favourites and meal-plan/shopping integration. Verify source links and recipe quality.

**Integration/dependencies:** Original/licensed/search-provider recipe data, normalized ingredient quantities and dietary rules shared with #21.

**Minimum acceptance scenario:** Given eggs/rice and a nut allergy, show genuinely feasible recipes, disclose missing items, scale servings and add only missing compatible ingredients to the shopping list.

**Public baseline references:** [SuperCook](https://www.supercook.com/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 66. Sweepo — Tâches ménagères

**Reference:** Sweepy. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Réparties couple / coloc. **Original status claim:** ✅.

**Source evidence:** [`ChoresView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/HomeModule.swift:68) in `LifeOS/Modules/HomeModule.swift`. Recurring chores store an assignee string, frequency and last-done date. This is not multi-user household collaboration.

**Work to deliver:** Add rooms, cleanliness/urgency, effort, schedules/rotation, household members, invitations, assigned notifications, completion history, points and shared activity. Support skip/reschedule and vacation modes.

**Integration/dependencies:** Household identity/roles/sync, recurrence and audit events; integrate chores into common tasks without duplicate completions.

**Minimum acceptance scenario:** Two household members complete the same chore offline; reconciliation records one occurrence and consistent credit. Reassignment updates reminders and removal of a member preserves history.

**Public baseline references:** [Sweepy](https://sweepy.com/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 67. 12pets — Mes animaux

**Reference:** 11pets. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Gamelle, véto, vaccins. **Original status claim:** ✅ Rappels annulés si l'animal est supprimé.

**Source evidence:** [`PetsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/HomeModule.swift:128) in `LifeOS/Modules/HomeModule.swift`. Pets and care events/reminders exist; deletion includes reminder cancellation.

**Work to deliver:** Add multi-pet profiles, medical/vaccination/medication history, feeding/grooming/measurements, records/photos, recurring care plans, shared caregivers and vet-ready exports.

**Integration/dependencies:** Pet subject type within shared treatment/reminder/document engines; caregiver access distinct from owner account.

**Minimum acceptance scenario:** Schedule a recurring treatment, record a dose and export the pet's care record. Delete/archive the pet and verify reminders and attachments follow the documented policy.

**Public baseline references:** [11pets](https://www.11pets.com/en/feature). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 68. HomeZen — Maintenance récurrente

**Reference:** HomeZada. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Filtres, révisions, plantes. **Original status claim:** ✅.

**Source evidence:** [`MaintenanceView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/HomeModule.swift:236) in `LifeOS/Modules/HomeModule.swift`. Manual recurring maintenance records and last-done dates exist; full reminder handling was not established in the view.

**Work to deliver:** Add properties/rooms/assets, serial numbers/warranties/manuals, recurring schedule/reminders, service records/vendors, receipts, home inventory/photos, projects/budgets and valuation/expense reporting for wider HomeZada scope.

**Integration/dependencies:** Shared property/asset/vault domains, recurrence and household access.

**Minimum acceptance scenario:** Register an appliance with warranty and filter schedule, mark serviced and attach receipt. Next due date recalculates, warning fires once, and an insurance inventory export includes the asset.

**Public baseline references:** [HomeZada](https://apps.apple.com/us/app/homezada-mobile/id473722482). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 🚗 Mobilité

### 69. Fuelo — Ma voiture

**Reference:** Fuelio. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Assurance, révision, carburant. **Original status claim:** ✅ Rappels annulés si la voiture est supprimée.

**Source evidence:** [`VehicleListView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MobilityModule.swift:11) in `LifeOS/Modules/MobilityModule.swift`. Vehicles, fuel logs, consumption calculations and service/insurance reminders exist.

**Work to deliver:** Add multiple fuel/charging types, fill-to-fill correctness, partial fills, odometer validation, expense categories, maintenance history, trip/mileage tracking, imports/exports and station prices where available.

**Integration/dependencies:** Vehicle/trip ledger, CoreLocation route capture and verified fuel-price provider; shared reminder/vault services.

**Minimum acceptance scenario:** Test partial fills, an odometer typo and a missed fill before accepting consumption. A business trip contributes mileage once; deleting a vehicle cancels its reminders.

**Public baseline references:** [Fuelio](https://www.fuel.io/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 70. CityMappr — Trajets & CO₂

**Reference:** Citymapper. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Empreinte + budget par mode. **Original status claim:** 🟡 Pas encore branché sur un service de transport.

**Source evidence:** [`TripCO2View`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MobilityTools.swift:47) in `LifeOS/Modules/MobilityTools.swift`. Manual distance/mode inputs produce estimated cost and CO₂ using constants. There is no live route planning.

**Work to deliver:** Add place search, multimodal routes, maps, departure/arrival times, live transit departures/disruptions, step guidance, saved commutes, accessibility preferences and real fares where sourced. Retain CO₂ as an explained estimate layered on real routes.

**Integration/dependencies:** Routing/geocoding and transit providers, GTFS/GTFS-RT coverage where supported, location and cache. City coverage must be explicit.

**Minimum acceptance scenario:** Plan an accessible route with a disrupted line; show realistic alternatives and data timestamp. Unsupported cities/feeds produce an honest limitation, not fabricated departures.

**Public baseline references:** [Citymapper](https://apps.apple.com/us/app/citymapper-all-live-transit/id469463298). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 71. Park Maps — Où ai-je garé ?

**Reference:** Google Maps. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Mémorise ta place. **Original status claim:** ✅.

**Source evidence:** [`ParkingView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/MobilityTools.swift:207) in `LifeOS/Modules/MobilityTools.swift`. Stores one GPS parking location/time/note and opens external Maps walking directions.

**Work to deliver:** Complete parking photo/floor/meter reminders and saved-location history. Literal Google Maps parity additionally requires place search/details, map browsing, route modes, navigation/traffic, saved lists, offline data and reviews; represent this as a substantial maps subsystem, not completed by the parking shortcut.

**Integration/dependencies:** Map SDK/routing/place/traffic providers and usage agreements; shared route service with #70. Provider-rendered functionality must remain usable inside LifeOS where technically supported.

**Minimum acceptance scenario:** Save a parking spot with poor GPS, correct the pin and navigate back. Map search and route planning work independently of parking; offline/unavailable routes are clearly identified.

**Public baseline references:** [Google Maps](https://apps.apple.com/us/app/google-maps/id585027354). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 👥 Social

### 72. Dexo — CRM personnel

**Reference:** Dex. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Qui relancer. **Original status claim:** ✅.

**Source evidence:** [`CRMView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SocialModule.swift:12) in `LifeOS/Modules/SocialModule.swift`. Contacts, last-contact dates, cadence/overdue calculation and a Contacts importer exist; import deduplication is name-based.

**Work to deliver:** Add stable source contact IDs, merge/conflict handling, groups/tags, interactions/notes, reminders, relationship history, search and supported email/calendar/contact integrations. Desktop/browser capture is separate work.

**Integration/dependencies:** Contacts/event adapters, CRM identity model and optional authorized communication sync.

**Minimum acceptance scenario:** Import two different people with the same name and one renamed person twice; preserve correct identities. Logging an interaction updates the next reminder and connected history exactly once.

**Public baseline references:** [Dex](https://getdex.com/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 73. Hipp — Anniversaires & cadeaux

**Reference:** hip. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Rappels + idées. **Original status claim:** ✅.

**Source evidence:** [`BirthdaysView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SocialModule.swift:99) in `LifeOS/Modules/SocialModule.swift`. Birthday dates and yearly reminders exist; name-derived identifiers need lifecycle review.

**Work to deliver:** Add contact/calendar import, custom occasions, configurable advance reminders, leap-day rules, gift ideas/history/budget, cards/messages and shared family calendars where supported. Prefer stable event IDs over names.

**Integration/dependencies:** Shared contacts/occasion/reminder service and optional card/message delivery provider.

**Minimum acceptance scenario:** Rename a person, change their birthday and delete the occasion; no orphan reminders. Test 29 February in leap/non-leap years and delivery at local time after travel.

**Public baseline references:** [hip](https://apps.apple.com/us/app/hip-birthday-reminder-app/id401949944). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 74. Partyful — Sorties & events

**Reference:** Partiful / Luma. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Organise tes événements. **Original status claim:** ✅ Rappel annulé si l'événement est supprimé.

**Source evidence:** [`EventsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/SocialModule.swift:188) in `LifeOS/Modules/SocialModule.swift`. Local title/date/location events with a reminder and deletion cancellation exist.

**Work to deliver:** Add invitation pages/links, guest identities, RSVP/maybe/waitlist, plus-ones, polls, comments/updates, reminders, guest permissions and calendar integration. Luma-style ticketing/check-in/refunds require a real commerce layer.

**Integration/dependencies:** Hosted invitation/RSVP backend, notifications, access controls and optional payments/ticketing provider. Do not send invitations without the user's action.

**Minimum acceptance scenario:** Create a private event, invite test guests, receive an RSVP and update the time. Unauthorized guests cannot see private details; cancelled tickets/RSVPs update capacity and reminders.

**Public baseline references:** [Partiful](https://help.partiful.com/en-us/articles/15525594-why-use-partiful); [Luma](https://help.luma.com/t/events). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 📁 Admin

### 75. Digicoffre — Coffre-fort documents

**Reference:** Digiposte. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** ID, contrats, garanties. **Original status claim:** ✅ Rappel d'expiration annulé si supprimé.

**Source evidence:** [`DocVaultView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/AdminModule.swift:11) in `LifeOS/Modules/AdminModule.swift`. Local document metadata/images, categories, expiry notes and reminders exist. This is not an integrated Digiposte document-retrieval service.

**Work to deliver:** Add original multi-page PDFs/files, OCR search, metadata/tags, versioning, access lock, secure backup/sync, import/export, controlled share links and account/document connectors. Preserve originals and attachment integrity across devices.

**Integration/dependencies:** Document/attachment storage with encryption/access controls, OCR index, sharing service and supported issuer connectors. Separate personal storage from any certified archival claim.

**Minimum acceptance scenario:** Import a multi-page contract, search a phrase on its last page, share with expiry and revoke access. Export/restore reproduces every original byte and metadata link.

**Public baseline references:** [Digiposte](https://www.laposte.fr/digiposte/tous-mes-documents-partout-et-tout-le-temps). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 76. Papernid — Échéances

**Reference:** Papernest. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Impôts, assurance, abos. **Original status claim:** ✅.

**Source evidence:** [`DeadlinesView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/AdminModule.swift:85) in `LifeOS/Modules/AdminModule.swift`. A manual due-date/reminder list exists. Current Papernest scope includes connected subscription management rather than only reminders.

**Work to deliver:** Link contracts/subscriptions, detect renewals from real records, import bills, show forecasts, compare sourced offers and track provider switching/cancellation through confirmations. Include moving-house workflows and energy information where the verified baseline applies.

**Integration/dependencies:** Shared #44/#46 bank/contract domains plus commercial provider integrations for switching. Keep manual deadlines useful while externally executed operations remain pending.

**Minimum acceptance scenario:** Import a contract renewal, schedule notice and initiate a sandbox provider change. Status only advances on a real confirmation; no fabricated savings or cancellation completion.

**Public baseline references:** [Papernest](https://apps.apple.com/fr/app/papernest-mes-abonnements/id6748385943). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 77. Lettre-Public — Générateur de courriers

**Reference:** Modèles Service-Public. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Résiliation, attestation…. **Original status claim:** ✅.

**Source evidence:** [`LetterGeneratorView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/AdminModule.swift:146) in `LifeOS/Modules/AdminModule.swift`. A finite template collection produces editable text and sharing.

**Work to deliver:** Build a searchable, versioned template catalogue with source/date/jurisdiction, conditional questionnaires, required-field validation, attachments, editable preview, PDF/DOCX export and delivery tracking if a delivery service is added.

**Integration/dependencies:** Official Service-Public template references, document renderer and deadline/contract linkage. The official template library is a source, not an embedded execution service.

**Minimum acceptance scenario:** Generate a cancellation letter with accents/address/date, inspect exported pages and verify required notice fields. Outdated/unavailable templates are flagged rather than silently reused.

**Public baseline references:** [Modèles Service-Public](https://www.service-public.gouv.fr/particuliers/vosdroits/demarches-et-outils). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 78. Adobo Scan — Scan & classement

**Reference:** Adobe Scan. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** OCR auto, range tout seul. **Original status claim:** ✅ VisionKit sur l'iPhone.

**Source evidence:** [`DocScanView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/DocScan.swift:56) in `LifeOS/Modules/DocScan.swift`. VisionKit capture, OCR/classification and desktop file import exist. The scanner delegate takes only imageOfPage(at: 0), dropping subsequent scanned pages.

**Work to deliver:** Preserve all pages/original PDFs; crop/rotate/reorder/delete pages, perspective cleanup, searchable PDF OCR, classification confidence/manual correction, search/share and vault integration. Audit desktop PDF import so it does not merely rasterize page one.

**Integration/dependencies:** Multi-page Document/Page/Attachment schema, Vision/PDFKit OCR pipeline and transactional file storage; phone camera plus desktop file/drag input.

**Minimum acceptance scenario:** Scan/import a five-page document, reorder pages and search text from page five. Export/reopen PDF preserves five pages and selectable text; cancellation/failure never reports a saved document falsely.

**Public baseline references:** [Adobe Scan](https://helpx.adobe.com/mobile-apps/help/adobe-scan-faq.html). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## ✈️ Voyage

### 79. TripUp — Mes voyages

**Reference:** TripIt. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Itinéraire + budget + valise. **Original status claim:** ✅.

**Source evidence:** [`TripsView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/TravelModule.swift:11) in `LifeOS/Modules/TravelModule.swift`. Manual trips, dates/budget, packing and basic trip details exist.

**Work to deliver:** Add structured reservations/segments for flights/hotels/rail/car, confirmation import/parsing, timezone-aware itinerary, documents/maps, sharing, expenses, packing and alerts. TripIt Pro-style status and disruption features depend on live feeds.

**Integration/dependencies:** Travel itinerary schema, email/file import with explicit access, parser review and #80/#83 services.

**Minimum acceptance scenario:** Import a multi-city confirmation with local timezones, correct one segment and share with a companion. Duplicate emails do not duplicate reservations; changed flights propagate without losing user notes.

**Public baseline references:** [TripIt](https://help.tripit.com/en/support/solutions/articles/103000063396-tripit-or-tripit-pro-). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 80. Xchange — Convertisseur

**Reference:** XE Currency. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** 12 devises, hors ligne. **Original status claim:** ✅.

**Source evidence:** [`CurrencyConverterView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/TravelTools.swift:31) in `LifeOS/Modules/TravelTools.swift`. Twelve perEUR values are hardcoded, including USD 1.08; the converter is an offline reference calculator, not live FX.

**Work to deliver:** Add timestamped live rates, refresh/cache/failure behavior, broader currencies, historical charts, favourites and rate alerts. Full XE transfer functionality requires a real payments service; conversion estimates must be distinct from executable quotes and fees.

**Integration/dependencies:** FX data provider, currency precision rules and shared finance/travel cache; optional transfer provider with complete status lifecycle.

**Minimum acceptance scenario:** Fetch a rate, go offline, convert a cross pair and display the original timestamp. Stale data is explicit; transfer failure cannot appear completed or debit a local balance fictitiously.

**Public baseline references:** [XE Currency](https://www.xe.com/app/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 81. iTraduis — Phrases de voyage

**Reference:** iTranslate. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** 5 langues, lues à voix haute. **Original status claim:** ✅.

**Source evidence:** [`PhrasebookView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/TravelTools.swift:204) in `LifeOS/Modules/TravelTools.swift`. A fixed five-language travel phrase list with speech output exists.

**Work to deliver:** Add searchable categories, favourites/custom phrases, pronunciation controls, offline language assets and destination collections. Literal iTranslate parity includes arbitrary text/voice/camera translation and conversation modes, which should reuse #82 instead of stopping at canned phrases.

**Integration/dependencies:** Shared translation/TTS/STT and language-capability registry; content translations reviewed per language.

**Minimum acceptance scenario:** Find and play a phrase offline, save a custom translation and reopen on desktop. Unsupported pronunciation/translation languages are visible before the user starts.

**Public baseline references:** [iTranslate](https://support.itranslate.com/hc/en-us/articles/16880687088788-iTranslate-Translator). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 82. Goggle Traduction — Traduction

**Reference:** Google Traduction. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** 12 langues, hors ligne (Apple Translation). **Original status claim:** ✅.

**Source evidence:** [`TranslationView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/Translator.swift:29) in `LifeOS/Modules/Translator.swift`. Apple Translation provides typed translation on supported OS/language combinations; the app lists a limited set of languages.

**Work to deliver:** Add dynamic capability checks, download management, language detection, history/favourites, speech input/output, conversation mode, camera/image OCR and document translation. Match supported reference workflows explicitly; do not assume Apple's language coverage equals Google's.

**Integration/dependencies:** Translation provider abstraction, Vision OCR, speech adapters and offline asset lifecycle; desktop capability checks.

**Minimum acceptance scenario:** Translate typed text, a photographed menu and a two-person exchange. Test uninstalled offline assets and unsupported pairs. Keep original formatting/context and never show untranslated text as a successful translation.

**Public baseline references:** [Google Traduction](https://support.google.com/translate/). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 83. Flighto — Suivi des vols

**Reference:** Flighty. **Progress:** Partial foundation; external service/collaboration gap.

**Original table scope:** Compte à rebours et statut. **Original status claim:** 🟡 Statut en direct à brancher.

**Source evidence:** [`FlightTrackerView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Modules/TravelModule.swift:172) in `LifeOS/Modules/TravelModule.swift`. Flight records/status are manually stored in AppStorage; a default on-time label and countdown do not establish live tracking.

**Work to deliver:** Add flight/date/airport lookup, live departure/arrival/gate/terminal/status, disruption alerts, incoming aircraft where supplied, timezone correctness, calendar/email import, sharing and travel history. Mark unknown status unknown until a provider confirms it.

**Integration/dependencies:** Flight-data provider with commercial access/coverage, backend polling/push and itinerary links. Preserve provider timestamp and confidence.

**Minimum acceptance scenario:** Simulate delayed, cancelled, diverted and gate-changed flights. Alerts update once; a disconnected feed never reverts to on-time. Date-line crossings and codeshares resolve the correct flight.

**Public baseline references:** [Flighty](https://flighty.com/pricing). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

## 🏡 En dehors des catégories

### 84. Réveil — Réveil

**Reference:** Alarmy. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Onglet réveil, briefing au réveil, activité en direct. **Original status claim:** ✅.

**Source evidence:** [`AlarmManager`](/Users/Shared/Claude/apps/lifeos/LifeOS/Core/AlarmManager.swift:18) in `LifeOS/Core/AlarmManager.swift`. Wake-up notifications, in-app ringing, snooze, a Live Activity and briefing flow exist. AlarmManager uses an in-process countdown and auto-transitions after about ten seconds; no AlarmKit usage was found there.

**Work to deliver:** Build multiple persistent alarms, repeat rules, labels/sounds, reliable supported system delivery, missions (math/photo/barcode/steps as selected), snooze policy, wake checks and history. Keep the briefing integration. Inventory Alarmy sleep-related features separately.

**Integration/dependencies:** Evaluate AlarmKit on supported OS, authorization and actual background/terminated behavior; fallback notifications must be named honestly. Camera/motion missions need device adapters; desktop requires its own delivery tests.

**Minimum acceptance scenario:** Test locked phone, silent/Focus modes under the chosen API contract, relaunch/reboot, DST and disabled authorization. A mission must be completed before the chosen dismiss policy advances; don't auto-dismiss after ten seconds.

**Public baseline references:** [Alarmy](https://alar.my/en). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 85. Ton coach — Ton coach

**Reference:** ChatGPT. **Progress:** Local foundation; depth/integration incomplete.

**Original table scope:** Assistant qui connaît toutes tes données. **Original status claim:** 🟡 Demande une clé dans Profil › Coach.

**Source evidence:** [`AIAssistantView`](/Users/Shared/Claude/apps/lifeos/LifeOS/Shared/AIAssistantView.swift:874) in `LifeOS/Shared/AIAssistantView.swift`. A substantial assistant already exists: persisted chat, streamed text, tools/actions, context/memory, provider routing, local/on-device fallbacks, photo input and speech/TTS hooks. The Notion 'requires a key' status is incomplete.

**Work to deliver:** Audit actual capability end-to-end, then add missing reference workflows: robust conversation/project organization, file/document analysis, grounded web research/citations, richer voice, image generation where provided, searchable history and reliable artifacts. Full ChatGPT capability inventory is separate from simply calling a text model; current image-only importer is not general file analysis.

**Integration/dependencies:** Reuse AICore/router/tools/memory rather than rewrite. Provider capability matrix, server-backed credentials where appropriate, file processing, citation provenance, budgets/cancellation and idempotent tool actions.

**Minimum acceptance scenario:** Run a scenario using real LifeOS data, attach a PDF, cite a retrieved source and preview/apply a task change. Cancel mid-stream and retry without duplicate mutations; unavailable providers show an actionable state and retain the draft.

**Public baseline references:** [ChatGPT](https://learn.chatgpt.com/docs/features). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 86. Score du jour & bilan — Score du jour & bilan

**Reference:** Bevel. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Un score qui mélange tous les objectifs, série, bilan du soir. **Original status claim:** ✅ Score d'énergie corrigé.

**Source evidence:** [`EnergyScore`](/Users/Shared/Claude/apps/lifeos/LifeOS/Services/EnergyScore.swift:9) in `LifeOS/Services/EnergyScore.swift`. A coverage-aware local score combines sleep quality/duration, hydration, habits, mood and fatigue, with tests and widget publishing. It is not Bevel's physiological model.

**Work to deliver:** Keep a transparent LifeOS daily-goal score while adding separately labeled recovery/sleep/strain/stress/nutrition trends and coaching where supported. Personal baselines, journal correlations and input coverage are essential. Inventory Bevel's current modules and map shared nutrition/workout services rather than duplicating them.

**Integration/dependencies:** Shared health/workout/nutrition/journal analytics and historical snapshots; validated definitions and no invented biometric inputs.

**Minimum acceptance scenario:** Withhold unavailable data, update a corrected sleep entry and compare all score displays. Explain each contribution and coverage; goal completion must not be mislabeled as measured physiological recovery.

**Public baseline references:** [Bevel](https://help.bevel.health/en/articles/11194113). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.

### 87. Accueil personnalisable — Accueil personnalisable

**Reference:** Widgets iOS. **Progress:** Partial implementation; device/data qualification gap.

**Original table scope:** Raccourcis et anneaux, ordre au doigt. **Original status claim:** ✅ Réordonnables à la poignée.

**Source evidence:** [`HomeWidgetGallery`](/Users/Shared/Claude/apps/lifeos/LifeOS/Core/HomeWidgetEditing.swift:146) in `LifeOS/Core/HomeWidgetEditing.swift`. Home ordering/customization and WidgetKit-related code, app-group snapshots and interactive reconciliation exist.

**Work to deliver:** Complete add/remove/reorder/resize/configure of supported dashboard cards; phone/tablet/desktop layouts; widget families, deep links and actions; persistent preferences and synchronized data. Distinguish in-app cards from actual OS widgets and Live Activities.

**Integration/dependencies:** Stable widget/tool IDs, shared read models/intents, capability registry and accessibility/keyboard reorder; preserve the separate Liquid Glass design system.

**Minimum acceptance scenario:** Reorder on phone, reopen desktop, invoke a widget action while the app is closed and verify exactly one domain update. Removed/archived modules never leave dead links or stale private data in snapshots.

**Public baseline references:** [Widgets iOS](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities). These sources inform the requirement scope; exact region/tier and unobserved workflows remain subject to baseline closure.
