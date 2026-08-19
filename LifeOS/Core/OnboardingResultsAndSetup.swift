import SwiftUI

// MARK: - Étape 5 : Modules recommandés

struct OnboardingResults: View {
    let name: String
    let recommendations: [AppCategory]
    let onDone: ([AppCategory]) -> Void

    @State private var selected: Set<AppCategory> = []

    private var preferencesSummary: [(module: AppCategory, bullets: [String])] {
        recommendations.compactMap { cat -> (module: AppCategory, bullets: [String])? in
            guard let configStr = UserDefaults.standard.string(forKey: "moduleConfig_\(cat.rawValue)"),
                  let data = configStr.data(using: .utf8),
                  let config = try? JSONDecoder().decode([String: String].self, from: data),
                  !config.isEmpty else { return nil }
            let labelMap: [String: [String: [String: String]]] = [
                "fitness": ["location": ["gym":"En salle","home":"A la maison","outdoor":"Dehors","mixed":"Mixte"],
                            "frequency": ["1_2":"1-2x/sem","3":"3x/sem","4p":"4x+/sem"],
                            "goal": ["loss":"Perte de poids","muscle":"Muscle","cardio":"Cardio","flex":"Souplesse"]],
                "nutrition": ["diet": ["omni":"Omnivore","vege":"Vegetarien","vegan":"Vegan","gf":"Sans gluten"],
                              "goal": ["loss":"Perdre du poids","mass":"Prise de masse","balance":"Equilibrer","energy":"Energie"]],
                "sleep": ["bedtime": ["early":"Avant 22h","normal":"22h-23h","late":"23h-0h","verylate":"Apres minuit"]],
                "mind": ["stress": ["low":"Faible","medium":"Modere","high":"Eleve","vhigh":"Tres eleve"]],
                "productivity": ["peak": ["morning":"Le matin","afternoon":"Apres-midi","evening":"Le soir"]],
                "invest": ["level": ["beginner":"Debutant","intermediate":"Intermediaire","expert":"Experimente"],
                           "risk": ["low":"Faible","medium":"Modere","high":"Eleve"]],
            ]
            let bullets: [String] = config.compactMap { (key, value) in
                let values = value.split(separator: ",").map(String.init)
                let moduleMap = labelMap[cat.rawValue]?[key] ?? [:]
                let labels = values.compactMap { moduleMap[$0] ?? $0 }
                return labels.isEmpty ? nil : labels.joined(separator: ", ")
            }
            guard !bullets.isEmpty else { return nil }
            return (module: cat, bullets: bullets)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    VStack(spacing: 10) {
                        Text(name.isEmpty ? "Parfait !" : "Parfait, \(name) !")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("Voici tes modules pour démarrer.\nCoche ou décoche selon tes envies.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, Theme.padWide)

                    if !preferencesSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TES PREFERENCES")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                                .padding(.horizontal, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(preferencesSummary, id: \.module) { item in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Image(systemName: item.module.icon)
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(item.module.tint)
                                                Text(item.module.title)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                            }
                                            ForEach(item.bullets, id: \.self) { b in
                                                HStack(spacing: 4) {
                                                    Circle()
                                                        .fill(item.module.tint)
                                                        .frame(width: 4, height: 4)
                                                    Text(b)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            item.module.tint.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(item.module.tint.opacity(0.2), lineWidth: 1)
                                        )
                                        .frame(minWidth: 130)
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.horizontal, 22)
                    }

                    VStack(spacing: 10) {
                        ForEach(recommendations) { cat in
                            let isOn = selected.contains(cat)
                            Button {
                                withAnimation(.spring(duration: 0.2)) {
                                    if isOn { selected.remove(cat) } else { selected.insert(cat) }
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: cat.icon)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                        .background(isOn ? cat.tint : Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(isOn ? .primary : .secondary)
                                        Text(cat.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.4))
                                        .font(.title2)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                                .opacity(isOn ? 1 : 0.6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)

                    Spacer(minLength: 16)
                }
            }

            OnboardingButton(
                label: selected.isEmpty ? "Sélectionne au moins un module" : "Commencer LifeOS",
                enabled: !selected.isEmpty,
                action: { onDone(recommendations.filter { selected.contains($0) }) }
            )
            .padding(.horizontal, Theme.padWide)
            .padding(.bottom, 52)
        }
        .onAppear {
            selected = Set(recommendations)
        }
    }
}

// MARK: - Module setup data

struct ModuleQuestion: Identifiable {
    let id: String
    let question: String
    let options: [ModuleOption]
    let multiSelect: Bool

