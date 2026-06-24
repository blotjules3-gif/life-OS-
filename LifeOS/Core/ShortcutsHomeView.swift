import SwiftUI

/// Outils directs qu'on peut épingler en raccourci sur l'accueil.
enum ShortcutTool: String, CaseIterable, Identifiable {
    case dashboard, tabata, calories, scan, todo, fasting, water, habits
    case focus, mood, breathing, bedtime, budget, portfolio, flashcards, nap, progressPhotos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Tableau de bord"
        case .tabata: return "HIIT / Tabata"
        case .calories: return "Calories"
        case .scan: return "Scan produit"
        case .todo: return "To-do"
        case .fasting: return "Jeûne"
        case .water: return "Hydratation"
        case .habits: return "Habitudes"
        case .focus: return "Focus"
        case .mood: return "Humeur"
        case .breathing: return "Respiration"
        case .bedtime: return "Coucher"
        case .budget: return "Budget"
        case .portfolio: return "Portefeuille"
        case .flashcards: return "Flashcards"
        case .nap: return "Sieste"
        case .progressPhotos: return "Photos"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .tabata: return "timer"
        case .calories: return "flame.fill"
        case .scan: return "barcode.viewfinder"
        case .todo: return "checklist"
        case .fasting: return "hourglass"
        case .water: return "drop.fill"
        case .habits: return "square.grid.3x3.fill"
        case .focus: return "brain.head.profile"
        case .mood: return "face.smiling"
        case .breathing: return "wind"
        case .bedtime: return "bed.double.fill"
        case .budget: return "tray.2.fill"
        case .portfolio: return "chart.pie.fill"
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .nap: return "powersleep"
        case .progressPhotos: return "camera.fill"
        }
    }
    var tint: Color {
        switch self {
        case .dashboard: return Color(hex: 0x618EF1)
        case .tabata, .habits, .nap: return AppCategory.fitness.tint
        case .calories, .scan, .fasting, .water: return AppCategory.nutrition.tint
        case .todo, .focus: return AppCategory.productivity.tint
        case .mood, .breathing: return AppCategory.mind.tint
        case .bedtime: return AppCategory.sleep.tint
        case .budget: return AppCategory.finance.tint
        case .portfolio: return AppCategory.invest.tint
        case .flashcards: return AppCategory.learning.tint
        case .progressPhotos: return AppCategory.looks.tint
        }
    }
    var isFullScreen: Bool { self == .tabata }

    @ViewBuilder var destination: some View {
        switch self {
        case .dashboard: HomeDashboardContent()
        case .tabata: TabataView()
        case .calories: MacroLogView()
        case .scan: BarcodeScaffold()
        case .todo: TodoView()
        case .fasting: FastingView()
        case .water: HydrationView()
        case .habits: HabitTrackerView()
        case .focus: FocusTimerView()
        case .mood: MoodJournalView()
        case .breathing: BreathingView()
        case .bedtime: BedtimeCalculatorView()
        case .budget: BudgetView()
        case .portfolio: PortfolioView()
        case .flashcards: FlashcardsView()
        case .nap: PowerNapView()
        case .progressPhotos: ProgressPhotoGalleryView()
        }
    }
}

struct ShortcutsHomeView: View {
    @AppStorage("homeShortcuts") private var enabledRaw = "tabata,calories,scan,todo,fasting,water,habits,mood"
    @State private var editing = false
    @State private var showCatalog = false
    @State private var path: [ShortcutTool] = []
    @State private var fullScreenTool: ShortcutTool?

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var enabled: [ShortcutTool] {
        enabledRaw.split(separator: ",").compactMap { ShortcutTool(rawValue: String($0)) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(greeting).font(.largeTitle.bold()).padding(.horizontal, 4)
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(enabled) { tool in
                            tile(tool)
                        }
                        if editing {
                            Button { showCatalog = true } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "plus").font(.title2.bold())
                                    Text("Ajouter").font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 26)
                                .background(RoundedRectangle(cornerRadius: Theme.radius).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(.secondary.opacity(0.5)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.pad)
            }
            .background(Theme.bg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "OK" : "Modifier") { withAnimation { editing.toggle() } }
                }
            }
            .navigationDestination(for: ShortcutTool.self) { $0.destination }
            .fullScreenCover(item: $fullScreenTool) { $0.destination }
            .sheet(isPresented: $showCatalog) { catalog }
        }
    }

    private func tile(_ tool: ShortcutTool) -> some View {
        Button {
            if editing { return }
            if tool.isFullScreen { fullScreenTool = tool } else { path.append(tool) }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(tool.tint.opacity(0.16)).frame(width: 52, height: 52)
                    Image(systemName: tool.icon).font(.title3.weight(.semibold)).foregroundStyle(tool.tint)
                }
                Text(tool.label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button { remove(tool) } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .offset(x: 8, y: -8)
                }
            }
            .scaleEffect(editing ? 0.97 : 1)
        }
        .buttonStyle(.plain)
    }

    private var catalog: some View {
        NavigationStack {
            List {
                ForEach(ShortcutTool.allCases) { tool in
                    Button {
                        if enabled.contains(tool) { remove(tool) } else { add(tool) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tool.icon).foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(tool.tint, in: RoundedRectangle(cornerRadius: 7))
                            Text(tool.label).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: enabled.contains(tool) ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(enabled.contains(tool) ? .green : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Raccourcis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showCatalog = false } } }
        }
    }

    private func add(_ tool: ShortcutTool) {
        guard !enabled.contains(tool) else { return }
        enabledRaw = (enabled + [tool]).map { $0.rawValue }.joined(separator: ",")
    }
    private func remove(_ tool: ShortcutTool) {
        enabledRaw = enabled.filter { $0 != tool }.map { $0.rawValue }.joined(separator: ",")
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon aprèm"
        case 18..<23: return "Bonsoir"
        default: return "Bonne nuit"
        }
    }
}
