import Foundation
import SwiftUI

// Studio photo: le modele d'une configuration de widget personnel.
//
// Partage entre l'app (qui ecrit) et l'extension widgets (qui lit seulement).
// Tout est Codable et chaque champ se decode avec une valeur par defaut: une
// configuration ecrite par une version plus ancienne reste lisible, et un champ
// ajoute plus tard ne casse pas l'index deja sur le disque.

// MARK: - Modeles prets a l'emploi

enum PhotoWidgetTemplate: String, Codable, CaseIterable, Identifiable {
    case photo, collage, note, countdown, goal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .collage: return "Collage"
        case .note: return "Note"
        case .countdown: return "Compte à rebours"
        case .goal: return "Objectif"
        }
    }

    var icon: String {
        switch self {
        case .photo: return "photo"
        case .collage: return "square.grid.2x2"
        case .note: return "note.text"
        case .countdown: return "hourglass"
        case .goal: return "target"
        }
    }

    var subtitle: String {
        switch self {
        case .photo: return "Une photo, ou plusieurs qui tournent"
        case .collage: return "Deux ou trois photos côte à côte"
        case .note: return "Un texte à garder sous les yeux"
        case .countdown: return "Les jours avant une date"
        case .goal: return "Où tu en es sur un objectif"
        }
    }

    /// Le modele montre des photos (au moins en fond).
    var usesPhotos: Bool { self == .photo || self == .collage }

    /// Familles d'ecran de verrouillage: seulement les modeles a texte, car une photo
    /// y serait rendue en une seule teinte par le systeme.
    var supportsLockScreen: Bool { self == .note || self == .countdown || self == .goal }
}

// MARK: - Valeurs simples

/// Couleur stockee en composantes sRGB, pour qu'elle survive au JSON.
struct PhotoWidgetColor: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    static let white = PhotoWidgetColor(r: 1, g: 1, b: 1)
    static let black = PhotoWidgetColor(r: 0, g: 0, b: 0)
    static let ink = PhotoWidgetColor(r: 0.11, g: 0.11, b: 0.12)
    static let paper = PhotoWidgetColor(r: 0.97, g: 0.96, b: 0.94)
    static let night = PhotoWidgetColor(r: 0.09, g: 0.10, b: 0.14)

    /// Nuancier propose dans l'editeur: peu de choix, tous lisibles.
    static let swatches: [(name: String, value: PhotoWidgetColor)] = [
        ("Blanc", .white), ("Papier", .paper), ("Encre", .ink), ("Noir", .black), ("Nuit", .night),
        ("Bleu", PhotoWidgetColor(r: 0.16, g: 0.45, b: 0.95)),
        ("Vert", PhotoWidgetColor(r: 0.20, g: 0.66, b: 0.36)),
        ("Orange", PhotoWidgetColor(r: 0.98, g: 0.55, b: 0.16)),
        ("Violet", PhotoWidgetColor(r: 0.55, g: 0.36, b: 0.92)),
        ("Turquoise", PhotoWidgetColor(r: 0.10, g: 0.66, b: 0.66)),
        ("Rose", PhotoWidgetColor(r: 0.95, g: 0.36, b: 0.56))
    ]

    /// Luminance relative WCAG, pour choisir une encre lisible.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

/// Rectangle normalise (0...1) dans l'image d'origine. (0,0,1,1) = image entiere.
struct PhotoCrop: Codable, Hashable {
    var x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1

    static let full = PhotoCrop()

    /// Rectangle toujours valide: dans l'image, et jamais plus petit que 5 %.
    var clamped: PhotoCrop {
        let w = min(1, max(0.05, width.isFinite ? width : 1))
        let h = min(1, max(0.05, height.isFinite ? height : 1))
        let cx = min(1 - w, max(0, x.isFinite ? x : 0))
        let cy = min(1 - h, max(0, y.isFinite ? y : 0))
        return PhotoCrop(x: cx, y: cy, width: w, height: h)
    }

    var isFull: Bool { let c = clamped; return c.x == 0 && c.y == 0 && c.width == 1 && c.height == 1 }

