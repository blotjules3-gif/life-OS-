import DeviceActivity
import ManagedSettings
import Foundation

/// Extension DeviceActivity d'Opale : leve le blocage a l'heure de fin, app fermee.
///
/// PAS encore dans le build : elle demande le droit Apple "Family Controls"
/// (distribution), comme l'app. Voir README.md de ce dossier pour l'activer.
/// Les noms doivent rester identiques a `ScreenTimeBlocker.storeName` et
/// `ScreenTimeBlocker.endKey` (UserDefaults du groupe d'apps).
final class LifeOSDeviceActivityMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .init("lifeos.focus"))
    private let group = UserDefaults(suiteName: "group.com.chifandco.lifeos")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue == "lifeos.focus" else { return }
        store.clearAllSettings()
        group?.removeObject(forKey: "screenBlock.end")
    }
}
