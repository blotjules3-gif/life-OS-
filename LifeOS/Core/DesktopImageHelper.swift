import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PDFKit

// MARK: - Helper pour sélection & glisser-déposer de fichiers images sur Desktop

enum DesktopImageHelper {
    /// Charge TOUTES les pages d'un document depuis une URL de fichier.
    ///
    /// Un PDF importe sur le bureau ne rendait que sa page 0, exactement le meme defaut
    /// que le scanner du telephone : un contrat de cinq pages entrait dans l'app comme
    /// une seule, sans message. Une image simple rend un tableau d'un element.
    static func loadPages(from url: URL) -> [UIImage] {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return [image]
        }
        guard let pdfDoc = PDFDocument(url: url), pdfDoc.pageCount > 0 else { return [] }
        return (0..<pdfDoc.pageCount).compactMap { index in
            guard let page = pdfDoc.page(at: index) else { return nil }
            let pageRect = page.bounds(for: .mediaBox)
            return UIGraphicsImageRenderer(size: pageRect.size).image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
        }
    }

    /// Premiere page seulement. Conserve pour les usages ou une vignette suffit ;
    /// pour importer un document, utiliser `loadPages`.
    static func loadImage(from url: URL) -> UIImage? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // 1. Essai direct UIImage
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }

        // 2. Si c'est un PDF, rendu de la première page
        if let pdfDoc = PDFDocument(url: url), let page = pdfDoc.page(at: 0) {
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            return image
        }

        return nil
    }

    /// Charge les données brutes (Data) depuis une URL sécurisée.
    static func loadData(from url: URL) -> Data? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? Data(contentsOf: url)
    }
}

// MARK: - Modifieur Drag & Drop d'images depuis le Finder

struct DesktopImageDropModifier: ViewModifier {
    let onImageDropped: (UIImage) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8]))
                        .background(Color.accentColor.opacity(0.08))
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.image.identifier, UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }

                // 1. Image directe
                if provider.canLoadObject(ofClass: UIImage.self) {
                    _ = provider.loadObject(ofClass: UIImage.self) { item, _ in
                        if let img = item as? UIImage {
                            DispatchQueue.main.async {
                                onImageDropped(img)
                            }
                        }
                    }
                    return true
                }

                // 2. Fichier glissé depuis le Finder (URL de fichier)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        var targetURL: URL?

                        if let url = item as? URL {
                            targetURL = url
                        } else if let data = item as? Data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil) {
                            targetURL = url
                        }

                        if let targetURL, let image = DesktopImageHelper.loadImage(from: targetURL) {
                            DispatchQueue.main.async {
                                onImageDropped(image)
                            }
                        }
                    }
                    return true
                }

                return false
            }
    }
}

extension View {
    /// Permet de glisser-déposer une image depuis le Finder directement sur la vue.
    func onDesktopImageDrop(perform action: @escaping (UIImage) -> Void) -> some View {
        modifier(DesktopImageDropModifier(onImageDropped: action))
    }
}
