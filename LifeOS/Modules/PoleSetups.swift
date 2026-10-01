import SwiftUI
import SwiftData

// MARK: - Formulaires de configuration des pôles (écrivent des données réelles)

// ---- Productivité ---------------------------------------------------------

struct ProductivitySetupView: View {
    @AppStorage(AppStorageKeys.focusMinGoal) private var focusGoal = 90
    @AppStorage(AppStorageKeys.focusLen)     private var focusLen = 25
    @AppStorage(AppStorageKeys.socialMaxMin) private var socialMax = 60

    @State private var goal = 90
    @State private var pomo = 25
    @State private var screen = 60
    private let tint = AppCategory.productivity.tint

    var body: some View {
        SetupFlow(title: "Productivité", accent: tint, pages: pages, onComplete: {
            focusGoal = goal; focusLen = pomo; socialMax = screen
            CategorySetup.markDone(.productivity); Haptics.success()
        }, preview: {
            [.make("Minutes de focus par jour", "\(focusGoal) min", "\(goal) min"),
             .make("Durée d'un Pomodoro", "\(focusLen) min", "\(pomo) min"),
             .make("Réseaux sociaux max", "\(socialMax) min", "\(screen) min")].compactMap { $0 }
        }, draft: draftIO)
        .onAppear { goal = focusGoal; pomo = focusLen; screen = socialMax }
    }
    private var pages: [SetupPage] {
        [
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "target", title: "Objectif de concentration",
                            subtitle: "Minutes de focus visées chaque jour.", accent: tint)
                SetupNumber(value: $goal, unit: "min", range: 15...480, step: 15, accent: tint) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "timer", title: "Durée d'un bloc Pomodoro", accent: tint)
                SetupNumber(value: $pomo, unit: "min", range: 10...60, step: 5, accent: tint) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "iphone", title: "Limite d'écran quotidienne",
                            subtitle: "Objectif pour réduire le temps sur le téléphone.", accent: tint)
                SetupNumber(value: $screen, unit: "min", range: 15...480, step: 15, accent: tint) } },
        ]
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("goal", goal)
            d.put("pomo", pomo)
            d.put("screen", screen)
            return d
        }, restore: { d in
            if let v = d.int("goal") { goal = v }
            if let v = d.int("pomo") { pomo = v }
            if let v = d.int("screen") { screen = v }
        })
    }
}

// ---- Mental & focus -------------------------------------------------------

struct MentalSetupView: View {
    @AppStorage(AppStorageKeys.meditationGoalMin) private var meditGoal = 10
    @AppStorage(AppStorageKeys.socialMaxMin)      private var socialMax = 60

    @State private var medit = 10
    @State private var screen = 60
    @State private var stress = "Moyen"
    private let tint = AppCategory.mind.tint

    var body: some View {
        SetupFlow(title: "Mental & focus", accent: tint, pages: pages, onComplete: {
            meditGoal = medit; socialMax = screen
            CategorySetup.markDone(.mind); Haptics.success()
        }, preview: {
            [.make("Méditation par jour", "\(meditGoal) min", "\(medit) min"),
             .make("Réseaux sociaux max", "\(socialMax) min", "\(screen) min")].compactMap { $0 }
        }, draft: draftIO)
        .onAppear { medit = meditGoal; screen = socialMax }
    }
    private var pages: [SetupPage] {
        [
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "brain.head.profile", title: "Ton niveau de stress ?",
                            subtitle: "On adaptera les respirations et sons proposés.", accent: tint)
                SetupChoice(options: ["Faible", "Moyen", "Élevé"], selection: $stress, accent: tint) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "leaf.fill", title: "Objectif de méditation",
                            subtitle: "Minutes par jour.", accent: tint)
                SetupNumber(value: $medit, unit: "min", range: 3...60, step: 1, accent: tint) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "hourglass", title: "Limite d'écran (détox)", accent: tint)
                SetupNumber(value: $screen, unit: "min", range: 15...480, step: 15, accent: tint) } },
        ]
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("medit", medit)
            d.put("screen", screen)
            d.put("stress", stress)
            return d
        }, restore: { d in
            if let v = d.int("medit") { medit = v }
            if let v = d.int("screen") { screen = v }
            if let v = d.string("stress") { stress = v }
        })
    }
}

