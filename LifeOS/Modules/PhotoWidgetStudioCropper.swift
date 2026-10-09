import SwiftUI
import UIKit

/// Calcul du cadre de recadrage (pur, teste).
enum PhotoCropMath {
    enum Aspect: String, CaseIterable, Identifiable {
        case small, medium, large, whole
        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: return "Petit"
            case .medium: return "Moyen"
            case .large: return "Grand"
            case .whole: return "Entière"
            }
        }
        /// Largeur / hauteur du widget vise (en points iPhone 6,1 pouces).
        var ratio: Double? {
            switch self {
            case .small: return 1
            case .medium: return 364.0 / 170.0
            case .large: return 364.0 / 382.0
            case .whole: return nil
            }
        }
    }

    /// Plus grand cadre normalise de ce rapport qui tient dans l'image.
    static func maxFrame(ratio: Double, imageSize: CGSize) -> (w: Double, h: Double) {
        let W = max(1, Double(imageSize.width)), H = max(1, Double(imageSize.height))
        if W / H > ratio { return (ratio * H / W, 1) }
        return (1, W / (ratio * H))
    }

    /// Cadre centre sur (cx, cy), a `zoom` (0,2 a 1) du plus grand cadre possible.
    static func crop(ratio: Double?, imageSize: CGSize, center: CGPoint, zoom: Double) -> PhotoCrop {
        guard let ratio else { return .full }
        let m = maxFrame(ratio: ratio, imageSize: imageSize)
        let z = min(1, max(0.2, zoom))
        let w = m.w * z, h = m.h * z
        return PhotoCrop(x: Double(center.x) - w / 2, y: Double(center.y) - h / 2, width: w, height: h).clamped
    }

    /// Rapport le plus proche d'un recadrage existant (pour rouvrir le recadrage).
    static func closestAspect(to crop: PhotoCrop, imageSize: CGSize) -> Aspect {
        guard !crop.isFull else { return .whole }
        let r = (crop.width * Double(imageSize.width)) / max(1, crop.height * Double(imageSize.height))
        return Aspect.allCases.filter { $0.ratio != nil }.min { abs(log($0.ratio! / r)) < abs(log($1.ratio! / r)) } ?? .small
    }
}

/// Recadrage simple: on deplace et on agrandit un cadre au rapport du widget vise.
/// Glisser deplace, pincer (ou le curseur, au clavier et a la souris) change la taille.
struct PhotoWidgetCropperView: View {
    let ref: PhotoRef
    let onDone: (PhotoCrop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var aspect: PhotoCropMath.Aspect = .small
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var zoom: Double = 1
    @State private var dragStart: CGPoint?
    @State private var pinchStart: Double?
    @State private var loaded = false

    private var imageSize: CGSize { image?.size ?? CGSize(width: 1, height: 1) }
    private var crop: PhotoCrop { PhotoCropMath.crop(ratio: aspect.ratio, imageSize: imageSize, center: center, zoom: zoom) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Format", selection: $aspect) {
                    ForEach(PhotoCropMath.Aspect.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                GeometryReader { geo in
                    if let image {
                        let fit = fitRect(imageSize: image.size, in: geo.size)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: fit.width, height: fit.height)
                                .position(x: fit.midX, y: fit.midY)
                            cropOverlay(fit: fit, size: geo.size)
                        }
                        .contentShape(Rectangle())
                        .gesture(dragGesture(fit: fit))
                        .simultaneousGesture(pinchGesture)
                        .accessibilityElement()
                        .accessibilityLabel("Zone de recadrage")
                        .accessibilityAdjustableAction { dir in
                            zoom = min(1, max(0.2, zoom + (dir == .increment ? 0.1 : -0.1)))
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 280)

                if aspect != .whole {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Taille du cadre").font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Slider(value: $zoom, in: 0.2...1).accessibilityLabel("Taille du cadre")
                    }
                    Text("Glisse le cadre pour choisir la partie gardée.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.pad)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Recadrer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { onDone(crop); dismiss() }.bold().disabled(image == nil)
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                image = await PhotoWidgetThumbCache.loadFull(ref.fileName)
                if let image {
                    aspect = PhotoCropMath.closestAspect(to: ref.crop, imageSize: image.size)
                    let c = ref.crop.clamped
                    center = CGPoint(x: c.x + c.width / 2, y: c.y + c.height / 2)
                    if let r = aspect.ratio {
                        zoom = min(1, max(0.2, c.width / PhotoCropMath.maxFrame(ratio: r, imageSize: image.size).w))
                    }
                }
            }
        }
    }

    private func fitRect(imageSize: CGSize, in box: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let s = min(box.width / imageSize.width, box.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    private func cropOverlay(fit: CGRect, size: CGSize) -> some View {
        let c = crop
        let rect = CGRect(x: fit.minX + c.x * fit.width, y: fit.minY + c.y * fit.height,
                          width: c.width * fit.width, height: c.height * fit.height)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRect(rect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Rectangle().stroke(Color.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .allowsHitTesting(false)
    }

    private func dragGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard aspect != .whole, fit.width > 0, fit.height > 0 else { return }
                let start = dragStart ?? center
                if dragStart == nil { dragStart = center }
                let nx = start.x + v.translation.width / fit.width
                let ny = start.y + v.translation.height / fit.height
                let c = PhotoCropMath.crop(ratio: aspect.ratio, imageSize: imageSize, center: CGPoint(x: nx, y: ny), zoom: zoom)
                center = CGPoint(x: c.x + c.width / 2, y: c.y + c.height / 2)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { m in
                guard aspect != .whole else { return }
                let start = pinchStart ?? zoom
                if pinchStart == nil { pinchStart = zoom }
                zoom = min(1, max(0.2, start * Double(m)))
            }
            .onEnded { _ in pinchStart = nil }
    }
}
