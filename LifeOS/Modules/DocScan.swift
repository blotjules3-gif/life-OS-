import SwiftUI
import SwiftData
import PhotosUI
import Vision
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
    @State private var savedToast = false

    private var cameraAvailable: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    sourceButtons
                    if busy { ProgressView("Lecture du texte…").padding() }
                    if analyzed { resultCard }
                }
                .padding()
            }
            if savedToast { toast }
        }
        .navigationTitle("Scan & classement").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            DocumentScannerView { img in if let img { handle(img) } }
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
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.viewfinder.fill").font(.system(size: 46)).foregroundStyle(.adminTint)
                    Text("Scanne ou choisis un document").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Text("LifeOS lit le texte, devine la catégorie et le range tout seul.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 34)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label("Scanner", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.adminTint)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choisir une photo", systemImage: "photo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.adminTint)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.adminTint)
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
            Label("Rangé dans le coffre-fort ✓", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.green, in: Capsule())
                .padding(.bottom, 30)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func handle(_ img: UIImage) {
        image = img; analyzed = false; busy = true
        Task {
            let recognized = await DocOCR.recognize(img)
            await MainActor.run {
                text = recognized
                category = DocClassifier.categorize(recognized)
                title = DocClassifier.suggestedTitle(recognized, category: category)
                busy = false; analyzed = true
            }
        }
    }

    private func save() {
        var filename: String? = nil
        if let image, let data = image.jpegData(compressionQuality: 0.8) {
            filename = ImageStore.save(data, prefix: "doc")
        }
        let doc = DocVault(title: title.isEmpty ? "Document" : title,
                           category: category, filename: filename, note: text)
        ctx.insert(doc)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation { savedToast = true }
        // reset
        image = nil; text = ""; analyzed = false; title = ""; pickerItem = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { savedToast = false } }
    }
}

// MARK: - Scanner de documents natif (VisionKit, sur appareil)

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScan: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: (UIImage?) -> Void
        init(onScan: @escaping (UIImage?) -> Void) { self.onScan = onScan }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let img = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            controller.dismiss(animated: true) { self.onScan(img) }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { self.onScan(nil) }
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true) { self.onScan(nil) }
        }
    }
}
