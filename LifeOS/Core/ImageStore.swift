import SwiftUI
import PhotosUI

/// Sauvegarde/chargement d'images dans le dossier Documents (garde-robe, photos avant/après, docs).
enum ImageStore {
    static var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    @discardableResult
    static func save(_ data: Data, prefix: String = "img") -> String {
        let name = "\(prefix)-\(UUID().uuidString).jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name))
        } catch {
            print("[ImageStore] save failed: \(error)")
        }
        return name
    }

    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(filename).path)
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        do {
            try FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        } catch {
            print("[ImageStore] delete failed: \(error)")
        }
    }
}

/// Vue qui affiche une image stockée par nom de fichier, avec placeholder.
struct StoredImage: View {
    let filename: String?
    var placeholder: String = "photo"
    var body: some View {
        if let img = ImageStore.load(filename) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.bg2
                Image(systemName: placeholder).font(.title).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Bouton + PhotosPicker qui renvoie le nom de fichier sauvegardé.
struct PhotoPickerButton: View {
    let label: String
    var prefix: String = "img"
    let onPicked: (String) -> Void
    @State private var selection: PhotosPickerItem?
    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Label(label, systemImage: "photo.badge.plus")
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let name = ImageStore.save(data, prefix: prefix)
                    await MainActor.run { onPicked(name) }
                }
            }
        }
    }
}
