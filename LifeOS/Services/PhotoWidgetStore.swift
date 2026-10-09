import Foundation
import SwiftUI
import WidgetKit

/// Fichiers des widgets photo: logique pure, testee sans l'app.
enum PhotoWidgetFiles {
    /// Noms de fichiers references par au moins une configuration.
    static func referenced(by configs: [PhotoWidgetConfig]) -> Set<String> {
        Set(configs.flatMap { $0.photos.map(\.fileName) })
    }

    /// Fichiers du dossier que plus personne n'utilise (ni configuration enregistree,
    /// ni brouillon en cours d'edition).
    static func orphans(in fileNames: [String], referenced: Set<String>, protecting: Set<String> = []) -> [String] {
        fileNames.filter { !referenced.contains($0) && !protecting.contains($0) }
    }

    static func listImages(in dir: URL) -> [(name: String, size: Int64)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true else { return nil }
            return (u.lastPathComponent, Int64(v?.fileSize ?? 0))
        }
    }

    static func totalSize(in dir: URL) -> Int64 {
        listImages(in: dir).reduce(0) { $0 + $1.size }
    }

    /// Supprime les fichiers orphelins. Rend les noms supprimes.
    @discardableResult
    static func cleanup(directory dir: URL, referenced: Set<String>, protecting: Set<String> = []) -> [String] {
        let names = listImages(in: dir).map(\.name)
        var removed: [String] = []
        for name in orphans(in: names, referenced: referenced, protecting: protecting) {
            if (try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))) != nil { removed.append(name) }
        }
        return removed
    }

    static func newFileName() -> String { "pw-\(UUID().uuidString).jpg" }

    /// Copie independante: nouvel identifiant, nouveaux fichiers (supprimer l'une
    /// ne casse jamais l'autre). `copyFile(ancien, nouveau)` fait la copie sur disque.
    static func duplicate(_ c: PhotoWidgetConfig, now: Date = Date(), copyFile: (String, String) throws -> Void) rethrows -> PhotoWidgetConfig {
        var copy = c
        copy.id = UUID()
        copy.name = duplicateName(c.name)
        copy.createdAt = now
        copy.updatedAt = now
        copy.photos = try c.photos.map { ref in
            let newName = newFileName()
            try copyFile(ref.fileName, newName)
            return PhotoRef(fileName: newName, crop: ref.crop, inRotation: ref.inRotation)
        }
        return copy
    }

    static func duplicateName(_ name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Widget" : base) + " (copie)"
    }

    /// Retire une configuration. Rend la liste restante et les fichiers a effacer:
    /// seulement ceux qu'aucune autre configuration n'utilise.
    static func remove(_ id: UUID, from configs: [PhotoWidgetConfig]) -> (configs: [PhotoWidgetConfig], filesToDelete: [String]) {
        guard let target = configs.first(where: { $0.id == id }) else { return (configs, []) }
        let rest = configs.filter { $0.id != id }
        let stillUsed = referenced(by: rest)
        let files = target.photos.map(\.fileName).filter { !stillUsed.contains($0) }
        return (rest, Array(Set(files)).sorted())
    }

    /// Insere ou remplace (meme identifiant), sans changer l'ordre de la liste.
    static func upsert(_ c: PhotoWidgetConfig, into configs: [PhotoWidgetConfig]) -> [PhotoWidgetConfig] {
        var out = configs
        if let i = out.firstIndex(where: { $0.id == c.id }) { out[i] = c } else { out.append(c) }
        return out
    }
}

enum PhotoWidgetStoreError: LocalizedError {
    case noSharedContainer
    case cacheFull
    case notAnImage
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSharedContainer:
            return "Le dossier partagé avec les widgets est introuvable. Réinstalle LifeOS si le problème reste."
        case .cacheFull:
            return "L'espace des photos de widgets est plein (60 Mo). Retire des photos d'un widget ou supprime un widget."
        case .notAnImage:
            return "Cette photo n'a pas pu être lue."
        case .writeFailed(let why):
            return "Enregistrement impossible : \(why)"
        }
    }
}

/// Source de verite des widgets photo cote app. L'extension ne fait que lire.
@MainActor
final class PhotoWidgetStore: ObservableObject {
    static let shared = PhotoWidgetStore()

    @Published private(set) var configs: [PhotoWidgetConfig] = []

