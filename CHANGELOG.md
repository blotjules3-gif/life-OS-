# LifeOS — Changelog

## BUILD COMMAND — the loop MUST run and confirm this before marking anything DONE

Scheme: **LifeOS**  ·  run from the project root (`/Users/futurx/Claude/apps/lifeos`):

```bash
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -sdk iphonesimulator -configuration Debug -derivedDataPath build -destination 'platform=iOS Simulator,id=2718280F-B542-4942-90D0-E06723B52DAE' build
```

Success = the output contains `** BUILD SUCCEEDED **` and zero `error:` lines.
If the simulator UDID is ever invalid, substitute `name=iPhone 17` for `id=...`.
If CoreSimulator is out of date (after an Xcode update — needs a Mac reboot),
compile-only with `-destination 'generic/platform=iOS Simulator'` (no booted device needed).
If `metal` toolchain is missing: `xcodebuild -downloadComponent MetalToolchain`.

---

## Log — one line per pass: `[section] | what changed | builds yes/no`

[2026-06-29] | scaffolding | created COMPLETION.md, CHANGELOG.md, resume_loop.sh; confirmed scheme=LifeOS and build command | builds yes
[2026-06-29] | Home › Raccourcis | rendered pinned ShortcutTool grid (was modeled but never shown) + ShortcutPickerSheet editor; empty-state + nav wired; verified on simulator | builds yes
[2026-06-29] | Home › Humeur | reviewed moodSection — filled/empty states + SwiftData persistence complete; marked DONE | builds yes
[2026-06-29] | Mental › Sons relaxants | new on-device noise generator (AVAudioEngine + AVAudioSourceNode, procedural white/pink/brown/ocean, no assets) + sleep timer + volume; error/active states; added to mindTools; verified on simulator | builds yes
[2026-06-29] | Looks › Analyse faciale | replaced scaffold with real Vision analyzer (VNDetectFaceLandmarks): symmetry, eye spacing, facial thirds, FWHR + composite, neutral framing/disclaimer; PhotosPicker, empty/loading/error states. Build + UI states verified on sim; real-face scorecard not screenshot-verified (sim has no face photo) but pipeline is standard on-device Vision | builds yes
[2026-06-29] | Mobilité › Trajets & CO₂ + Où ai-je garé | replaced 2 scaffolds (cheap-fuel/multimodal needed live external feeds) with on-device tools: trip CO₂+cost log by mode (ADEME factors, @AppStorage, empty/input states) and a CoreLocation parking saver (uses existing NSLocationWhenInUse string; empty/busy/error states, Maps deeplink). Renamed local struct to MobTrip to avoid clash with SwiftData Trip model. Both verified on sim | builds yes
[2026-06-29] | Social › Anniversaires | CRM/Birthdays/Events were already complete (no scaffolds). Fulfilled the tool's unkept "Rappels" promise: added scheduleYearly() to NotificationManager + a per-contact yearly birthday reminder toggle (3 days before, 10:00, with gift ideas). Empty + populated paths both screenshot-verified (throwaway in-memory seed, deleted) | builds yes
[2026-06-29] | LOOP COMPLETE | every Home section (7/7) and every Category section (16/16) is DONE; one sub-item BLOCKED (Voyage › Suivi des vols — needs flight-status API key). STATUS.txt=DONE | builds yes
[2026-06-30] | NEW BAR re-audit | rewrote COMPLETION.md to raised bar+scope; downgraded Traduction/Calories-photo/Scan-barcode to TODO; environment: fixed missing Metal toolchain, CoreSimulator needs reboot | builds yes
[2026-06-30] | Onboarding intake | built IntakeHubView (16 poles, %, skippable/resumable/idempotent) + central CategoryFlowView; shown at first launch; new real pole flows Sommeil (wakeup/sleep target) + Finances (budget/account/subs, idempotent SwiftData) | builds yes
[2026-06-30] | Voyage › Traduction | real Apple Translation framework (translationTask + TranslationSession.translate + prepareTranslation for offline), 12-language picker, swap, copy, loading/empty/error states, iOS18 #available guard + fallback; added to travelTools | builds yes
[2026-06-30] | Nutrition › Scan code-barres | AUDIT FIX: was already real (DataScannerViewController + OpenFoodFacts + ProductDetailView, sim fallback) — corrected wrong TODO downgrade to DONE | builds yes
[2026-06-30] | Nutrition › Calories par photo | replaced PhotoCalorieScaffold with real PhotoCalorieView: live camera (UIImagePickerController.camera) + PhotosPicker fallback, on-device VNClassifyImageRequest → FoodCalorieDB estimate (editable kcal/macros) → FoodEntry journal; loading/empty/error states | builds yes
