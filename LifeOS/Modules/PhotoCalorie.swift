import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
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
                let obs = (request.results ?? [])
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
    /// Si vrai, la caméra s'ouvre immédiatement à l'apparition. Utilisé par les
    /// raccourcis rapides (Control Center, widget Home, Siri) pour amener
    /// l'utilisateur directement à la prise de photo.
    var autoOpenCamera: Bool = false

    @Environment(\.modelContext) private var ctx
    @State private var image: UIImage?
    @State private var guess: FoodGuess?
    /// Aliments detectes, modifiables un par un avant enregistrement.
    @State private var items: [FoodRecognitionPipeline.DetectedFood] = []
    @State private var showAddItem = false
    @State private var busy = false
    @State private var failed = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var meal = "Déjeuner"
    @State private var savedToast = false
    /// Jour du repas. Aujourd'hui par defaut, modifiable pour un repas oublie.
    @State private var mealDay = Date()
    /// Garde contre le double appui : un seul enregistrement a la fois.
    @State private var saving = false
    /// Message quand l'enregistrement echoue. La saisie reste a l'ecran.
    @State private var saveError: String?
    @State private var aiNote = ""
    @State private var aiQuestion: String?
    /// Quel moteur a repondu, et avec quelle confiance: affiche avec le resultat.
    @State private var engineLine = ""
    @State private var usedAI = false

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
                    if let saveError { saveErrorCard(saveError) }
                    if !items.isEmpty, !busy { itemsCard }
                    if image == nil && !busy { intro }
                }
                .padding()
            }
            .onDesktopImageDrop { img in
                handle(img)
            }
            if savedToast { toast }
        }
        .navigationTitle("Calories par photo").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddItem) {
            ManualFoodSheet { added in items.append(added); failed = false }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in if let img { handle(img) } }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let img = DesktopImageHelper.loadImage(from: url) {
                    handle(img)
                }
            case .failure:
                break
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { handle(img) }
            }
        }
        .onAppear {
            #if DEBUG
            // `-calaiImage /chemin/photo.jpg`: analyse une photo annotee du banc
            // d'essai (tools/calai-bench) sans camera, pour verifier l'ecran reel.
            if image == nil, let path = DebugLaunchFlags.value("-calaiImage"), let img = UIImage(contentsOfFile: path) {
                handle(img); return
            }
            #endif
            if autoOpenCamera && cameraAvailable && image == nil {
                // Léger délai pour laisser la vue apparaître avant d'empiler
                // le fullScreenCover — sinon l'animation est saccadée.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showCamera = true
                }
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
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 48)).foregroundStyle(tint)
                    #if targetEnvironment(macCatalyst)
                    Text("Glisse une photo ici ou choisis un fichier")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Glisser-déposer depuis le Finder ou clic ci-dessous")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    #else
                    Text("Photographie ton assiette").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    #endif
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .raisedSurface(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(tint.opacity(0.35)))
            }
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            #if targetEnvironment(macCatalyst)
            Button {
                showFilePicker = true
            } label: {
                Label("Fichiers (Finder)...", systemImage: "folder.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Photothèque", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .raisedSurface(RoundedRectangle(cornerRadius: 12), .nested)
                    .foregroundStyle(tint)
            }
            #else
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label("Prendre une photo", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(cameraAvailable ? "Galerie" : "Choisir une photo", systemImage: "photo")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .raisedSurface(RoundedRectangle(cornerRadius: 12), .nested).foregroundStyle(tint)
            }
            #endif
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimation sur l'appareil").font(.headline)
            Text("Vision reconnaît le plat et propose une estimation de calories et macros. Ajuste si besoin avant d'ajouter au journal. Aucune photo n'est envoyée.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    /// Sans cle et sans reconnaissance, l'ecran ne doit pas s'arreter la : on propose
    /// tout de suite la recherche (Ciqual + OpenFoodFacts), qui ecrit dans le meme journal.
    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plat non reconnu. Reprends la photo de plus près, ou cherche l'aliment.", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(Theme.warning)
            Button { showAddItem = true } label: {
                Label("Chercher un aliment", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }
            .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Theme.warning.opacity(0.20), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func resultCard(_ g: FoodGuess) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "infinity").foregroundStyle(tint)
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
            mealDayPicker
            Button { save(g) } label: {
                saveLabel.frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
            }.buttonStyle(.plain).disabled(saving)
            if usedAI {
                if !aiNote.isEmpty {
                    Text(aiNote).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label("Analysé par ton coach d'après ta photo", systemImage: "infinity")
                    .font(.caption2).foregroundStyle(tint)
            }
            Text(usedAI
                 ? "Estimation à partir de la portion visible — ajuste si besoin."
                 : "Estimation locale approximative — ajuste les kcal si la portion diffère.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Resultat: une ligne par aliment, tout modifiable

    private var totals: (kcal: Int, p: Double, c: Double, f: Double) {
        items.reduce(into: (0, 0.0, 0.0, 0.0)) { acc, i in
            acc.0 += i.kcal; acc.1 += i.protein; acc.2 += i.carbs; acc.3 += i.fat
        }
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Détecté dans ta photo").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { showAddItem = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("Ajouter un aliment")
            }

            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        // Le nom est modifiable: la reconnaissance se trompe, et
                        // corriger vaut mieux que supprimer et ressaisir.
                        TextField("Aliment", text: $item.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(item.kcal) kcal")
                            .font(.subheadline.bold()).foregroundStyle(tint)
                    }
                    HStack(spacing: 10) {
                        Text("\(Int(item.grams)) g")
                            .font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 52, alignment: .leading)
                        // La portion est l'hypothese la plus fragile de toute la
                        // chaine: on la met en avant et on la rend glissante.
                        Slider(value: $item.grams, in: 10...600, step: 5)
                        Button(role: .destructive) {
                            items.removeAll { $0.id == item.id }
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Retirer \(item.name)")
                    }
                    if !item.alternatives.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("Plutôt :").font(.caption2).foregroundStyle(Theme.textSecondary)
                                ForEach(item.alternatives, id: \.self) { alt in
                                    Button(alt) {
                                        if let i = items.firstIndex(where: { $0.id == item.id }) {
                                            items[i] = FoodRecognitionPipeline.renamed(items[i], to: alt)
                                        }
                                    }
                                    .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Text("P \(item.protein, specifier: "%.1f")").font(.caption2)
                        Text("G \(item.carbs, specifier: "%.1f")").font(.caption2)
                        Text("L \(item.fat, specifier: "%.1f")").font(.caption2)
                        Spacer()
                        Label(item.source.label, systemImage: item.source == .estimate ? "questionmark.circle" : "checkmark.seal")
                            .font(.caption2)
                            .foregroundStyle(item.source == .estimate ? Theme.warning : Theme.success)
                        Text("\(Int(item.confidence * 100))%")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 8)
                Divider().opacity(0.15)
            }

            HStack {
                Text("Total").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(totals.kcal) kcal").font(.title3.bold()).foregroundStyle(tint)
            }
            HStack(spacing: 12) {
                macro("P", totals.p); macro("G", totals.c); macro("L", totals.f)
            }

            Picker("Repas", selection: $meal) {
                ForEach(["Petit-déj", "Déjeuner", "Dîner", "Collation"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)

            mealDayPicker

            Button { saveItems() } label: {
                saveLabel
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty || saving)

            if let q = aiQuestion {
                Label(q, systemImage: "questionmark.bubble").font(.caption).foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usedAI, !aiNote.isEmpty {
                Text(aiNote).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !engineLine.isEmpty {
                Text(engineLine).font(.caption2).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // On annonce l'hypothese au lieu de faire croire a une mesure.
            Text("Les portions sont des hypothèses, pas une pesée : ajuste avec le curseur. Aliments génériques : table Ciqual (ANSES) ; produits emballés : OpenFoodFacts.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: 16))
    }

    /// Enregistre UNE ligne de journal par aliment, pas un total anonyme:
    /// autrement on ne peut plus corriger un seul element plus tard.
    ///
    /// Tout ou rien, via `FoodLogService`. En cas d'echec la photo et les lignes
    /// restent a l'ecran avec un message et un bouton pour reessayer: avant, un
    /// echec affichait "Ajoute au journal" et effacait la saisie.
    private func saveItems() {
        guard !saving, !items.isEmpty else { return }
        let when = FoodLogService.mealDate(day: mealDay)
        let drafts = items.map {
            FoodLogService.Draft(name: $0.name, calories: $0.kcal, protein: $0.protein,
                                 carbs: $0.carbs, fat: $0.fat, meal: meal, date: when)
        }
        commit(drafts) { items = [] }
    }

    private func commit(_ drafts: [FoodLogService.Draft], clear: () -> Void) {
        saving = true
        defer { saving = false }
        do {
            try FoodLogService.log(drafts, in: ctx)
        } catch {
            Haptics.warning()
            withAnimation { saveError = error.localizedDescription }
            return
        }
        saveError = nil
        Haptics.success()
        withAnimation { savedToast = true }
        clear()
        image = nil; guess = nil; pickerItem = nil; mealDay = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { savedToast = false } }
    }

    private var saveLabel: some View {
        HStack(spacing: 8) {
            if saving { ProgressView().tint(.white) }
            else { Image(systemName: "plus.circle.fill") }
            Text(saving ? "Enregistrement…" : "Ajouter au journal")
        }
    }

    private var mealDayPicker: some View {
        DatePicker("Jour du repas", selection: $mealDay, in: ...Date(), displayedComponents: .date)
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
    }

    private func saveErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message).font(.subheadline).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Réessayer") {
                if let g = guess { save(g) } else { saveItems() }
            }
            .font(.subheadline.weight(.semibold))
            .disabled(saving)
        }
        .padding(14)
        .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
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
        .raisedSurface(RoundedRectangle(cornerRadius: 10), .nested)
    }
    private func macro(_ l: String, _ v: Double) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(v))g").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private var toast: some View {
        VStack { Spacer()
            Label("Ajouté au journal", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Theme.success, in: Capsule()).padding(.bottom, 30)
        }.transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func handle(_ img: UIImage) {
        image = img; guess = nil; items = []; failed = false; busy = true; aiNote = ""; usedAI = false
        aiQuestion = nil; engineLine = ""
        Task {
            // 1. Vrai modele de vision s'il y a une cle. Il REGARDE l'assiette
            //    et juge la portion, au lieu de reconnaitre un mot et de lire
            //    une table ou une pizza vaut toujours le meme nombre.
            if await FoodPhotoAnalyzer.isAvailable {
                switch await FoodPhotoAnalyzer.analyze(img) {
                case .success(let a) where !a.items.isEmpty:
                    let engine = await FoodPhotoAnalyzer.engineName ?? "ton fournisseur"
                    await MainActor.run {
                        // Un element par aliment vu, valeurs Ciqual quand l'aliment y
                        // est (plat fait maison), sinon celles du modele pour la portion.
                        items = a.items.map { i in
                            if let g = FoodRecognitionPipeline.generic(i.name, preparation: i.preparation) {
                                return .init(name: i.name, confidence: i.confidence, grams: i.grams,
                                             kcal100: g.0, protein100: g.1, carbs100: g.2, fat100: g.3,
                                             source: .ciqual, alternatives: i.alternatives, preparation: i.preparation)
                            }
                            let f = 100 / max(i.grams, 1)
                            return .init(name: i.name, confidence: i.confidence, grams: i.grams,
                                         kcal100: i.kcal * f, protein100: i.protein * f, carbs100: i.carbs * f, fat100: i.fat * f,
                                         source: .estimate, alternatives: i.alternatives, preparation: i.preparation)
                        }
                        aiNote = a.note; aiQuestion = a.question; usedAI = true; busy = false
                        engineLine = "Analysé par ton coach avec \(engine). La photo est envoyée à ce service, LifeOS ne la garde pas."
                        Haptics.medium()
                    }
                    return
                case .success:
                    AppLog.data.info("analyse du plat: aucun aliment vu par le coach, repli sur l'appareil")
                case .failure(let e):
                    // On n'abandonne pas: l'estimation locale vaut mieux que
                    // rien. Mais la raison est tracee, sinon une cle morte
                    // ressemble a un modele qui se trompe.
                    AppLog.data.error("analyse du plat par le coach echouee: \(String(describing: e), privacy: .public)")
                }
            }
            // 2. Sans cle: reconnaissance sur l'appareil, puis VRAIES valeurs
            //    nutritionnelles d'OpenFoodFacts. Aucune cle, aucun compte.
            let detected = await FoodRecognitionPipeline.analyse(img)
            await MainActor.run {
                busy = false
                let best = detected.map(\.confidence).max() ?? 0
                engineLine = "Reconnaissance sur l'appareil (Apple Vision), confiance \(Int(best * 100)) % : "
                    + (best < 0.5 ? "incertaine, vérifie chaque aliment. " : "")
                    + "Elle reconnaît des catégories, pas le détail d'une assiette ; portions supposées."
                if detected.isEmpty {
                    failed = true
                } else {
                    items = detected
                    usedAI = false
                    Haptics.medium()
                }
            }
        }
    }
    private func save(_ g: FoodGuess) {
        guard !saving else { return }
        let draft = FoodLogService.Draft(name: g.name, calories: guess?.kcal ?? g.kcal,
                                         protein: g.protein, carbs: g.carbs, fat: g.fat,
                                         meal: meal, date: FoodLogService.mealDate(day: mealDay))
        commit([draft]) {}
    }
}

// MARK: - Ajout manuel d'un aliment (recherche OpenFoodFacts)

/// Quand la reconnaissance rate un element de l'assiette.
///
/// On cherche dans OpenFoodFacts, donc les valeurs sont reelles et non
/// inventees, et la portion reste modifiable dans la liste apres ajout.
struct ManualFoodSheet: View {
    var onAdd: (FoodRecognitionPipeline.DetectedFood) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [FoodProduct] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Chercher un aliment…", text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await run() } }
                        if searching { ProgressView().controlSize(.small) }
                    }
                }
                if searched && results.isEmpty && !searching {
                    Section {
                        Text("Aucun résultat. Essaie un mot plus simple, par exemple « riz » plutôt que « riz basmati complet ».")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                ForEach(results) { p in
                    Button {
                        onAdd(FoodRecognitionPipeline.DetectedFood(
                            name: p.name.isEmpty ? query : p.name,
                            confidence: 1,            // choisi a la main, donc certain
                            grams: 100,
                            kcal100: Double(p.kcal), protein100: p.protein,
                            carbs100: p.carbs, fat100: p.fat,
                            source: .openFoodFacts))
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Text("\(p.kcal) kcal / 100 g" + (p.brand.isEmpty ? "" : " · \(p.brand)"))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Ajouter un aliment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        searching = true
        results = await FoodSearchService.search(q)
        searching = false
        searched = true
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
