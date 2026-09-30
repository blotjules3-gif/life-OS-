import Foundation
import Vision
import AppKit
// Classement Apple Vision (le meme que l'app sans cle), 8 premiers labels par photo.
let dir = CommandLine.arguments[1]
for f in try! FileManager.default.contentsOfDirectory(atPath: dir).sorted() where f.hasSuffix(".jpg") {
    guard let img = NSImage(contentsOfFile: dir + "/" + f), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let req = VNClassifyImageRequest()
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    let top = (req.results ?? []).filter { $0.confidence > 0.05 }.prefix(8).map { "\($0.identifier) \(Int($0.confidence * 100))%" }
    print(f.replacingOccurrences(of: ".jpg", with: ""), "|", top.joined(separator: ", "))
}