// ---- Looksmaxx ------------------------------------------------------------

struct LooksSetupView: View {
    @AppStorage(AppStorageKeys.skinType)           private var skinType = ""
    @AppStorage(AppStorageKeys.skinConcernsRaw)    private var concernsRaw = ""
    @AppStorage(AppStorageKeys.skincareLevel)      private var skincareLevelStore = ""
    @AppStorage(AppStorageKeys.faceShape)          private var faceShapeStore = ""
    @AppStorage(AppStorageKeys.hairColor)          private var hairColorStore = ""
    @AppStorage(AppStorageKeys.hairGoalsRaw)       private var hairGoalsRaw = ""
    @AppStorage(AppStorageKeys.browGoalsRaw)       private var browGoalsRaw = ""
    @AppStorage(AppStorageKeys.smileGoalsRaw)      private var smileGoalsRaw = ""
    @AppStorage(AppStorageKeys.groomingRaw)        private var groomingRaw = ""
    @AppStorage(AppStorageKeys.skincareReminders)  private var reminders = false

    @State private var type = "Normale"
    @State private var concerns: Set<String> = []
    @State private var skincareLevel = "Basique"
    @State private var faceShape = ""
    @State private var hairColor = "Châtain"
    @State private var hairGoals: Set<String> = []
    @State private var browGoals: Set<String> = []
    @State private var smileGoals: Set<String> = []
    @State private var grooming: Set<String> = []
    @State private var remind = "Oui"
    private let tint = AppCategory.looks.tint

    private let skinTypes: [(String, String)] = [
        ("Normale", "Grain fin, ni trop grasse ni sèche, peu d'imperfections."),
        ("Sèche", "Tiraille, aspect terne, parfois des squames."),
        ("Grasse", "Brille (zone T), pores dilatés, tendance imperfections."),
        ("Mixte", "Zone T grasse, joues normales à sèches."),
        ("Sensible", "Rougeurs, réactive, tiraille avec certains produits."),
    ]

    var body: some View {
        SetupFlow(title: "Looksmaxx", accent: tint, pages: pages, onComplete: {
            skinType = type
            concernsRaw = concerns.sorted().joined(separator: ",")
            skincareLevelStore = skincareLevel
            faceShapeStore = faceShape
            hairColorStore = hairColor
            hairGoalsRaw = hairGoals.sorted().joined(separator: ",")
            browGoalsRaw = browGoals.sorted().joined(separator: ",")
            smileGoalsRaw = smileGoals.sorted().joined(separator: ",")
            groomingRaw = grooming.sorted().joined(separator: ",")
            reminders = (remind == "Oui")
            CategorySetup.markDone(.looks); Haptics.success()
        }, preview: {
            let list: (Set<String>) -> String = { $0.isEmpty ? "—" : $0.sorted().joined(separator: ", ") }
            let stored: (String) -> Set<String> = { Set($0.split(separator: ",").map(String.init)) }
            return [.make("Type de peau", skinType.isEmpty ? "—" : skinType, type),
                    .make("Préoccupations", list(stored(concernsRaw)), list(concerns)),
                    .make("Routine skincare", skincareLevelStore.isEmpty ? "—" : skincareLevelStore, skincareLevel),
                    .make("Rappels skincare", reminders ? "Oui" : "Non", remind)].compactMap { $0 }
        }, draft: draftIO)
        .onAppear {
            if !skinType.isEmpty { type = skinType }
            concerns = Set(concernsRaw.split(separator: ",").map(String.init))
            if !skincareLevelStore.isEmpty { skincareLevel = skincareLevelStore }
            faceShape = faceShapeStore
            if !hairColorStore.isEmpty { hairColor = hairColorStore }
            hairGoals = Set(hairGoalsRaw.split(separator: ",").map(String.init))
            browGoals = Set(browGoalsRaw.split(separator: ",").map(String.init))
            smileGoals = Set(smileGoalsRaw.split(separator: ",").map(String.init))
            grooming = Set(groomingRaw.split(separator: ",").map(String.init))
            remind = reminders ? "Oui" : "Non"
        }
    }

