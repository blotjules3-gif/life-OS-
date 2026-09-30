import SwiftUI
import PhotosUI
@preconcurrency import Vision
import UIKit

// MARK: - Analyse faciale (Apple Vision, sur l'appareil, gratuit)
// Des mesures geometriques, pas une note de beaute: aucune valeur n'est "bonne".
// La geometrie pure est dans `FaceGeometry` (testee sur des points synthetiques).

struct FaceMetric: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String       // valeur lisible
    let note: String        // ce que la valeur veut dire, et ses limites
    var warning = false     // mesure non fiable (pose, point manquant)
}

enum FaceAnalyzer {
    /// Renvoie la liste de mesures, ou nil si aucun visage net detecte.
    static func analyze(_ image: UIImage) async -> [FaceMetric]? {
        guard let cg = image.cgImage else { return nil }
        let orientation = cgOrientation(image.imageOrientation)
        // Taille de l'image REDRESSEE: les points doivent etre en pixels, dans le
        // meme repere pour x et y, sinon un axe incline et largeur/hauteur mentent.
        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let size = rotated ? CGSize(width: cg.height, height: cg.width) : CGSize(width: cg.width, height: cg.height)
        return await withCheckedContinuation { cont in
            let request = VNDetectFaceLandmarksRequest { req, _ in
                guard let face = (req.results as? [VNFaceObservation])?
                    .max(by: { $0.boundingBox.area < $1.boundingBox.area }),
                      let lm = face.landmarks else { cont.resume(returning: nil); return }
                let yaw = face.yaw.map { $0.doubleValue * 180 / .pi }
                cont.resume(returning: compute(lm, imageSize: size, yawDegrees: yaw))
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
        }
    }

    private static func compute(_ lm: VNFaceLandmarks2D, imageSize: CGSize, yawDegrees: Double?) -> [FaceMetric]? {
        func px(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { r?.pointsInImage(imageSize: imageSize) ?? [] }
        let contour = px(lm.faceContour)
        guard contour.count > 2 else { return nil }
        let g = FaceGeometry.Landmarks(
            contour: contour, medianLine: px(lm.medianLine), noseCrest: px(lm.noseCrest),
            leftEye: px(lm.leftEye), rightEye: px(lm.rightEye),
            leftBrow: px(lm.leftEyebrow), rightBrow: px(lm.rightEyebrow),
            outerLips: px(lm.outerLips), nose: px(lm.nose))
        return metrics(g, yawDegrees: yawDegrees)
    }

    /// Texte des mesures, a partir de points deja en pixels.
    static func metrics(_ g: FaceGeometry.Landmarks, yawDegrees: Double?) -> [FaceMetric]? {
        var out: [FaceMetric] = []
        let pose = yawDegrees.map { String(format: "Tête tournée de %.0f°.", abs($0)) } ?? "Angle de la tête inconnu."

        switch FaceGeometry.symmetry(g, yawDegrees: yawDegrees) {
        case .measured(let deviation, let pairs):
            out.append(.init(icon: "rectangle.portrait.and.arrow.right", title: "Écart de symétrie",
                             value: String(format: "%.1f %%", deviation * 100),
                             note: "Distance moyenne entre un point et le reflet de son jumeau (\(pairs) paires), en % de la largeur du visage. Plus bas = plus symétrique. Tous les visages ont un écart. La tête penchée est compensée; une tête tournée, un sourire, une ombre ou un selfie de près l'augmentent. \(pose)"))
        case .poseTooTurned(let yaw):
            out.append(.init(icon: "rectangle.portrait.and.arrow.right", title: "Écart de symétrie",
                             value: "Non mesuré",
                             note: String(format: "Tête tournée de %.0f° (au delà de %.0f°): un côté paraît plus étroit par la seule perspective. Reprends une photo bien de face.", abs(yaw), FaceGeometry.maxYawDegrees),
                             warning: true))
        case .unavailable:
            out.append(.init(icon: "rectangle.portrait.and.arrow.right", title: "Écart de symétrie",
                             value: "Non mesuré",
                             note: "La ligne médiane du visage n'a pas été détectée: sans axe fiable, pas de mesure.",
                             warning: true))
        }

        let r = FaceGeometry.ratios(g)
        if let v = r.eyeSpacing {
            out.append(.init(icon: "eye", title: "Écartement des yeux",
                             value: String(format: "%.2f", v),
                             note: "Distance entre les centres des yeux / largeur du visage. Repère souvent cité: environ 0,46."))
        }
        if let v = r.thirds {
            out.append(.init(icon: "ruler", title: "Tiers du visage",
                             value: String(format: "%.2f", v),
                             note: "Hauteur sourcils → base du nez / base du nez → menton. 1,0 = deux tiers égaux."))
        }
        if let v = r.widthToHeight {
            out.append(.init(icon: "square", title: "Largeur / hauteur (FWHR)",
                             value: String(format: "%.2f", v),
                             note: "Largeur du visage / hauteur sourcils → lèvre haute. Valeurs courantes entre 1,7 et 2,1."))
        }
        return out.isEmpty ? nil : out
    }

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
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    #if targetEnvironment(macCatalyst)
                    HStack(spacing: 12) {
                        Button {
                            showFilePicker = true
                        } label: {
                            Label(image == nil ? "Fichiers (Finder)..." : "Changer de fichier", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.looksTint.gradient, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                .foregroundStyle(.white).font(.headline)
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Photothèque", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall), .nested)
                                .foregroundStyle(Color.looksTint).font(.headline)
                        }
                    }
                    #else
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(image == nil ? "Choisir un portrait" : "Changer de photo",
                              systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.looksTint.gradient, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .foregroundStyle(.white).font(.headline)
                    }
                    #endif
                    if busy { ProgressView("Analyse des points du visage…").padding() }
                    if noFace { errorCard }
                    if let m = metrics, !busy { results(m) }
                    if image == nil && !busy { intro }
                    disclaimer
                }
                .padding(Theme.pad)
            }
            .onDesktopImageDrop { img in
                Task { await run(img) }
            }
        }
        .navigationTitle("Analyse faciale").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let img = DesktopImageHelper.loadImage(from: url) {
                    Task { await run(img) }
                } else { noFace = true }
            case .failure:
                noFace = true
            }
        }
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
                    #if targetEnvironment(macCatalyst)
                    Text("Glisse un portrait ici ou choisis un fichier").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("Photo de face, bien éclairée").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    #else
                    Text("Photo de face, bien éclairée").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    #endif
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .raisedSurface(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(Color.looksTint.opacity(0.35)))
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mesures géométriques, sur ton appareil").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Vision détecte les points de ton visage et calcule des rapports géométriques (symétrie, écartement des yeux, tiers du visage, FWHR). Aucune photo ne quitte l'appareil.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var errorCard: some View {
        Label("Aucun visage net détecté. Essaie une photo de face, bien éclairée, sans lunettes.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Theme.warning.opacity(0.20), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func results(_ m: [FaceMetric]) -> some View {
        // Pas de note globale: additionner des ecarts a des "ideaux" fabriquait un
        // score de beaute deguise.
        VStack(spacing: 14) { ForEach(m) { metric in metricRow(metric) } }
    }

    private func metricRow(_ m: FaceMetric) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: m.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background((m.warning ? Theme.warning : Color.looksTint).gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(m.value).font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(m.warning ? Theme.warning : Color.looksTint)
                }
                Text(m.note).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var disclaimer: some View {
        Text("Ces chiffres décrivent la géométrie d'une photo, pas une personne. Ils ne disent rien de la beauté ni de la santé, et changent avec la lumière, l'objectif et l'expression.")
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
