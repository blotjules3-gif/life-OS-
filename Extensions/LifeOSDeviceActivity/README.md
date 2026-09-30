# Extension DeviceActivity (Opale)

Leve un blocage Opale a l'heure de fin, meme app fermee. Preparee, **pas dans le build**.

Pourquoi pas encore : l'extension et l'app demandent le droit `com.apple.developer.family-controls`
en distribution. Tant qu'Apple ne l'a pas accorde au compte, un profil TestFlight qui le
contient ne peut pas etre signe, et l'envoi echouerait.

## Le jour ou Apple accorde le droit

1. `LifeOS/LifeOS.entitlements` : ajouter `com.apple.developer.family-controls` = true.
2. Creer l'identifiant `com.chifandco.lifeos.DeviceActivity` (groupe d'apps
   `group.com.chifandco.lifeos`, capacite Family Controls) et son profil App Store.
3. Ajouter une cible "Device Activity Monitor Extension" avec ces 3 fichiers, l'embarquer
   dans l'app.
4. `ScreenTimeBlocker` : ecrire `screenBlock.end` aussi dans le groupe d'apps (l'extension
   le lit pour l'effacer). Le planning systeme est deja pose par `block()`.
5. Tester sur un vrai iPhone : bloquer 15 min, fermer LifeOS, attendre la fin, verifier
   que les apps se rouvrent ; relancer l'app ; retirer l'autorisation dans Reglages.
