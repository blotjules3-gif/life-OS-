import XCTest
@testable import LifeOS

/// Corpus reel (tools/yuko-bench/petfood/build_corpus.py) : fiches Open Pet Food Facts
/// tirees SYSTEMATIQUEMENT (1 sur 20 des aliments chat vendus en France, 1 sur 7 des
/// friandises, recherche "chaton", 1 sur 2 des fiches SANS categorie chat ni chien, plus le
/// produit de l'utilisateur). Chaque fiche passe
/// dans le vrai code : decodage de la base, lecture d'etiquette (texte Vision deja lu sur
/// Mac avec les memes reglages), fusion, identite, note.
///
/// Le test ne fixe PAS de notes : il verifie les regles (pas de note sans espece ni
/// composition, un manque est toujours dit, jamais dans les calories humaines) et ecrit
/// le rapport REPORT.md a cote du script, avec les fiches non resolues et leur cause.
@MainActor
final class PetFoodCorpusTests: XCTestCase {

    struct Corpus: Decodable {
        let built: String
        let items: [Item]
    }
    struct Item: Decodable {
        let code: String
        let why: String
        let status: Int
        let product: OFFItem?
        let ocr: [OCR]?
    }
    struct OCR: Decodable { let photo: String; let url: String; let text: String?; let error: String? }

    struct Row {
        let code, name, why, identity, composition, photo, outcome, confidence, cause: String
        let scored: Bool
    }

    func testRealCorpusFollowsTheRules() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "petfood-corpus", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(corpus.items.count, 60)
        var rows: [Row] = []

        for item in corpus.items {
            guard item.status == 1, let raw = item.product,
                  var p = raw.product(fallbackCode: item.code, source: .pet, allowUnnamed: true) else {
                rows.append(Row(code: item.code, name: "—", why: item.why, identity: "—", composition: "—", photo: "—",
                                outcome: "fiche absente", confidence: "—", cause: "code absent de la base", scored: false))
                continue
            }
            // Meme choix que PetLabelReader.read : la lecture la plus complete.
            let texts = (item.ocr ?? []).compactMap(\.text).filter { !$0.isEmpty }
            let best = texts.max { PetLabelReader.quality(PetLabel.sections($0), $0) < PetLabelReader.quality(PetLabel.sections($1), $1) }
            var fromLabel = false
            if let t = best {
                let sec = PetLabel.sections(t)
                let a = sec.analytics.map(PetLabel.analytics) ?? PetLabel.analytics(t)
                if sec.composition != nil || !a.isEmpty {
                    let reading = PetProfile.LabelReading(text: t, declaration: sec.declaration, composition: sec.composition,
                                                          additives: sec.additives, analytics: a,
                                                          source: "photo déposée dans Open Pet Food Facts", photoDate: nil,
                                                          readAt: Date(), validated: false, fromUserPhoto: false)
                    let before = p.ingredientsText
                    p = PetMerge.apply(PetProfile(gtin: PetProfile.key(item.code), aliases: [], species: nil, lifeStage: nil,
                                                  label: reading, updatedAt: Date()), to: p)
                    fromLabel = before == nil && p.ingredientsText != nil
                }
            }
            let id = ProductScore.petIdentity(p)
            let r = ProductScore.evaluate(p)

            // Regles, sur chaque fiche.
            XCTAssertTrue(ProductFit.evaluate(p, goals: Set(ProductGoal.allCases)).verdicts.isEmpty, item.code)
            if let v = r.value {
                XCTAssertNotNil(id.species, "\(item.code) : note sans espece")
                XCTAssertNotNil(p.ingredientsText, "\(item.code) : note sans composition")
                XCTAssertTrue((0...100).contains(v))
                XCTAssertNotNil(r.confidence, "\(item.code) : note sans confiance")
            }
            if case .notEvaluated = r.outcome { XCTAssertFalse(r.missing.isEmpty, "\(item.code) : un refus dit toujours ce qui manque") }

            let identity: String = {
                if let o = id.otherAnimal, id.species == nil { return "autre animal (\(o))" }
                guard let s = id.species else { return id.ambiguous ? "ambigu chat/chien" : "espèce inconnue" }
                let stage = id.lifeStage.map { $0 == .young ? "jeune" : $0 == .senior ? "senior" : "adulte" } ?? "stade ?"
                let kind = id.kind.map { $0 == .complete ? "complet" : $0 == .complementary ? "complémentaire" : "friandise" } ?? "type ?"
                return "\(s.rawValue) · \(stage) · \(kind)"
            }()
            let composition = p.ingredientsText == nil ? "absente" : fromLabel ? "étiquette lue" : "base"
            let labelPhoto = !(p.labelPhotos ?? []).filter { $0.kind != .front }.isEmpty
            let photo = [p.imageURL != nil ? "face" : nil, labelPhoto ? "étiquette" : nil].compactMap { $0 }.joined(separator: " + ")
            let outcome: String
            switch r.outcome {
            case .scored(let v): outcome = "\(v)/100"
            case .notEvaluated: outcome = "pas de note"
            case .notApplicable: outcome = "hors méthode"
            }
            var cause = ""
            if r.value == nil {
                if case .notApplicable = r.outcome { cause = "aliment pour \(id.otherAnimal ?? "un autre animal")" }
                else {
                    cause = "manque : " + r.missing.joined(separator: ", ")
                    if p.ingredientsText == nil { cause += labelPhoto ? (texts.isEmpty ? " (photo d'étiquette illisible)" : " (étiquette lue, composition non trouvée)") : " (aucune photo d'étiquette dans la base)" }
                }
            } else if !r.missing.isEmpty {
                cause = "note partielle, manque : " + r.missing.joined(separator: ", ")
            }
            rows.append(Row(code: item.code, name: String(p.name.prefix(48)), why: item.why, identity: identity,
                            composition: composition, photo: photo.isEmpty ? "aucune" : photo, outcome: outcome,
                            confidence: r.confidence.map { "\($0.level)" } ?? "—", cause: cause, scored: r.value != nil))
        }