    /// Fichiers importes dans un brouillon pas encore enregistre: le nettoyage ne
    /// doit pas les effacer sous les pieds de l'editeur.
    private var pendingFiles: Set<String> = []
    /// Reloader injectable (tests).
    var reloadWidgets: () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetStorage.widgetKind) }

    init() { reload() }

    func reload() {
        configs = PhotoWidgetStorage.readIndex()
    }

    func config(id: UUID) -> PhotoWidgetConfig? { configs.first { $0.id == id } }

    // MARK: Ecriture

    func save(_ config: PhotoWidgetConfig) throws {
        var c = config
        c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.name.isEmpty { c.name = c.template.title }
        c.updatedAt = Date()
        let next = PhotoWidgetFiles.upsert(c, into: configs)
        try write(next)
        pendingFiles.subtract(c.photos.map(\.fileName))
        cleanup()
    }

    @discardableResult
    func duplicate(_ id: UUID) throws -> PhotoWidgetConfig {
        guard let source = config(id: id) else { throw PhotoWidgetStoreError.writeFailed("widget introuvable") }
        guard let dir = PhotoWidgetStorage.imagesDirectory else { throw PhotoWidgetStoreError.noSharedContainer }
        let extra = source.photos.reduce(Int64(0)) { sum, ref in
            let size = (try? dir.appendingPathComponent(ref.fileName).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
        if PhotoWidgetFiles.totalSize(in: dir) + extra > PhotoWidgetStorage.cacheCapBytes { throw PhotoWidgetStoreError.cacheFull }
        var created: [String] = []
        do {
            let copy = try PhotoWidgetFiles.duplicate(source) { old, new in
                try FileManager.default.copyItem(at: dir.appendingPathComponent(old), to: dir.appendingPathComponent(new))
                created.append(new)
            }
            try write(PhotoWidgetFiles.upsert(copy, into: configs))
            return copy
        } catch {
            for name in created { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
            throw (error as? PhotoWidgetStoreError) ?? PhotoWidgetStoreError.writeFailed(error.localizedDescription)
        }
    }

    func delete(_ id: UUID) throws {
        let result = PhotoWidgetFiles.remove(id, from: configs)
        try write(result.configs)
        if let dir = PhotoWidgetStorage.imagesDirectory {
            for name in result.filesToDelete { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        }
    }

    private func write(_ next: [PhotoWidgetConfig]) throws {
        do {
            try PhotoWidgetStorage.writeIndex(next)
        } catch {
            throw PhotoWidgetStoreError.writeFailed(error.localizedDescription)
        }
        configs = next
        reloadWidgets()
    }

    // MARK: Photos

    /// Reduit puis range les photos choisies. Le travail lourd (decodage, JPEG) se fait
    /// hors du fil principal. Rend une reference par photo lisible.
    func importPhotos(_ datas: [Data]) async throws -> [PhotoRef] {
        guard let dir = PhotoWidgetStorage.imagesDirectory else { throw PhotoWidgetStoreError.noSharedContainer }
        let jpegs: [Data?] = await Task.detached(priority: .userInitiated) {
            datas.map { PhotoWidgetImage.downsizedJPEG(from: $0) }
        }.value
        let readable = jpegs.compactMap { $0 }
        if readable.isEmpty && !datas.isEmpty { throw PhotoWidgetStoreError.notAnImage }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let incoming = readable.reduce(Int64(0)) { $0 + Int64($1.count) }
        if PhotoWidgetFiles.totalSize(in: dir) + incoming > PhotoWidgetStorage.cacheCapBytes {
            cleanup()
            if PhotoWidgetFiles.totalSize(in: dir) + incoming > PhotoWidgetStorage.cacheCapBytes { throw PhotoWidgetStoreError.cacheFull }
        }
        var refs: [PhotoRef] = []
        for data in readable {
            let name = PhotoWidgetFiles.newFileName()
            do {
                try data.write(to: dir.appendingPathComponent(name), options: .atomic)
                pendingFiles.insert(name)
                refs.append(PhotoRef(fileName: name))
            } catch {
                throw PhotoWidgetStoreError.writeFailed(error.localizedDescription)
            }
        }
        return refs
    }

    /// L'editeur a ete ferme sans enregistrer: ses photos importees partent.
    func discardDraftFiles(_ names: [String]) {
        let used = PhotoWidgetFiles.referenced(by: configs)
        guard let dir = PhotoWidgetStorage.imagesDirectory else { return }
        for name in names where !used.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            pendingFiles.remove(name)
        }
    }

    /// Efface les photos que plus rien n'utilise. Appele apres chaque enregistrement
    /// et a l'ouverture du studio (rattrape un brouillon abandonne par un arret force).
    @discardableResult
    func cleanup() -> [String] {
        guard let dir = PhotoWidgetStorage.imagesDirectory else { return [] }
        return PhotoWidgetFiles.cleanup(directory: dir, referenced: PhotoWidgetFiles.referenced(by: configs), protecting: pendingFiles)
    }

    var usedBytes: Int64 {
        guard let dir = PhotoWidgetStorage.imagesDirectory else { return 0 }
        return PhotoWidgetFiles.totalSize(in: dir)
    }
}
