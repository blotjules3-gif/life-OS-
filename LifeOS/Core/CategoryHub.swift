//
//  CategoryHub.swift
//
//  Hub de catégorie DATA-DRIVEN : les outils d'un pôle sont décrits en données
//  (CategoryTool) puis rendus dans le MÊME mode d'affichage que la grille de
//  catégories (bulles libres / bulles rangées / icônes / liste), piloté par le
//  même @AppStorage("catLayout"). Ouvrir une catégorie reprend donc le visuel actif.
//
//  Aucun module n'est modifié : on référence simplement leurs vues détail.
//

import SwiftUI

// MARK: - Modèle d'outil

struct CategoryTool: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    let title: String
    var subtitle: String = ""
    var tint: Color = Theme.accent
    var fullScreen: Bool = false        // true = présenté en plein écran (cache la barre LifeOS)
    let dest: () -> AnyView

    init<V: View>(_ icon: String, _ title: String, _ subtitle: String = "",
                  tint: Color = Theme.accent, fullScreen: Bool = false,
                  @ViewBuilder dest: @escaping () -> V) {
        self.icon = icon; self.title = title; self.subtitle = subtitle
        self.tint = tint; self.fullScreen = fullScreen
        self.dest = { AnyView(dest()) }
    }

    static func == (l: CategoryTool, r: CategoryTool) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Fond thématique partagé (extrait de BubbleCategoriesView pour cohérence)

