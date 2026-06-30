import SwiftUI
import SwiftData
import PhotosUI
import Vision
import UIKit

// MARK: - Calories par photo : caméra + classification on-device (Vision) + estimation

struct FoodGuess {
    let name: String
    var kcal: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    let confidence: Double
}

enum FoodCalorieDB {
    // mot-clé (label Vision, en anglais) → (nom FR, kcal, protéines, glucides, lipides) par portion type
    static let table: [(String, String, Int, Double, Double, Double)] = [
        ("pizza", "Pizza (part)", 285, 12, 36, 10),
        ("cheeseburger", "Burger", 350, 17, 30, 17), ("hamburger", "Burger", 350, 17, 30, 17),
        ("hotdog", "Hot-dog", 290, 11, 24, 17), ("hot dog", "Hot-dog", 290, 11, 24, 17),
        ("banana", "Banane", 105, 1, 27, 0), ("orange", "Orange", 62, 1, 15, 0),
        ("lemon", "Citron", 17, 1, 5, 0), ("strawberr", "Fraises", 50, 1, 12, 0),
        ("pineapple", "Ananas", 82, 1, 22, 0), ("pomegranate", "Grenade", 105, 2, 26, 1),
        ("apple", "Pomme", 95, 0, 25, 0), ("granny smith", "Pomme", 95, 0, 25, 0),
        ("broccoli", "Brocoli", 55, 4, 11, 1), ("cauliflower", "Chou-fleur", 27, 2, 5, 0),
        ("cucumber", "Concombre", 16, 1, 4, 0), ("mushroom", "Champignons", 22, 3, 3, 0),
        ("bell pepper", "Poivron", 30, 1, 7, 0), ("bagel", "Bagel", 250, 10, 48, 2),
        ("pretzel", "Bretzel", 160, 4, 33, 1), ("croissant", "Croissant", 230, 5, 26, 12),
        ("french loaf", "Pain", 250, 9, 48, 2), ("baguette", "Pain", 250, 9, 48, 2),
        ("burrito", "Burrito", 450, 18, 50, 18), ("guacamole", "Guacamole", 150, 2, 9, 13),
        ("mashed potato", "Purée", 210, 4, 35, 7), ("carbonara", "Pâtes carbonara", 500, 20, 55, 22),
        ("spaghetti", "Pâtes", 380, 13, 70, 6), ("meat loaf", "Pain de viande", 290, 20, 10, 18),
        ("ice cream", "Glace", 210, 4, 24, 11), ("ice lolly", "Glace", 80, 0, 20, 0),
        ("espresso", "Café", 5, 0, 1, 0), ("red wine", "Verre de vin", 125, 0, 4, 0),
        ("trifle", "Dessert", 300, 4, 40, 14), ("sushi", "Sushi", 350, 12, 60, 6),
        ("salad", "Salade", 150, 3, 10, 10), ("egg", "Œuf", 78, 6, 1, 5),
        ("rice", "Riz", 200, 4, 45, 0), ("soup", "Soupe", 150, 5, 18, 6),
        ("steak", "Steak", 380, 38, 0, 25), ("chicken", "Poulet", 240, 27, 0, 14),
    ]

    static func match(_ label: String) -> (String, Int, Double, Double, Double)? {
        let l = label.lowercased()
        for e in table where l.contains(e.0) { return (e.1, e.2, e.3, e.4, e.5) }
        return nil
    }
}

enum FoodVision {
    /// Classifie l'image et renvoie la meilleure estimation alimentaire.
    static func classify(_ image: UIImage) async -> FoodGuess? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { cont in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
                let obs = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.05 }
                // 1) premier label reconnu présent dans la base alimentaire
                for o in obs.prefix(15) {
                    if let m = FoodCalorieDB.match(o.identifier) {
                        cont.resume(returning: FoodGuess(name: m.0, kcal: m.1, protein: m.2, carbs: m.3, fat: m.4,
                                                         confidence: Double(o.confidence)))
                        return
                    }
                }
                // 2) sinon, meilleur label brut + estimation par défaut (éditable)
                if let top = obs.first {
                    let name = top.identifier.split(separator: ",").first.map(String.init)?.capitalized ?? "Plat"
                    cont.resume(returning: FoodGuess(name: name, kcal: 250, protein: 10, carbs: 30, fat: 10,
                                                     confidence: Double(top.confidence)))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Vue

struct PhotoCalorieView: View {
    @Environment(\.modelContext) private var ctx
    @State private var image: UIImage?
    @State private var guess: FoodGuess?
    @State private var busy = false
    @State private var failed = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var meal = "Déjeuner"
    @State private var savedToast = false

    private let tint = AppCategory.nutrition.tint
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    sourceButtons
                    if busy { ProgressView("Analyse du plat…").padding() }
                    if failed { errorCard }
                    if let guess, !busy { resultCard(guess) }
                    if image == nil && !busy { intro }
                }
                .padding()
            }
            if savedToast { toast }
        }
        .navigationTitle("Calories par photo").navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in if let img { handle(img) } }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { handle(img) }
            }
        }
    }

    private var preview: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 240).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 50)).foregroundStyle(tint)
                    Text("Photographie ton assiette").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label("Prendre une photo", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(cameraAvailable ? "Galerie" : "Choisir une photo", systemImage: "photo")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(tint)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimation sur l'appareil").font(.headline)
            Text("Vision reconnaît le plat et propose une estimation de calories et macros. Ajuste si besoin avant d'ajouter au journal. Aucune photo n'est envoyée.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var errorCard: some View {
        Label("Plat non reconnu. Reprends la photo de plus près, ou ajoute manuellement.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func resultCard(_ g: FoodGuess) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(tint)
                Text(g.name).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(g.confidence * 100))%").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                stepperBox("kcal", value: Binding(get: { guess?.kcal ?? 0 }, set: { guess?.kcal = $0 }), step: 10)
                macro("P", g.protein); macro("G", g.carbs); macro("L", g.fat)
            }
            Picker("Repas", selection: $meal) {
                ForEach(["Petit-déj", "Déjeuner", "Dîner", "Collation"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            Button { save(g) } label: {
                Label("Ajouter au journal", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
            }.buttonStyle(.plain)
            Text("Estimation indicative — ajuste les kcal si la portion diffère.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stepperBox(_ label: String, value: Binding<Int>, step: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value.wrappedValue)").font(.title3.weight(.bold)).foregroundStyle(tint)
                Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Stepper("", value: value, in: 0...3000, step: step).labelsHidden()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 10))
    }
    private func macro(_ l: String, _ v: Double) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(v))g").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private var toast: some View {
        VStack { Spacer()
            Label("Ajouté au journal ✓", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.green, in: Capsule()).padding(.bottom, 30)
        }.transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func handle(_ img: UIImage) {
        image = img; guess = nil; failed = false; busy = true
        Task {
            let g = await FoodVision.classify(img)
            await MainActor.run { busy = false; if let g { guess = g; Haptics.medium() } else { failed = true } }
        }
    }
    private func save(_ g: FoodGuess) {
        let e = FoodEntry(name: g.name, calories: guess?.kcal ?? g.kcal, protein: g.protein, carbs: g.carbs, fat: g.fat, meal: meal)
        ctx.insert(e); try? ctx.save()
        Haptics.success()
        withAnimation { savedToast = true }
        image = nil; guess = nil; pickerItem = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { savedToast = false } }
    }
}

// MARK: - Caméra système (capture une vraie photo)

struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { self.onCapture(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onCapture(nil) }
        }
    }
}
