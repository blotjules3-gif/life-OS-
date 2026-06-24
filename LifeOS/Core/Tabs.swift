import SwiftUI
import SwiftData

// MARK: - Chat / Assistant

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

struct ChatView: View {
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var fasts: [FastingSession]
    @Query private var habits: [Habit]
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("waterGoal") private var waterGoal = 2500

    @State private var input = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(fromUser: false, text: "Salut 👋 Je suis ton assistant LifeOS. Demande-moi par ex. « combien de calories aujourd'hui ? », « combien d'eau ? », ou « où suivre mon jeûne ? ».")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(messages) { m in
                                HStack {
                                    if m.fromUser { Spacer(minLength: 40) }
                                    Text(m.text)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(m.fromUser ? Color.accentColor : Theme.card,
                                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .foregroundStyle(m.fromUser ? .white : .primary)
                                    if !m.fromUser { Spacer(minLength: 40) }
                                }
                                .id(m.id)
                            }
                            IntegrationNotice(text: "Cet assistant répond en local à partir de tes données. Pour des réponses libres et un vrai coaching, on peut le brancher sur l'API Claude (un appel réseau avec tes données en contexte).")
                                .padding(.top, 6)
                        }
                        .padding(Theme.pad)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                HStack(spacing: 10) {
                    TextField("Écris un message…", text: $input)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.bg2, in: Capsule())
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Color.accentColor)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, Theme.pad).padding(.vertical, 10)
                .background(.bar)
            }
            .background(Theme.bg)
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        messages.append(ChatMessage(fromUser: true, text: q))
        input = ""
        let reply = answer(for: q.lowercased())
        messages.append(ChatMessage(fromUser: false, text: reply))
    }

    private func answer(for q: String) -> String {
        let kcal = foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
        let water = waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
        if q.contains("calor") || q.contains("manger") || q.contains("mangé") {
            return "Tu es à \(kcal) kcal aujourd'hui, objectif \(kcalGoal). Il te reste \(max(0, kcalGoal - kcal)) kcal."
        }
        if q.contains("eau") || q.contains("hydrat") || q.contains("bois") || q.contains("bu") {
            return "Tu as bu \(water) ml sur \(waterGoal) ml. \(water >= waterGoal ? "Objectif atteint 💧" : "Encore \(waterGoal - water) ml à boire.")"
        }
        if q.contains("jeûn") || q.contains("jeun") || q.contains("fast") {
            if let a = fasts.first(where: { $0.isActive }) {
                return "Jeûne en cours depuis \(Int(a.elapsed/3600))h\(Int(a.elapsed.truncatingRemainder(dividingBy: 3600)/60))min, objectif \(a.targetHours)h. Va dans Catégories › Nutrition › Jeûne."
            }
            return "Aucun jeûne en cours. Lance-le dans Catégories › Nutrition › Jeûne intermittent."
        }
        if q.contains("habitude") || q.contains("streak") {
            let done = habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
            return "Tu as validé \(done)/\(habits.count) habitudes aujourd'hui. Continue 🔥"
        }
        if q.contains("dormir") || q.contains("sommeil") || q.contains("coucher") {
            return "Pour ton heure de coucher idéale, va dans Catégories › Sommeil › Heure de coucher optimale."
        }
        if q.contains("bonjour") || q.contains("salut") || q.contains("hello") || q.contains("hey") {
            return "Hello 👋 Je peux te dire tes calories, ton eau, ton jeûne ou tes habitudes du jour. Demande !"
        }
        if q.contains("merci") { return "Avec plaisir 🙌" }
        return "Je peux t'aider sur : calories, hydratation, jeûne, habitudes, sommeil. Reformule avec un de ces mots, ou ouvre le pôle concerné dans Catégories."
    }
}

// MARK: - Photo / Scanner

struct CameraView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ToolRow(icon: "fork.knife", title: "Scanner un plat",
                            subtitle: "Estimer les calories par photo", tint: Color(hex: 0x4CC38A)) { PhotoCalorieScaffold() }
                    ToolRow(icon: "barcode.viewfinder", title: "Scanner un code-barres",
                            subtitle: "Note santé + alternative", tint: Color(hex: 0x4CC38A)) { BarcodeScaffold() }
                    ToolRow(icon: "doc.viewfinder", title: "Scanner un document",
                            subtitle: "Coffre-fort + OCR", tint: Color(hex: 0x8A93A8)) { DocScanScaffold() }
                } header: {
                    Text("Capture")
                } footer: {
                    Text("Sur un vrai iPhone, ces outils ouvrent l'appareil photo. Sur simulateur, la caméra n'est pas disponible.")
                }
            }
            .navigationTitle("Scanner")
        }
    }
}

// MARK: - Profil & objectifs

struct ProfileView: View {
    @AppStorage("userName") private var name = ""
    @AppStorage("stepGoal") private var stepGoal = 10000
    @AppStorage("waterGoal") private var waterGoal = 2500
    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 150
    @AppStorage("fastTarget") private var fastTarget = 16
    @State private var healthConnected = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            TextField("Ton prénom", text: $name).font(.title3.weight(.semibold))
                            Text("Membre LifeOS").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }

                Section("Objectifs quotidiens") {
                    Stepper("Pas : \(stepGoal)", value: $stepGoal, in: 2000...30000, step: 500)
                    Stepper("Eau : \(waterGoal) ml", value: $waterGoal, in: 500...5000, step: 250)
                    Stepper("Calories : \(kcalGoal) kcal", value: $kcalGoal, in: 1000...5000, step: 50)
                    Stepper("Protéines : \(proteinGoal) g", value: $proteinGoal, in: 30...300, step: 5)
                    Stepper("Jeûne : \(fastTarget) h", value: $fastTarget, in: 12...24, step: 1)
                }

                Section("Santé") {
                    Button {
                        Task { healthConnected = await HealthService.shared.requestAuthorization() }
                    } label: {
                        Label(healthConnected ? "Apple Santé connecté ✓" : "Connecter Apple Santé", systemImage: "heart.fill")
                            .foregroundStyle(healthConnected ? .green : Color.accentColor)
                    }
                }

                Section("Notifications") {
                    Button {
                        Task { _ = await NotificationManager.shared.requestAuthorization() }
                    } label: {
                        Label("Activer les rappels", systemImage: "bell.fill")
                    }
                    Button(role: .destructive) {
                        NotificationManager.shared.cancelAll()
                    } label: {
                        Label("Annuler tous les rappels", systemImage: "bell.slash")
                    }
                }

                Section("À propos") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Pôles", value: "15")
                    LabeledContent("Données", value: "Stockées sur l'appareil")
                }
            }
            .navigationTitle("Profil")
        }
    }
}
