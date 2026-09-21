import SwiftUI
import PhotosUI

/// Sauvegarde/chargement d'images dans le dossier Documents (garde-robe, photos avant/après, docs).
enum ImageStore {
    static var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// Ecrit l'image et rend son nom de fichier, ou nil si l'ecriture a rate.
    ///
    /// Avant, le nom etait rendu MEME quand l'ecriture echouait. L'appelant
    /// enregistrait donc une fiche qui pointe vers un fichier inexistant: le
    /// document etait perdu, la fiche restait, et l'ecran affichait une icone
    /// de remplacement pour toujours. Un disque plein suffisait.
    @discardableResult
    static func save(_ data: Data, prefix: String = "img") -> String? {
        let name = "\(prefix)-\(UUID().uuidString).jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name))
            return name
        } catch {
            AppLog.data.error("ImageStore save failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(filename).path)
    }

    static func loadAsync(_ filename: String?) async -> UIImage? {
        guard let filename else { return nil }
        let path = dir.appendingPathComponent(filename).path
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: path)
        }.value
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        do {
            try FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        } catch {
            AppLog.data.error("ImageStore delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Vue qui affiche une image stockée par nom de fichier, avec placeholder.
struct StoredImage: View {
    let filename: String?
    var placeholder: String = "photo"
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.bg2
                    Image(systemName: placeholder).font(.title).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .task(id: filename) {
            image = await ImageStore.loadAsync(filename)
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
        .task(id: selection) {
            guard let item = selection else { return }
            if let data = try? await item.loadTransferable(type: Data.self),
               let name = ImageStore.save(data, prefix: prefix) {
                onPicked(name)
            }
        }
    }
}
