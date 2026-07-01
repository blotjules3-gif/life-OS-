# LifeOS — Completion Tracker (NEW BAR)

Scope: **Onboarding**, **Home**, and all **16 Category** sections.

**DONE bar (raised):** a section is DONE only when it performs its REAL function
(no placeholder/stub), handles loading + empty + error states, nav wired, data is
real (onboarding answers / device sensors / free on-device frameworks — no fake
seed data), and compiles via the build command at the top of CHANGELOG.md.
A "clearly marked stub" is now **TODO**, not DONE.

Build check note: CoreSimulator is currently out of date (needs a Mac reboot to
boot a sim). Compile-only verification uses `-destination 'generic/platform=iOS Simulator'`.

---

## ONBOARDING (intake → pre-fills modules)

| Item | Status | Note |
|---|---|---|
| Identity (name, gender) — existing OnboardingView | DONE | writes userName/userGender |
| Intake hub (all 16 poles, progress %, skippable, resumable, idempotent) | DONE | `IntakeHubView`, shown at first launch + relaunchable |
| Pole flow · Nutrition | DONE | computes kcal/protein/water, shopping, supplement reco — real writes |
| Pole flow · Fitness | DONE | detailed program (real exercises/machines), idempotent |
| Pole flow · Sommeil | DONE | wake/duration/alarm → wakeup* + sleepTargetHours |
| Pole flow · Finances | DONE | budget + courant account + subscriptions (idempotent SwiftData) |
| Pole flow · Productivité·Mental·Looks·Cycle·Mobilité | DONE | write real AppStorage/SwiftData (focus/screen, meditation, skin, cycle dates, Vehicle) |
| Pole flows · 7 remaining | TODO | invest, career, learning, home, social, admin, travel |

---

## HOME (`ShortcutsHomeView.swift`) — real, re-audited

All sections operate on live data (SwiftData + HealthKit) — kept DONE:
greeting/energy, re-engage banner, weekly module card, habits, goals rings,
mood check-in, Raccourcis grid + editor. Profile-completion card added.

---

## CATEGORIES — re-audited against the new bar

| # | Category | Status | Note |
|---|---|---|---|
| 1 | Sommeil (`sleep`) | DONE | + onboarding flow |
| 2 | Nutrition (`nutrition`) | DONE | all tools real (incl. both camera features below) |
| – | Nutrition › Calories par photo | **DONE** | real camera (UIImagePickerController) + PhotosPicker fallback + on-device Vision (VNClassifyImageRequest) food classify → kcal/macros estimate (editable) → FoodEntry journal; loading/empty/error states. Live camera needs a physical device |
| – | Nutrition › Scan code-barres | **DONE** | was already real: VisionKit DataScannerViewController + OpenFoodFacts (nutriscore/nova) + ProductDetailView; manual-code + search fallback on sim. (Earlier audit wrongly downgraded it) |
| 3 | Sport (`fitness`) | DONE | program + Tabata linked + onboarding flow |
| 4 | Looks (`looks`) | DONE | Vision face analysis real |
| 5 | Mental (`mind`) | DONE | on-device soundscape real; Détox écran = timer only |
| – | Mental › Détox écran (real app blocking) | **BLOCKED** | needs Apple Screen Time entitlement (FamilyControls) — not on free profile/sim |
| 6 | Productivité (`productivity`) | DONE | |
| 7 | Finances (`finance`) | DONE | + onboarding flow |
| 8 | Investissement (`invest`) | DONE | live quotes feature = BLOCKED (market data key) |
| 9 | Carrière (`career`) | DONE | |
| 10 | Apprentissage (`learning`) | DONE | Leitner real |
| 11 | Maison (`home`) | DONE | |
| 12 | Mobilité (`mobility`) | DONE | Trajets CO₂ + parking real; cheap-fuel = BLOCKED |
| 13 | Social (`social`) | DONE | CRM/birthdays/events + reminders real |
| 14 | Admin (`admin`) | DONE | OCR real |
| 15 | Voyage (`travel`) | PARTIAL | converter + phrases + translator real |
| – | Voyage › Traduction | **DONE** | real Apple Translation (translationTask/TranslationSession + offline prepareTranslation), 12 langs, iOS18-guarded; compile-verified (visual pending sim reboot) |
| – | Voyage › Suivi des vols | **BLOCKED** | flight-status API key |
| 16 | Cycle (`cycle`) | DONE | |

### Legitimately BLOCKED (real external key required)
- Mobilité › cheapest fuel — live fuel-price feed.
- Voyage › flight status — flight-status API key.
- Invest › live market quotes — market-data key.
- (Bank aggregation, transit routing — same: external key.)

### Next passes (priority order)
1. Voyage › Traduction (Apple Translation, iOS 18) — real translator.
2. Nutrition › Scan code-barres (DataScanner + OpenFoodFacts).
3. Nutrition › Calories par photo (camera + estimate).
4. Remaining 12 onboarding pole flows.
