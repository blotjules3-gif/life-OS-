import SwiftUI
import SwiftData
import ImageIO

extension ShapeStyle where Self == Color { static var looksTint: Color { AppCategory.looks.tint } }

// MARK: - Hub Looksmaxx


// MARK: - Skincare

struct SkincareView: View {
    @AppStorage(AppStorageKeys.skincareAM) private var amRaw = "Nettoyant|Sérum vitamine C|Crème hydratante|SPF 50"
    @AppStorage(AppStorageKeys.skincarePM) private var pmRaw = "Démaquillant|Nettoyant|Rétinol|Crème de nuit"
    @AppStorage(AppStorageKeys.skincareReminders) private var reminders = false
    @AppStorage(AppStorageKeys.skincareDoneAM) private var doneAMDate = ""
    @AppStorage(AppStorageKeys.skincareDonePM) private var donePMDate = ""
    @AppStorage(AppStorageKeys.skinType) private var skinType = ""
    @AppStorage(AppStorageKeys.skinConcernsRaw) private var skinConcernsRaw = ""
    @AppStorage(AppStorageKeys.skinTreatment) private var skinTreatment = ""

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
                                    .font(.title3).foregroundStyle(.looksTint)
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
                            .background(Color.looksTint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).stroke(Color.looksTint.opacity(0.2), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }

                    routineCard("Matin", steps: amSteps,
                                done: doneAMDate == today) { doneAMDate = doneAMDate == today ? "" : today }
                    routineCard("Soir", steps: pmSteps,
                                done: donePMDate == today) { donePMDate = donePMDate == today ? "" : today }

                    Toggle("Rappels matin (8h) & soir (22h)", isOn: $reminders)
                        .tint(.looksTint)
                        .onChange(of: reminders) { _, _ in syncReminders() }
                        // Le texte du rappel reprend la routine affichee: s'il change
                        // de profil, le rappel deja pose doit suivre.
                        .onChange(of: skinType) { _, _ in if reminders { syncReminders() } }
                        .onChange(of: skinConcernsRaw) { _, _ in if reminders { syncReminders() } }
                        .onChange(of: skinTreatment) { _, _ in if reminders { syncReminders() } }
                        .card()

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

    /// Le corps du rappel etait fige sur "Nettoyant + sérum + SPF", meme quand la
    /// routine generee etait autre (eau micellaire pour peau sensible...).
    private func syncReminders() {
        if reminders {
            NotificationManager.shared.scheduleDaily(id: "skinAM", title: "Routine skincare matin", body: SkinRoutineEngine.reminderBody(steps: amSteps), hour: 8, minute: 0)
            NotificationManager.shared.scheduleDaily(id: "skinPM", title: "Routine skincare soir", body: SkinRoutineEngine.reminderBody(steps: pmSteps), hour: 22, minute: 0)
        } else {
            NotificationManager.shared.cancel(id: "skinAM")
            NotificationManager.shared.cancel(id: "skinPM")
        }
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
        return SkinRoutineEngine.eveningSteps(skinType: skinType, concerns: skinConcernsRaw, treatment: skinTreatment)
    }