struct ThemedBubbleBackground: View {
    let theme: AppTheme
    var body: some View {
        let cols = theme.bubbleBG
        ZStack {
            if theme == .gothic {
                Color(hex: 0x050506)
                RadialGradient(colors: [.clear, Color.black.opacity(0.7)],
                               center: .center, startRadius: 60, endRadius: 520)
            } else if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: cols
                )
            } else {
                LinearGradient(colors: [cols[0], cols[4], cols[8]],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

// MARK: - Hub générique : rend les outils dans le mode d'affichage actif

struct CategoryHubView: View {
    let category: AppCategory

    @AppStorage("catLayout") private var layoutRaw = "organic"
    @AppStorage("appTheme")  private var appThemeRaw = "classic"
    @State private var cover: CategoryTool?

    private var layout: CatLayout { CatLayout(rawValue: layoutRaw) ?? .organic }
    private var theme: AppTheme   { AppTheme(rawValue: appThemeRaw) ?? .classic }
    private var tools: [CategoryTool] { category.tools }

    var body: some View {
        content
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(layout == .list ? .large : .inline)
            .fullScreenCover(item: $cover) { $0.dest() }
    }

    @ViewBuilder private var content: some View {
        switch layout {
        case .list:    listLayout
        case .icons:   iconGrid
        case .organic: bubbleCluster(tidy: false)
        case .tidy:    bubbleCluster(tidy: true)
        }
    }

    // Navigation : push normal, ou plein écran pour les outils fullScreen.
    @ViewBuilder
    private func toolLink<L: View>(_ tool: CategoryTool, @ViewBuilder label: () -> L) -> some View {
        if tool.fullScreen {
            Button { Haptics.soft(); cover = tool } label: { label() }.buttonStyle(.plain)
        } else {
            NavigationLink { tool.dest() } label: { label() }.buttonStyle(.plain)
        }
    }

    // ===== Mode Liste (rendu natif identique à l'ancien hub) =====
    private var listLayout: some View {
        List {
            ForEach(tools) { tool in
                if tool.fullScreen {
                    Button { Haptics.soft(); cover = tool } label: { rowLabel(tool, chevron: true) }
                        .buttonStyle(.plain)
                } else {
                    NavigationLink { tool.dest() } label: { rowLabel(tool, chevron: false) }
                }
            }
        }
    }

    private func rowLabel(_ tool: CategoryTool, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: tool.icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tool.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title).font(.body).foregroundStyle(.primary)
                if !tool.subtitle.isEmpty {
                    Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            if chevron {
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // ===== Mode Icônes =====
    private var iconGrid: some View {
        ZStack {
            ThemedBubbleBackground(theme: theme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 20) {
                    ForEach(tools) { tool in
                        toolLink(tool) {
                            VStack(spacing: 8) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 66, height: 66)
                                    .background(themedTint(tool).gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .shadow(color: themedTint(tool).opacity(0.4), radius: 8, y: 4)
                                Text(tool.title)
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
                                    .frame(height: 30, alignment: .top)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 120)
            }
        }
    }

    // ===== Modes Bulles (libres / rangées) =====
    private func bubbleCluster(tidy: Bool) -> some View {
        ZStack {
            ThemedBubbleBackground(theme: theme).ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width
                let availH = geo.size.height
                let cols = tools.count <= 4 ? 2 : 3
                let rows = Int(ceil(Double(tools.count) / Double(cols)))
                let cellW = w / CGFloat(cols)
                let base = cellW * 0.84
                let rowH = cellW * 1.02
                let blockH = CGFloat(rows) * rowH
                // Centre verticalement le bloc quand il tient ; sinon laisse défiler.
                let contentH = max(availH, blockH + 110)
                let startY = max(30, (contentH - blockH) / 2 - 24)

                ScrollView(showsIndicators: false) {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(tools.enumerated()), id: \.element.id) { i, tool in
                                let col = i % cols
                                let row = i / cols
                                let sizeMul: CGFloat = tidy ? 1.0 : [1.14, 0.9, 1.05, 0.86, 1.0, 0.94][i % 6]
                                let d = base * sizeMul
                                let jx: CGFloat = tidy ? 0 : CGFloat(sin(Double(i) * 2.1)) * cellW * 0.10
                                let jy: CGFloat = tidy ? 0 : CGFloat(cos(Double(i) * 1.7)) * rowH * 0.05
                                let bob: CGFloat = tidy ? 0 : CGFloat(sin(t * 0.5 + Double(i) * 1.3) * 4)
                                let x = (CGFloat(col) + 0.5) * cellW + jx
                                let y = startY + (CGFloat(row) + 0.5) * rowH + jy + bob
                                toolLink(tool) {
                                    toolBubble(tool, diameter: d, index: i, base: base, t: t)
                                }
                                .position(x: x, y: y)
                            }
                        }
                        .frame(width: w, height: contentH)
                    }
                    .frame(width: w, height: contentH)
                }
            }
        }
    }

    @ViewBuilder
    private func toolBubble(_ tool: CategoryTool, diameter d: CGFloat, index i: Int, base: CGFloat, t: Double) -> some View {
        if theme == .gothic {
            ChromeCategoryButton(
                title: tool.title,
                sfSymbolName: tool.icon,
                assetName: ChromeCategoryButton.asset(for: d, base: base, index: i),
                size: d,
                showLabel: true,
                pressed: false,
                time: t,
                phase: Double(i) * 1.7
            )
        } else {
            BubbleView(
                title: tool.title,
                systemImage: tool.icon,
                tint: themedTint(tool),
                diameter: d,
                showLabel: true,
                time: t,
                seed: Double(i) * 2.1,
                style: bubbleStyle
            )
        }
    }

    private var bubbleStyle: BubbleStyle {
        var s = BubbleStyle()
        if theme == .gothic { s.metal = 1; s.colorGlow = 0; s.whiteGlow = 0 }
        return s
    }

    // Teinte selon le thème (même logique que la grille de catégories).
    private func themedTint(_ tool: CategoryTool) -> Color {
        switch theme {
        case .classic, .dark: return tool.tint
        case .pinky:  return [Color(hex: 0xFF4F9D), Color(hex: 0xFF77B5), Color(hex: 0xF06EA9),
                              Color(hex: 0xFF8AC4), Color(hex: 0xE85C9E)][stableIndex(tool) % 5]
        case .gothic: return [Color(hex: 0xAEB7C4), Color(hex: 0xC6CED9), Color(hex: 0x99A3B2),
                              Color(hex: 0xD2D8E1), Color(hex: 0xB4BCC8)][stableIndex(tool) % 5]
        case .cloud:  return [Color(hex: 0xC3D2E8), Color(hex: 0xD2DEEE), Color(hex: 0xB7C8E2),
                              Color(hex: 0xCBD8EC), Color(hex: 0xDCE5F2)][stableIndex(tool) % 5]
        }
    }
    private func stableIndex(_ tool: CategoryTool) -> Int { tools.firstIndex(of: tool) ?? 0 }
}

// MARK: - Données : outils par catégorie (référencent les vues détail des modules)

extension AppCategory {
    var tools: [CategoryTool] {
        switch self {
        case .sleep:        return sleepTools
        case .nutrition:    return nutritionTools
        case .fitness:      return fitnessTools
        case .looks:        return looksTools
        case .mind:         return mindTools
        case .productivity: return productivityTools
        case .finance:      return financeTools
        case .invest:       return investTools
        case .career:       return careerTools
        case .learning:     return learningTools
        case .home:         return homeTools
        case .mobility:     return mobilityTools
        case .social:       return socialTools
        case .admin:        return adminTools
        case .travel:       return travelTools
        case .cycle:        return cycleTools
        }
    }
}

private let cycleTools: [CategoryTool] = [
    .init("calendar.badge.clock", "Suivi du cycle", "Règles · durée · prédiction", tint: .cycleTint) { CycleTrackerView() },
    .init("waveform.path.ecg", "Symptômes", "Crampes, humeur, énergie, peau", tint: .cycleTint) { CycleSymptomsView() },
    .init("chart.bar.fill", "Historique", "Régularité · durée moyenne", tint: .cycleTint) { CycleHistoryView() },
]

private let sleepTools: [CategoryTool] = [
    .init("bed.double.fill", "Heure de coucher optimale", "Cycles de 90 min · réveil léger", tint: .sleepTint) { BedtimeCalculatorView() },
    .init("powersleep", "Power nap", "Sieste calibrée 20 ou 90 min", tint: .sleepTint) { PowerNapView() },
    .init("moon.zzz.fill", "Coucher progressif", "Rappel + lumière bleue + mode nuit", tint: .sleepTint) { WindDownView() },
    .init("cloud.moon.fill", "Journal de rêves", "Note vocale + texte + humeur", tint: .sleepTint) { DreamJournalView() },
    .init("heart.text.square.fill", "Score de récupération", "HRV + FC repos (Apple Santé)", tint: .sleepTint) { RecoveryScoreView() },
]

private let nutritionTools: [CategoryTool] = [
    .init("timer", "Jeûne intermittent", "16:8, 18:6, OMAD — façon Zero", tint: .nutriTint) { FastingView() },
    .init("chart.pie.fill", "Calories & macros", "Journal du jour + objectifs", tint: .nutriTint) { CalAIView() },
    .init("refrigerator.fill", "Mon frigo", "Inventaire + idées repas", tint: .nutriTint) { FridgeView() },
    .init("cart.fill", "Liste de courses", "Par rayon, cochable", tint: .nutriTint) { ShoppingListView() },
    .init("drop.fill", "Hydratation", "Suivi + rappels", tint: .nutriTint) { HydrationView() },
    .init("pills.fill", "Compléments", "Rappels personnalisés", tint: .nutriTint) { SupplementsView() },
    .init("allergens", "Allergènes & régimes", "Halal, vegan, sans gluten…", tint: .nutriTint) { DietProfileView() },
    .init("camera.viewfinder", "Calories par photo", "Cal AI — à brancher", tint: .nutriTint) { PhotoCalorieScaffold() },
    .init("barcode.viewfinder", "Scan code-barres santé", "Yuka + prix + alternative", tint: .nutriTint) { ScanProductView() },
]

private let fitnessTools: [CategoryTool] = [
    .init("figure.walk", "Compteur de pas", "Aujourd'hui + 7 jours (Santé)", tint: .fitTint) { StepsView() },
    .init("dumbbell.fill", "Muscu & progression", "Charges, volume, 1RM, courbe", tint: .fitTint) { StrengthView() },
    .init("timer", "HIIT / Tabata", "Minuteur sportif plein écran", tint: .fitTint, fullScreen: true) { TabataView() },
    .init("figure.cooldown", "Mobilité & stretching", "Routines guidées", tint: .fitTint) { MobilityRoutineView() },
    .init("flame.fill", "Streaks & défis", "Régularité d'entraînement", tint: .fitTint) { StreaksView() },
]

private let looksTools: [CategoryTool] = [
    .init("face.dashed", "Analyse faciale", "Symétrie, harmony — Umax", tint: .looksTint) { FaceAnalysisScaffold() },
    .init("sparkles", "Routine skincare", "Matin/soir + rappels", tint: .looksTint) { SkincareView() },
    .init("camera.fill", "Photos avant / après", "Suivi visuel daté", tint: .looksTint) { ProgressPhotoGalleryView() },
    .init("mouth.fill", "Mewing & posture", "Rappels + minuteur", tint: .looksTint) { MewingPostureView() },
    .init("tshirt.fill", "Garde-robe & outfits", "Suggestion selon météo", tint: .looksTint) { WardrobeView() },
]

private let mindTools: [CategoryTool] = [
    .init("wind", "Respiration & cohérence", "Box breathing, 365…", tint: .mindTint) { BreathingView() },
    .init("leaf.fill", "Méditation", "Minuteur silencieux guidé", tint: .mindTint) { MeditationView() },
    .init("face.smiling.inverse", "Humeur & gratitude", "Journal quotidien", tint: .mindTint) { MoodJournalView() },
    .init("hourglass", "Détox écran", "Usage & objectifs", tint: .mindTint) { ScreenDetoxView() },
    .init("sun.horizon.fill", "Briefing du matin", "Motivation + ta journée", tint: .mindTint) { MorningBriefingView() },
]

private let productivityTools: [CategoryTool] = [
    .init("checklist", "To-do intelligente", "Priorités, projets, échéances", tint: .prodTint) { TodoView() },
    .init("calendar.day.timeline.left", "Time-blocking auto", "L'app remplit ta journée", tint: .prodTint) { TimeBlockView() },
    .init("square.grid.3x3.fill", "Habit tracker", "Streaks & régularité", tint: .prodTint) { HabitTrackerView() },
    .init("timer", "Focus / Pomodoro", "25 min concentration", tint: .prodTint) { FocusTimerView() },
    .init("note.text", "Notes & second cerveau", "Capture rapide + tags", tint: .prodTint) { NotesView() },
]

private let financeTools: [CategoryTool] = [
    .init("building.columns.fill", "Comptes & dépenses", "Solde + transactions + alertes", tint: .finTint) { AccountsView() },
    .init("tray.2.fill", "Budget par enveloppes", "Catégorise et plafonne", tint: .finTint) { BudgetView() },
    .init("repeat.circle.fill", "Abonnements", "Détecte les oubliés + résilie", tint: .finTint) { SubscriptionsView() },
    .init("person.2.circle.fill", "Split entre potes", "Tricount intégré", tint: .finTint) { SplitView() },
    .init("target", "Objectifs d'épargne", "Projection temps restant", tint: .finTint) { SavingsView() },
    .init("link.circle.fill", "Agrégation bancaire", "Bankin / Linxo — à brancher", tint: .finTint) { BankScaffold() },
]

private let investTools: [CategoryTool] = [
    .init("bitcoinsign.circle.fill", "Crypto", "Marché, risque et potentiel en temps réel", tint: .investTint, fullScreen: true) { CryptoAppView() },
    .init("chart.pie.fill", "Portefeuille", "Actions + crypto en un dashboard", tint: .investTint) { PortfolioView() },
    .init("chart.line.uptrend.xyaxis", "Net worth & FIRE", "Patrimoine + projection", tint: .investTint) { NetWorthView() },
    .init("house.fill", "Immobilier", "Biens, loyers, cashflow", tint: .investTint) { RealEstateView() },
    .init("percent", "Simulateur fiscalité", "Impôt sur le revenu (FR)", tint: .investTint) { TaxSimulatorView() },
]

private let careerTools: [CategoryTool] = [
    .init("tray.full.fill", "Suivi des candidatures", "Pipeline par statut", tint: .careerTint) { ApplicationsView() },
    .init("doc.text.fill", "Générateur de CV", "Remplis → exporte", tint: .careerTint) { CVBuilderView() },
    .init("checklist.checked", "Compétences manquantes", "Gap + plan pour combler", tint: .careerTint) { SkillGapView() },
    .init("mic.fill", "Mock interview", "Entraînement entretien", tint: .careerTint) { MockInterviewView() },
    .init("magnifyingglass", "Matching d'offres", "LinkedIn / Indeed — à brancher", tint: .careerTint) { JobMatchScaffold() },
]

private let learningTools: [CategoryTool] = [
    .init("rectangle.on.rectangle.angled", "Flashcards", "Répétition espacée (SM-2)", tint: .learnTint) { FlashcardsView() },
    .init("lightbulb.max.fill", "Micro-learning du jour", "Une pépite par jour", tint: .learnTint) { MicroLearningView() },
    .init("books.vertical.fill", "Résumés de livres", "Tes idées clés — Blinkist", tint: .learnTint) { BookSummariesView() },
    .init("chart.bar.fill", "Plan de montée en compétence", "Skill → jalons", tint: .learnTint) { SkillPlanView() },
]

private let homeTools: [CategoryTool] = [
    .init("calendar.badge.exclamationmark", "Anti-gaspi & péremption", "Ce qui périme bientôt", tint: .homeTint) { AntiWasteView() },
    .init("frying.pan.fill", "Recettes avec les restes", "Cuisine ce que tu as", tint: .homeTint) { LeftoverRecipesView() },
    .init("checklist", "Tâches ménagères", "Réparties couple / coloc", tint: .homeTint) { ChoresView() },
    .init("pawprint.fill", "Mes animaux", "Gamelle, véto, vaccins", tint: .homeTint) { PetsView() },
    .init("wrench.and.screwdriver.fill", "Maintenance récurrente", "Filtres, révisions, plantes", tint: .homeTint) { MaintenanceView() },
]

private let mobilityTools: [CategoryTool] = [
    .init("car.fill", "Ma voiture", "Assurance, révision, carburant", tint: .mobTint) { VehicleListView() },
    .init("fuelpump.fill", "Carburant le moins cher", "Carte stations — à brancher", tint: .mobTint) { FuelMapScaffold() },
    .init("point.topleft.down.to.point.bottomright.curvepath", "Itinéraire multimodal", "Citymapper — à brancher", tint: .mobTint) { MultimodalScaffold() },
]

private let socialTools: [CategoryTool] = [
    .init("person.crop.circle.badge.clock", "CRM personnel", "Qui relancer", tint: .socialTint) { CRMView() },
    .init("gift.fill", "Anniversaires & cadeaux", "Rappels + idées", tint: .socialTint) { BirthdaysView() },
    .init("calendar.badge.plus", "Sorties & events", "Organise tes événements", tint: .socialTint) { EventsView() },
]

private let adminTools: [CategoryTool] = [
    .init("lock.doc.fill", "Coffre-fort documents", "ID, contrats, garanties", tint: .adminTint) { DocVaultView() },
    .init("bell.badge.fill", "Échéances", "Impôts, assurance, abos", tint: .adminTint) { DeadlinesView() },
    .init("envelope.fill", "Générateur de courriers", "Résiliation, attestation…", tint: .adminTint) { LetterGeneratorView() },
    .init("doc.viewfinder.fill", "Scan & classement", "OCR auto — à brancher", tint: .adminTint) { DocScanScaffold() },
]

private let travelTools: [CategoryTool] = [
    .init("map.fill", "Mes voyages", "Itinéraire + budget + valise", tint: .travelTint) { TripsView() },
    .init("airplane.circle.fill", "Suivi des vols", "Statut & retards — à brancher", tint: .travelTint) { FlightScaffold() },
]
