# LifeOS — Détection et forçage de langue

## Comportement actuel

### Détection auto (par défaut)
- **Comment** : `CFBundleLocalizations = ["fr", "en"]` dans `Info.plist` déclare que LifeOS supporte français + anglais uniquement. iOS pioche automatiquement la première langue supportée dans les préférences système de l'utilisateur.
- **Fallback** : si iOS ne peut pas matcher (langue exotique), retombe sur `CFBundleDevelopmentRegion = "fr"` (français par défaut).

### Forçage manuel (Profil → Langue de l'app)
- **Auto** : supprime l'override, iOS reprend son choix natif.
- **Français** : force `["fr"]` dans `AppleLanguages` (UserDefaults).
- **English** : force `["en"]` dans `AppleLanguages`.
- **Application** : appliqué au boot via `LanguageForcer.applyPersistedChoice()` dans `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
- **Effet visuel** : nécessite un **redémarrage complet de l'app** — SwiftUI ne relit pas les strings au vol.

## Sources de strings dans l'app

| Source | Où | Statut |
|---|---|---|
| `Localizable.xcstrings` | `LifeOS/Localizable.xcstrings` (1134 clés) | ~5% traduites en EN (66/1134) |
| `Text("...")` hardcodés | ~440 occurrences dans `LifeOS/**/*.swift` | Jamais extraites |
| Info.plist usage descriptions | `LifeOS/Info.plist` | Français uniquement |

## Cas d'usage

### iPhone en FR + auto
→ App affichée 100% FR. Comportement le plus courant, entièrement fonctionnel.

### iPhone en EN + auto
→ App affichée en EN pour les 66 clés traduites + FR pour tout le reste. **Mélange chaotique** — c'est pourquoi le sélecteur "Français" est utile en attendant la traduction complète.

### iPhone en EN + choix "Français"
→ App affichée 100% FR. Comportement cohérent, recommandé pour éviter le mélange en attendant la traduction EN complète.

### iPhone en FR + choix "English"
→ App affichée en EN pour les 66 clés traduites + FR pour tout le reste. **Mélange** — le sheet le signale honnêtement à l'utilisateur.

## Roadmap traduction

Pour atteindre "100% EN quand iPhone EN" :

1. **Extraction** — passer les 440 `Text("...")` FR en `Text(String(localized: "clé.stable"))` avec ajout dans `Localizable.xcstrings`. Estimé 6h avec script sécurisé + revue manuelle.
2. **Traduction** — traduire les 1068+ nouvelles clés en EN via LLM ou service pro. Estimé 3-4h.
3. **Info.plist** — traduire les 8 usage descriptions (`NSCameraUsageDescription`, etc.) via `InfoPlist.strings` fichier de localisation. Estimé 30 min.
4. **Validation** — passer manuellement chaque écran principal en EN sur simulateur. Estimé 2h.

Total : **~12h** de travail dédié. Documenté comme item de phase future dans `.claude/commands/ship.md`.

## Vérification

```bash
# Compter les Text() FR hardcodés restants
grep -rE 'Text\("[A-ZÀ-ÿ][a-zà-ÿ]' LifeOS --include="*.swift" | wc -l

# Compter les clés traduites EN dans xcstrings
python3 -c "
import json
d = json.load(open('LifeOS/Localizable.xcstrings'))
total = len(d.get('strings', {}))
en_translated = sum(1 for k, v in d.get('strings', {}).items()
                    if v.get('localizations', {}).get('en', {}).get('stringUnit', {}).get('state') == 'translated')
print(f'{en_translated}/{total} clés traduites en EN')
"
```

## Décision produit

**Aujourd'hui** : sélecteur de langue disponible + honnêteté dans l'UI (le sheet EN prévient du mélange). Cohérence maximale = choisir "Français".

**Plus tard (phase 4 ou 5)** : extraction + traduction complète EN pour permettre "100% EN quand iPhone EN". Techniquement possible dès aujourd'hui, juste long.