    /// Le meme rectangle en pixels pour une image de cette taille.
    func pixelRect(width pw: Int, height ph: Int) -> CGRect {
        let c = clamped
        let rect = CGRect(x: (c.x * Double(pw)).rounded(.down), y: (c.y * Double(ph)).rounded(.down),
                          width: max(1, (c.width * Double(pw)).rounded()), height: max(1, (c.height * Double(ph)).rounded()))
        return rect.intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
    }
}

/// Une photo choisie par l'utilisateur, deja redimensionnee dans le conteneur partage.
struct PhotoRef: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Nom du fichier dans `PhotoWidgets/images/` du groupe d'apps.
    var fileName: String
    var crop: PhotoCrop = .full
    /// Fait partie de la rotation (vrai par defaut).
    var inRotation: Bool = true

    init(id: UUID = UUID(), fileName: String, crop: PhotoCrop = .full, inRotation: Bool = true) {
        self.id = id; self.fileName = fileName; self.crop = crop; self.inRotation = inRotation
    }

    private enum CodingKeys: String, CodingKey { case id, fileName, crop, inRotation }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decode(String.self, forKey: .fileName)
        crop = try c.decodeIfPresent(PhotoCrop.self, forKey: .crop) ?? .full
        inRotation = try c.decodeIfPresent(Bool.self, forKey: .inRotation) ?? true
    }
}

enum PhotoWidgetRotation: String, Codable, CaseIterable, Identifiable {
    case off, hourly, every3h, every6h, daily
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Jamais"
        case .hourly: return "Toutes les heures"
        case .every3h: return "Toutes les 3 h"
        case .every6h: return "Toutes les 6 h"
        case .daily: return "Chaque jour"
        }
    }

    /// Duree d'un cycle. `nil` = pas de rotation.
    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .hourly: return 3600
        case .every3h: return 3 * 3600
        case .every6h: return 6 * 3600
        case .daily: return 24 * 3600
        }
    }
}

enum PhotoWidgetLayout: String, Codable, CaseIterable, Identifiable {
    case single, grid2, grid3
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "Une"
        case .grid2: return "Deux"
        case .grid3: return "Trois"
        }
    }
    var slots: Int {
        switch self { case .single: return 1; case .grid2: return 2; case .grid3: return 3 }
    }
}

enum PhotoWidgetBackground: String, Codable, CaseIterable, Identifiable {
    /// Couleur unie.
    case color
    /// La premiere photo, floutee, derriere le texte.
    case blurredPhoto
    var id: String { rawValue }
    var title: String { self == .color ? "Couleur" : "Photo floutée" }
}

struct PhotoWidgetStyle: Codable, Hashable {
    var layout: PhotoWidgetLayout = .single
    /// Marge interieure, en points.
    var padding: Double = 12
    /// Rayon des photos a l'interieur du widget (le bord du widget lui meme est fixe par iOS).
    var cornerRadius: Double = 12
    var borderWidth: Double = 0
    var borderColor: PhotoWidgetColor = .white
    var background: PhotoWidgetBackground = .color
    var backgroundColor: PhotoWidgetColor = .paper

    init() {}
    private enum CodingKeys: String, CodingKey { case layout, padding, cornerRadius, borderWidth, borderColor, background, backgroundColor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try c.decodeIfPresent(PhotoWidgetLayout.self, forKey: .layout) ?? .single
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? 12
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 12
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
        borderColor = try c.decodeIfPresent(PhotoWidgetColor.self, forKey: .borderColor) ?? .white
        background = try c.decodeIfPresent(PhotoWidgetBackground.self, forKey: .background) ?? .color
        backgroundColor = try c.decodeIfPresent(PhotoWidgetColor.self, forKey: .backgroundColor) ?? .paper
    }
}

enum PhotoWidgetFontFamily: String, Codable, CaseIterable, Identifiable {
    /// Police du systeme (SF Pro).
    case system
    /// Satoshi, la police des titres de LifeOS.
    case satoshi
    /// Inter, la police du texte de LifeOS.
    case inter
    case rounded, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Système"
        case .satoshi: return "Satoshi"
        case .inter: return "Inter"
        case .rounded: return "Arrondie"
        case .serif: return "Serif"
        case .mono: return "Mono"
        }
    }
}

enum PhotoWidgetFontWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold, black
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: return "Normal"
        case .medium: return "Moyen"
        case .semibold: return "Demi gras"
        case .bold: return "Gras"
        case .black: return "Très gras"
        }
    }
    var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .black: return .black
        }
    }
}

