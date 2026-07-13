import SwiftUI
@preconcurrency import Vision
import PhotosUI
import UIKit

// MARK: - Illustrations dessinées des TYPES DE PEAU (gros plan schématique)
// Faute de pouvoir embarquer des photos libres de droits, on illustre chaque type
// par un rendu de peau dessiné (teinte + texture + brillance) qui reste parlant.

struct SkinTypeArt: View {
    let type: String
    var body: some View {
        ZStack {
            base
            texture
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private var skinTone: Color { Color(hex: 0xE8C4A8) }

    private var base: some View {
        LinearGradient(colors: [skinTone.opacity(0.95), skinTone.opacity(0.75)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder private var texture: some View {
        switch type {
        case "Grasse":
            // reflets brillants (sébum)
            Canvas { ctx, size in
                for p in shineSpots(size) {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 14, height: 9)),
                             with: .color(.white.opacity(0.5)))
                }
            }
            .blur(radius: 3)
        case "Sèche":
            // fines craquelures / desquamation
            Canvas { ctx, size in
                for l in flakeLines(size) {
                    var path = Path(); path.move(to: l.0); path.addLine(to: l.1)
                    ctx.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
                }
            }
        case "Mixte":
            // zone T brillante au centre, joues mates
            HStack(spacing: 0) {
                Color.clear.frame(maxWidth: .infinity)
                LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .center, endPoint: .bottom)
                    .frame(width: 60).blur(radius: 6)
                Color.clear.frame(maxWidth: .infinity)
            }
        case "Sensible":
            // rougeurs diffuses
            Canvas { ctx, size in
                for p in shineSpots(size) {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 22, height: 16)),
                             with: .color(Color(hex: 0xD8564E).opacity(0.28)))
                }
            }
            .blur(radius: 7)
        default:
            // Normale : grain fin, teint uniforme
            Canvas { ctx, size in
                for p in poreDots(size) {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.6, height: 1.6)),
                             with: .color(.black.opacity(0.06)))
                }
            }
        }
    }

    private func shineSpots(_ s: CGSize) -> [CGPoint] {
        let w = max(1, Int(s.width)), h = max(1, Int(s.height))
        var pts: [CGPoint] = []
        for i in 0..<10 {
            let x = CGFloat((i * 73) % w)
            let y = CGFloat((i * 41) % h)
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }
    private func flakeLines(_ s: CGSize) -> [(CGPoint, CGPoint)] {
        let w = max(1, Int(s.width)), h = max(1, Int(s.height))
        var out: [(CGPoint, CGPoint)] = []
        for i in 0..<26 {
            let x = CGFloat((i * 37) % w)
            let y = CGFloat((i * 53) % h)
            out.append((CGPoint(x: x, y: y), CGPoint(x: x + 8, y: y + 3)))
        }
        return out
    }
    private func poreDots(_ s: CGSize) -> [CGPoint] {
        let w = max(1, Int(s.width)), h = max(1, Int(s.height))
        var pts: [CGPoint] = []
        for i in 0..<120 {
            let x = CGFloat((i * 17) % w)
            let y = CGFloat((i * 29) % h)
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }
}

/// Carte de sélection illustrée (type de peau) : dessin + libellé + description.
struct SkinTypeCard: View {
    let type: String
    let desc: String
    let selected: Bool
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkinTypeArt(type: type)
            Text(type).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(desc).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(selected ? accent : Color.clear, lineWidth: 2.5))
    }
}

// MARK: - FORME DU VISAGE + recommandations

enum FaceShape: String, CaseIterable {
    case ovale = "Ovale", ronde = "Ronde", carree = "Carrée"
    case allongee = "Allongée", coeur = "Cœur", losange = "Losange"

