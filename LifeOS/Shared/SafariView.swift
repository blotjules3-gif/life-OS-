import SwiftUI
import SafariServices

/// Wrapper SwiftUI pour `SFSafariViewController`.
///
/// Ouvre une URL dans un Safari embarqué dans LifeOS — l'utilisateur ne quitte
/// pas l'app. Idéal pour aller récupérer une clé API sur un site externe
/// sans casser le contexte (moins de friction, retour instantané avec le bouton
/// "Fermer" natif).
///
/// Utilisation :
///   .sheet(isPresented: $showSafari) {
///       SafariView(url: URL(string: "https://openrouter.ai/keys")!)
///           .ignoresSafeArea()
///   }
struct SafariView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(named: "AccentColor")
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // Rien — URL non mutable
    }
}
