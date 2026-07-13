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
    @AppStorage("skinType") private var skinType = ""
    @AppStorage("skinConcernsRaw") private var skinConcernsRaw = ""

    @State private var showProfile = false
    private var today: String { ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: .now)) }
    private var hasProfile: Bool { !skinType.isEmpty }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    // Profil peau
                    if hasProfile {
                        skinProfileBadge
                    } else {
                        Button { showProfile = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.square.fill")
                                    .font(.system(size: 20)).foregroundStyle(.looksTint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Configure ton profil peau")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Obtiens une routine adaptée à ton type de peau")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(Color.looksTint.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).stroke(Color.looksTint.opacity(0.2), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }

                    routineCard("Matin", steps: amSteps,
                                done: doneAMDate == today) { doneAMDate = doneAMDate == today ? "" : today }
                    routineCard("Soir", steps: pmSteps,
                                done: donePMDate == today) { donePMDate = donePMDate == today ? "" : today }

                    Toggle("Rappels matin (8h) & soir (22h)", isOn: $reminders)
                        .tint(.looksTint)
                        .onChange(of: reminders) { _, on in
                            if on {
                                NotificationManager.shared.scheduleDaily(id: "skinAM", title: "Routine skincare matin", body: "Nettoyant + sérum + SPF", hour: 8, minute: 0)
                                NotificationManager.shared.scheduleDaily(id: "skinPM", title: "Routine skincare soir", body: "Démaquille et hydrate avant de dormir", hour: 22, minute: 0)
                            } else {
                                NotificationManager.shared.cancel(id: "skinAM")
                                NotificationManager.shared.cancel(id: "skinPM")
                            }
                        }.card()

                    NavigationLink { ProgressPhotoGalleryView() } label: {
                        Label("Photos avant/après", systemImage: "camera").foregroundStyle(.looksTint)
                            .frame(maxWidth: .infinity).card(padding: 12)
                    }.buttonStyle(.plain)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Skincare").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProfile) { SkinProfileSetupView() }
    }

    // Routine adaptée au profil ou générique
    private var amSteps: [String] {
        guard !skinType.isEmpty else {
            return amRaw.split(separator: "|").map(String.init)
        }
        return SkinRoutineEngine.morningSteps(skinType: skinType, concerns: skinConcernsRaw)
    }
    private var pmSteps: [String] {
        guard !skinType.isEmpty else {
            return pmRaw.split(separator: "|").map(String.init)
        }
        return SkinRoutineEngine.eveningSteps(skinType: skinType, concerns: skinConcernsRaw)
    }

    private var skinProfileBadge: some View {
        Button { showProfile = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profil peau : \(skinType.capitalized)")
                        .font(.subheadline.weight(.semibold))
                    if !skinConcernsRaw.isEmpty {
                        Text(skinConcernsRaw.replacingOccurrences(of: ",", with: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Modifier").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
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

// MARK: - Moteur de routine skincare personnalisée

enum SkinRoutineEngine {
    static func morningSteps(skinType: String, concerns: String) -> [String] {
        let hasAcne    = concerns.contains("acné")
        let hasTaches  = concerns.contains("taches")
        let isSensible = skinType == "sensible"
        let isGrasse   = skinType == "grasse"
        let isSèche    = skinType == "sèche"
        let hasTreat   = concerns.contains("traitement")

        var steps = [String]()
        steps.append(isGrasse || hasAcne ? "Nettoyant gel purifiant" : isSensible ? "Eau micellaire (sans rinçage)" : "Nettoyant doux")
        if hasAcne && !hasTreat    { steps.append("Sérum niacinamide 10%") }
        if hasTaches               { steps.append("Sérum vitamine C") }
        if !hasAcne && !hasTaches  { steps.append("Sérum hydratant") }
        steps.append(isSèche ? "Crème riche hydratante" : isSensible ? "Crème barrière légère" : "Crème hydratante non comédogène")
        steps.append(isSensible ? "SPF 50 minéral" : "SPF 50")
        return steps
    }

    static func eveningSteps(skinType: String, concerns: String) -> [String] {
        let hasAcne    = concerns.contains("acné")
        let isGrasse   = skinType == "grasse"
        let isSensible = skinType == "sensible"
        let isSèche    = skinType == "sèche"
        let hasTreat   = concerns.contains("traitement")

        var steps = [String]()
        steps.append("Démaquillant (huile ou baume)")
        steps.append(isGrasse || hasAcne ? "Nettoyant gel purifiant" : "Nettoyant doux")
        if hasTreat                    { steps.append("Traitement prescrit (appliquer sur peau sèche)") }
        else if hasAcne                { steps.append("Acide salicylique 1% (3× par semaine)") }
        else if !isSensible            { steps.append("Rétinol 0,1% (2× par semaine)") }
        steps.append(isSèche ? "Crème de nuit riche" : isSensible ? "Crème barrière réparatrice" : "Crème de nuit légère")
        return steps
    }
}

// MARK: - Setup profil peau

struct SkinProfileSetupView: View {
    @AppStorage("skinType") private var skinType = ""
    @AppStorage("skinConcernsRaw") private var skinConcernsRaw = ""
    @AppStorage("skinTreatment") private var skinTreatment = ""
    @AppStorage("userGender") private var gender = ""
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType = ""
    @State private var concerns: Set<String> = []
    @State private var hasTreatment = false
    @State private var treatmentText = ""
    @State private var step = 0

    private let skinTypes = ["normale", "sèche", "grasse", "mixte", "sensible"]
    private let skinConcerns = ["acné", "taches", "rides", "pores", "teint terne", "rougeurs"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { s in
                        Capsule().fill(step >= s ? Color.looksTint : Color.secondary.opacity(0.15)).frame(height: 4)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)

                Group {
                    switch step {
                    case 0: typeStep
                    case 1: concernsStep
                    case 2: treatmentStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal:   .move(edge: .leading).combined(with: .opacity)))
                .id(step)

                Spacer()
            }
            .navigationTitle("Profil peau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ton type de peau").font(.title2.bold()).padding(.horizontal, 24)
            VStack(spacing: 10) {
                ForEach(skinTypes, id: \.self) { t in
                    Button { selectedType = t } label: {
                        HStack {
                            Text(t.capitalized).font(.body)
                            Spacer()
                            if selectedType == t {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.looksTint)
                            }
                        }
                        .padding(14)
                        .background(selectedType == t ? Color.looksTint.opacity(0.1) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 24)
            Spacer()
            Button { withAnimation { step = 1 } } label: {
                Text("Continuer").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(selectedType.isEmpty ? Color.secondary.opacity(0.3) : Color.looksTint,
                                in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain).disabled(selectedType.isEmpty).padding(.horizontal, 24).padding(.bottom, 32)
        }
    }

    private var concernsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tes préoccupations").font(.title2.bold()).padding(.horizontal, 24)
            Text("Plusieurs choix possibles").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 24)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(skinConcerns, id: \.self) { c in
                    Button { if concerns.contains(c) { concerns.remove(c) } else { concerns.insert(c) } } label: {
                        Text(c.capitalized).font(.subheadline.weight(.medium))
                            .foregroundStyle(concerns.contains(c) ? Color.looksTint : .primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(concerns.contains(c) ? Color.looksTint.opacity(0.12) : Theme.card,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(concerns.contains(c) ? Color.looksTint.opacity(0.4) : Color.clear, lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 24)
            Spacer()
            Button { withAnimation { step = 2 } } label: {
                Text("Continuer").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.looksTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 32)
        }
    }

    private var treatmentStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Traitement en cours ?").font(.title2.bold()).padding(.horizontal, 24)
            Text("Tretinoin, adapalène, acide azélaïque, isotrétinoïne...").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 24)
            VStack(spacing: 10) {
                Button { hasTreatment = false } label: {
                    HStack { Text("Non, aucun traitement"); Spacer(); if !hasTreatment { Image(systemName: "checkmark.circle.fill").foregroundStyle(.looksTint) } }
                        .padding(14).background(!hasTreatment ? AnyShapeStyle(Color.looksTint.opacity(0.1)) : Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                Button { hasTreatment = true } label: {
                    HStack { Text("Oui, j'ai un traitement"); Spacer(); if hasTreatment { Image(systemName: "checkmark.circle.fill").foregroundStyle(.looksTint) } }
                        .padding(14).background(hasTreatment ? AnyShapeStyle(Color.looksTint.opacity(0.1)) : Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                if hasTreatment {
                    TextField("Nom du traitement (ex: tretinoin 0,025%)", text: $treatmentText)
                        .textFieldStyle(.roundedBorder).padding(.top, 4)
                }
            }.padding(.horizontal, 24)
            Spacer()
            Button {
                skinType = selectedType
                var c = Array(concerns)
                if hasTreatment { c.append("traitement") }
                skinConcernsRaw = c.joined(separator: ",")
                skinTreatment = hasTreatment ? treatmentText : ""
                dismiss()
            } label: {
                Text("Enregistrer mon profil").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.looksTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 32)
        }
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
                                if on { NotificationManager.shared.scheduleDaily(id: "posture\(h)", title: "Redresse-toi", body: "Épaules en arrière, menton rentré, langue au palais.", hour: h, minute: 0) }
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
                            Text("Froid").tag(0); Text("Doux").tag(1); Text("Chaud").tag(2)
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
                    if filename != nil { Text("Photo ajoutée").foregroundStyle(.green).font(.caption) }
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