enum PhotoWidgetAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var title: String {
        switch self { case .leading: return "Gauche"; case .center: return "Centre"; case .trailing: return "Droite" }
    }
    var icon: String {
        switch self { case .leading: return "text.alignleft"; case .center: return "text.aligncenter"; case .trailing: return "text.alignright" }
    }
    var text: TextAlignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    var horizontal: HorizontalAlignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    var frame: Alignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
}

struct PhotoWidgetTypography: Codable, Hashable {
    var family: PhotoWidgetFontFamily = .satoshi
    /// Taille du texte principal, en points (bornee a l'affichage).
    var size: Double = 20
    var weight: PhotoWidgetFontWeight = .bold
    var color: PhotoWidgetColor = .ink
    var alignment: PhotoWidgetAlignment = .leading

    init() {}
    private enum CodingKeys: String, CodingKey { case family, size, weight, color, alignment }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = try c.decodeIfPresent(PhotoWidgetFontFamily.self, forKey: .family) ?? .satoshi
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 20
        weight = try c.decodeIfPresent(PhotoWidgetFontWeight.self, forKey: .weight) ?? .bold
        color = try c.decodeIfPresent(PhotoWidgetColor.self, forKey: .color) ?? .ink
        alignment = try c.decodeIfPresent(PhotoWidgetAlignment.self, forKey: .alignment) ?? .leading
    }
}

struct PhotoWidgetContent: Codable, Hashable {
    /// Texte de la note, ou legende posee sur une photo.
    var text: String = ""
    var countdownDate: Date? = nil
    var countdownLabel: String = ""
    var goalTitle: String = ""
    var goalCurrent: Double = 0
    var goalTarget: Double = 0
    var goalUnit: String = ""

    init() {}
    private enum CodingKeys: String, CodingKey { case text, countdownDate, countdownLabel, goalTitle, goalCurrent, goalTarget, goalUnit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        countdownDate = try c.decodeIfPresent(Date.self, forKey: .countdownDate)
        countdownLabel = try c.decodeIfPresent(String.self, forKey: .countdownLabel) ?? ""
        goalTitle = try c.decodeIfPresent(String.self, forKey: .goalTitle) ?? ""
        goalCurrent = try c.decodeIfPresent(Double.self, forKey: .goalCurrent) ?? 0
        goalTarget = try c.decodeIfPresent(Double.self, forKey: .goalTarget) ?? 0
        goalUnit = try c.decodeIfPresent(String.self, forKey: .goalUnit) ?? ""
    }
}

/// Ce qui s'ouvre quand on touche le widget.
struct PhotoWidgetTapAction: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable { case home, tool, studio }
    var kind: Kind = .studio
    /// `AppCategory.rawValue` de l'outil (kind == .tool).
    var category: String = ""
    /// Nom stable de l'outil (`CategoryTool.defaultTitle`).
    var toolName: String = ""

    static let home = PhotoWidgetTapAction(kind: .home)
    static let studio = PhotoWidgetTapAction(kind: .studio)
    static func tool(category: String, name: String) -> PhotoWidgetTapAction {
        PhotoWidgetTapAction(kind: .tool, category: category, toolName: name)
    }

    /// Lien profond ouvert par le widget. Un outil sans nom retombe sur l'accueil:
    /// jamais un lien vers rien.
    func url(configID: UUID) -> URL {
        switch kind {
        case .home:
            return URL(string: "lifeos://home")!
        case .studio:
            return URL(string: "lifeos://photo-widget?id=\(configID.uuidString)")!
        case .tool:
            guard !category.isEmpty, !toolName.isEmpty else { return URL(string: "lifeos://home")! }
            var comps = URLComponents()
            comps.scheme = "lifeos"; comps.host = "tool"
            comps.queryItems = [URLQueryItem(name: "cat", value: category), URLQueryItem(name: "name", value: toolName)]
            return comps.url ?? URL(string: "lifeos://home")!
        }
    }
}

// MARK: - Configuration

struct PhotoWidgetConfig: Codable, Hashable, Identifiable {
    static let currentVersion = 1

