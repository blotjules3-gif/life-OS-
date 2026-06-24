import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var looksTint: Color { AppCategory.looks.tint } }

// MARK: - Hub Looksmaxx

struct LooksHubView: View {
    var body: some View {
        HubScaffold(category: .looks) {
            ToolRow(icon: "face.dashed", title: "Analyse faciale",
                    subtitle: "Symétrie, harmony — Umax", tint: .looksTint) { FaceAnalysisScaffold() }
            ToolRow(icon: "sparkles", title: "Routine skincare",
                    subtitle: "Matin/soir + rappels", tint: .looksTint) { SkincareView() }
            ToolRow(icon: "camera.fill", title: "Photos avant / après",
                    subtitle: "Suivi visuel daté", tint: .looksTint) { ProgressPhotoGalleryView() }
            ToolRow(icon: "mouth.fill", title: "Mewing & posture",
                    subtitle: "Rappels + minuteur", tint: .looksTint) { MewingPostureView() }
            ToolRow(icon: "tshirt.fill", title: "Garde-robe & outfits",
                    subtitle: "Suggestion selon météo", tint: .looksTint) { WardrobeView() }
        }
    }
}

// MARK: - Skincare

struct SkincareView: View {
    @AppStorage("skincareAM") private var amRaw = "Nettoyant|Sérum vitamine C|Crème hydratante|SPF 50"
    @AppStorage("skincarePM") private var pmRaw = "Démaquillant|Nettoyant|Rétinol|Crème de nuit"
    @AppStorage("skincareReminders") private var reminders = false
    @AppStorage("skincareDoneAM") private var doneAMDate = ""
    @AppStorage("skincareDonePM") private var donePMDate = ""

    private var today: String { ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: .now)) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    routineCard("Matin ☀️", steps: amRaw.split(separator: "|").map(String.init),
                                done: doneAMDate == today) { doneAMDate = doneAMDate == today ? "" : today }
                    routineCard("Soir 🌙", steps: pmRaw.split(separator: "|").map(String.init),
                                done: donePMDate == today) { donePMDate = donePMDate == today ? "" : today }
                    Toggle("Rappels matin (8h) & soir (22h)", isOn: $reminders)
                        .tint(.looksTint)
                        .onChange(of: reminders) { _, on in
                            if on {
                                NotificationManager.shared.scheduleDaily(id: "skinAM", title: "Routine skincare ☀️", body: "Nettoyant + sérum + SPF", hour: 8, minute: 0)
                                NotificationManager.shared.scheduleDaily(id: "skinPM", title: "Routine skincare 🌙", body: "Démaquille et hydrate avant de dormir", hour: 22, minute: 0)
                            } else { NotificationManager.shared.cancel(id: "skinAM"); NotificationManager.shared.cancel(id: "skinPM") }
                        }.card()
                    NavigationLink { ProgressPhotoGalleryView() } label: {
                        Label("Voir mes photos avant/après", systemImage: "camera").foregroundStyle(.looksTint)
                            .frame(maxWidth: .infinity).card(padding: 12)
                    }.buttonStyle(.plain)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Routine skincare").navigationBarTitleDisplayMode(.inline)
    }
    private func routineCard(_ title: String, steps: [String], done: Bool, toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: toggle) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(done ? .green : Theme.textSecondary)
                }
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 10) {
                    Text("\(i+1)").font(.caption.bold()).frame(width: 22, height: 22)
                        .background(Color.looksTint.opacity(0.2), in: Circle()).foregroundStyle(.looksTint)
                    Text(step).font(.subheadline).foregroundStyle(Theme.textPrimary)
                }
            }
        }.card()
    }
}

// MARK: - Photos avant/après

struct ProgressPhotoGalleryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                if photos.isEmpty {
                    EmptyState(icon: "camera", title: "Aucune photo", message: "Prends une photo de référence aujourd'hui, puis compare dans 1 mois.")
                } else {
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(photos) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                StoredImage(filename: p.filename)
                                    .frame(height: 180).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                HStack {
                                    Text(p.date, style: .date).font(.caption2).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(p.category).font(.caption2.bold()).foregroundStyle(.looksTint)
                                }
                            }
                            .contextMenu { Button(role: .destructive) { ImageStore.delete(p.filename); ctx.delete(p) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }.padding(Theme.pad)
                }
            }
        }
        .navigationTitle("Avant / après").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            PhotoPickerButton(label: "", prefix: "progress") { name in ctx.insert(ProgressPhoto(filename: name)) }
        } }
    }
}

// MARK: - Mewing & posture

struct MewingPostureView: View {
    @AppStorage("postureReminder") private var posture = false
    @State private var engine = CountdownEngine()
    @State private var started = false

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Mewing — séance guidée")
                        Text("Langue à plat contre le palais, dents légèrement en contact, lèvres fermées. Respire par le nez. Tiens la position pendant le minuteur.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }.card()

                    TimerDial(engine: engine, tint: .looksTint, caption: started ? "Maintiens la posture" : "3 min")
                    if !started {
                        PrimaryButton(title: "Démarrer 3 min", icon: "play.fill", tint: .looksTint) {
                            started = true; engine.onFinish = { started = false }; engine.start(seconds: 180)
                        }
                    } else {
                        PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) { engine.stop(); started = false }
                    }