    init(_ id: String, _ question: String, _ options: [ModuleOption], multiSelect: Bool = false) {
        self.id = id; self.question = question; self.options = options; self.multiSelect = multiSelect
    }
}

struct ModuleOption: Identifiable {
    let id: String
    let label: String
    let icon: String

    init(_ id: String, _ label: String, _ icon: String = "") {
        self.id = id; self.label = label; self.icon = icon
    }
}

let moduleSetupQuestions: [AppCategory: [ModuleQuestion]] = [
    .fitness: [
        ModuleQuestion("location", "Ou tu t'entraines ?", [
            ModuleOption("gym",     "En salle",    "building.2"),
            ModuleOption("home",    "A la maison", "house"),
            ModuleOption("outdoor", "Dehors",      "leaf"),
            ModuleOption("mixed",   "Mixte",       "shuffle"),
        ]),
        ModuleQuestion("frequency", "Frequence par semaine ?", [
            ModuleOption("1_2", "1 – 2 fois", "1.circle"),
            ModuleOption("3",   "3 fois",     "3.circle"),
            ModuleOption("4p",  "4 fois +",   "bolt"),
        ]),
        ModuleQuestion("goal", "Ton objectif sport ?", [
            ModuleOption("loss",   "Perte de poids",  "scalemass"),
            ModuleOption("muscle", "Prise de muscle", "dumbbell"),
            ModuleOption("cardio", "Cardio",           "heart.circle"),
            ModuleOption("flex",   "Souplesse",        "figure.mind.and.body"),
        ]),
    ],
    .nutrition: [
        ModuleQuestion("diet", "Regime alimentaire ?", [
            ModuleOption("omni",  "Omnivore",   "fork.knife"),
            ModuleOption("vege",  "Vegetarien", "leaf"),
            ModuleOption("vegan", "Vegan",      "sparkles"),
            ModuleOption("gf",    "Sans gluten","exclamationmark.circle"),
        ]),
        ModuleQuestion("goal", "Objectif nutrition ?", [
            ModuleOption("loss",    "Perdre du poids",    "arrow.down.circle"),
            ModuleOption("mass",    "Prendre de la masse","arrow.up.circle"),
            ModuleOption("balance", "Equilibrer",          "equal.circle"),
            ModuleOption("energy",  "Plus d'energie",     "bolt"),
        ]),
    ],
    .sleep: [
        ModuleQuestion("bedtime", "Tu te couches habituellement a ?", [
            ModuleOption("early",    "Avant 22h",   "moon.stars"),
            ModuleOption("normal",   "22h – 23h",   "moon"),
            ModuleOption("late",     "23h – 0h",    "cloud.moon"),
            ModuleOption("verylate", "Apres minuit","moon.zzz"),
        ]),
        ModuleQuestion("issue", "Problemes de sommeil ?", [
            ModuleOption("falling", "Endormissement",  "zzz"),
            ModuleOption("waking",  "Reveils nocturnes","alarm"),
            ModuleOption("none",    "Aucun",            "checkmark.circle"),
        ], multiSelect: true),
    ],
    .mind: [
        ModuleQuestion("stress", "Niveau de stress actuel ?", [
            ModuleOption("low",    "Faible",     "leaf"),
            ModuleOption("medium", "Modere",     "minus.circle"),
            ModuleOption("high",   "Eleve",      "exclamationmark.triangle"),
            ModuleOption("vhigh",  "Tres eleve", "flame"),
        ]),
        ModuleQuestion("practice", "Tu pratiques deja ?", [
            ModuleOption("meditation", "Meditation", "brain.head.profile"),
            ModuleOption("journaling", "Journal",    "book"),
            ModuleOption("sport",      "Sport",      "figure.run"),
            ModuleOption("nothing",    "Rien encore","circle"),
        ], multiSelect: true),
    ],
    .productivity: [
        ModuleQuestion("peak", "Quand es-tu le plus productif ?", [
            ModuleOption("morning",   "Le matin",    "sunrise"),
            ModuleOption("afternoon", "L'apres-midi","sun.max"),
            ModuleOption("evening",   "Le soir",     "sunset"),
        ]),
        ModuleQuestion("method", "Methode de travail ?", [
            ModuleOption("pomodoro", "Pomodoro",  "timer"),
            ModuleOption("tasks",    "To-do list","checklist"),
            ModuleOption("block",    "Timeblock", "calendar"),
            ModuleOption("free",     "Flux libre","wand.and.stars"),
        ]),
    ],
    .finance: [
        ModuleQuestion("goal", "Objectif principal ?", [
            ModuleOption("save",   "Epargner plus",     "banknote"),
            ModuleOption("debt",   "Rembourser dettes", "arrow.down.circle"),
            ModuleOption("budget", "Suivre le budget",  "chart.pie"),
            ModuleOption("invest", "Investir",           "chart.line.uptrend.xyaxis"),
        ]),
    ],
    .invest: [
        ModuleQuestion("level", "Ton niveau en investissement ?", [
            ModuleOption("beginner",     "Debutant",     "star"),
            ModuleOption("intermediate", "Intermediaire","star.leadinghalf.filled"),
            ModuleOption("expert",       "Experimente",  "star.fill"),
        ]),
        ModuleQuestion("risk", "Appetit au risque ?", [
            ModuleOption("low",    "Faible", "shield"),
            ModuleOption("medium", "Modere", "shield.lefthalf.filled"),
            ModuleOption("high",   "Eleve",  "bolt.shield"),
        ]),
    ],
    .career: [
        ModuleQuestion("goal", "Ton objectif carriere ?", [
            ModuleOption("promotion", "Promotion",           "arrow.up.circle"),
            ModuleOption("change",    "Changer de domaine",  "arrow.right.circle"),
            ModuleOption("startup",   "Creer mon activite",  "flame"),
            ModuleOption("job",       "Trouver un emploi",   "magnifyingglass"),
        ]),
    ],
    .learning: [
        ModuleQuestion("domain", "Domaine principal ?", [
            ModuleOption("tech",      "Tech / Code","laptopcomputer"),
            ModuleOption("business",  "Business",   "briefcase"),
            ModuleOption("languages", "Langues",    "globe"),
            ModuleOption("other",     "Autre",      "ellipsis.circle"),
        ]),
        ModuleQuestion("time", "Temps dispo par jour ?", [
            ModuleOption("15",  "15 min","timer"),
            ModuleOption("30",  "30 min","timer"),
            ModuleOption("60",  "1h",    "clock"),
            ModuleOption("60p", "1h+",   "infinity"),
        ]),
    ],
    .looks: [
        ModuleQuestion("goal", "Ton objectif ?", [
            ModuleOption("loss",     "Perte de poids",    "arrow.down.circle"),
            ModuleOption("mass",     "Prise de masse",    "arrow.up.circle"),
            ModuleOption("tone",     "Tonifier",           "bolt"),
            ModuleOption("wellness", "Bien-etre general",  "heart"),
        ]),
        ModuleQuestion("skincare", "Suivi skincare ?", [
            ModuleOption("yes",  "Oui, routine complete", "checkmark.circle"),
            ModuleOption("basic","Basique seulement",     "minus.circle"),
            ModuleOption("no",   "Non",                   "xmark.circle"),
        ]),
    ],
    .social: [
        ModuleQuestion("type", "Tu es plutot ?", [
            ModuleOption("intro", "Introverti",    "person"),
            ModuleOption("extro", "Extraverti",    "person.3"),
            ModuleOption("mixed", "Entre les deux","person.2"),
        ]),
        ModuleQuestion("goal", "Objectif social ?", [
            ModuleOption("meet",   "Rencontrer du monde",     "person.badge.plus"),
            ModuleOption("deepen", "Ameliorer mes relations", "heart.circle"),
            ModuleOption("both",   "Les deux",                "sparkles"),
        ]),
    ],
    .home: [
        ModuleQuestion("type", "Type de logement ?", [
            ModuleOption("apartment", "Appartement","building.2"),
            ModuleOption("house",     "Maison",     "house"),
            ModuleOption("studio",    "Studio",     "squareshape"),
            ModuleOption("shared",    "Colocation", "person.2"),
        ]),
    ],
    .mobility: [
        ModuleQuestion("vehicle", "Transport principal ?", [
            ModuleOption("car",     "Voiture",    "car"),
            ModuleOption("moto",    "Moto",       "figure.outdoor.cycle"),
            ModuleOption("bike",    "Velo",       "bicycle"),
            ModuleOption("transit", "Transports", "bus"),
        ]),
    ],
    .admin: [
        ModuleQuestion("priority", "Ta priorite admin ?", [
            ModuleOption("docs",      "Documents",  "doc.text"),
            ModuleOption("taxes",     "Impots",     "eurosign.circle"),
            ModuleOption("insurance", "Assurances", "shield"),
            ModuleOption("all",       "Tout gerer", "tray.full"),
        ]),
    ],
    .travel: [
        ModuleQuestion("style", "Tu voyages plutot ?", [
            ModuleOption("solo",    "Solo",      "person"),
            ModuleOption("couple",  "En couple", "person.2"),
            ModuleOption("family",  "En famille","person.3"),
            ModuleOption("friends", "Entre amis","person.3.fill"),
        ]),
    ],
    .cycle: [
        ModuleQuestion("goal", "Ton objectif ?", [
            ModuleOption("tracking",   "Suivi cycle",      "calendar"),
            ModuleOption("fertility",  "Fertilite",         "heart.circle"),
            ModuleOption("pain",       "Gestion douleurs",  "cross.circle"),
            ModuleOption("understand", "Mieux comprendre",  "book"),
        ]),
    ],
]

// MARK: - Etape 5 : Setup par module

struct OnboardingModuleSetup: View {
    let modules: [AppCategory]
    let skipHabitStep: Bool
    let onNext: ([String: [String: String]]) -> Void