    var summary: String {
        switch self {
        case .ovale:    return "Proportions équilibrées — la forme la plus polyvalente."
        case .ronde:    return "Largeur ≈ hauteur, joues pleines, angles doux."
        case .carree:   return "Mâchoire marquée et angulaire, front large."
        case .allongee: return "Visage plus long que large, front haut."
        case .coeur:    return "Front large qui s'affine vers un menton pointu."
        case .losange:  return "Pommettes larges, front et mâchoire plus étroits."
        }
    }
    /// Coupes de cheveux qui mettent en valeur cette forme.
    var haircuts: [String] {
        switch self {
        case .ovale:    return ["Presque tout marche", "Fringe / frange texturée", "Mi-long dégradé", "Buzz/crop net"]
        case .ronde:    return ["Volume sur le dessus, côtés courts", "Quiff / pompadour (allonge)", "Éviter les coupes rondes/bol"]
        case .carree:   return ["Crop texturé", "Côtés fondus (fade)", "Adoucir avec du flou", "Éviter les carrés rigides"]
        case .allongee: return ["Frange pour raccourcir le front", "Côtés plus fournis", "Éviter trop de volume au sommet"]
        case .coeur:    return ["Longueur/texture au niveau de la mâchoire", "Frange latérale", "Éviter le volume au sommet"]
        case .losange:  return ["Frange + volume au front", "Un peu de barbe pour élargir la mâchoire", "Côtés pas trop courts"]
        }
    }
    var beard: String {
        switch self {
        case .ovale:    return "Barbe courte et nette, longueur uniforme."
        case .ronde:    return "Barbe plus fournie au menton pour allonger."
        case .carree:   return "Barbe courte qui suit la ligne — garde les angles."
        case .allongee: return "Barbe sur les joues, courte au menton (élargit)."
        case .coeur:    return "Barbe fournie au menton pour équilibrer le front."
        case .losange:  return "Barbe pleine à la mâchoire pour l'élargir."
        }
    }
}

struct FaceAnalysis { let shape: FaceShape; let confidence: Double; let ratio: Double; let notes: [String] }

/// Silhouette dessinée de la forme du visage.
struct FaceShapeArt: View {
    let shape: FaceShape
    var color: Color = Theme.textPrimary
    var body: some View {
        Path { p in
            let r = CGRect(x: 12, y: 6, width: 76, height: 100)
            switch shape {
            case .ovale:    p.addEllipse(in: CGRect(x: 22, y: 4, width: 56, height: 104))
            case .ronde:    p.addEllipse(in: CGRect(x: 14, y: 12, width: 72, height: 88))
            case .carree:   p.addRoundedRect(in: CGRect(x: 16, y: 8, width: 68, height: 96), cornerSize: CGSize(width: 16, height: 16))
            case .allongee: p.addEllipse(in: CGRect(x: 28, y: 2, width: 44, height: 108))
            case .coeur:
                p.move(to: CGPoint(x: 18, y: 26)); p.addQuadCurve(to: CGPoint(x: 82, y: 26), control: CGPoint(x: 50, y: 2))
                p.addQuadCurve(to: CGPoint(x: 50, y: 108), control: CGPoint(x: 86, y: 78))
                p.addQuadCurve(to: CGPoint(x: 18, y: 26), control: CGPoint(x: 14, y: 78))
            case .losange:
                p.move(to: CGPoint(x: 50, y: 2)); p.addLine(to: CGPoint(x: 86, y: 55))
                p.addLine(to: CGPoint(x: 50, y: 110)); p.addLine(to: CGPoint(x: 14, y: 55)); p.closeSubpath()
                _ = r
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        .frame(width: 100, height: 114)
    }
}

// MARK: - Analyse ON-DEVICE de la forme du visage (Vision)

enum FaceShapeAnalyzer {
    static func analyze(_ image: UIImage) async -> FaceAnalysis? {
        guard let cg = image.cgImage else { return nil }
        let orientation = cgOrientation(image.imageOrientation)
        return await withCheckedContinuation { cont in
            let req = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([req])
                guard let face = req.results?.first else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: classify(face, imgW: CGFloat(cg.width), imgH: CGFloat(cg.height)))
            }
        }
    }