                    Toggle("Rappel posture toutes les 2h (9h-19h)", isOn: $posture)
                        .tint(.looksTint)
                        .onChange(of: posture) { _, on in
                            for h in stride(from: 9, through: 19, by: 2) {
                                if on { NotificationManager.shared.scheduleDaily(id: "posture\(h)", title: "Redresse-toi 🧍", body: "Épaules en arrière, menton rentré, langue au palais.", hour: h, minute: 0) }
                                else { NotificationManager.shared.cancel(id: "posture\(h)") }
                            }
                        }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Mewing & posture").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Garde-robe & outfits

struct WardrobeView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var items: [WardrobeItem]
    @State private var showAdd = false
    @State private var weather = 1   // 0 froid, 1 doux, 2 chaud
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Outfit du jour", subtitle: "Selon la météo")
                        Picker("Météo", selection: $weather) {
                            Text("❄️ Froid").tag(0); Text("🌤️ Doux").tag(1); Text("☀️ Chaud").tag(2)
                        }.pickerStyle(.segmented)
                        let outfit = OutfitEngine.suggest(items: items, weather: weather)
                        if outfit.isEmpty {
                            Text("Ajoute des vêtements pour générer une tenue.").font(.footnote).foregroundStyle(Theme.textSecondary)
                        } else {
                            ForEach(outfit) { it in
                                HStack {
                                    StoredImage(filename: it.filename, placeholder: "tshirt").frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading) {
                                        Text(it.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text("\(it.category) · \(it.colorName)").font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }.card()

                    if items.isEmpty {
                        EmptyState(icon: "tshirt", title: "Garde-robe vide", message: "Ajoute tes pièces une à une.")
                    } else {
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(items) { it in
                                VStack(spacing: 4) {
                                    StoredImage(filename: it.filename, placeholder: "tshirt").frame(height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(it.name).font(.caption2).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                }
                                .contextMenu { Button(role: .destructive) { ImageStore.delete(it.filename); ctx.delete(it) } label: { Label("Supprimer", systemImage: "trash") } }
                            }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Garde-robe").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { WardrobeEditor() }
    }
}

enum OutfitEngine {
    /// Sélectionne une pièce par catégorie adaptée à la chaleur recherchée.
    static func suggest(items: [WardrobeItem], weather: Int) -> [WardrobeItem] {
        // weather 0=froid (warmth 3), 1=doux (2), 2=chaud (1)
        let targetWarmth = 3 - weather
        var result: [WardrobeItem] = []
        for cat in ["Haut", "Bas", "Chaussures", "Veste"] {
            let pool = items.filter { $0.category == cat }
            guard !pool.isEmpty else { continue }
            if cat == "Veste" && weather == 2 { continue } // pas de veste quand il fait chaud
            let best = pool.min { abs($0.warmth - targetWarmth) < abs($1.warmth - targetWarmth) }
            if let best { result.append(best) }
        }
        return result
    }
}

struct WardrobeEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var category = "Haut"; @State private var color = "Noir"
    @State private var warmth = 2; @State private var filename: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex: Pull col rond)", text: $name)
                Picker("Catégorie", selection: $category) { ForEach(["Haut","Bas","Chaussures","Veste","Accessoire"], id: \.self) { Text($0) } }
                Picker("Couleur", selection: $color) { ForEach(["Noir","Blanc","Gris","Bleu","Beige","Vert","Marron","Rouge"], id: \.self) { Text($0) } }
                Picker("Chaleur", selection: $warmth) { Text("Léger").tag(1); Text("Moyen").tag(2); Text("Chaud").tag(3) }
                Section("Photo") {
                    PhotoPickerButton(label: "Choisir une photo", prefix: "wardrobe") { filename = $0 }
                    if filename != nil { Text("Photo ajoutée ✓").foregroundStyle(.green).font(.caption) }
                }
            }
            .navigationTitle("Ajouter une pièce").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(WardrobeItem(name: name, category: category, colorName: color, warmth: warmth, filename: filename)); dismiss()
                }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Analyse faciale (scaffold)

struct FaceAnalysisScaffold: View {
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "face.dashed").font(.system(size: 56)).foregroundStyle(.looksTint).padding(.top, 30)
                    Text("Analyse faciale").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    IntegrationNotice(text: "Les scores type Umax / LooksMax AI (symétrie, ratios, « potential ») reposent sur la détection de points faciaux + un modèle entraîné, souvent contesté scientifiquement. Techniquement on peut détecter 76+ landmarks gratuitement avec le framework Vision d'Apple (VNDetectFaceLandmarks) et calculer des ratios objectifs (symétrie, tiers du visage, ratio largeur/hauteur). Le « score d'attractivité » lui nécessite un modèle ML entraîné séparé.")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ce qui est faisable proprement").font(.headline).foregroundStyle(Theme.textPrimary)
                        bullet("Détection landmarks : Vision (gratuit, on-device)")
                        bullet("Ratios objectifs : symétrie G/D, règle des tiers, FWHR")
                        bullet("Suivi dans le temps via les photos avant/après (déjà actif)")
                        bullet("Score « subjectif » : modèle ML à entraîner/host séparément")
                    }.card()
                    NavigationLink { ProgressPhotoGalleryView() } label: {
                        Label("Commencer par une photo de référence", systemImage: "camera").foregroundStyle(.looksTint).frame(maxWidth: .infinity).card(padding: 12)
                    }.buttonStyle(.plain)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Analyse faciale").navigationBarTitleDisplayMode(.inline)
    }
    private func bullet(_ t: String) -> some View { Text("• " + t).font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
}