    private var pages: [SetupPage] {
        [
            // 1 — Analyse de la forme du visage (on-device) → coupe adaptée
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "face.dashed", title: "Analyse de ton visage",
                            subtitle: "Prends une photo de face : ton iPhone estime la forme de ton visage et te conseille la coupe la plus flatteuse.",
                            accent: tint)
                FaceScanView(accent: tint) { shape in faceShape = shape.rawValue }
            } },

            // 2 — Type de peau ILLUSTRÉ
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "drop.fill", title: "Ton type de peau ?",
                            subtitle: "Regarde ta peau 1 h après nettoyage, sans produit.", accent: tint)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(skinTypes, id: \.0) { st in
                        Button { type = st.0; Haptics.soft() } label: {
                            SkinTypeCard(type: st.0, desc: st.1, selected: type == st.0, accent: tint)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14)
            } },

            // 3 — Préoccupations peau
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "infinity", title: "Tes objectifs peau",
                            subtitle: "On adaptera ta routine skincare.", accent: tint)
                SetupMultiChoice(options: ["Acné", "Points noirs", "Rides", "Taches", "Cernes", "Pores", "Rougeurs", "Éclat", "Fermeté"],
                                 selection: $concerns, accent: tint) } },

            // 4 — Niveau de routine skincare
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "list.bullet.clipboard", title: "Ta routine actuelle ?",
                            subtitle: "On te proposera les étapes qui manquent (nettoyant, hydratant, SPF…).", accent: tint)
                SetupChoice(options: ["Aucune", "Basique (nettoyant + crème)", "Complète (sérums, SPF…)"],
                            selection: $skincareLevel, accent: tint,
                            icons: ["xmark.circle", "drop", "infinity"]) } },

            // 5 — Cheveux (couleur = base pour conseiller les sourcils)
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "comb.fill", title: "Couleur de tes cheveux ?",
                            subtitle: "Sert de repère pour tes sourcils (voir étape suivante).", accent: tint)
                SetupChoice(options: ["Noir", "Brun", "Châtain", "Blond", "Roux", "Gris/Blanc"],
                            selection: $hairColor, accent: tint) } },

            // 6 — Sourcils (règle : 1 teinte + foncé que les cheveux, trim)
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "eyebrow", title: "Sourcils",
                            subtitle: "Astuce : teins-les ~1 ton PLUS FONCÉ que tes cheveux pour encadrer le regard, et trim les longueurs qui dépassent.",
                            accent: tint)
                LooksTipCard(icon: "paintbrush.pointed.fill",
                             text: "Ta base cheveux : \(hairColor). Vise une teinte sourcils légèrement plus foncée.",
                             accent: tint)
                SetupMultiChoice(options: ["Épaissir", "Redéfinir la ligne", "Teindre plus foncé", "Trim régulier", "Combler les trous"],
                                 selection: $browGoals, accent: tint) } },

            // 7 — Cheveux : objectifs
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "scissors", title: "Objectifs cheveux",
                            subtitle: faceShape.isEmpty ? "On te guidera selon ta forme de visage." : "Forme détectée : \(faceShape). On adapte les conseils.",
                            accent: tint)
                SetupMultiChoice(options: ["Coupe adaptée", "Densité/pousse", "Soin du cuir chevelu", "Antipelliculaire", "Coiffage", "Barbe"],
                                 selection: $hairGoals, accent: tint) } },

            // 8 — Sourire / dents
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "mouth.fill", title: "Sourire & dents",
                            subtitle: "Un sourire soigné change tout le visage.", accent: tint)
                SetupMultiChoice(options: ["Blanchiment", "Alignement", "Détartrage régulier", "Haleine fraîche", "Fil dentaire quotidien"],
                                 selection: $smileGoals, accent: tint) } },

            // 9 — Soins & grooming
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "comb", title: "Soins & grooming",
                            subtitle: "Les détails qui font la différence.", accent: tint)
                SetupMultiChoice(options: ["Barbe entretenue", "Ongles nets", "Parfum", "Posture", "Sommeil (cernes)", "Hydratation", "Lèvres", "Épilation"],
                                 selection: $grooming, accent: tint) } },

            // 10 — Rappels
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "bell.fill", title: "Rappels routine matin/soir ?",
                            subtitle: "Skincare, sourcils, fil dentaire… on te rappelle au bon moment.", accent: tint)
                SetupChoice(options: ["Oui", "Non"], selection: $remind, accent: tint,
                            icons: ["checkmark.circle", "xmark.circle"]) } },
        ]
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("type", type)
            d.put("concerns", concerns)
            d.put("skincareLevel", skincareLevel)
            d.put("faceShape", faceShape)
            d.put("hairColor", hairColor)
            d.put("hairGoals", hairGoals)
            d.put("browGoals", browGoals)
            d.put("smileGoals", smileGoals)
            d.put("grooming", grooming)
            d.put("remind", remind)
            return d
        }, restore: { d in
            if let v = d.string("type") { type = v }
            if let v = d.set("concerns") { concerns = v }
            if let v = d.string("skincareLevel") { skincareLevel = v }
            if let v = d.string("faceShape") { faceShape = v }
            if let v = d.string("hairColor") { hairColor = v }
            if let v = d.set("hairGoals") { hairGoals = v }
            if let v = d.set("browGoals") { browGoals = v }
            if let v = d.set("smileGoals") { smileGoals = v }
            if let v = d.set("grooming") { grooming = v }
            if let v = d.string("remind") { remind = v }
        })
    }
}

