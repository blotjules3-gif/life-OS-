import SwiftUI
import PhotosUI
import Vision
import UIKit

// MARK: - Analyse faciale objective (Apple Vision, on-device, gratuit)
// Mesures géométriques neutres — PAS un score d'attractivité (non scientifique).

struct FaceMetric: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String       // valeur lisible (ratio, %)
    let score: Int          // 0–100 : proximité d'une référence classique
    let note: String
}

enum FaceAnalyzer {
    /// Renvoie la liste de métriques, ou nil si aucun visage net détecté.
    static func analyze(_ image: UIImage) async -> [FaceMetric]? {
        guard let cg = image.cgImage else { return nil }
        let orientation = cgOrientation(image.imageOrientation)
        return await withCheckedContinuation { cont in
            let request = VNDetectFaceLandmarksRequest { req, _ in
                guard let face = (req.results as? [VNFaceObservation])?
                    .max(by: { $0.boundingBox.area < $1.boundingBox.area }),
                      let lm = face.landmarks else { cont.resume(returning: nil); return }
                cont.resume(returning: compute(lm))
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
        }
    }

    // Toutes les coordonnées via normalizedPoints (0..1 dans la bbox du visage).
    private static func compute(_ lm: VNFaceLandmarks2D) -> [FaceMetric]? {
        guard let contour = lm.faceContour?.normalizedPoints, contour.count > 2 else { return nil }
        let xs = contour.map { $0.x }, ys = contour.map { $0.y }
        let faceW = (xs.max()! - xs.min()!)
        let faceH = (ys.max()! - ys.min()!)
        guard faceW > 0.01, faceH > 0.01 else { return nil }

        var metrics: [FaceMetric] = []

        // 1) Symétrie : alignement gauche/droite des yeux + sourcils autour de l'axe médian
        if let le = center(lm.leftEye?.normalizedPoints), let re = center(lm.rightEye?.normalizedPoints) {
            let midX = (le.x + re.x) / 2
            let dxL = abs(le.x - midX), dxR = abs(re.x - midX)
            let horiz = abs(dxL - dxR) / faceW                 // écart d'écartement
            let vert = abs(le.y - re.y) / faceH                // dénivelé des yeux
            var browDev: CGFloat = 0
            if let lb = center(lm.leftEyebrow?.normalizedPoints),
               let rb = center(lm.rightEyebrow?.normalizedPoints) {
                browDev = abs(lb.y - rb.y) / faceH
            }
            let deviation = (horiz + vert + browDev) / 3
            let score = clampScore(100 - Double(deviation) * 600)
            metrics.append(.init(icon: "rectangle.portrait.and.arrow.right",
                                 title: "Symétrie",
                                 value: "\(score)/100", score: score,
                                 note: score >= 80 ? "Traits bien alignés" : "Léger déséquilibre G/D — normal, tout le monde en a"))
        }

        // 2) Écartement des yeux : distance inter-oculaire / largeur du visage (réf ≈ 0.46)
        if let le = center(lm.leftEye?.normalizedPoints), let re = center(lm.rightEye?.normalizedPoints) {
            let ratio = Double(abs(le.x - re.x) / faceW)
            let score = closeness(ratio, ideal: 0.46, tol: 0.14)
            metrics.append(.init(icon: "eye",
                                 title: "Écartement des yeux",
                                 value: String(format: "%.2f", ratio), score: score,
                                 note: "Réf. classique ≈ 0,46 (un œil entre les deux)"))
        }

        // 3) Règle des tiers : milieu (sourcils→base du nez) vs bas (base du nez→menton)
        if let brow = avgY(lm.leftEyebrow?.normalizedPoints, lm.rightEyebrow?.normalizedPoints),
           let noseBase = lm.nose?.normalizedPoints.map({ $0.y }).min(),
           let chin = ys.min() {
            let mid = abs(brow - noseBase)
            let lower = abs(noseBase - chin)
            if mid > 0.01, lower > 0.01 {
                let ratio = Double(mid / lower)
                let score = closeness(ratio, ideal: 1.0, tol: 0.4)
                metrics.append(.init(icon: "ruler",
                                     title: "Règle des tiers",
                                     value: String(format: "%.2f", ratio), score: score,
                                     note: "Équilibre milieu / bas du visage (réf ≈ 1,0)"))
            }
        }

        // 4) FWHR : largeur bizygomatique / hauteur (sourcils→lèvre haute)
        if let brow = avgY(lm.leftEyebrow?.normalizedPoints, lm.rightEyebrow?.normalizedPoints),
           let lipTop = lm.outerLips?.normalizedPoints.map({ $0.y }).max() {
            let upperH = abs(brow - lipTop)
            if upperH > 0.01 {
                let fwhr = Double(faceW / upperH)
                let score = closeness(fwhr, ideal: 1.9, tol: 0.6)
                metrics.append(.init(icon: "square",
                                     title: "Ratio largeur/hauteur (FWHR)",
                                     value: String(format: "%.2f", fwhr), score: score,
                                     note: "Typique 1,7–2,1"))
            }
        }

        return metrics.isEmpty ? nil : metrics
    }

    // MARK: helpers
    private static func center(_ pts: [CGPoint]?) -> CGPoint? {
        guard let pts, !pts.isEmpty else { return nil }
        let sx = pts.reduce(0) { $0 + $1.x }, sy = pts.reduce(0) { $0 + $1.y }
        return CGPoint(x: sx / CGFloat(pts.count), y: sy / CGFloat(pts.count))
    }
    private static func avgY(_ a: [CGPoint]?, _ b: [CGPoint]?) -> CGFloat? {
        let ca = center(a), cb = center(b)
        switch (ca, cb) {
        case let (x?, y?): return (x.y + y.y) / 2
        case let (x?, nil): return x.y
        case let (nil, y?): return y.y
        default: return nil
        }
    }
    private static func closeness(_ v: Double, ideal: Double, tol: Double) -> Int {
        clampScore(100 - abs(v - ideal) / tol * 100)
    }
    private static func clampScore(_ d: Double) -> Int { max(0, min(100, Int(d.rounded()))) }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up; case .down: return .down
        case .left: return .left; case .right: return .right
        case .upMirrored: return .upMirrored; case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored; case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private extension CGRect { var area: CGFloat { width * height } }

// MARK: - Vue

struct FaceAnalysisView: View {
    @State private var image: UIImage?
    @State private var metrics: [FaceMetric]?
    @State private var busy = false
    @State private var noFace = false
    @State private var pickerItem: PhotosPickerItem?

    private var overall: Int {
        guard let m = metrics, !m.isEmpty else { return 0 }
        return Int((Double(m.reduce(0) { $0 + $1.score }) / Double(m.count)).rounded())
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(image == nil ? "Choisir un portrait" : "Changer de photo",
                              systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.looksTint.gradient, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white).font(.headline)
                    }
                    if busy { ProgressView("Analyse des points du visage…").padding() }
                    if noFace { errorCard }
                    if let m = metrics, !busy { results(m) }
                    if image == nil && !busy { intro }
                    disclaimer
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Analyse faciale").navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await run(img)
                }
            }
        }
    }

    private var preview: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "face.dashed").font(.system(size: 54)).foregroundStyle(.looksTint)
                    Text("Photo de face, bien éclairée").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mesures objectives, sur ton iPhone").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Vision détecte les points de ton visage et calcule des ratios géométriques neutres (symétrie, écartement des yeux, règle des tiers, FWHR). Aucune photo ne quitte l'appareil.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var errorCard: some View {
        Label("Aucun visage net détecté. Essaie une photo de face, bien éclairée, sans lunettes.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func results(_ m: [FaceMetric]) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Harmonie géométrique").font(.caption).foregroundStyle(Theme.textSecondary)
                Text("\(overall)").font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.looksTint)
                Text("indicatif — géométrie, pas un jugement").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))

            ForEach(m) { metric in metricRow(metric) }
        }
    }

    private func metricRow(_ m: FaceMetric) -> some View {
        HStack(spacing: 14) {
            Image(systemName: m.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.looksTint.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(m.value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.looksTint)
                }
                ProgressView(value: Double(m.score), total: 100).tint(.looksTint)
                Text(m.note).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var disclaimer: some View {
        Text("Les ratios faciaux « idéaux » sont des conventions, pas une vérité. Cet outil mesure de la géométrie, il ne note pas une personne.")
            .font(.caption2).foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center).padding(.top, 4)
    }

    private func run(_ img: UIImage) async {
        await MainActor.run { image = img; metrics = nil; noFace = false; busy = true }
        let result = await FaceAnalyzer.analyze(img)
        await MainActor.run {
            busy = false
            if let result { metrics = result } else { noFace = true }
            Haptics.soft()
        }
    }
}
