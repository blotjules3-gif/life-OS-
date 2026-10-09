import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

// Ou vivent les widgets photo, et comment on lit leurs images sans exploser la
// memoire de l'extension (environ 30 Mo au total).
//
// Disposition dans le groupe d'apps:
//   PhotoWidgets/index.json        toutes les configurations (ecrit par l'app seule)
//   PhotoWidgets/images/<nom>.jpg  photos deja reduites a 1000 px de cote maximum
//
// L'app ecrit, l'extension lit. Ecriture atomique (fichier temporaire + renommage):
// l'extension ne peut jamais lire un index a moitie ecrit.

enum PhotoWidgetStorage {
    /// Remplacable dans les tests.
    nonisolated(unsafe) static var rootOverride: URL?

    static let widgetKind = "PhotoWidget"
    /// Cote maximum d'une photo stockee.
    static let maxStoredPixel: CGFloat = 1000
    static let jpegQuality: CGFloat = 0.8
    /// Plafond de l'espace occupe par les photos des widgets.
    static let cacheCapBytes: Int64 = 60 * 1024 * 1024

    static var root: URL? {
        if let rootOverride { return rootOverride }
        return LifeOSGroup.container?.appendingPathComponent("PhotoWidgets", isDirectory: true)
    }
    static var indexURL: URL? { root?.appendingPathComponent("index.json") }
    static var imagesDirectory: URL? { root?.appendingPathComponent("images", isDirectory: true) }

    static func imageURL(_ fileName: String) -> URL? {
        // Un nom ne doit jamais sortir du dossier (pas de "../").
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.hasPrefix(".") else { return nil }
        return imagesDirectory?.appendingPathComponent(fileName)
    }

    private struct IndexFile: Codable {
        var version = 1
        var configs: [PhotoWidgetConfig]
    }

    /// Configurations enregistrees. Fichier absent = aucune. Fichier illisible = aucune
    /// aussi, mais il est garde de cote (index.json.bad) pour ne rien perdre.
    static func readIndex() -> [PhotoWidgetConfig] {
        guard let url = indexURL, let data = try? Data(contentsOf: url) else { return [] }
        return decodeIndex(data) ?? []
    }

    static func decodeIndex(_ data: Data) -> [PhotoWidgetConfig]? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(IndexFile.self, from: data))?.configs
    }

    static func encodeIndex(_ configs: [PhotoWidgetConfig]) throws -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(IndexFile(configs: configs))
    }

    static func writeIndex(_ configs: [PhotoWidgetConfig]) throws {
        guard let root, let url = indexURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encodeIndex(configs).write(to: url, options: .atomic)
    }

    static func config(id: UUID) -> PhotoWidgetConfig? {
        readIndex().first { $0.id == id }
    }
}

// MARK: - Choix du widget (requete de l'entite, testee sans WidgetKit)

struct PhotoWidgetSummary: Hashable, Identifiable {
    let id: UUID
    let name: String
    let template: PhotoWidgetTemplate
}

enum PhotoWidgetIndexQuery {
    static func summaries(_ configs: [PhotoWidgetConfig]) -> [PhotoWidgetSummary] {
        configs.map { PhotoWidgetSummary(id: $0.id, name: $0.name, template: $0.template) }
    }

    /// Entites demandees par identifiant. Un identifiant supprime ne revient pas:
    /// le widget qui le portait affiche alors son etat "supprime".
    static func entities(for ids: [UUID], in configs: [PhotoWidgetConfig]) -> [PhotoWidgetSummary] {
        let byID = Dictionary(configs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }.map { PhotoWidgetSummary(id: $0.id, name: $0.name, template: $0.template) }
    }

    /// Recherche par nom (insensible a la casse et aux accents).
    static func matching(_ text: String, in configs: [PhotoWidgetConfig]) -> [PhotoWidgetSummary] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return summaries(configs) }
        return summaries(configs.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
    }

    /// Ceux proposes a l'ecran de verrouillage: seulement les modeles a texte.
    static func lockScreenSummaries(_ configs: [PhotoWidgetConfig]) -> [PhotoWidgetSummary] {
        summaries(configs.filter { $0.template.supportsLockScreen })
    }
}

// MARK: - Images

enum PhotoWidgetImage {
    /// Image reduite par ImageIO: le fichier n'est jamais decode en pleine taille.
    /// L'orientation EXIF est appliquee.
    static func downsampled(at url: URL, maxPixel: CGFloat) -> CGImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        return thumbnail(src, maxPixel: maxPixel)
    }

    static func downsampled(data: Data, maxPixel: CGFloat) -> CGImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        return thumbnail(src, maxPixel: maxPixel)
    }

    private static func thumbnail(_ src: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixel))
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Photo choisie -> JPEG reduit (cote max `maxPixel`). nil si ce n'est pas une image.
    static func downsizedJPEG(from data: Data, maxPixel: CGFloat = PhotoWidgetStorage.maxStoredPixel,
                              quality: CGFloat = PhotoWidgetStorage.jpegQuality) -> Data? {
        guard let cg = downsampled(data: data, maxPixel: maxPixel) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Taille en pixels d'une image encodee, sans la decoder.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }

    static func cropped(_ image: CGImage, to crop: PhotoCrop) -> CGImage {
        guard !crop.isFull else { return image }
        let rect = crop.pixelRect(width: image.width, height: image.height)
        return image.cropping(to: rect) ?? image
    }

    #if canImport(UIKit)
    /// Photo prete a afficher: lue reduite (`maxPixel`), puis recadree.
    static func load(_ ref: PhotoRef, maxPixel: CGFloat) -> UIImage? {
        guard let url = PhotoWidgetStorage.imageURL(ref.fileName),
              let cg = downsampled(at: url, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: cropped(cg, to: ref.crop))
    }
    #endif
}

// MARK: - Polices

enum PhotoWidgetFonts {
    /// Enregistre les polices livrees avec la cible courante (l'extension a sa propre
    /// copie de Satoshi et Inter). Sans effet si elles le sont deja.
    private static let registerOnce: Void = {
        let names = ["Satoshi-Regular", "Satoshi-Medium", "Satoshi-Bold", "Satoshi-Black", "Inter-Regular", "Inter-Bold"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func register() { _ = registerOnce }

    static func postScriptName(_ family: PhotoWidgetFontFamily, _ weight: PhotoWidgetFontWeight) -> String? {
        switch family {
        case .satoshi:
            switch weight {
            case .regular: return "Satoshi-Regular"
            case .medium: return "Satoshi-Medium"
            case .semibold, .bold: return "Satoshi-Bold"
            case .black: return "Satoshi-Black"
            }
        case .inter:
            switch weight {
            case .regular, .medium: return "Inter-Regular"
            case .semibold, .bold, .black: return "Inter-Bold"
            }
        default:
            return nil
        }
    }

    /// Police a une taille donnee. Une police absente retombe sur celle du systeme,
    /// jamais sur un texte invisible.
    static func font(_ family: PhotoWidgetFontFamily, weight: PhotoWidgetFontWeight, size: CGFloat) -> Font {
        register()
        if let name = postScriptName(family, weight) {
            #if canImport(UIKit)
            if UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
            #endif
            return .system(size: size, weight: weight.fontWeight)
        }
        let design: Font.Design
        switch family {
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        default: design = .default
        }
        return .system(size: size, weight: weight.fontWeight, design: design)
    }
}
