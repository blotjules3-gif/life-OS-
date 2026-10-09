import SwiftUI
import UIKit

/// Composants UI partagés par tous les modules.

extension Color {
    /// Noir ou blanc, celui des deux qui se lit sur cette couleur.
    var readableInk: Color {
        let ui = UIColor(self).resolvedColor(with: UITraitCollection.current)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luma > 0.6 ? .black : .white
        }
        if let rgb = ui.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
           let comps = rgb.components, comps.count >= 3 {
            let luma = 0.2126 * comps[0] + 0.7152 * comps[1] + 0.0722 * comps[2]
            return luma > 0.6 ? .black : .white
        }
        var white: CGFloat = 0
        if ui.getWhite(&white, alpha: &a) {
            return white > 0.6 ? .black : .white
        }
        return .black
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .black)).textCase(.uppercase).kerning(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).monoLabel(10)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).monoLabel(11).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pastille d'icône : petite tuile teintée à glyphe contrasté (façon Réglages d'iOS).
/// Le thème Verre, qui la passait en verre, est archivé : il se lit "Suivre
/// l'appareil" (voir `AppTheme.resolved`), donc la pastille reste teintée partout.
struct IconBadge: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 44
    var body: some View {
        // Pastille de COULEUR pleine, glyphe noir ou blanc selon la teinte. Lisible sur
        // clair comme sur sombre, et en palette neutre (la teinte devient un gris de
        // même luminance, donc `readableInk` choisit toujours le bon contraste).
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(tint.readableInk)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous).fill(tint))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var icon: String? = nil
    var tint: Color = Theme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.headline)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.system(size: 15, weight: .black)).textCase(.uppercase).kerning(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(Theme.textPrimary)
            .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(LifeOSPressStyle())
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String = ""
    var tint: Color = Theme.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 76, height: 76)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 17, weight: .black)).textCase(.uppercase).kerning(-0.2)
                .foregroundStyle(Theme.textPrimary)
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 14, weight: .black)).textCase(.uppercase).kerning(0.5)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(LifeOSPressStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

/// Bandeau qui signale un module nécessitant une intégration externe (IA / banque / API).
struct IntegrationNotice: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.badge.clock")
                .foregroundStyle(Theme.warning)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.warning.opacity(0.26), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

/// Anneau de progression réutilisable (timers, scores, objectifs).
struct ProgressRing: View {
    var progress: Double          // 0...1
    var lineWidth: CGFloat = 12
    var tint: Color = Theme.accent
    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8, bounce: 0.12), value: progress)
        }
    }
}

/// Petit utilitaire de formatage de durée.
func formatHMS(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%02d:%02d", m, sec)
}

func formatHoursMinutes(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60
    return "\(h)h\(String(format: "%02d", m))"
}

// MARK: - Champs et sélections : une même famille (lot 8)
//
// Avant : 223 champs, 24 en `.roundedBorder` (cadre UIKit gris), le reste nu ; les
// sélections étaient des pastilles dessinées à la main, chacune différente. Ces deux
// styles posent la même matière que les cartes et boutons (`raisedSurface`,
// `glassControl`), donc un champ, un menu et une sélection se reconnaissent comme de
// la même famille sur iPhone, iPad et desktop.

/// Habillage d'un champ : boîte encastrée (voile, pas un second verre posé sur la
/// carte), hauteur tactile 44 pt minimum, icône facultative.
struct GlassFieldChrome: ViewModifier {
    var icon: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            content
                .font(AppFont.body(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .inset)
        .opacity(isEnabled ? 1 : GlassControl.disabledOpacity)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

/// `TextField("…", text: $x).textFieldStyle(.glass)` : le champ partagé de LifeOS.
struct GlassFieldStyle: TextFieldStyle {
    var icon: String? = nil
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.modifier(GlassFieldChrome(icon: icon))
    }
}

extension TextFieldStyle where Self == GlassFieldStyle {
    static var glass: GlassFieldStyle { GlassFieldStyle() }
    static func glass(icon: String) -> GlassFieldStyle { GlassFieldStyle(icon: icon) }
}

extension View {
    /// Même habillage pour ce qui n'est pas un `TextField` (SecureField, TextEditor,
    /// menu `Picker`, `DatePicker` compact…).
    func glassField(icon: String? = nil) -> some View {
        modifier(GlassFieldChrome(icon: icon))
    }
}

/// Une pastille de sélection : verre interactif quand elle est choisie, nue sinon.
/// Le choix se lit sans couleur (matière + graisse + coche), donc aussi en neutre.
struct SelectionChip: View {
    let title: String
    var symbol: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AppFont.body(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                if isSelected { Color.clear.glassControl(Capsule()) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(LifeOSPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Choix exclusif entre quelques options (2 à 4), dans une capsule encastrée.
/// La pastille choisie glisse d'une option à l'autre, sauf avec "Réduire les
/// animations" où elle change de place sans mouvement.
struct GlassSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var symbol: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]
    var accessibilityTitle: String = ""

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    guard option.value != selection else { return }
                    if reduceMotion { selection = option.value }
                    else { withAnimation(Theme.animQuick) { selection = option.value } }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol).font(.subheadline.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        Text(option.title)
                            .font(AppFont.body(size: 13, weight: selected ? .semibold : .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 6)
                    .background {
                        if selected {
                            Color.clear.glassControl(Capsule())
                                .matchedGeometryEffect(id: "glassSegmentedSelection", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(LifeOSPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .raisedSurface(Capsule(), .inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}
