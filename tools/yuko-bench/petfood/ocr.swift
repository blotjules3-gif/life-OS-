// Meme lecture que PetLabelReader (LifeOS/Services/PetEnrichment.swift), sur Mac :
// photo redressee et ramenee a 2 400 px (prepared), puis Vision, memes reglages.
// Usage : swift ocr.swift photo.jpg
import Vision
import ImageIO
import Foundation
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let src = CGImageSourceCreateWithData(data as CFData, nil)!
let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                             kCGImageSourceCreateThumbnailWithTransform: true,
                             kCGImageSourceThumbnailMaxPixelSize: 2400]
let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)!
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
req.recognitionLanguages = ["fr-FR", "en-US", "de-DE", "es-ES", "it-IT", "nl-NL"]
try! VNImageRequestHandler(cgImage: img).perform([req])
let lines = (req.results ?? []).sorted { a, b in
    abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01 ? a.boundingBox.midY > b.boundingBox.midY : a.boundingBox.minX < b.boundingBox.minX
}.compactMap { $0.topCandidates(1).first?.string }
print(lines.joined(separator: " "))