/// Petit encart conseil illustré, réutilisable dans les questionnaires.
struct LooksTipCard: View {
    let icon: String
    let text: String
    var accent: Color = .accentColor
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.onAccent).frame(width: 40, height: 40)
                .background(accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .padding(.horizontal, 14)
    }
}

// ---- Cycle menstruel ------------------------------------------------------

struct CycleSetupView: View {
    @AppStorage(AppStorageKeys.cycleStartDate)  private var startTS: Double = 0
    @AppStorage(AppStorageKeys.cycleLengthDays) private var length = 28

    @State private var start = Date()
    @State private var len = 28
    private let tint = AppCategory.cycle.tint

    var body: some View {
        SetupFlow(title: "Cycle menstruel", accent: tint, pages: pages, onComplete: {
            startTS = start.timeIntervalSince1970
            length = len
            CategorySetup.markDone(.cycle); Haptics.success()
        }, preview: {
            let f: (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }
            return [.make("Début des dernières règles", startTS > 0 ? f(Date(timeIntervalSince1970: startTS)) : "—", f(start)),
                    .make("Durée du cycle", "\(length) jours", "\(len) jours")].compactMap { $0 }
        }, draft: draftIO)
        .onAppear { if startTS > 0 { start = Date(timeIntervalSince1970: startTS) }; len = length }
    }
    private var pages: [SetupPage] {
        [
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "calendar.badge.clock", title: "Début de tes dernières règles",
                            subtitle: "Pour prédire ton prochain cycle.", accent: tint)
                DatePicker("", selection: $start, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(tint)
                    .padding(.horizontal, 14)
                    .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall)).padding(.horizontal, 14) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "arrow.triangle.2.circlepath", title: "Durée de ton cycle",
                            subtitle: "En moyenne 28 jours.", accent: tint)
                SetupNumber(value: $len, unit: "jours", range: 20...40, accent: tint) } },
        ]
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("start", start)
            d.put("len", len)
            return d
        }, restore: { d in
            if let v = d.date("start") { start = v }
            if let v = d.int("len") { len = v }
        })
    }
}

