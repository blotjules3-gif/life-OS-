# Passe 01 — Secteur Services

Date : 2026-07-13
Fichiers audités : 18 (~4124 lignes)

## Constatations

### Bloquant

**B1. `UserContextBuilder.swift:30` — le profil de vie n'est jamais transmis au coach**

```swift
let lifeProfile = ud.string(forKey: "userLifeProfile") ?? ""
```

Rien dans l'app n'écrit à la clé `"userLifeProfile"`. La clé réellement écrite par l'onboarding est `"lifeProfile"` (cf. `OnboardingView.swift:65` et `UserPreferencesKeys.lifeProfile`). Conséquence : le bloc `Profil: …` n'apparaît jamais dans le contexte envoyé au coach.

Fix : lire `"lifeProfile"`.

### Important

**I1. `ServerStatusMonitor.swift:39` — chaîne UI contient « LLM »**

```swift
case .llmDown(let err):  return "Coach indisponible — \(err ?? "clé LLM invalide")"
```

`statusLabel` est affiché dans l'app. Convention LifeOS : jamais dire « IA », « LLM », « modèle » à l'utilisateur.

Fix : neutraliser la chaîne.

### Cosmétique / cohérence

**C1. `AppStorageKeys.swift:20` — clé « userLifeProfile » morte**

Registre non utilisé par personne aujourd'hui (grep global `AppStorageKeys.` ne retourne que des commentaires). Mais si quelqu'un s'en sert un jour, `userLifeProfile` pointe vers une clé phantôme.

Fix : aligner la valeur sur `"lifeProfile"` (nom Swift conservé pour compat future).

## Fixes à appliquer dans cette passe

1. UserContextBuilder.swift ligne 30 : `"userLifeProfile"` → `"lifeProfile"`
2. ServerStatusMonitor.swift ligne 39 : neutraliser le message d'erreur
3. AppStorageKeys.swift ligne 20 : `"userLifeProfile"` → `"lifeProfile"`

## Hors périmètre (autre passe)

- Double registre de clés (`AppStorageKeys` en Services, `UserPreferencesKeys` en Core) → passe Core
- Cohérence Int vs Double pour `lastSleepHours` (marche via NSNumber, non urgent)
- Migration des `print()` vers un logger → passe transverse
- Hardcoding UserDefaults keys dans UserContextBuilder → dépend de la décision registre
- Refactor de la structure des sections notif dans ContextualNotifications → structure, hors sujet
