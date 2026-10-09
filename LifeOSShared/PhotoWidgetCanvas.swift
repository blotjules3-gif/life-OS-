import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

// Le dessin d'un widget photo, partage par l'apercu du studio et l'extension:
// l'apercu montre exactement ce que le widget affichera.
//
// Separe en deux couches, comme WidgetKit le demande:
//  - `PhotoWidgetBackdrop`: le fond (photo plein cadre, photo floutee ou couleur),
//    pose par l'extension dans `containerBackground`, que le systeme peut retirer
//    (StandBy, ecran verrouille, mode teinte);
//  - `PhotoWidgetContentView`: le contenu.

enum PhotoWidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large, rectangular
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Petit"
        case .medium: return "Moyen"
        case .large: return "Grand"
        case .rectangular: return "Verrouillage"
        }
    }

    /// Taille en points d'un iPhone 6,1 pouces (la plus repandue). Les autres
    /// iPhone varient de quelques points: iOS choisit, pas nous.
    var points: CGSize {
        switch self {
        case .small: return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large: return CGSize(width: 364, height: 382)
        case .rectangular: return CGSize(width: 172, height: 76)
        }
    }

    /// Rayon des coins du widget sur l'ecran d'accueil (fixe par iOS).
    var cornerRadius: CGFloat { self == .rectangular ? 12 : 22 }

    /// Cote maximum, en pixels, a lire pour une photo de ce widget.
    func maxPixel(slots: Int) -> CGFloat {
        let base: CGFloat
        switch self {
        case .small: base = 520
        case .medium, .large: base = 900
        case .rectangular: base = 300
        }
        return slots > 1 ? max(320, base * 0.66) : base
    }

    #if canImport(UIKit)
    init(family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .systemLarge, .systemExtraLarge: self = .large
        default: self = .rectangular
        }
    }
    #endif
}

/// Ce que l'extension (ou l'apercu) doit dessiner.
enum PhotoWidgetDisplayState: Equatable {
    case config(PhotoWidgetConfig, photoOffset: Int)
    /// Aucun widget choisi pour cette instance.
    case notChosen(hasConfigs: Bool)
    /// La configuration choisie a ete supprimee dans LifeOS.
    case deleted
    /// Galerie des widgets: modele generique, jamais presente comme le tien.
    case placeholder
}

// MARK: - Fond

struct PhotoWidgetBackdrop: View {
    let config: PhotoWidgetConfig?
    /// Premiere photo affichee (deja lue et reduite).
    let firstImage: UIImage?

    var body: some View {
        if let config {
            if let img = firstImage, PhotoWidgetLayoutRules.photoIsBackdrop(config) {
                Image(uiImage: img).photoWidgetFill()
            } else if let img = firstImage, config.style.background == .blurredPhoto {
                ZStack {
                    config.style.backgroundColor.color
                    Image(uiImage: img).photoWidgetFill()
                        .blur(radius: 18).scaleEffect(1.15)
                    Color.black.opacity(0.18)
                }
            } else {
                config.style.backgroundColor.color
            }
        } else {
            Color(.secondarySystemBackground)
        }
    }
}

enum PhotoWidgetLayoutRules {
    /// La photo occupe tout le widget (pas de marge ni de bordure): elle devient le fond.
    static func photoIsBackdrop(_ c: PhotoWidgetConfig) -> Bool {
        c.template == .photo && c.style.padding <= 0.5 && c.style.borderWidth <= 0.5
    }

    /// Marge minimum autour d'un texte: le bord arrondi du widget ne doit pas le couper.
    static func textPadding(_ c: PhotoWidgetConfig, size: PhotoWidgetSize) -> CGFloat {
        if size == .rectangular { return 0 }
        return max(14, CGFloat(c.style.padding))
    }

    /// Taille du texte principal adaptee a la taille du widget.
    static func fontSize(_ c: PhotoWidgetConfig, size: PhotoWidgetSize) -> CGFloat {
        let base = CGFloat(min(72, max(10, c.typography.size)))
        switch size {
        case .small: return base * 0.85
        case .medium: return base
        case .large: return base * 1.15
        case .rectangular: return min(15, base)
        }
    }

    /// Encre lisible sur une couleur de fond.
    static func ink(on background: PhotoWidgetColor) -> PhotoWidgetColor {
        background.luminance > 0.4 ? .ink : .white
    }
}

/// Mode teinte d'iOS 18: les photos passent en niveaux de gris teintes au lieu d'un
/// aplat illisible. (Le reglage n'existe que sur `Image`.)
extension Image {
    @ViewBuilder
    func photoWidgetFill() -> some View {
        if #available(iOS 18.0, macCatalyst 18.0, *) {
            self.resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFill()
        } else {
            self.resizable().scaledToFill()
        }
    }
}