    init(modules: [AppCategory], skipHabitStep: Bool = false, onNext: @escaping ([String: [String: String]]) -> Void) {
        self.modules = modules
        self.skipHabitStep = skipHabitStep
        self.onNext = onNext
    }

    @State private var currentIndex = 0
    @State private var answers: [String: [String: String]] = [:]
    @State private var showHabitPicker = false
    @State private var selectedHabitModules: Set<String> = []

    private var modulesWithQuestions: [AppCategory] {
        modules.filter { moduleSetupQuestions[$0]?.isEmpty == false }
    }

    private var currentModule: AppCategory? {
        guard currentIndex < modulesWithQuestions.count else { return nil }
        return modulesWithQuestions[currentIndex]
    }

    private var currentQuestions: [ModuleQuestion] {
        guard let m = currentModule else { return [] }
        return moduleSetupQuestions[m] ?? []
    }

    private var canAdvance: Bool {
        guard let m = currentModule else { return true }
        let dict = answers[m.rawValue] ?? [:]
        return currentQuestions.filter { !$0.multiSelect }.allSatisfy { dict[$0.id] != nil }
    }

    var body: some View {
        if modulesWithQuestions.isEmpty {
            Color.clear.onAppear { onNext([:]) }
        } else if showHabitPicker {
            habitPickerView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else {
            VStack(spacing: 0) {
                subProgress
                    .padding(.horizontal, Theme.padWide)
                    .padding(.bottom, 20)

                if let m = currentModule {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            moduleHeader(m)
                            ForEach(currentQuestions) { q in
                                questionBlock(q, module: m)
                            }
                            Color.clear.frame(height: 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                }

                OnboardingButton(
                    label: currentIndex < modulesWithQuestions.count - 1 ? "Module suivant" : "Configurer mes habitudes",
                    enabled: canAdvance
                ) {
                    advance()
                }
                .padding(.horizontal, Theme.padWide)
                .padding(.bottom, 52)
                .animation(.spring(duration: 0.2), value: canAdvance)
            }
        }
    }

    private var habitPickerView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Tes habitudes a creer")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("On les prepare pour toi, desactivees.\nTu les actives quand tu veux.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, Theme.padWide)
            .padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(modulesWithQuestions) { m in
                        let on = selectedHabitModules.contains(m.rawValue)
                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                if on { selectedHabitModules.remove(m.rawValue) }
                                else { selectedHabitModules.insert(m.rawValue) }
                            }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: m.icon)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        on ? m.tint : Color.primary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(on ? .primary : .secondary)
                                    Text(m.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? m.tint : Color.secondary.opacity(0.4))
                                    .font(.title2)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                            .opacity(on ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }

            OnboardingButton(label: "Demarrer LifeOS", enabled: true) {
                UserDefaults.standard.set(
                    selectedHabitModules.joined(separator: ","),
                    forKey: "habitModulesRaw"
                )
                onNext(answers)
            }
            .padding(.horizontal, Theme.padWide)
            .padding(.bottom, 52)
        }
        .onAppear {
            if selectedHabitModules.isEmpty {
                selectedHabitModules = Set(modulesWithQuestions.map { $0.rawValue })
            }
        }
    }

    private var subProgress: some View {
        HStack(spacing: 6) {
            ForEach(modulesWithQuestions.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= currentIndex ? modulesWithQuestions[i].tint : Color.primary.opacity(0.1))
                    .frame(height: 3)
            }
        }
        .animation(.spring(duration: 0.3), value: currentIndex)
    }

    private func moduleHeader(_ m: AppCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(m.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Module \(currentIndex + 1) sur \(modulesWithQuestions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func questionBlock(_ q: ModuleQuestion, module: AppCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(q.question)
                .font(.subheadline.weight(.semibold))

            let raw = (answers[module.rawValue] ?? [:])[q.id] ?? ""
            let selected = Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(q.options) { opt in
                    let on = selected.contains(opt.id)
                    Button {
                        pick(opt, question: q, module: module)
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            if !opt.icon.isEmpty {
                                Image(systemName: opt.icon)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(on ? .white : module.tint)
                            }
                            Text(opt.label)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(on ? .white : .primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            on ? module.tint : module.tint.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(on ? Color.clear : module.tint.opacity(0.2), lineWidth: 1)
                        )
                        .scaleEffect(on ? 0.97 : 1.0)
                        .animation(.spring(duration: 0.18), value: on)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ opt: ModuleOption, question q: ModuleQuestion, module: AppCategory) {
        var dict = answers[module.rawValue] ?? [:]
        if q.multiSelect {
            var set = Set((dict[q.id] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
            if set.contains(opt.id) {
                set.remove(opt.id)
            } else if opt.id == "nothing" {
                set = ["nothing"]
            } else {
                set.remove("nothing")
                set.insert(opt.id)
            }
            dict[q.id] = set.joined(separator: ",")
        } else {
            dict[q.id] = opt.id
        }
        answers[module.rawValue] = dict
    }

    private func advance() {
        if currentIndex < modulesWithQuestions.count - 1 {
            withAnimation(.spring(duration: 0.35)) { currentIndex += 1 }
        } else if !skipHabitStep {
            withAnimation(.spring(duration: 0.35)) { showHabitPicker = true }
        } else {
            onNext(answers)
        }
    }
}