    private static func classify(_ face: VNFaceObservation, imgW: CGFloat, imgH: CGFloat) -> FaceAnalysis {
        let bb = face.boundingBox
        let widthPx = bb.width * imgW
        let heightPx = bb.height * imgH
        let ratio = heightPx / max(1, widthPx)   // >1 = plus long que large

        // Largeur de la mâchoire via le contour du visage (fraction de la largeur du visage).
        var jawFrac: CGFloat = 0.8
        if let contour = face.landmarks?.faceContour?.normalizedPoints, contour.count > 3 {
            let xs = contour.map { $0.x }
            jawFrac = (xs.max()! - xs.min()!)   // 0…1 relatif à la bounding box
        }

        var shape: FaceShape
        var notes: [String] = []
        if ratio >= 1.45 {
            shape = .allongee
            notes.append("Visage plus long que large.")
        } else if ratio <= 1.18 {
            shape = jawFrac > 0.9 ? .carree : .ronde
            notes.append(shape == .carree ? "Mâchoire large et marquée." : "Largeur et hauteur proches, angles doux.")
        } else {
            if jawFrac < 0.74 { shape = .coeur; notes.append("Mâchoire plus étroite que le front.") }
            else if jawFrac > 0.92 { shape = .losange; notes.append("Pommettes larges, extrémités plus fines.") }
            else { shape = .ovale; notes.append("Proportions équilibrées.") }
        }
        let confidence = Double(face.confidence)
        return FaceAnalysis(shape: shape, confidence: confidence, ratio: Double(ratio), notes: notes)
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up;          case .upMirrored: return .upMirrored
        case .down: return .down;      case .downMirrored: return .downMirrored
        case .left: return .left;      case .leftMirrored: return .leftMirrored
        case .right: return .right;    case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Écran d'analyse du visage (utilisé dans le questionnaire Looksmaxx)
// (réutilise `CameraPicker(onCapture:)` déjà défini dans PhotoCalorie.swift)

struct FaceScanView: View {
    var accent: Color
    var onResult: (FaceShape) -> Void = { _ in }

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var image: UIImage?
    @State private var result: FaceAnalysis?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            if let result {
                resultCard(result)
            } else {
                placeholder
            }

            HStack(spacing: 10) {
                Button { showCamera = true } label: {
                    Label("Prendre une photo", systemImage: "camera.fill")
                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(Theme.onAccent)
                }.buttonStyle(.plain)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Galerie", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            if failed {
                Text("Aucun visage détecté — cadre bien ton visage de face, en lumière.")
                    .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            Text("Analyse 100 % sur ton iPhone — aucune photo n'est envoyée.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in showCamera = false; if let img { analyze(img) } }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    analyze(ui)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.bg2).frame(height: 190)
                if loading {
                    ProgressView().tint(accent)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "face.dashed").font(.system(size: 44, weight: .semibold)).foregroundStyle(accent)
                        Text("Analyse ta forme de visage").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Pour te recommander LA coupe adaptée").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func resultCard(_ r: FaceAnalysis) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                FaceShapeArt(shape: r.shape, color: accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Forme estimée").monoLabel(10).foregroundStyle(Theme.textSecondary)
                    Text(r.shape.rawValue).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                    Text(r.shape.summary).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            recBlock(title: "Coupes recommandées", items: r.shape.haircuts)
            recBlock(title: "Barbe", items: [r.shape.beard])
        }
        .padding(16)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private func recBlock(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(items, id: \.self) { it in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 6)
                    Text(it).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func analyze(_ img: UIImage) {
        image = img; loading = true; failed = false; result = nil
        Task {
            let r = await FaceShapeAnalyzer.analyze(img)
            await MainActor.run {
                loading = false
                if let r { result = r; onResult(r.shape); Haptics.success() }
                else { failed = true; Haptics.warning() }
            }
        }
    }
}
