import SwiftUI

// MARK: - Server Config Sheet (DEBUG only)
//
// Extrait d'`AIAssistantView.swift` pour réduire le God file.
// Outil de dev uniquement : en prod, l'URL et la clé API viennent de
// Config.xcconfig et ne doivent pas être modifiables depuis l'UI.

#if DEBUG
struct ServerConfigView: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = Configuration.apiBaseURL
    @State private var keyText = Configuration.apiKey
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL du serveur")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("http://192.168.1.x:8000", text: $urlText)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($urlFocused)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clé API")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SecureField("api-key", text: $keyText)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Connexion backend LifeOS")
                } footer: {
                    Text("Lance le serveur sur ton Mac puis entre son adresse IP locale (même réseau Wi-Fi). Exemple : http://192.168.1.7:8000")
                        .font(.caption)
                }

                Section {
                    Button("Utiliser l'adresse par défaut") {
                        urlText = "http://192.168.1.7:8000"
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Configurer le serveur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: "dev.apiBaseURL")
                        let trimmedKey = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(trimmedKey.isEmpty ? nil : trimmedKey, forKey: "dev.apiKey")
                        onSave()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { urlFocused = true }
        }
    }
}
#endif
