import SwiftUI
import SwiftData

// MARK: - Formulaires de configuration des pôles (écrivent des données réelles)

// ---- Productivité ---------------------------------------------------------

struct ProductivitySetupView: View {
    @AppStorage("focusMinGoal") private var focusGoal = 90
    @AppStorage("focusLen")     private var focusLen = 25
    @AppStorage("socialMaxMin") private var socialMax = 60

    @State private var goal = 90
    @State private var pomo = 25
    @State private var screen = 60
    private let tint = AppCategory.productivity.tint

    var body: some View {
        SetupFlow(title: "Productivité", accent: tint, pages: pages) {
            focusGoal = goal; focusLen = pomo; socialMax = screen
            CategorySetup.markDone(.productivity); Haptics.success()
        }
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
}

// ---- Mental & focus -------------------------------------------------------

struct MentalSetupView: View {
    @AppStorage("meditationGoalMin") private var meditGoal = 10
    @AppStorage("socialMaxMin")      private var socialMax = 60

    @State private var medit = 10
    @State private var screen = 60
    @State private var stress = "Moyen"
    private let tint = AppCategory.mind.tint

    var body: some View {
        SetupFlow(title: "Mental & focus", accent: tint, pages: pages) {
            meditGoal = medit; socialMax = screen
            CategorySetup.markDone(.mind); Haptics.success()
        }
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
}

// ---- Looksmaxx ------------------------------------------------------------

struct LooksSetupView: View {
    @AppStorage("skinType")           private var skinType = ""
    @AppStorage("skinConcernsRaw")    private var concernsRaw = ""
    @AppStorage("skincareReminders")  private var reminders = false

    @State private var type = "Normale"
    @State private var concerns: Set<String> = []
    @State private var remind = "Oui"
    private let tint = AppCategory.looks.tint

    var body: some View {
        SetupFlow(title: "Looksmaxx", accent: tint, pages: pages) {
            skinType = type
            concernsRaw = concerns.sorted().joined(separator: ",")
            reminders = (remind == "Oui")
            CategorySetup.markDone(.looks); Haptics.success()
        }
        .onAppear {
            if !skinType.isEmpty { type = skinType }
            concerns = Set(concernsRaw.split(separator: ",").map(String.init))
            remind = reminders ? "Oui" : "Non"
        }
    }
    private var pages: [SetupPage] {
        [
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "face.smiling", title: "Ton type de peau ?", accent: tint)
                SetupChoice(options: ["Normale", "Sèche", "Grasse", "Mixte", "Sensible"], selection: $type, accent: tint) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "sparkles", title: "Tes objectifs peau",
                            subtitle: "On adaptera ta routine skincare.", accent: tint)
                SetupMultiChoice(options: ["Acné", "Points noirs", "Rides", "Taches", "Cernes", "Pores", "Rougeurs", "Éclat"],
                                 selection: $concerns, accent: tint) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "bell.fill", title: "Rappels routine matin/soir ?", accent: tint)
                SetupChoice(options: ["Oui", "Non"], selection: $remind, accent: tint,
                            icons: ["checkmark.circle", "xmark.circle"]) } },
        ]
    }
}

// ---- Cycle menstruel ------------------------------------------------------

struct CycleSetupView: View {
    @AppStorage("cycleStartDate")  private var startTS: Double = 0
    @AppStorage("cycleLengthDays") private var length = 28

    @State private var start = Date()
    @State private var len = 28
    private let tint = AppCategory.cycle.tint

    var body: some View {
        SetupFlow(title: "Cycle menstruel", accent: tint, pages: pages) {
            startTS = start.timeIntervalSince1970
            length = len
            CategorySetup.markDone(.cycle); Haptics.success()
        }
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 14) } },
            SetupPage { VStack(spacing: 16) {
                SetupHeader(icon: "arrow.triangle.2.circlepath", title: "Durée de ton cycle",
                            subtitle: "En moyenne 28 jours.", accent: tint)
                SetupNumber(value: $len, unit: "jours", range: 20...40, accent: tint) } },
        ]
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
        SetupFlow(title: "Mobilité", accent: tint, pages: pages, onComplete: commit)
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
            v.name = name
            v.insuranceRenewal = setInsurance ? insurance : nil
            try? ctx.save()
        }
        CategorySetup.markDone(.mobility); Haptics.success()
    }
}
