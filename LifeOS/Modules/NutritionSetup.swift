import SwiftUI
import SwiftData

// MARK: - Formulaire de configuration « Alimentation »
// Pré-remplit : objectif calorique, hydratation, liste de courses, compléments recommandés.

struct NutritionSetupView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("kcalGoal")  private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("proteinGoal") private var proteinGoal = 150
    // Profil central — déjà connu / réutilisé par les autres catégories (jamais redemandé).
    @AppStorage("userGender")   private var userGender = ""
    @AppStorage("userAge")      private var age = 25
    @AppStorage("userWeight")   private var weight = 75
    @AppStorage("userHeight")   private var height = 178
    @AppStorage("userActivity") private var activity = "Modéré (3-4×/sem)"
    @AppStorage("userGoalFit")  private var sharedGoal = ""

    @State private var goal = "Maintenir"
    @State private var shopping: Set<String> = []
    @State private var chosenSupps: Set<String> = []       // recommandés cochés
    @State private var extraSupps: Set<String> = []        // ajouts depuis le reste du catalogue

    private let tint = AppCategory.nutrition.tint
    private var isFemme: Bool { userGender == "femme" }

    private let shoppingOptions = [
        "Sopalin", "Papier toilette", "Sacs poubelle", "Éponges", "Liquide vaisselle",
        "Lessive", "Sel", "Poivre", "Huile d'olive", "Beurre", "Œufs", "Lait",
        "Café", "Sucre", "Farine", "Ail", "Oignons", "Citrons", "Dentifrice",
        "Savon", "Piles", "Film alimentaire", "Riz", "Pâtes"
    ]

    private var recommended: [SuppRecoItem] {
        SupplementPlan.recommended(goal: fitGoal, gender: userGender)
    }
    /// Objectif fitness équivalent (pour les recommandations de compléments).
    private var fitGoal: String {
        if !sharedGoal.isEmpty { return sharedGoal }
        switch goal {
        case "Perdre du gras": return "Perte de gras"
        case "Prendre du muscle": return "Prise de muscle"
        default: return "Forme générale"
        }
    }

    var body: some View {
        SetupFlow(title: "Alimentation", accent: tint, pages: pages, onComplete: commit)
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "fork.knife", title: "On cale ta nutrition",
                                subtitle: "Quelques infos pour calculer tes besoins exacts et préparer tes outils.",
                                accent: tint)
                    SetupNumber(value: $age, unit: "ans", range: 12...100, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "scalemass", title: "Ton poids ?", accent: tint)
                    SetupNumber(value: $weight, unit: "kg", range: 35...250, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "ruler", title: "Ta taille ?", accent: tint)
                    SetupNumber(value: $height, unit: "cm", range: 130...230, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "flame", title: "Ton niveau d'activité ?", accent: tint)
                    SetupChoice(options: ["Sédentaire", "Léger (1-2×/sem)", "Modéré (3-4×/sem)", "Intense (5×+/sem)"],
                                selection: $activity, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "target", title: "Ton objectif ?", accent: tint)
                    SetupChoice(options: ["Perdre du gras", "Maintenir", "Prendre du muscle"],
                                selection: $goal, accent: tint,
                                icons: ["arrow.down.circle", "equal.circle", "arrow.up.circle"])
                    summaryCard
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "cart", title: "Ce que tu oublies tout le temps",
                                subtitle: "On les ajoute direct à ta liste de courses.", accent: tint)
                    SetupMultiChoice(options: shoppingOptions, selection: $shopping, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "pills.fill", title: "Compléments recommandés",
                                subtitle: "Sélectionnés pour ton objectif. Touche « Ajouter » : dosage + rappel inclus.",
                                accent: tint)
                    recoList
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "checkmark.seal.fill", title: "C'est prêt !",
                                subtitle: "Ta catégorie Alimentation est configurée. On enregistre tout.", accent: tint)
                    finalSummary
                }
            }
        ]
    }

    // MARK: recommandations de compléments (cartes avec dosage + Ajouter)

    private var recoList: some View {
        VStack(spacing: 10) {
            ForEach(recommended) { item in
                let on = chosenSupps.contains(item.name)
                HStack(spacing: 12) {
                    Image(systemName: item.reco.icon).font(.title3).foregroundStyle(tint).frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                            Text(item.dosage).font(.caption.weight(.semibold)).foregroundStyle(tint)
                        }
                        Text(item.reason).font(.caption2).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(item.reco.momentLabel) · \(item.reco.foodLabel)")
                            .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                    }
                    Spacer()
                    Button {
                        if on { chosenSupps.remove(item.name) } else { chosenSupps.insert(item.name) }
                        Haptics.soft()
                    } label: {
                        Text(on ? "Ajouté" : "Ajouter")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(on ? .white : tint)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(on ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)),
                                       in: Capsule())
                    }.buttonStyle(.plain)
                }
                .padding(12)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(on ? tint : .clear, lineWidth: 1.5))
            }
            DisclosureGroup("Ajouter d'autres compléments") {
                SetupMultiChoice(options: SupplementPlan.extra, selection: $extraSupps, accent: tint)
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium)).tint(tint)
            .padding(.horizontal, 14).padding(.top, 4)
        }
        .padding(.horizontal, 14)
    }

    // MARK: calculs

    private var bmr: Double {
        let w = Double(weight), h = Double(height), a = Double(age)
        return 10 * w + 6.25 * h - 5 * a + (isFemme ? -161 : 5)
    }
    private var tdee: Double {
        let f: Double
        switch activity {
        case "Sédentaire": f = 1.2
        case "Léger (1-2×/sem)": f = 1.375
        case "Intense (5×+/sem)": f = 1.725
        default: f = 1.55
        }
        return bmr * f
    }
    private var computedKcal: Int {
        let adj: Double = goal == "Perdre du gras" ? -400 : (goal == "Prendre du muscle" ? 300 : 0)
        return Int(((tdee + adj) / 10).rounded()) * 10
    }
    private var computedWater: Int { Int((Double(weight) * 35 / 100).rounded()) * 100 }
    private var computedProtein: Int { Int((Double(weight) * (goal == "Perdre du gras" ? 2.0 : 1.8)).rounded()) }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            metric("\(computedKcal)", "kcal", "flame.fill")
            metric("\(computedProtein) g", "protéines", "fish.fill")
            metric("\(computedWater)", "ml d'eau", "drop.fill")
        }.padding(.horizontal, 14)
    }
    private var finalSummary: some View {
        VStack(spacing: 10) {
            summaryCard
            row("cart.fill", "\(shopping.count) articles ajoutés à la liste de courses")
            row("pills.fill", "\(chosenSupps.count + extraSupps.count) compléments programmés avec rappels")
        }
    }
    private func metric(_ v: String, _ l: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(v).font(.headline.weight(.bold)).foregroundStyle(Theme.textPrimary).minimumScaleFactor(0.7).lineLimit(1)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(14).background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)
    }

    // MARK: enregistrement

    private func commit() {
        kcalGoal = computedKcal
        waterGoal = computedWater
        proteinGoal = computedProtein

        for name in shopping {
            ctx.insert(ShoppingItem(name: name, aisle: "Maison & épicerie"))
        }
        // Compléments recommandés (avec dosage en conseil) + ajouts.
        let recoByName = Dictionary(uniqueKeysWithValues: recommended.map { ($0.name, $0) })
        for name in chosenSupps.union(extraSupps) {
            let r = SupplementAdvisor.reco(for: name)
            let dose = recoByName[name]?.dosage
            let advice = dose != nil ? "\(dose!) · \(r.advice)" : r.advice
            ctx.insert(Supplement(name: name, hour: r.hour, minute: r.minute, active: true,
                                  moment: r.moment, withFood: r.withFood, advice: advice, confirm: true))
            NotificationManager.shared.scheduleDaily(
                id: "supp.\(name)",
                title: "\(name)\(dose!= nil?" · \(dose!)" : "")",
                body: advice.isEmpty ? "\(r.momentLabel) · \(r.foodLabel)" : advice,
                hour: r.hour, minute: r.minute)
        }
        try? ctx.save()
        CategorySetup.markDone(.nutrition)
        Haptics.success()
    }
}