        // Le produit de l'utilisateur doit sortir en chaton, note calculee.
        let user = try XCTUnwrap(rows.first { $0.code == "8445290938091" })
        XCTAssertTrue(user.scored, user.cause)
        XCTAssertTrue(user.identity.hasPrefix("chat · jeune"), user.identity)

        let report = Self.report(rows, built: corpus.built)
        print(report)
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/yuko-bench/petfood/REPORT.md")
        try? report.write(to: out, atomically: true, encoding: .utf8)
    }

    static func report(_ rows: [Row], built: String) -> String {
        func count(_ f: (Row) -> Bool) -> String { "\(rows.filter(f).count)/\(rows.count)" }
        let vague = rows.filter { $0.why.hasPrefix("fiche sans catégorie") }
        var s = """
        # Corpus Yuko aliments chat (méthode \(ProductScore.petMethodVersion))

        Corpus construit le \(built) par `build_corpus.py` (échantillon systématique, pas trié).
        Rapport écrit par `PetFoodCorpusTests` : chaque fiche passe dans le vrai code de l'app.
        Quatre mesures séparées, comme demandé :

        - **Identification** (espèce reconnue) : \(count { $0.identity.hasPrefix("chat") || $0.identity.hasPrefix("chien") })
        - **Composition** disponible : \(count { $0.composition != "absente" }) (dont lue sur l'étiquette : \(count { $0.composition == "étiquette lue" }))
        - **Photo** : face \(count { $0.photo.contains("face") }), étiquette \(count { $0.photo.contains("étiquette") })
        - **Note /100** : \(count(\.scored))

        Fiches SANS catégorie chat ni chien (comme « one junior ») : \(vague.count) tirées.
        Espèce reconnue \(vague.filter { $0.identity.hasPrefix("chat") || $0.identity.hasPrefix("chien") }.count)
        (chat \(vague.filter { $0.identity.hasPrefix("chat") }.count), chien \(vague.filter { $0.identity.hasPrefix("chien") }.count)),
        ambiguë \(vague.filter { $0.identity.hasPrefix("ambigu") }.count), autre animal \(vague.filter { $0.identity.hasPrefix("autre") }.count),
        notées \(vague.filter(\.scored).count). Ici l'identification se mesure vraiment : le reste du
        corpus vient de la catégorie « aliment pour chat », donc l'espèce y est donnée par la base.

        | Code | Produit | Tirage | Identité | Composition | Photos | Note | Confiance |
        |---|---|---|---|---|---|---|---|

        """
        for r in rows {
            s += "| \(r.code) | \(r.name.replacingOccurrences(of: "|", with: "/")) | \(r.why) | \(r.identity) | \(r.composition) | \(r.photo) | \(r.outcome) | \(r.confidence) |\n"
        }
        s += "\n## Fiches non résolues ou partielles, avec la cause\n\n| Code | Produit | Cause |\n|---|---|---|\n"
        for r in rows where !r.cause.isEmpty {
            s += "| \(r.code) | \(r.name.replacingOccurrences(of: "|", with: "/")) | \(r.cause) |\n"
        }
        return s
    }
}
