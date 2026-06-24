import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var learnTint: Color { AppCategory.learning.tint } }

// MARK: - Hub Apprentissage

struct LearningHubView: View {
    var body: some View {
        HubScaffold(category: .learning) {
            ToolRow(icon: "rectangle.on.rectangle.angled", title: "Flashcards",
                    subtitle: "Répétition espacée (SM-2)", tint: .learnTint) { FlashcardsView() }
            ToolRow(icon: "lightbulb.max.fill", title: "Micro-learning du jour",
                    subtitle: "Une pépite par jour", tint: .learnTint) { MicroLearningView() }
            ToolRow(icon: "books.vertical.fill", title: "Résumés de livres",
                    subtitle: "Tes idées clés — Blinkist", tint: .learnTint) { BookSummariesView() }
            ToolRow(icon: "chart.bar.fill", title: "Plan de montée en compétence",
                    subtitle: "Skill → jalons", tint: .learnTint) { SkillPlanView() }
        }
    }
}

// MARK: - Flashcards (SM-2)

struct FlashcardsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var cards: [Flashcard]
    @State private var showAdd = false
    @State private var reviewing = false
    private var decks: [String] { Array(Set(cards.map { $0.deck })).sorted() }
    private var dueCount: Int { cards.filter { $0.due <= Date() }.count }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("\(dueCount)").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(.learnTint)
                        Text("cartes à réviser").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity).card()
                    if dueCount > 0 {
                        PrimaryButton(title: "Démarrer la révision", icon: "play.fill", tint: .learnTint) { reviewing = true }
                    }
                    if cards.isEmpty {
                        EmptyState(icon: "rectangle.on.rectangle.angled", title: "Aucune carte", message: "Crée tes flashcards. L'algorithme planifie les révisions pour ancrer durablement.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Paquets")
                            ForEach(decks, id: \.self) { d in
                                HStack { Image(systemName: "square.stack.fill").foregroundStyle(.learnTint); Text(d).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(cards.filter { $0.deck == d }.count)").foregroundStyle(Theme.textSecondary) }.card(padding: 12)
                            }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Flashcards").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { FlashcardEditor(decks: decks) }
        .fullScreenCover(isPresented: $reviewing) { ReviewSession(cards: cards.filter { $0.due <= Date() }) }
    }
}

struct FlashcardEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let decks: [String]
    @State private var front = ""; @State private var back = ""; @State private var deck = "Général"
    var body: some View {
        NavigationStack {
            Form {
                TextField("Paquet", text: $deck)
                if !decks.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(decks, id: \.self) { d in Button(d) { deck = d }.buttonStyle(.bordered).tint(.learnTint).font(.caption) } } } }
                Section("Recto") { TextField("Question", text: $front, axis: .vertical).lineLimit(2...5) }
                Section("Verso") { TextField("Réponse", text: $back, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle("Nouvelle carte").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Flashcard(front: front, back: back, deck: deck.isEmpty ? "Général" : deck)); dismiss() }.disabled(front.isEmpty) }
            }
        }
    }
}

struct ReviewSession: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [Flashcard]
    @State private var index = 0
    @State private var flipped = false

    var body: some View {
        ZStack {
            Theme.background
            if index >= cards.count {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 60)).foregroundStyle(.green)
                    Text("Révision terminée 🎉").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                    PrimaryButton(title: "Fermer", tint: .learnTint) { dismiss() }.padding(.horizontal, 40)
                }
            } else {
                let card = cards[index]
                VStack(spacing: 24) {
                    HStack { Text("\(index+1)/\(cards.count)").foregroundStyle(Theme.textSecondary); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) } }
                    Spacer()
                    VStack(spacing: 16) {
                        Text(flipped ? "RÉPONSE" : "QUESTION").font(.caption.bold()).foregroundStyle(.learnTint)
                        Text(flipped ? card.back : card.front).font(.title2.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, minHeight: 240).card().onTapGesture { withAnimation { flipped.toggle() } }
                    Spacer()
                    if !flipped {
                        PrimaryButton(title: "Voir la réponse", icon: "eye.fill", tint: .learnTint) { withAnimation { flipped = true } }
                    } else {
                        HStack(spacing: 10) {
                            gradeButton("À revoir", .red, 2)
                            gradeButton("Correct", .orange, 4)
                            gradeButton("Facile", .green, 5)
                        }
                    }
                }.padding()
            }
        }
    }
    private func gradeButton(_ label: String, _ color: Color, _ q: Int) -> some View {
        Button { grade(q) } label: { Text(label).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14).background(color, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white) }
    }
    private func grade(_ q: Int) {
        SM2.apply(to: cards[index], quality: q)
        flipped = false
        index += 1
    }
}

/// Algorithme SuperMemo-2 pour la répétition espacée.
enum SM2 {
    static func apply(to card: Flashcard, quality q: Int) {
        if q < 3 {
            card.reps = 0; card.intervalDays = 1
        } else {
            switch card.reps {
            case 0: card.intervalDays = 1
            case 1: card.intervalDays = 6
            default: card.intervalDays = Int((Double(card.intervalDays) * card.ease).rounded())
            }
            card.reps += 1
        }
        card.ease = max(1.3, card.ease + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)))
        card.due = Calendar.current.date(byAdding: .day, value: max(1, card.intervalDays), to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
}

// MARK: - Micro-learning