// MARK: - Contenu

struct PhotoWidgetContentView: View {
    let state: PhotoWidgetDisplayState
    /// Photos affichees, dans l'ordre (deja decalees par la rotation, lues et reduites).
    let images: [UIImage]
    let size: PhotoWidgetSize
    let now: Date

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch state {
        case .config(let config, _):
            if size == .rectangular {
                lockScreen(config)
            } else {
                content(config)
            }
        case .notChosen(let hasConfigs):
            message(icon: "photo.on.rectangle.angled",
                    title: hasConfigs ? "Choisis un widget" : "Aucun widget photo",
                    detail: hasConfigs ? "Touche longuement ce widget, puis Modifier pour choisir lequel afficher."
                                       : "Crée-le dans LifeOS : Profil, Widgets photo.")
        case .deleted:
            message(icon: "trash.slash", title: "Widget supprimé dans LifeOS",
                    detail: "Choisis-en un autre : touche longuement, puis Modifier.")
        case .placeholder:
            message(icon: "photo.on.rectangle.angled", title: "Widget photo",
                    detail: "Tes photos, une note, un compte à rebours ou un objectif.")
        }
    }

    // MARK: Ecran d'accueil

    @ViewBuilder
    private func content(_ c: PhotoWidgetConfig) -> some View {
        if let missing = c.missingContent {
            message(icon: c.template.icon, title: c.name, detail: missing + " Ouvre LifeOS pour le faire.",
                    ink: PhotoWidgetLayoutRules.ink(on: c.style.backgroundColor).color)
        } else {
            switch c.template {
            case .photo: photo(c)
            case .collage: collage(c)
            case .note: note(c)
            case .countdown: countdown(c)
            case .goal: goal(c)
            }
        }
    }

    private func font(_ c: PhotoWidgetConfig, scale: CGFloat = 1) -> Font {
        PhotoWidgetFonts.font(c.typography.family, weight: c.typography.weight,
                              size: PhotoWidgetLayoutRules.fontSize(c, size: size) * scale)
    }

    private func photoTile(_ img: UIImage?, _ c: PhotoWidgetConfig) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(c.style.cornerRadius), style: .continuous)
        return Color.clear
            .overlay {
                if let img {
                    Image(uiImage: img).photoWidgetFill()
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                }
            }
            .clipShape(shape)
            .overlay {
                if c.style.borderWidth > 0.5 {
                    shape.strokeBorder(c.style.borderColor.color, lineWidth: CGFloat(min(c.style.borderWidth, 12)))
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func photo(_ c: PhotoWidgetConfig) -> some View {
        let caption = c.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        ZStack(alignment: .bottom) {
            if !PhotoWidgetLayoutRules.photoIsBackdrop(c) {
                photoTile(images.first, c).padding(CGFloat(c.style.padding))
            } else {
                Color.clear
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(font(c))
                    .foregroundStyle(c.typography.color.color)
                    .multilineTextAlignment(c.typography.alignment.text)
                    .lineLimit(size == .small ? 2 : 3)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: c.typography.alignment.frame)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(alignment: .bottom) {
                        if renderingMode == .fullColor {
                            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .padding(CGFloat(c.style.padding))
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption.isEmpty ? "Photo, \(c.name)" : "Photo, \(caption)")
    }

    @ViewBuilder
    private func collage(_ c: PhotoWidgetConfig) -> some View {
        let gap = max(2, CGFloat(c.style.padding) / 2)
        let pad = CGFloat(c.style.padding)
        let slots = min(c.style.layout.slots, max(1, images.count))
        Group {
            if slots <= 1 {
                photoTile(images.first, c)
            } else if slots == 2 {
                if size == .large {
                    VStack(spacing: gap) { photoTile(images[0], c); photoTile(images[1], c) }
                } else {
                    HStack(spacing: gap) { photoTile(images[0], c); photoTile(images[1], c) }
                }
            } else {
                HStack(spacing: gap) {
                    photoTile(images[0], c)
                    VStack(spacing: gap) { photoTile(images[1], c); photoTile(images[2], c) }
                }
            }
        }
        .padding(pad)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collage de \(slots) photos, \(c.name)")
    }

    private func note(_ c: PhotoWidgetConfig) -> some View {
        Text(c.content.text)
            .font(font(c))
            .foregroundStyle(c.typography.color.color)
            .multilineTextAlignment(c.typography.alignment.text)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: c.typography.alignment.frame)
            .padding(PhotoWidgetLayoutRules.textPadding(c, size: size))
            .widgetAccentable()
    }

    private func countdown(_ c: PhotoWidgetConfig) -> some View {
        let days = PhotoWidgetCountdown.daysLeft(to: c.content.countdownDate ?? now, from: now)
        let label = c.content.countdownLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let ink = c.typography.color.color
        return VStack(alignment: c.typography.alignment.horizontal, spacing: 2) {
            if !label.isEmpty {
                Text(label)
                    .font(font(c, scale: 0.42))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            Text(PhotoWidgetCountdown.headline(days: days))
                .font(font(c, scale: days == 0 ? 0.7 : 1.4))
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.4)
                .widgetAccentable()
            if days != 0 {
                Text(PhotoWidgetCountdown.caption(days: days))
                    .font(font(c, scale: 0.4))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if size != .small, let date = c.content.countdownDate {
                Text(date, format: .dateTime.day().month(.wide).year())
                    .font(font(c, scale: 0.36))
                    .foregroundStyle(ink.opacity(0.7))
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(c.typography.alignment.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: c.typography.alignment.frame)
        .padding(PhotoWidgetLayoutRules.textPadding(c, size: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PhotoWidgetCountdown.sentence(days: days, label: label))
    }

    private func goal(_ c: PhotoWidgetConfig) -> some View {
        let f = PhotoWidgetGoal.fraction(current: c.content.goalCurrent, target: c.content.goalTarget)
        let ink = c.typography.color.color
        return VStack(alignment: c.typography.alignment.horizontal, spacing: 8) {
            Text(c.content.goalTitle)
                .font(font(c, scale: 0.8))
                .foregroundStyle(ink)
                .lineLimit(2).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text("\(Int((f * 100).rounded())) %")
                .font(font(c, scale: 1.5))
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .widgetAccentable()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.18))
                    Capsule().fill(ink).frame(width: max(6, geo.size.width * f))
                        .widgetAccentable()
                }
            }
            .frame(height: 8)
            Text(PhotoWidgetGoal.progressText(current: c.content.goalCurrent, target: c.content.goalTarget, unit: c.content.goalUnit))
                .font(font(c, scale: 0.5))
                .foregroundStyle(ink.opacity(0.8))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .multilineTextAlignment(c.typography.alignment.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(PhotoWidgetLayoutRules.textPadding(c, size: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.content.goalTitle), \(Int((f * 100).rounded())) pour cent, \(PhotoWidgetGoal.progressText(current: c.content.goalCurrent, target: c.content.goalTarget, unit: c.content.goalUnit))")
    }

    // MARK: Ecran verrouille (teinte imposee par iOS)

    @ViewBuilder
    private func lockScreen(_ c: PhotoWidgetConfig) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let missing = c.missingContent {
                Label(c.name, systemImage: c.template.icon).font(.headline).widgetAccentable()
                Text(missing).font(.caption).lineLimit(2)
            } else {
                switch c.template {
                case .note:
                    Text(c.content.text).font(.headline).lineLimit(3).minimumScaleFactor(0.7).widgetAccentable()
                case .countdown:
                    let days = PhotoWidgetCountdown.daysLeft(to: c.content.countdownDate ?? now, from: now)
                    let label = c.content.countdownLabel.isEmpty ? c.name : c.content.countdownLabel
                    Label(label, systemImage: "hourglass").font(.caption).lineLimit(1)
                    Text(days == 0 ? "Aujourd'hui" : "\(PhotoWidgetCountdown.headline(days: days)) \(PhotoWidgetCountdown.caption(days: days))")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7).widgetAccentable()
                case .goal:
                    let f = PhotoWidgetGoal.fraction(current: c.content.goalCurrent, target: c.content.goalTarget)
                    Label(c.content.goalTitle, systemImage: "target").font(.caption).lineLimit(1)
                    ProgressView(value: f).widgetAccentable()
                    Text(PhotoWidgetGoal.progressText(current: c.content.goalCurrent, target: c.content.goalTarget, unit: c.content.goalUnit))
                        .font(.caption2).lineLimit(1)
                case .photo, .collage:
                    Label(c.name, systemImage: c.template.icon).font(.headline).widgetAccentable()
                    Text("Les photos s'affichent sur l'écran d'accueil.").font(.caption).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Etats sans contenu

    private func message(icon: String, title: String, detail: String, ink: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: size == .rectangular ? 13 : 20, weight: .semibold))
                .widgetAccentable()
            Text(title).font(.system(size: size == .rectangular ? 13 : 15, weight: .bold)).lineLimit(2)
            Text(detail).font(.system(size: size == .rectangular ? 11 : 12)).lineLimit(size == .small ? 4 : 3)
                .minimumScaleFactor(0.8).opacity(0.85)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(size == .rectangular ? 0 : 14)
        .accessibilityElement(children: .combine)
    }
}
