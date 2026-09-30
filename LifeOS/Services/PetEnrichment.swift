import Foundation
import Vision
import UIKit
import ImageIO

// MARK: - Donnees animaux gardees sur l'appareil, par produit

/// Ce que LifeOS a appris sur un aliment animal EN PLUS de la base : espece et stade
/// choisis par l'utilisateur, etiquette lue sur photo. Range sous le GTIN CANONIQUE
/// (le meme produit scanne en UPC-A ou avec un zero en trop retrouve ses donnees),
/// avec les codes vraiment vus en alias. Jamais fusionne avec un autre GTIN : une
/// recette au saumon et une au poulet, ou un junior et un adulte, restent separes.
struct PetProfile: Codable, Equatable {
    let gtin: String
    var aliases: [String]
    var species: PetLabel.Species?
    var lifeStage: PetLabel.LifeStage?
    var label: LabelReading?
    var updatedAt: Date

    struct LabelReading: Codable, Equatable {
        /// Texte lu, tel quel (garde pour la preuve et une relecture).
        var text: String
        var declaration: String?
        var composition: String?
        var additives: String?
        var analytics: PetLabel.Analytics
        /// "Photo de l'étiquette déposée dans Open Pet Food Facts le 8 déc. 2024".
        var source: String
        var photoDate: Date?
        var readAt: Date
        /// Vrai quand l'utilisateur a relu et valide (ou corrige) le texte.
        var validated: Bool
        var fromUserPhoto: Bool
    }

    static func key(_ code: String) -> String { Barcode.normalize(code)?.canonical ?? code }
}

// MARK: - Fusion base + appareil

enum PetMerge {
    /// Complete la fiche de la base avec le profil. Regles :
    /// - un choix de l'utilisateur (espece, stade) passe devant tout ;
    /// - la base garde la main sur ce qu'elle a ; l'etiquette lue ne remplit que les trous ;
    /// - composition et valeurs viennent de la MEME etiquette quand la base n'a pas de
    ///   composition ; si la base a une composition mais pas de valeurs, les valeurs de
    ///   l'etiquette ne sont prises que si les premiers ingredients concordent (sinon
    ///   deux versions de la recette se melangeraient).
    static func apply(_ profile: PetProfile?, to p: CatalogProduct) -> CatalogProduct {
        guard p.isPetFood, let profile else { return p }
        var q = p
        var facts = q.petFacts ?? CatalogProduct.PetFacts()
        facts.userSpecies = profile.species
        facts.userLifeStage = profile.lifeStage
        if let l = profile.label {
            facts.declaration = facts.declaration ?? l.declaration
            facts.additivesText = facts.additivesText ?? l.additives
            facts.labelDate = l.photoDate
            let origin = l.fromUserPhoto ? "ta photo" : "la photo de l'étiquette de la base"
            let check = l.validated ? "relue par toi" : "lue automatiquement, à vérifier"
            if q.ingredientsText == nil, let c = l.composition {
                q.ingredientsText = c
                if !l.analytics.isEmpty { q.petAnalysis = analysis(l.analytics) }
                facts.provenance.append("Composition et constituants : \(origin) (\(l.source)), \(check).")
            } else if q.petAnalysis == nil, !l.analytics.isEmpty {
                if let base = q.ingredientsText, let c = l.composition, sameRecipe(base, c) {
                    q.petAnalysis = analysis(l.analytics)
                    facts.provenance.append("Constituants : \(origin) (\(l.source)), \(check). Composition : base.")
                } else if l.composition == nil {
                    q.petAnalysis = analysis(l.analytics)
                    facts.provenance.append("Constituants : \(origin) (\(l.source)), \(check).")
                } else {
                    facts.provenance.append("L'étiquette lue ne commence pas par les mêmes ingrédients que la base : valeurs non mélangées (peut-être une autre version de la recette).")
                }
            }
        }
        q.petFacts = facts
        return q
    }

    static func analysis(_ a: PetLabel.Analytics) -> CatalogProduct.PetAnalysis {
        var r = CatalogProduct.PetAnalysis(protein: a.protein, fat: a.fat, fibre: a.fibre, ash: a.ash, moisture: a.moisture)
        r.taurine = a.taurine; r.calcium = a.calcium; r.phosphorus = a.phosphorus
        return r
    }

    /// Meme recette si au moins 2 des 3 premiers ingredients ont le meme nom.
    static func sameRecipe(_ a: String, _ b: String) -> Bool {
        func head(_ s: String) -> [String] {
            PetLabel.ingredients(s).prefix(3).map { PetLabel.fold($0.name).trimmingCharacters(in: .whitespaces) }
        }
        let x = head(a), y = head(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return zip(x, y).filter { $0 == $1 || $0.contains($1) || $1.contains($0) }.count >= min(2, min(x.count, y.count))
    }
}

// MARK: - Lecture des photos d'etiquette sur l'appareil

enum PetLabelReader {
    enum ReadError: LocalizedError, Equatable {
        case noPhoto, network(String), unreadable, nothingFound
        var errorDescription: String? {
            switch self {
            case .noPhoto: return "La base n'a pas de photo de l'étiquette pour ce produit."
            case .network(let m): return "Photo de l'étiquette injoignable (\(m)). Réessaie."
            case .unreadable: return "La photo de l'étiquette n'a pas pu être lue."
            case .nothingFound: return "Ni composition ni constituants trouvés sur la photo de l'étiquette."
            }
        }
    }

