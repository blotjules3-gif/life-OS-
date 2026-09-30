import UIKit

/// Fabrique UN fichier PDF a partir des pages d'un document.
///
/// Avant, "Exporter" partageait les pages comme images separees: un contrat de
/// cinq pages arrivait en cinq JPEG. Ici: une page PDF par image, format A4,
/// image entiere et proportions gardees, dans l'ordre donne.
enum DocumentPDF {

    enum Failure: LocalizedError, Equatable {
        case noPages
        case writeFailed
        var errorDescription: String? {
            switch self {
            case .noPages: return "Ce document n'a aucune page à exporter."
            case .writeFailed: return "Le PDF n'a pas pu être créé. Réessaie."
            }
        }
    }

    /// A4 en points PDF.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 18

    static func data(pages: [UIImage]) throws -> Data {
        guard !pages.isEmpty else { throw Failure.noPages }
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            for img in pages {
                ctx.beginPage()
                let box = bounds.insetBy(dx: margin, dy: margin)
                img.draw(in: fit(img.size, in: box))
            }
        }
    }

    /// Ecrit le PDF dans un dossier temporaire, avec un nom lisible.
    static func write(pages: [UIImage], title: String) throws -> URL {
        let d = try data(pages: pages)
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-").trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((safe.isEmpty ? "Document" : safe) + ".pdf")
        do { try d.write(to: url, options: .atomic) } catch { throw Failure.writeFailed }
        return url
    }

    /// Rectangle qui contient l'image entiere, centre, sans deformation.
    static func fit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}

extension UIImage {
    /// Tourne de 90 degres dans le sens horaire (redessine les pixels, pour que
    /// l'OCR et le PDF voient bien la page droite).
    func rotatedClockwise() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: newSize, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
