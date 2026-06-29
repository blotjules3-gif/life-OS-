# LifeOS — Completion Tracker

Scope locked to **Home** and **Category** sections only. Onboarding, settings,
profile, alarm, chat/assistant are **out of scope** (note issues in CHANGELOG.md, do not touch).

Status legend: `TODO` = not built / incomplete · `DONE` = UI + states + nav + data + compiles · `BLOCKED` = needs external resource (one line on what unblocks).

A section is **DONE** only when ALL hold: UI matches the bubble design system; loading/empty/error
states handled; nav in & out wired; data populated (real or clearly-marked stub); project compiles
with zero errors via the xcodebuild command at the top of CHANGELOG.md.

---

## HOME (`ShortcutsHomeView.swift`) — do these first

| Section | Status |
|---|---|
| Greeting header + energy badge (`userName`, `todayEnergyScore`) | DONE |
| Re-engagement banner (`showReengage` / `reengageMessage`) | DONE |
| Weekly module suggestion card (`weeklyModuleSuggestion`) | DONE |
| Habitudes section (`habitsSection`) | DONE |
| Objectifs du jour — rings + 3 objectives (`goalsSection`) | DONE |
| Humeur du jour — check-in (`moodSection`) | DONE |
| Quick-shortcuts grid (`ShortcutTool` / `homeShortcuts`) — rendered as **Raccourcis** + editor sheet | DONE |

---

## CATEGORIES (`CategoryHub.swift` tool arrays) — 16 pôles

| # | Category | Tools | Status | Note |
|---|---|---|---|---|
| 1 | Sommeil & réveil (`sleep`) | 5 | DONE | |
| 2 | Nutrition (`nutrition`) | 9 | DONE | suppléments + reco + notifs livrés |
| 3 | Sport & fitness (`fitness`) | 6 | DONE | programme + notifs muscu livrés |
| 4 | Looksmaxx (`looks`) | 5 | TODO | analyse faciale réelle (Vision) à ajouter |
| 5 | Mental & focus (`mind`) | 5 | TODO | sons relaxants / ASMR on-device à ajouter |
| 6 | Productivité (`productivity`) | 5 | DONE | |
| 7 | Finances perso (`finance`) | 6 | DONE | |
| 8 | Investissement (`invest`) | 5 | DONE | |
| 9 | Carrière (`career`) | 5 | DONE | |
| 10 | Apprentissage (`learning`) | 5 | DONE | langues (Leitner) livré |
| 11 | Maison & quotidien (`home`) | 5 | DONE | |
| 12 | Mobilité (`mobility`) | 3 | TODO | catégorie maigre, à enrichir |
| 13 | Social & relations (`social`) | 3 | TODO | catégorie maigre, à enrichir |
| 14 | Admin & paperasse (`admin`) | 4 | DONE | scan OCR on-device livré |
| 15 | Voyage (`travel`) | 4 | DONE | convertisseur + phrases livrés |
| 16 | Cycle menstruel (`cycle`) | 3 | DONE | |

### Known BLOCKED sub-items (do not fake)
- Voyage › **Suivi des vols** (`FlightScaffold`) — BLOCKED: needs a flight-status API key (e.g. AviationStack/FlightAware). Unblock = provide key + endpoint.
- Looks › **Analyse faciale** — feasible on-device (Vision face landmarks); only BLOCKED if it needs device-only camera testing beyond the simulator.