    /// Remplacable dans les tests.
    nonisolated(unsafe) static var session: URLSession = .shared

    /// Texte d'une image, lu par Vision sur l'appareil (rien n'est envoye).
    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { a, b in
                        // Haut vers bas, puis gauche vers droite (coordonnees Vision : y vers le haut).
                        abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01 ? a.boundingBox.midY > b.boundingBox.midY
                                                                               : a.boundingBox.minX < b.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: " "))
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["fr-FR", "en-US", "de-DE", "es-ES", "it-IT", "nl-NL"]
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([req]) }
            catch { cont.resume(throwing: error) }
        }
    }

    /// Lit les photos d'etiquette CHOISIES par la base (composition puis valeurs) et
    /// rend ce qui a ete trouve, avec sa provenance. Ne remplit rien de faux : un
    /// champ non trouve reste vide.
    static func read(_ p: CatalogProduct, database: String) async -> Result<PetProfile.LabelReading, ReadError> {
        let photos = (p.labelPhotos ?? []).filter { $0.kind != .front }
        guard !photos.isEmpty else { return .failure(.noPhoto) }
        var best: (PetLabel.Sections, String, CatalogProduct.LabelPhoto)?
        var lastError: ReadError = .unreadable
        for photo in photos {
            do {
                var req = URLRequest(url: photo.url, timeoutInterval: 25)
                req.setValue("LifeOS/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await session.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200, let img = prepared(data) else {
                    lastError = .unreadable; continue
                }
                let text = try await recognize(img)
                let sec = PetLabel.sections(text)
                // La base a souvent deux photos de la meme etiquette (composition, valeurs),
                // l'une plus nette que l'autre. On garde la lecture la plus complete : un
                // chiffre mal lu ("07 %%" pour 0,7 %) fait perdre des champs, donc la
                // version nette gagne.
                if best == nil || quality(sec, text) > quality(best!.0, best!.1) { best = (sec, text, photo) }
            } catch {
                lastError = .network(error.localizedDescription)
            }
        }
        guard let (sec, text, photo) = best else { return .failure(lastError) }
        let analytics = sec.analytics.map(PetLabel.analytics) ?? PetLabel.analytics(text)
        guard sec.composition != nil || !analytics.isEmpty else { return .failure(.nothingFound) }
        let date = photo.uploaded.map { " le \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return .success(.init(text: text, declaration: sec.declaration, composition: sec.composition, additives: sec.additives,
                              analytics: analytics, source: "photo déposée dans \(database)\(date)",
                              photoDate: photo.uploaded, readAt: Date(), validated: false, fromUserPhoto: false))
    }

    /// Photo redressee (orientation EXIF appliquee) et ramenee a 2 400 px au plus. Les
    /// photos de la base font jusqu'a 4 096 px : lues telles quelles sur l'iPhone, le
    /// texte sortait moins bien qu'a 1 800 px (mesure le 1er oct. sur 8445290938091).
    static func prepared(_ data: Data, maxPixels: Int = 2400) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Nombre de valeurs lues + composition (x3) + additifs + ingredients avec pourcentage.
    static func quality(_ sec: PetLabel.Sections, _ text: String) -> Int {
        let a = sec.analytics.map(PetLabel.analytics) ?? PetLabel.analytics(text)
        let values = [a.protein, a.fat, a.ash, a.fibre, a.moisture, a.taurine, a.calcium, a.phosphorus, a.omega3, a.omega6, a.dha].compactMap { $0 }.count
        let pcts = sec.composition.map { PetLabel.ingredients($0).filter { $0.percent != nil }.count } ?? 0
        return values + (sec.composition == nil ? 0 : 3) + (sec.additives == nil ? 0 : 1) + pcts
    }

    /// Lecture d'une photo prise par l'utilisateur (composition, valeurs ou etiquette entiere).
    static func read(userImage: UIImage) async -> Result<PetProfile.LabelReading, ReadError> {
        // Photo de l'appareil : orientation et taille comme pour la base.
        guard let data = userImage.jpegData(compressionQuality: 0.9), let cg = prepared(data) else { return .failure(.unreadable) }
        guard let text = try? await recognize(cg) else { return .failure(.unreadable) }
        let sec = PetLabel.sections(text)
        let analytics = sec.analytics.map(PetLabel.analytics) ?? PetLabel.analytics(text)
        guard sec.composition != nil || !analytics.isEmpty else { return .failure(.nothingFound) }
        return .success(.init(text: text, declaration: sec.declaration, composition: sec.composition, additives: sec.additives,
                              analytics: analytics, source: "ta photo", photoDate: Date(), readAt: Date(),
                              validated: false, fromUserPhoto: true))
    }
}
