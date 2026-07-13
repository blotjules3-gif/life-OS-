# Audit LifeOS — log rotatif

Chaque relance du prompt "audit complet" traite UN secteur non encore fait.
L'ordre est fixe pour ne pas mélanger les passes.

## Secteurs et statut

| # | Secteur | Statut | Fichier passe |
|---|---------|--------|---------------|
| 1 | Services (Swift, /LifeOS/Services) | FAIT 2026-07-13 | pass-01-services.md |
| 2 | Core (vues principales, lifecycle) | FAIT 2026-07-13 | pass-02-core.md |
| 3 | Shared (composants transverses, AIAssistantView) | FAIT 2026-07-13 | pass-03-shared.md |
| 4 | Modules (features par domaine, 41 fichiers) | FAIT 2026-07-13 | pass-04-modules.md |
| 5 | Models (SwiftData) | FAIT 2026-07-13 | pass-05-models.md |
| 6 | Widgets (LifeOSWidgets) | FAIT 2026-07-13 | pass-06-widgets.md |
| 7 | Backend Python (FastAPI) | à faire | — |
| 8 | Config / Assets / Info.plist / xcconfig | à faire | — |

## Règles

- Ne jamais retoucher un secteur déjà "fait" dans une nouvelle passe (sauf régression détectée)
- Chaque passe = un fichier `pass-NN-<secteur>.md` avec constatations, fixes, vérifications
- Chaque fix : brace check (Diff: 0) + relecture du diff
- Aucune réécriture qui change la structure d'un fichier