// ---- Mobilité (crée un véhicule réel, idempotent) -------------------------

struct MobilitySetupView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var vehicles: [Vehicle]

    @State private var hasCar = "Oui"
    @State private var name = ""
    @State private var insurance = Date()
    @State private var setInsurance = false
    private let tint = AppCategory.mobility.tint

    var body: some View {
        SetupFlow(title: "Mobilité", accent: tint, pages: pages, onComplete: commit, preview: {
            let f: (Date?) -> String = { $0?.formatted(date: .abbreviated, time: .omitted) ?? "—" }
            let v = vehicles.first
            guard hasCar == "Oui" else { return [] }
            return [.make("Véhicule", v?.name ?? "—", name.isEmpty ? "—" : name),
                    .make("Renouvellement assurance", f(v?.insuranceRenewal), setInsurance ? f(insurance) : "—")].compactMap { $0 }
        }, draft: draftIO)
            .onAppear {
                if let v = vehicles.first { name = v.name; if let i = v.insuranceRenewal { insurance = i; setInsurance = true } }
            }
    }
    private var pages: [SetupPage] {
        [
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "car.fill", title: "As-tu une voiture ?",
                            subtitle: "On suivra assurance, révision et carburant.", accent: tint)
                SetupChoice(options: ["Oui", "Non"], selection: $hasCar, accent: tint,
                            icons: ["checkmark.circle", "xmark.circle"]) } },
            SetupPage(canAdvance: { hasCar == "Non" || !name.trimmingCharacters(in: .whitespaces).isEmpty }) {
                VStack(spacing: 16) {
                    if hasCar == "Oui" {
                        SetupHeader(icon: "airplane", title: "Ta voiture", subtitle: "Marque et modèle.", accent: tint)
                        TextField("Ex : Peugeot 208", text: $name).textFieldStyle(.roundedBorder).padding(.horizontal, 14)
                        Toggle("Renseigner l'échéance d'assurance", isOn: $setInsurance).padding(.horizontal, 14).tint(tint)
                        if setInsurance {
                            DatePicker("Assurance à renouveler", selection: $insurance, displayedComponents: .date)
                                .padding(.horizontal, 14)
                        }
                    } else {
                        SetupHeader(icon: "figure.walk", title: "Pas de voiture",
                                    subtitle: "Tu peux quand même suivre tes trajets & ton empreinte CO₂.", accent: tint)
                    }
                }
            },
        ]
    }
    private func commit() {
        if hasCar == "Oui", !name.trimmingCharacters(in: .whitespaces).isEmpty {
            let v = vehicles.first ?? { let nv = Vehicle(); ctx.insert(nv); return nv }()
            // Les identifiants de rappel derivent du nom et des dates: on annule
            // avec les ANCIENNES valeurs avant de changer, puis on repose. Sinon
            // l'ancien rappel survivait et la nouvelle date n'en avait aucun.
            VehicleReminders.cancel(v, others: vehicles)
            v.name = name
            v.insuranceRenewal = setInsurance ? insurance : nil
            VehicleReminders.schedule(v)
            do { try ctx.save() } catch { AppLog.data.error("MobilitySetup save failed: \(error.localizedDescription, privacy: .public)") }
        }
        CategorySetup.markDone(.mobility); Haptics.success()
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("hasCar", hasCar)
            d.put("name", name)
            d.put("insurance", insurance)
            d.put("setInsurance", setInsurance)
            return d
        }, restore: { d in
            if let v = d.string("hasCar") { hasCar = v }
            if let v = d.string("name") { name = v }
            if let v = d.date("insurance") { insurance = v }
            if let v = d.bool("setInsurance") { setInsurance = v }
        })
    }
}
