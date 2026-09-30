import UIKit
import Vision
import CoreImage
import CryptoKit

/// Photo produit "packshot": le produit seul, sur fond blanc, cadre serre.
///
/// Open Food Facts ne donne un packshot officiel que quand la MARQUE a depose sa
/// photo (compte producteur). Sinon la photo vient d'un client, prise en magasin
/// ou sur une table. On detoure alors le produit sur l'appareil (Vision, sans
/// serveur ni envoi de la photo) et on le pose sur du blanc. Si le detourage
/// echoue, la photo d'origine est gardee telle quelle: jamais une image vide.
enum ProductPhoto {
    private static let context = CIContext()

    /// Produit detoure sur blanc, carre, avec une marge. nil si Vision ne trouve pas
    /// de sujet (ou n'est pas disponible, comme dans certains simulateurs).
    static func onWhite(_ image: UIImage, margin: CGFloat = 0.08) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first, !obs.allInstances.isEmpty,
              let mask = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler),
              let box = subjectBounds(mask) else { return nil }
        let maskImage = CIImage(cvPixelBuffer: mask)
        let white = CIImage(color: .white).cropped(to: input.extent)
        let cut = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: white, kCIInputMaskImageKey: maskImage])

        // Cadre carre autour du sujet (repere Core Image: origine en bas a gauche).
        let flipped = CGRect(x: box.minX, y: input.extent.height - box.maxY, width: box.width, height: box.height)
        let side = max(flipped.width, flipped.height) * (1 + 2 * margin)
        let square = CGRect(x: flipped.midX - side / 2, y: flipped.midY - side / 2, width: side, height: side)
        let canvas = cut.composited(over: CIImage(color: .white).cropped(to: square)).cropped(to: square)
        guard let out = context.createCGImage(canvas, from: square) else { return nil }
        return UIImage(cgImage: out)
    }

    /// Rectangle des pixels du sujet dans le masque (repere image: origine en haut).
    static func subjectBounds(_ mask: CVPixelBuffer, threshold: Float = 0.5) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask),
              CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float else { return nil }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        let row = CVPixelBufferGetBytesPerRow(mask)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<w where line[x] >= threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: Cache disque des photos traitees

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ProductPhotos", isDirectory: true)
    }

    static func cacheURL(for source: URL) -> URL {
        let digest = SHA256.hash(data: Data(source.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(digest + ".jpg")
    }

    static func cached(_ source: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: cacheURL(for: source)) else { return nil }
        return UIImage(data: data)
    }

    static func store(_ image: UIImage, for source: URL) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if let data = image.jpegData(compressionQuality: 0.88) { try? data.write(to: cacheURL(for: source), options: .atomic) }
    }
}
