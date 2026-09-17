import SwiftUI

/// Éditeur d'un provider "custom" — création ou édition.
///
/// L'user renseigne :
///   - Nom affichable (ex: "Mon Ollama local")
///   - Dialecte (OpenAI-compatible ou Anthropic-compatible)
///   - URL base (ex: "http://192.168.1.10:11434/v1")
///   - Modèle (ex: "llama3.2:latest")
///   - Clé API (optionnelle pour endpoints locaux type Ollama)
///
/// Sauvegarde via `CustomProviderStore.shared`.
struct CustomProviderEditor: View {

    /// Config existante à éditer, ou `nil` pour création.
    let editing: CustomProviderStore.Config?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var dialect: CustomProviderStore.Dialect = .openaiCompatible
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var apiKey: String = ""
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex: Mon Ollama local)", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Nom d'affichage")
                } footer: {
                    Text("Ce nom apparaît dans la liste de tes coachs disponibles.")
                }

                Section {
                    Picker("Dialecte", selection: $dialect) {
                        ForEach(CustomProviderStore.Dialect.allCases, id: \.self) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exemples d'endpoints connus :")
                            .font(.caption.weight(.semibold))
                        ForEach(dialect.examples, id: \.self) { ex in
                            Text("· \(ex)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    TextField("URL base (ex: http://localhost:11434/v1)", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Nom du modèle (ex: llama3.2:latest)", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Endpoint")
                }

                Section {
                    SecureField(existingKeyMasked() ?? "Clé API (optionnelle pour Ollama local)",
                                text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Authentification")
                } footer: {
                    Text("La clé est stockée dans le Trousseau iOS et n'est envoyée qu'à ton URL. Laisse vide pour un endpoint qui n'exige pas d'auth.")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text(editing == nil ? "Ajouter ce provider" : "Enregistrer")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              baseURL.trimmingCharacters(in: .whitespaces).isEmpty ||
                              model.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDelete = true
                        } label: {
                            Text("Supprimer ce provider")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nouveau provider" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss(); onDismiss() }
                }
            }
            .onAppear(perform: loadIfEditing)
            .confirmationDialog("Supprimer ce provider ?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let c = editing {
                        CustomProviderStore.shared.delete(c.id)
                    }
                    dismiss()
                    onDismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private func loadIfEditing() {
        guard let c = editing else { return }
        name = c.name
        dialect = c.dialect
        baseURL = c.baseURL
        model = c.model
        // On ne pré-remplit pas la clé (SecureField), l'user peut la garder ou la remplacer.
    }

    private func existingKeyMasked() -> String? {
        guard let c = editing,
              let key = CustomProviderStore.shared.key(for: c),
              key.count >= 4 else { return nil }
        return "Clé enregistrée : ••••\(key.suffix(4))"
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)

        if var config = editing {
            config.name = trimmedName
            config.dialect = dialect
            config.baseURL = trimmedURL
            config.model = trimmedModel
            CustomProviderStore.shared.update(config)
            if !trimmedKey.isEmpty {
                CustomProviderStore.shared.setKey(trimmedKey, for: config)
            }
        } else {
            CustomProviderStore.shared.add(
                name: trimmedName,
                dialect: dialect,
                baseURL: trimmedURL,
                model: trimmedModel,
                apiKey: trimmedKey.isEmpty ? nil : trimmedKey
            )
        }

        dismiss()
        onDismiss()
    }
}
