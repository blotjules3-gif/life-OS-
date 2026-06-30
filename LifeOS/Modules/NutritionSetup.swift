import SwiftUI
import SwiftData

// MARK: - Formulaire de configuration « Alimentation »
// Pré-remplit : objectif calorique, hydratation, liste de courses, compléments.

struct NutritionSetupView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("kcalGoal")  private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500

    // Réponses
    @State private var sex = "Homme"
    @State private var age = 25
    @State private var weight = 75
    @State private var height = 178
    @State private var activity = "Modéré (3-4×/sem)"
    @State private var goal = "Maintenir"
    @State private var shopping: Set<String> = []
    @State private var supplements: Set<String> = []

    private let tint = AppCategory.nutrition.tint

    // Articles souvent oubliés
    private let shoppingOptions = [
        "Sopalin", "Papier toilette", "Sacs poubelle", "Éponges", "Liquide vaisselle",
        "Lessive", "Sel", "Poivre", "Huile d'olive", "Beurre", "Œufs", "Lait",
        "Café", "Sucre", "Farine", "Ail", "Oignons", "Citrons", "Dentifrice",
        "Savon", "Piles", "Film alimentaire", "Riz", "Pâtes"
    ]
    private let supplementOptions = [
        "Oméga 3", "Vitamine D", "Magnésium", "Zinc", "Vitamine C", "Multivitamines",
        "Créatine", "Whey", "Ashwagandha", "Probiotiques", "Fer", "Vitamine B12",
        "Collagène", "Curcuma", "Ginseng", "Mélatonine", "Spiruline", "Coenzyme Q10",
        "Calcium", "Potassium", "Vitamine K2", "Glucosamine", "Rhodiola", "Iode"
    ]

    var body: some View {
        SetupFlow(title: "Alimentation", accent: tint, pages: pages, onComplete: commit)
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 18) {
                    SetupHeader(icon: "fork.knife", title: "On cale ta nutrition",
                                subtitle: "Quelques questions pour calculer tes besoins et préparer tes outils.",
                                accent: tint)
                    SetupChoice(options: ["Homme", "Femme"], selection: $sex, accent: tint,
                                icons: ["figure.stand", "figure.stand.dress"])
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "figure.arms.open", title: "Ton âge ?", accent: tint)
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
                    SetupHeader(icon: "pills", title: "Tes compléments",
                                subtitle: "Sélectionne ceux que tu prends (ou veux prendre). On te dira QUAND les prendre + rappels.",
                                accent: tint)
                    SetupMultiChoice(options: supplementOptions, selection: $supplements, accent: tint)
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

    // MARK: calculs

    private var bmr: Double {
        let w = Double(weight), h = Double(height), a = Double(age)
        return 10 * w + 6.25 * h - 5 * a + (sex == "Homme" ? 5 : -161)
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

    private var summaryCard: some View {
        HStack(spacing: 12) {
            metric("\(computedKcal)", "kcal / jour", "flame.fill")
            metric("\(computedWater)", "ml d'eau", "drop.fill")
        }.padding(.horizontal, 14)
    }
    private var finalSummary: some View {
        VStack(spacing: 10) {
            summaryCard
            row("cart.fill", "\(shopping.count) articles ajoutés à la liste de courses")
            row("pills.fill", "\(supplements.count) compléments programmés")
        }
    }
    private func metric(_ v: String, _ l: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(v).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)
    }

    // MARK: enregistrement

    private func commit() {
        kcalGoal = computedKcal
        waterGoal = computedWater

        for name in shopping {
            ctx.insert(ShoppingItem(name: name, aisle: "Maison & épicerie"))
        }
        for name in supplements {
            let r = SupplementAdvisor.reco(for: name)
            ctx.insert(Supplement(name: name, hour: r.hour, minute: r.minute, active: true,
                                  moment: r.moment, withFood: r.withFood, advice: r.advice, confirm: true))
            NotificationManager.shared.scheduleDaily(
                id: "supp.\(name)",
                title: "💊 \(name)",
                body: r.advice.isEmpty ? "\(r.momentLabel) · \(r.foodLabel)" : r.advice,
                hour: r.hour, minute: r.minute)
        }
        try? ctx.save()
        CategorySetup.markDone(.nutrition)
        Haptics.success()
    }
}