struct MicroLearningView: View {
    private let facts = [
        ("Effet de simple exposition", "Plus on est exposé à quelque chose, plus on l'apprécie. Utile en marketing… et en networking."),
        ("Loi de Parkinson", "Le travail s'étale pour occuper le temps disponible. Donne-toi des deadlines courtes."),
        ("Règle des 2 minutes", "Si une tâche prend moins de 2 min, fais-la tout de suite (GTD, David Allen)."),
        ("Intérêts composés", "Le plus puissant levier financier : commencer tôt bat épargner beaucoup."),
        ("Biais de confirmation", "On cherche ce qui confirme nos croyances. Cherche activement le contre-argument."),
        ("Pareto 80/20", "80% des résultats viennent de 20% des actions. Identifie ces 20%."),
        ("Pic-fin", "On juge une expérience sur son pic émotionnel et sa fin, pas sa moyenne."),
        ("Dette technique", "Les raccourcis d'aujourd'hui sont les ralentissements de demain. Refactore tôt.")
    ]
    private var todayFact: (String, String) { facts[Calendar.current.ordinality(of: .day, in: .era, for: .now)! % facts.count] }
    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 20) {
                Image(systemName: "lightbulb.max.fill").font(.system(size: 50)).foregroundStyle(.learnTint).padding(.top, 40)
                Text("Pépite du jour").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                VStack(spacing: 12) {
                    Text(todayFact.0).font(.title2.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    Text(todayFact.1).font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }.card()
                Text("Reviens demain pour une nouvelle notion.").font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
            }.padding()
        }
        .navigationTitle("Micro-learning").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Résumés de livres

struct BookSummariesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \BookSummary.date, order: .reverse) private var books: [BookSummary]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if books.isEmpty {
                        EmptyState(icon: "books.vertical", title: "Aucun résumé", message: "Note les idées clés de tes lectures pour les retenir.")
                    } else {
                        ForEach(books) { b in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(b.title).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text(String(repeating: "★", count: b.rating)).foregroundStyle(.learnTint).font(.caption) }
                                if !b.author.isEmpty { Text(b.author).font(.caption).foregroundStyle(Theme.textSecondary) }
                                if !b.keyIdeas.isEmpty { Text(b.keyIdeas).font(.subheadline).foregroundStyle(Theme.textPrimary.opacity(0.9)) }
                            }.frame(maxWidth: .infinity, alignment: .leading).card()
                                .contextMenu { Button(role: .destructive) { ctx.delete(b) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                    IntegrationNotice(text: "Générer automatiquement le résumé d'un livre (façon Blinkist) à partir d'un titre se branche via un modèle de langage. Ici tu captures tes propres idées clés — ce qui est en réalité bien plus efficace pour la mémorisation.")
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Résumés de livres").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { BookEditor() }
    }
}

struct BookEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var author = ""; @State private var ideas = ""; @State private var rating = 4
    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $title)
                TextField("Auteur", text: $author)
                Stepper("Note : \(rating)/5", value: $rating, in: 1...5)
                Section("Idées clés") { TextField("Ce que tu retiens…", text: $ideas, axis: .vertical).lineLimit(4...12) }
            }
            .navigationTitle("Nouveau résumé").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(BookSummary(title: title, author: author, keyIdeas: ideas, rating: rating)); dismiss() }.disabled(title.isEmpty) }
            }
        }
    }
}

// MARK: - Plan de montée en compétence

struct SkillPlanView: View {
    @AppStorage("skillPlanName") private var skill = ""
    @AppStorage("skillPlanSteps") private var stepsRaw = ""
    @AppStorage("skillPlanDone") private var doneRaw = ""
    @State private var newStep = ""

    private var steps: [String] { stepsRaw.split(separator: "\n").map(String.init) }
    private var done: Set<String> { Set(doneRaw.split(separator: "\n").map(String.init)) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Compétence visée")
                        TextField("Ex: Parler anglais couramment", text: $skill).textFieldStyle(.roundedBorder)
                    }.card()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack { SectionHeader(title: "Jalons", subtitle: "\(done.count)/\(steps.count) faits"); Spacer() }
                        if !steps.isEmpty { ProgressView(value: Double(done.count), total: Double(max(1, steps.count))).tint(.learnTint) }
                        ForEach(steps, id: \.self) { s in
                            Button { toggle(s) } label: {
                                HStack { Image(systemName: done.contains(s) ? "checkmark.circle.fill" : "circle").foregroundStyle(done.contains(s) ? .green : Theme.textSecondary); Text(s).strikethrough(done.contains(s)).foregroundStyle(Theme.textPrimary); Spacer() }
                            }
                        }
                        HStack {
                            TextField("Ajouter un jalon…", text: $newStep).textFieldStyle(.roundedBorder).onSubmit(addStep)
                            Button(action: addStep) { Image(systemName: "plus.circle.fill").foregroundStyle(.learnTint) }.disabled(newStep.isEmpty)
                        }
                    }.card()

                    Text("Astuce : transforme chaque jalon en flashcards et habitudes pour le rendre automatique.").font(.caption).foregroundStyle(Theme.textSecondary)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Plan de compétence").navigationBarTitleDisplayMode(.inline)
    }
    private func addStep() { guard !newStep.isEmpty else { return }; stepsRaw += (stepsRaw.isEmpty ? "" : "\n") + newStep; newStep = "" }
    private func toggle(_ s: String) {
        var d = done
        if d.contains(s) { d.remove(s) } else { d.insert(s) }
        doneRaw = d.joined(separator: "\n")
    }
}
