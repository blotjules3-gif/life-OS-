import UIKit

#if DEBUG
/// Imprime l'arbre des CALayer de l'app, avec les reglages du verre d'Apple.
///
/// **Pourquoi.** `.glassEffect()` ne dit pas ce qu'il dessine. La seule facon de
/// savoir si on obtient VRAIMENT le materiau d'Apple, et pas un repli, est de
/// regarder les couches que CoreAnimation construit. Apple empile, par element:
///   CABackdropLayer(filters: glassBackground, scale: 0.25)
///     -> CASDFLayer(effect: CASDFOutputEffect)
///   CASDFLayer(effect: CASDFKeyFillHighlightEffect)   <- le liseré
///     -> CAPortalLayer
/// Si notre arbre ne contient pas ces classes, on n'a pas le verre, point.
///
/// Lecture par KVC sur des classes privees: c'est un outil de diagnostic, il est
/// enferme dans `#if DEBUG` et n'existe pas dans un build Release.
enum GlassProbe {

    /// Les reglages du liseré, lus sur l'effet.
    private static let highlightKeys = [
        "keyAngle", "keySpread", "keyAmount", "keyHeight",
        "fillAngle", "fillSpread", "fillAmount", "fillHeight",
        "curvature"
    ]

    static func runIfAsked() {
        guard DebugLaunchFlags.has("-dumpLayers") else { return }
        // Laisser SwiftUI finir sa premiere passe de rendu, sinon l'arbre est vide.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { dump() }
    }

    static func dump() {
        var counts: [String: Int] = [:]
        var lines: [String] = []

        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows { walk(window.layer, 0, &counts, &lines) }
        }

        var out = ["=== GLASSPROBE START ==="]
        out += lines
        out.append("--- counts ---")
        out += counts.sorted { $0.value > $1.value }.map { "\($0.value)\t\($0.key)" }
        out.append("=== GLASSPROBE END ===")
        let text = out.joined(separator: "\n")
        print(text)
        // Le fichier est la sortie qui compte : `print` depuis le simulateur se perd
        // selon la facon dont l'app a ete lancee, un fichier se lit toujours.
        try? text.write(to: AppPaths.documents.appendingPathComponent("glassprobe.txt"),
                        atomically: true, encoding: .utf8)
    }

    private static func walk(_ layer: CALayer, _ depth: Int,
                             _ counts: inout [String: Int], _ lines: inout [String]) {
        let name = String(describing: type(of: layer))
        counts[name, default: 0] += 1
        let pad = String(repeating: "  ", count: depth)

        switch name {
        case "CABackdropLayer":
            let scale = layer.value(forKey: "scale") as? Double ?? -1
            let group = layer.value(forKey: "groupName") as? String ?? "nil"
            let filters = (layer.filters as? [NSObject])?.map { String(describing: $0) } ?? []
            lines.append("\(pad)BACKDROP \(fmt(layer.frame)) scale=\(scale) group=\(group) filters=\(filters)")

        case "CASDFLayer":
            let effect = layer.value(forKey: "effect") as AnyObject?
            let ename = effect.map { String(describing: type(of: $0)) } ?? "nil"
            var extra = ""
            if ename == "CASDFKeyFillHighlightEffect", let e = effect {
                extra = " " + highlightKeys
                    .map { "\($0)=\((e.value(forKey: $0) as? Double).map { String(format: "%.4f", $0) } ?? "?")" }
                    .joined(separator: " ")
            }
            lines.append("\(pad)SDF \(fmt(layer.frame)) effect=\(ename)\(extra)")

        case "CASDFElementLayer":
            let mode = layer.value(forKey: "mode") as? String ?? "?"
            let op = layer.value(forKey: "operation") as? String ?? "?"
            let oval = layer.value(forKey: "gradientOvalization") as? Double ?? -1
            lines.append("\(pad)ELEM \(fmt(layer.frame)) r=\(layer.cornerRadius) mode=\(mode) op=\(op) oval=\(oval)")

        default:
            break
        }

        layer.sublayers?.forEach { walk($0, depth + 1, &counts, &lines) }
    }

    private static func fmt(_ r: CGRect) -> String {
        String(format: "{%.0f,%.0f %.1fx%.1f}", r.origin.x, r.origin.y, r.width, r.height)
    }
}
#endif
