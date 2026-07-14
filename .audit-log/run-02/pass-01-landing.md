# Run 2 — Passe 01 · Landing page docs/

Date : 2026-07-13
Fichiers audités : 5 HTML (~1671 lignes) + vendor Three.js + icon.png
Contexte : nouvelle passe après merge des 6 commits de site LifeOS de l'associé (`pote`) dans `jules`.

## Regression check préalable

**15/15 fixes du run 1 sont intacts** après merge. Aucun rollback détecté.

## Constatations sur le nouveau contenu

### CRITIQUE — risque légal / App Store

**C1. Contradiction privacy policy ↔ backend réel**

- `docs/privacy.html:50` : « Pas de compte, pas de serveur, pas de publicité, pas de trackers. »
- `docs/privacy.html:56` : « LifeOS fonctionne entièrement hors ligne et sur votre appareil. **Nous n'exploitons aucun serveur applicatif et n'avons techniquement aucun accès à vos données** »

**Réalité côté code :**
- `Configuration.swift:24` : `apiBaseURL = "https://lifeos-api-production-91e2.up.railway.app"`
- `backend/app/main.py` : FastAPI déployé sur Railway
- `AgentAPI.chat()` transmet `user_context` au serveur — ce contexte contient poids, cycle, humeur, habitudes du jour, ratios force/poids (cf. `UserContextBuilder.swift`)
- Chat + goals + challenges + energy sont persistés côté DB Railway (Postgres, cf. `backend/app/models/db.py`)

C'est **une non-conformité GDPR** et un **risque App Store** (privacy policy trompeuse → App Review Guideline 5.1.1). Deux options — décision produit + juridique nécessaire :
- **A. Réaligner la privacy sur la réalité** : disclose le backend Railway, le contexte transmis, la finalité (coach LLM Mistral), la durée de rétention, les droits d'accès/suppression, le sous-traitant (Mistral + Railway).
- **B. Réaligner le code sur la privacy** : basculer 100% en `LocalCoach` (déjà en place, tourne sur device), désactiver `AgentAPI`, arrêter le backend Railway. Aucune donnée ne quitte l'iPhone.

**Ne pas laisser en l'état.**

### Important — App Store review

**I1. `docs/support.html:59` — email support qui ressemble à un placeholder**

```html
<a class="btn" href="mailto:theoxspam@gmail.com?subject=%5BLifeOS%5D%20Support">Écrire un e-mail</a>
```

`theoxspam@gmail.com` a l'air d'une adresse jetable / placeholder. Guideline App Store 1.5 exige un contact support valide. Si c'est bien l'adresse de ton pote, ça passe ; sinon c'est bloquant à la review. À confirmer.

### Cohérence chiffres

**Ch1. Nombre de pôles — 3 valeurs différentes selon la source**

| Source | Nombre | État |
|--------|--------|------|
| `AppCategory.swift:3` commentaire (avant) | 15 | ~~FAUX~~ |
| `AppCategory.swift:3` commentaire (après fix) | 17 | ✓ (16 pour tous + cycle conditionnel) |
| Enum `AppCategory` cases | 17 | source de vérité |
| `docs/index.html` × 3 + `classic.html` × 2 | 16 | possible marketing (excl. cycle) — à confirmer |

**Ch2. `docs/index.html:319` / `classic.html:275` — 41 entités**

```html
<b>100 % on-device</b><span>Les 41 entités de données vivent en local.</span>
```

Code a **49 `@Model final class`** dans `LifeOS/Models/`. Écart de 8. Possible marketing simplifié (entités user-facing vs relation models internes comme `HabitCompletion`) — à confirmer avec pote.

### Style — inconsistance délibérée ?

**S1. Tutoiement (marketing) vs vouvoiement (légal + support)**

- `index.html` / `classic.html` : 16 occurrences de « ta/ton » (LifeOS app-style)
- `privacy.html` / `terms.html` / `support.html` : 16 occurrences de « vos/votre »

Convention française classique (marketing tutoie, légal vouvoi), donc probablement intentionnel. À laisser.

## Absents / vérifiés OK

- **0 script externe** — tout vendor est local, aucune CDN, pas de CSP à configurer
- **0 dev placeholder** (Lorem/TODO/FIXME/example@) hors le mail flag ci-dessus
- **Viewport meta** correct sur toutes les pages
- **`lang="fr"`** sur toutes les pages
- **`rel="noopener"`** sur les liens `target="_blank"` — safe
- **Footer + navigation** cohérents entre pages légales
- **Détails HTML5 `<details>`** pour la FAQ support — accessible native

## Application

1. `LifeOS/Core/AppCategory.swift:3` — commentaire 15 → 17 pôles (fixé).
   Brace check : Diff: 0.

## À décider — pas touché

1. **Landing 16 pôles / 41 entités** — attend confirmation de ton pote (choix marketing volontaire ou incohérence à corriger)
2. **Email support** `theoxspam@gmail.com` — attend confirmation que c'est le vrai
3. **Privacy vs backend** — décision produit + juridique (option A ou B)

## Bilan

Landing page bien codée sur le fond (0 warning HTML/CSS, 0 dépendance externe, RGPD-conforme sur la forme). Mais **le fond juridique est incompatible avec le code** — c'est le point le plus grave découvert dans tout l'audit, run 1 + run 2 confondus. À traiter avant App Store submission.