    var version = PhotoWidgetConfig.currentVersion
    var id: UUID
    var name: String
    var template: PhotoWidgetTemplate
    var photos: [PhotoRef] = []
    var rotation: PhotoWidgetRotation = .off
    var style = PhotoWidgetStyle()
    var typography = PhotoWidgetTypography()
    var content = PhotoWidgetContent()
    var action: PhotoWidgetTapAction = .studio
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, template: PhotoWidgetTemplate, now: Date = Date()) {
        self.id = id; self.name = name; self.template = template
        createdAt = now; updatedAt = now
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, name, template, photos, rotation, style, typography, content, action, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Widget"
        // Un modele inconnu (ajoute par une version plus recente) devient une note,
        // plutot que de rendre tout l'index illisible.
        template = (try? c.decodeIfPresent(PhotoWidgetTemplate.self, forKey: .template)) ?? .note
        photos = try c.decodeIfPresent([PhotoRef].self, forKey: .photos) ?? []
        rotation = (try? c.decodeIfPresent(PhotoWidgetRotation.self, forKey: .rotation)) ?? .off
        style = try c.decodeIfPresent(PhotoWidgetStyle.self, forKey: .style) ?? PhotoWidgetStyle()
        typography = try c.decodeIfPresent(PhotoWidgetTypography.self, forKey: .typography) ?? PhotoWidgetTypography()
        content = try c.decodeIfPresent(PhotoWidgetContent.self, forKey: .content) ?? PhotoWidgetContent()
        action = try c.decodeIfPresent(PhotoWidgetTapAction.self, forKey: .action) ?? .studio
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    /// Lien ouvert par le widget.
    var tapURL: URL { action.url(configID: id) }

    /// Photos qui tournent. Si l'utilisateur les a toutes sorties de la rotation,
    /// on garde toutes les photos: un widget ne doit jamais devenir vide par erreur.
    var rotatingPhotos: [PhotoRef] {
        let chosen = photos.filter(\.inRotation)
        return chosen.isEmpty ? photos : chosen
    }

    /// Ce qui manque pour que le widget affiche quelque chose de vrai, ou nil.
    var missingContent: String? {
        switch template {
        case .photo, .collage:
            return photos.isEmpty ? "Ajoute au moins une photo." : nil
        case .note:
            return content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Écris le texte de ta note." : nil
        case .countdown:
            return content.countdownDate == nil ? "Choisis la date du compte à rebours." : nil
        case .goal:
            if content.goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Donne un nom à ton objectif." }
            return content.goalTarget > 0 ? nil : "Indique la valeur à atteindre."
        }
    }

    /// Configuration de depart d'un modele: utilisable telle quelle apres avoir choisi
    /// les photos ou ecrit le texte. Aucun chiffre ni texte invente presente comme le tien.
    static func makeDefault(_ template: PhotoWidgetTemplate, now: Date = Date()) -> PhotoWidgetConfig {
        var c = PhotoWidgetConfig(name: template.title, template: template, now: now)
        switch template {
        case .photo:
            c.style.layout = .single
            c.style.padding = 0
            c.style.cornerRadius = 0
            c.typography.color = .white
            c.typography.size = 15
            c.typography.weight = .semibold
            c.rotation = .daily
        case .collage:
            c.style.layout = .grid2
            c.style.padding = 6
            c.style.cornerRadius = 10
            c.style.backgroundColor = .white
            c.typography.color = .ink
            c.typography.size = 14
        case .note:
            c.style.backgroundColor = .paper
            c.typography.family = .satoshi
            c.typography.size = 18
            c.typography.weight = .bold
            c.typography.color = .ink
        case .countdown:
            c.style.backgroundColor = .night
            c.typography.color = .white
            c.typography.size = 34
            c.typography.weight = .black
            c.typography.alignment = .center
        case .goal:
            c.style.backgroundColor = .paper
            c.typography.color = .ink
            c.typography.size = 22
            c.typography.weight = .bold
        }
        return c
    }
}

// MARK: - Calculs purs (testes)

