import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
import VisionKit
import UIKit

// MARK: - OCR on-device (Apple Vision, gratuit, hors-ligne)

enum DocOCR {
    static func recognize(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                cont.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
        }
    }
}

// MARK: - Classement par règles (texte → catégorie)

enum DocClassifier {
    static func categorize(_ text: String) -> String {
        let t = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        func has(_ ks: String...) -> Bool { ks.contains { t.contains($0) } }
        if has("facture", "montant", " ttc", " tva", "total a payer", "invoice", "n° client") { return "Facture" }
        if has("ordonnance", "medecin", "mutuelle", "assurance maladie", "vaccin", "posologie") { return "Santé" }
        if has("impot", "avis d'imposition", "fiscal", "urssaf", "tax return") { return "Impôts" }
        if has("carte d'identite", "passeport", "passport", "permis de conduire", "titre de sejour") { return "Identité" }
        if has("garantie", "warranty", "ticket de caisse", "bon d'achat") { return "Garantie" }
        if has("contrat", "bail", "police d'assurance", "conditions generales", "signature des parties") { return "Contrat" }
        return "Identité"
    }

    static func suggestedTitle(_ text: String, category: String) -> String {
        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 && $0.count <= 60 }
        return lines.first ?? "Document \(category)"
    }
}

let docCategories = ["Identité", "Contrat", "Facture", "Garantie", "Santé", "Impôts"]

// MARK: - Scan & classement

struct DocScanView: View {
    @Environment(\.modelContext) private var ctx
    @State private var image: UIImage?
    @State private var text = ""
    @State private var category = "Identité"
    @State private var title = ""
    @State private var busy = false
    @State private var analyzed = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFilePicker = false
    /// Toutes les pages du scan en cours (la premiere sert de vignette).
    @State private var pages: [UIImage] = []
    @State private var savedToast = false
    @State private var saveError: String?

    private var cameraAvailable: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    sourceButtons
                    if busy { ProgressView("Lecture du texte…").padding() }
                    if let saveError {
                        // Etat d'erreur visible: sans lui, l'utilisateur croit
                        // son document range alors que l'image est perdue.
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    if analyzed { resultCard }
                }
                .padding()
            }
            .onDesktopImageDrop { img in
                handle(img)
            }
            if savedToast { toast }
        }
        .navigationTitle("Scan & classement").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image, .pdf]) { result in
            switch result {
            case .success(let url):
                // Toutes les pages : un PDF de cinq pages importe depuis le bureau
                // n'entrait dans l'app que par sa page 0, comme le scanner du telephone.
                let pages = DesktopImageHelper.loadPages(from: url)
                if !pages.isEmpty { handle(pages) }
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showCamera) {
            DocumentScannerView { pages in if !pages.isEmpty { handle(pages) } }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    handle(img)
                }
            }
        }
    }

    private var preview: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.viewfinder.fill").font(.system(size: 46)).foregroundStyle(.adminTint)
                    #if targetEnvironment(macCatalyst)
                    Text("Glisse un document ici ou choisis un fichier").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("Supporte les images et les documents PDF").font(.caption).foregroundStyle(Theme.textSecondary)
                    #else
                    Text("Scanne ou choisis un document").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Text("LifeOS lit le texte, devine la catégorie et le range tout seul.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    #endif
                }
                .frame(maxWidth: .infinity).padding(.vertical, 34)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(Color.adminTint.opacity(0.35)))
            }
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            #if targetEnvironment(macCatalyst)
            Button {
                showFilePicker = true
            } label: {
                Label("Fichiers (Finder)...", systemImage: "folder.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.adminTint)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Photothèque", systemImage: "photo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.adminTint)
            #else
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label("Scanner", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.adminTint)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choisir une photo", systemImage: "photo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.adminTint)
            #endif
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "infinity").foregroundStyle(.adminTint)
                Text("Classé automatiquement").font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Catégorie").font(.caption).foregroundStyle(Theme.textSecondary)
                Picker("Catégorie", selection: $category) {
                    ForEach(docCategories, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).tint(.adminTint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Titre").font(.caption).foregroundStyle(Theme.textSecondary)
                TextField("Titre du document", text: $title).textFieldStyle(.roundedBorder)
            }
            if !text.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Texte reconnu").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(text).font(.caption).foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 10))
                        .lineLimit(8)
                }
            }
            Button { save() } label: {
                Label("Ranger dans le coffre-fort", systemImage: "lock.doc.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.adminTint)
        }
        .padding()
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private var toast: some View {
        VStack {
            Spacer()
            Label("Rangé dans le coffre-fort", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.green, in: Capsule())
                .padding(.bottom, 30)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func handle(_ img: UIImage) { handle([img]) }

    /// Traite TOUTES les pages. Le texte reconnu est celui de l'ensemble du document,
    /// donc une date d'expiration ou un montant en derniere page est enfin trouve.
    private func handle(_ incoming: [UIImage]) {
        guard !incoming.isEmpty else { return }
        pages = incoming
        image = incoming.first
        analyzed = false; busy = true
        Task {
            var parts: [String] = []
            for page in incoming { parts.append(await DocOCR.recognize(page)) }
            let recognized = parts.joined(separator: "\n\n")
            await MainActor.run {
                text = recognized
                category = DocClassifier.categorize(recognized)
                title = DocClassifier.suggestedTitle(recognized, category: category)
                busy = false; analyzed = true
            }
        }
    }

    private func save() {
        saveError = nil
        var filename: String? = nil
        var pageFiles: [String] = []
        let toSave = pages.isEmpty ? [image].compactMap { $0 } : pages
        for page in toSave {
            guard let data = page.jpegData(compressionQuality: 0.8),
                  let f = ImageStore.save(data, prefix: "doc") else { continue }
            pageFiles.append(f)
        }
        filename = pageFiles.first
        let pagesLost = pageFiles.count < toSave.count
        if pagesLost {
            // On n'enregistre PAS un document ampute en affichant "enregistré".
            // L'ecran garde ses pages pour permettre un nouvel essai : un faux succes
            // ferait croire l'archivage fait alors que des pages manquent.
            saveError = "Enregistrement interrompu : \(pageFiles.count) page(s) sur \(toSave.count) écrites. Rien n'a été archivé, réessaie."
            for f in pageFiles { ImageStore.delete(f) }   // pas de fichiers orphelins
            return
        }

        let doc = DocVault(title: title.isEmpty ? "Document" : title,
                           category: category, filename: filename, note: text,
                           pageFilenames: pageFiles)
        ctx.insert(doc)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation { savedToast = true }
        // reset : `pages` DOIT etre vide ici, sinon le scan suivant repart avec les
        // pages du precedent et enregistre un document melange.
        image = nil; pages = []; text = ""; analyzed = false; title = ""; pickerItem = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { savedToast = false } }
    }
}

// MARK: - Scanner de documents natif (VisionKit, sur appareil)

struct DocumentScannerView: UIViewControllerRepresentable {
    /// Rend TOUTES les pages. La version precedente ne lisait que la page 0 et jetait
    /// le reste en silence.
    var onScan: ([UIImage]) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        init(onScan: @escaping ([UIImage]) -> Void) { self.onScan = onScan }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true) { self.onScan(pages) }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { self.onScan([]) }
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true) { self.onScan([]) }
        }
    }
}