    private var skinProfileBadge: some View {
        Button { showProfile = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18)).foregroundStyle(Theme.success)
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
            .background(Theme.success.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func routineCard(_ title: String, steps: [String], done: Bool, toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: toggle) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(done ? Theme.success : Theme.textSecondary)
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
    /// Marqueur range avec les preoccupations quand un traitement est declare.
    static let treatmentMarker = "traitement"

    /// Lit la chaine sauvee ("acné,rides,traitement") en preoccupations + traitement.
    static func decode(concernsRaw: String) -> (concerns: Set<String>, hasTreatment: Bool) {
        var set = Set(concernsRaw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        let treat = set.remove(treatmentMarker) != nil
        return (set, treat)
    }

    /// Inverse de `decode`. Trie pour que la meme saisie donne la meme chaine.
    static func encode(concerns: Set<String>, hasTreatment: Bool) -> String {
        var c = concerns.subtracting([treatmentMarker]).sorted()
        if hasTreatment { c.append(treatmentMarker) }
        return c.joined(separator: ",")
    }

    /// Texte du rappel = la routine reelle, pas un texte fige.
    static func reminderBody(steps: [String]) -> String {
        steps.isEmpty ? "C'est l'heure de ta routine." : steps.joined(separator: " + ")
    }

    // Avant, seules "acné" et "taches" etaient lues: cocher rides, pores, teint
    // terne ou rougeurs ne changeait rien a la routine.
    static func morningSteps(skinType: String, concerns: String) -> [String] {
        let (set, hasTreat) = decode(concernsRaw: concerns)
        let hasAcne    = set.contains("acné")
        let hasTaches  = set.contains("taches")
        let hasRides   = set.contains("rides")
        let hasPores   = set.contains("pores")
        let hasTerne   = set.contains("teint terne")
        // Rougeurs = peau reactive: on prend les versions douces.
        let isSensible = skinType == "sensible" || set.contains("rougeurs")
        let isGrasse   = skinType == "grasse"
        let isSèche    = skinType == "sèche"

        var steps = [String]()
        steps.append(isGrasse || hasAcne ? "Nettoyant gel purifiant" : isSensible ? "Eau micellaire (sans rinçage)" : "Nettoyant doux")
        let niacinamide = (hasAcne || hasPores) && !hasTreat
        let vitaminC    = hasTaches || hasTerne || hasRides
        if niacinamide             { steps.append("Sérum niacinamide 10%") }
        if vitaminC                { steps.append("Sérum vitamine C") }
        if !niacinamide && !vitaminC { steps.append("Sérum hydratant") }
        steps.append(isSèche ? "Crème riche hydratante" : isSensible ? "Crème barrière légère" : "Crème hydratante non comédogène")
        steps.append(isSensible ? "SPF 50 minéral" : "SPF 50")
        return steps
    }

    static func eveningSteps(skinType: String, concerns: String, treatment: String = "") -> [String] {
        let (set, hasTreat) = decode(concernsRaw: concerns)
        let hasAcne    = set.contains("acné")
        let hasPores   = set.contains("pores")
        let isGrasse   = skinType == "grasse"
        let isSensible = skinType == "sensible" || set.contains("rougeurs")
        let isSèche    = skinType == "sèche"
        let name = treatment.trimmingCharacters(in: .whitespacesAndNewlines)

        var steps = [String]()
        steps.append("Démaquillant (huile ou baume)")
        steps.append(isGrasse || hasAcne ? "Nettoyant gel purifiant" : "Nettoyant doux")
        if hasTreat {
            // Le nom saisi par l'utilisateur etait sauve puis jamais affiche.
            steps.append(name.isEmpty ? "Traitement prescrit (appliquer sur peau sèche)"
                                      : "Traitement prescrit : \(name) (appliquer sur peau sèche)")
        }
        else if hasAcne || hasPores    { steps.append("Acide salicylique 1% (3× par semaine)") }
        else if !isSensible            { steps.append("Rétinol 0,1% (2× par semaine)") }
        steps.append(isSèche ? "Crème de nuit riche" : isSensible ? "Crème barrière réparatrice" : "Crème de nuit légère")
        return steps
    }
}

// MARK: - Setup profil peau

struct SkinProfileSetupView: View {
    @AppStorage(AppStorageKeys.skinType) private var skinType = ""
    @AppStorage(AppStorageKeys.skinConcernsRaw) private var skinConcernsRaw = ""
    @AppStorage(AppStorageKeys.skinTreatment) private var skinTreatment = ""
    @AppStorage(AppStorageKeys.userGender) private var gender = ""
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
        // Repart du profil sauve: avant, l'editeur demarrait vide et "Modifier"
        // puis Enregistrer effacait preoccupations et traitement non ressaisis.
        .onAppear(perform: loadSaved)
    }

    private func loadSaved() {
        selectedType = skinType
        let saved = SkinRoutineEngine.decode(concernsRaw: skinConcernsRaw)
        concerns = saved.concerns
        hasTreatment = saved.hasTreatment
        treatmentText = skinTreatment
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
                        .background(selectedType == t ? Color.looksTint.opacity(0.1) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            .background(concerns.contains(c) ? Color.looksTint.opacity(0.20) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .padding(14).background(!hasTreatment ? AnyShapeStyle(Color.looksTint.opacity(0.1)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                Button { hasTreatment = true } label: {
                    HStack { Text("Oui, j'ai un traitement"); Spacer(); if hasTreatment { Image(systemName: "checkmark.circle.fill").foregroundStyle(.looksTint) } }
                        .padding(14).background(hasTreatment ? AnyShapeStyle(Color.looksTint.opacity(0.1)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                if hasTreatment {
                    TextField("Nom du traitement (ex: tretinoin 0,025%)", text: $treatmentText)
                        .textFieldStyle(.roundedBorder).padding(.top, 4)
                }
            }.padding(.horizontal, 24)
            Spacer()
            Button {
                skinType = selectedType
                skinConcernsRaw = SkinRoutineEngine.encode(concerns: concerns, hasTreatment: hasTreatment)
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
    /// Categorie des prochaines photos. Avant, tout partait en "Visage" (valeur
    /// par defaut du modele), meme une photo du corps.
    @State private var category = "Visage"
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    static let categories = ["Visage", "Peau", "Corps"]

    /// Date de prise de vue lue dans l'EXIF du fichier.
    /// Avant, chaque photo prenait l'heure de l'import: une photo d'il y a trois
    /// mois apparaissait datee d'aujourd'hui dans une galerie "avant / apres".
    static func captureDate(of data: Data) -> Date? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        return raw.flatMap { parseExifDate($0) }
    }

    /// Format EXIF "yyyy:MM:dd HH:mm:ss", heure locale de l'appareil photo.
    /// Une date dans le futur est rejetee (horloge d'appareil fausse).
    static func parseExifDate(_ s: String, now: Date = Date(), timeZone: TimeZone = .current) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let d = f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              d <= now.addingTimeInterval(86_400) else { return nil }
        return d
    }

    private func addPhoto(_ name: String) {
        // Sans EXIF (capture d'ecran, image retouchee), seule la date d'import est connue.
        let taken = ImageStore.url(for: name)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { Self.captureDate(of: $0) }
        ctx.insert(ProgressPhoto(date: taken ?? .now, filename: name, category: category))
    }

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
                            .contextMenu {
                                // Reclasser les photos deja importees en "Visage" par erreur.
                                ForEach(Self.categories.filter { $0 != p.category }, id: \.self) { c in
                                    Button { p.category = c } label: { Label("Classer en \(c)", systemImage: "tag") }
                                }
                                Button(role: .destructive) { ImageStore.delete(p.filename); ctx.delete(p) } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
                    }.padding(Theme.pad)
                }
            }
        }
        .navigationTitle("Avant / après").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Catégorie", selection: $category) {
                    ForEach(Self.categories, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).tint(.looksTint)
            }
            ToolbarItem(placement: .topBarTrailing) {
                PhotoPickerButton(label: "", prefix: "progress") { name in addPhoto(name) }
            }
        }
    }
}

// MARK: - Mewing & posture

struct MewingPostureView: View {
    @AppStorage(AppStorageKeys.postureReminder) private var posture = false
    @State private var engine = CountdownEngine(key: "mewing")
    /// Derive du moteur: un @State local repartait a faux au retour sur l'ecran
    /// alors que la seance restauree tournait encore ("Démarrer" sur un cadran
    /// qui defile, et un appui relancait la seance).
    private var started: Bool { engine.isRunning }

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
                            engine.start(seconds: 180)
                        }
                    } else {
                        PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) { engine.stop() }
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
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
    /// Le fichier photo est ecrit des le choix. Sans ce drapeau, Annuler (ou un
    /// balayage vers le bas) laissait un fichier orphelin dans Documents.
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex: Pull col rond)", text: $name)
                Picker("Catégorie", selection: $category) { ForEach(["Haut","Bas","Chaussures","Veste","Accessoire"], id: \.self) { Text($0) } }
                Picker("Couleur", selection: $color) { ForEach(["Noir","Blanc","Gris","Bleu","Beige","Vert","Marron","Rouge"], id: \.self) { Text($0) } }
                Picker("Chaleur", selection: $warmth) { Text("Léger").tag(1); Text("Moyen").tag(2); Text("Chaud").tag(3) }
                Section("Photo") {
                    PhotoPickerButton(label: "Choisir une photo", prefix: "wardrobe") { name in
                        // Une 2e photo remplace la 1re: l'ancienne ne servira plus.
                        if let old = filename, old != name { ImageStore.delete(old) }
                        filename = name
                    }
                    if filename != nil { Text("Photo ajoutée").foregroundStyle(Theme.success).font(.caption) }
                }
            }
            .navigationTitle("Ajouter une pièce").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(WardrobeItem(name: name, category: category, colorName: color, warmth: warmth, filename: filename))
                    saved = true; dismiss()
                }.disabled(name.isEmpty) }
            }
        }
        .onDisappear { if !saved, let f = filename { ImageStore.delete(f) } }
    }
}

// MARK: - Analyse faciale (scaffold)

