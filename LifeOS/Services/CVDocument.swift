import UIKit

/// CV mis en page, en PDF A4, a partir des champs du createur de CV.
///
/// Avant (audit V2): "Exporter le CV" partageait une chaine de texte brute avec
/// des tirets en guise de titres. Ici: vrai document, texte selectionnable dans le
/// PDF, sauts de page automatiques pour les longues experiences, accents gardes,
/// sections vides retirees.
enum CVDocument {

    struct Fields: Equatable {
        var name = "", title = "", contact = ""
        var summary = "", experience = "", education = "", skills = ""

        var isEmpty: Bool {
            [name, title, contact, summary, experience, education, skills]
                .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    static let pageSize = CGSize(width: 595, height: 842)          // A4 en points
    static let margins = UIEdgeInsets(top: 56, left: 56, bottom: 56, right: 56)

    /// Texte mis en forme, une section par bloc non vide.
    static func attributed(_ f: Fields, accent: UIColor = UIColor(red: 0.16, green: 0.33, blue: 0.62, alpha: 1)) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func para(spacingBefore: CGFloat = 0, after: CGFloat = 4) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = spacingBefore; p.paragraphSpacing = after
            p.lineHeightMultiple = 1.12; return p
        }
        func add(_ text: String, _ font: UIFont, _ color: UIColor = .black, _ style: NSParagraphStyle) {
            out.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !t(f.name).isEmpty { add(t(f.name), .systemFont(ofSize: 24, weight: .bold), .black, para(after: 2)) }
        if !t(f.title).isEmpty { add(t(f.title), .systemFont(ofSize: 13, weight: .medium), accent, para(after: 2)) }
        if !t(f.contact).isEmpty { add(t(f.contact), .systemFont(ofSize: 10), .darkGray, para(after: 10)) }
        for (heading, body) in [("Profil", f.summary), ("Expérience", f.experience), ("Formation", f.education), ("Compétences", f.skills)] {
            let b = t(body)
            guard !b.isEmpty else { continue }
            add(heading.uppercased(), .systemFont(ofSize: 10.5, weight: .semibold), accent, para(spacingBefore: 12, after: 5))
            for line in b.components(separatedBy: .newlines) where !t(line).isEmpty {
                add(t(line), .systemFont(ofSize: 10.5), .black, para(after: 3))
            }
        }
        return out
    }

    /// PDF pagine (TextKit: un conteneur de texte par page).
    static func pdf(_ f: Fields) -> Data {
        let text = attributed(f)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let frame = CGRect(origin: .zero, size: pageSize)
        let textSize = CGSize(width: pageSize.width - margins.left - margins.right,
                              height: pageSize.height - margins.top - margins.bottom)
        var containers: [NSTextContainer] = []
        repeat {
            let c = NSTextContainer(size: textSize)
            c.lineFragmentPadding = 0
            layout.addTextContainer(c)
            containers.append(c)
            layout.ensureLayout(for: c)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 50

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: f.name.isEmpty ? "CV" : "CV \(f.name)",
                               kCGPDFContextCreator as String: "LifeOS"]
        return UIGraphicsPDFRenderer(bounds: frame, format: format).pdfData { ctx in
            for c in containers {
                let range = layout.glyphRange(for: c)
                guard range.length > 0 else { continue }
                ctx.beginPage()
                layout.drawBackground(forGlyphRange: range, at: CGPoint(x: margins.left, y: margins.top))
                layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: margins.left, y: margins.top))
            }
        }
    }

    static func write(_ f: Fields) throws -> URL {
        let safe = f.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CV \(safe.isEmpty ? "LifeOS" : safe).pdf")
        try pdf(f).write(to: url, options: .atomic)
        return url
    }
}