enum PhotoWidgetCountdown {
    /// Jours calendaires entre aujourd'hui et la date cible (negatif si passee).
    /// Compte en jours LOCAUX: le 5 a 23 h, une cible au 6 a 1 h est "demain", pas "aujourd'hui".
    static func daysLeft(to target: Date, from now: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Grand chiffre affiche.
    static func headline(days: Int) -> String {
        if days == 0 { return "Aujourd'hui" }
        return days > 0 ? "\(days)" : "\(-days)"
    }

    /// Ligne sous le chiffre.
    static func caption(days: Int) -> String {
        switch days {
        case 0: return "C'est le jour J"
        case 1: return "jour restant"
        case 2...: return "jours restants"
        case -1: return "jour depuis"
        default: return "jours depuis"
        }
    }

    /// Phrase complete (lecteur d'ecran, ecran de verrouillage).
    static func sentence(days: Int, label: String) -> String {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = l.isEmpty ? "la date" : l
        switch days {
        case 0: return "\(what) : aujourd'hui"
        case 1: return "\(what) : demain"
        case 2...: return "\(what) : dans \(days) jours"
        case -1: return "\(what) : hier"
        default: return "\(what) : il y a \(-days) jours"
        }
    }

    /// Prochain minuit local: le chiffre change a ce moment-la.
    static func nextChange(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
    }
}

enum PhotoWidgetGoal {
    /// Avancement 0...1 (0 si la cible n'est pas posee).
    static func fraction(current: Double, target: Double) -> Double {
        guard target > 0, current.isFinite, target.isFinite else { return 0 }
        return min(1, max(0, current / target))
    }

    static func format(_ v: Double) -> String {
        if v.rounded() == v, abs(v) < 1e12 { return String(Int(v)) }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func progressText(current: Double, target: Double, unit: String) -> String {
        let u = unit.trimmingCharacters(in: .whitespaces)
        return "\(format(current)) / \(format(target))" + (u.isEmpty ? "" : " \(u)")
    }
}

/// Calendrier de rotation. L'index est cale sur l'horloge (et sur minuit local pour
/// "chaque jour"), pas sur le moment du rechargement: recharger le widget ne le fait
/// pas revenir a la premiere photo.
enum PhotoWidgetSchedule {
    struct Slot: Equatable {
        let date: Date
        /// Decalage dans la liste des photos qui tournent.
        let photoOffset: Int
    }

    static let maxEntries = 24

    /// Debut du cycle courant.
    static func cycleStart(for now: Date, interval: TimeInterval, daily: Bool, calendar: Calendar) -> Date {
        if daily { return calendar.startOfDay(for: now) }
        let t = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / interval).rounded(.down) * interval)
    }

    /// Numero du cycle (croissant) qui contient `date`.
    static func cycleIndex(for date: Date, interval: TimeInterval, daily: Bool, calendar: Calendar) -> Int {
        if daily {
            let ref = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
            return calendar.dateComponents([.day], from: ref, to: calendar.startOfDay(for: date)).day ?? 0
        }
        return Int((date.timeIntervalSince1970 / interval).rounded(.down))
    }

    /// Une entree par cycle: la premiere a `now`, les suivantes a chaque debut de cycle.
    /// Sans rotation (ou une seule photo): une seule entree.
    static func slots(photoCount: Int, rotation: PhotoWidgetRotation, now: Date,
                      calendar: Calendar = .current, maxEntries: Int = PhotoWidgetSchedule.maxEntries) -> [Slot] {
        guard photoCount > 1, let interval = rotation.interval, maxEntries > 0 else {
            return [Slot(date: now, photoOffset: 0)]
        }
        let daily = rotation == .daily
        var out: [Slot] = []
        var start = cycleStart(for: now, interval: interval, daily: daily, calendar: calendar)
        for i in 0..<min(maxEntries, max(photoCount, 1) * 4) {
            let idx = cycleIndex(for: start, interval: interval, daily: daily, calendar: calendar)
            let offset = ((idx % photoCount) + photoCount) % photoCount
            out.append(Slot(date: i == 0 ? now : start, photoOffset: offset))
            let next: Date
            if daily {
                next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            } else {
                next = start.addingTimeInterval(interval)
            }
            start = next
        }
        return out
    }

    /// Photos montrees pour un decalage: `count` photos a partir du decalage, en boucle.
    static func photos(_ list: [PhotoRef], offset: Int, count: Int) -> [PhotoRef] {
        guard !list.isEmpty, count > 0 else { return [] }
        return (0..<min(count, list.count)).map { list[(offset + $0) % list.count] }
    }
}
