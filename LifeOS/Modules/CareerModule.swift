import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var careerTint: Color { AppCategory.career.tint } }

// MARK: - Hub Carrière


// MARK: - Candidatures

struct ApplicationsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \JobApplication.date, order: .reverse) private var apps: [JobApplication]
    @State private var showAdd = false
    private let statuses = ["Repéré","Postulé","Entretien","Offre","Refusé"]

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(statuses, id: \.self) { s in
                            VStack { Text("\(apps.filter { $0.status == s }.count)").font(.headline.bold()).foregroundStyle(.careerTint); Text(s).font(.caption2).foregroundStyle(Theme.textSecondary) }.frame(maxWidth: .infinity)
                        }
                    }.card()

                    if apps.isEmpty {
                        EmptyState(icon: "tray.full", title: "Aucune candidature", message: "Ajoute une offre que tu suis.")
                    } else {
                        ForEach(statuses, id: \.self) { status in
                            let group = apps.filter { $0.status == status }
                            if !group.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionHeader(title: status)
                                    ForEach(group) { a in
                                        NavigationLink { ApplicationEditor(app: a) } label: {
                                            HStack {
                                                VStack(alignment: .leading) { Text(a.company).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary); Text(a.role).font(.caption).foregroundStyle(Theme.textSecondary) }
                                                Spacer()
                                                Text(a.date, style: .date).font(.caption2).foregroundStyle(Theme.textSecondary)
                                            }.card(padding: 12)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Candidatures").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { NavigationStack { ApplicationEditor(app: nil) } }
    }
}

struct ApplicationEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let app: JobApplication?
    @State private var company = ""; @State private var role = ""; @State private var status = "Repéré"
    @State private var url = ""; @State private var notes = ""
    private let statuses = ["Repéré","Postulé","Entretien","Offre","Refusé"]
    var body: some View {
        Form {
            TextField("Entreprise", text: $company)
            TextField("Poste", text: $role)
            Picker("Statut", selection: $status) { ForEach(statuses, id: \.self) { Text($0) } }
            TextField("Lien de l'offre", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
        }
        .navigationTitle(app == nil ? "Nouvelle candidature" : company).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { save(); dismiss() }.disabled(company.isEmpty) } }
        .onAppear { if let app { company = app.company; role = app.role; status = app.status; url = app.url; notes = app.notes } }
    }
    private func save() {
        if let app { app.company = company; app.role = role; app.status = status; app.url = url; app.notes = notes }
        else { ctx.insert(JobApplication(company: company, role: role, status: status, url: url, notes: notes)) }
    }
}

// MARK: - CV Builder

struct CVBuilderView: View {
    @AppStorage(AppStorageKeys.cvName) private var name = ""
    @AppStorage(AppStorageKeys.cvTitle) private var title = ""
    @AppStorage(AppStorageKeys.cvContact) private var contact = ""
    @AppStorage(AppStorageKeys.cvSummary) private var summary = ""
    @AppStorage(AppStorageKeys.cvExperience) private var experience = ""
    @AppStorage(AppStorageKeys.cvEducation) private var education = ""
    @AppStorage(AppStorageKeys.cvSkills) private var skills = ""
    @State private var showOptimiser = false
    @State private var aiReady = false

    private var generated: String {
        """
        \(name.uppercased())
        \(title)
        \(contact)

        — PROFIL —
        \(summary)

        — EXPÉRIENCE —
        \(experience)

        — FORMATION —
        \(education)

        — COMPÉTENCES —
        \(skills)
        """
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    group("Identité") {
                        field("Nom complet", $name)
                        field("Titre (ex: Développeur iOS)", $title)
                        field("Contact (email · tél · ville)", $contact)
                    }
                    group("Profil") { editor($summary, "Résumé en 2-3 lignes…") }
                    group("Expérience") { editor($experience, "Poste · Entreprise · Dates · réalisations…") }
                    group("Formation") { editor($education, "Diplôme · École · Année…") }
                    group("Compétences") { editor($skills, "Swift, gestion de projet, anglais…") }

                    ShareLink(item: generated) {
                        Label("Exporter / Partager le CV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.careerTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall)).foregroundStyle(.white)
                    }
                    if aiReady {
                        Button { showOptimiser = true } label: {
                            Label("Adapter mon CV à une offre", systemImage: "infinity")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered).tint(.careerTint)
                        .disabled(summary.isEmpty && experience.isEmpty)
                    } else {
                        Text("Ajoute une clé dans Profil › Coach pour adapter automatiquement ton CV à une offre.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Générateur de CV").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showOptimiser) {
            CVOptimiserSheet(summary: $summary, experience: $experience, skills: $skills)
        }
        .task { aiReady = await MainActor.run { AIText.isConfigured } }
    }
    private func group<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { SectionHeader(title: t); c() }.card()
    }
    private func field(_ p: String, _ b: Binding<String>) -> some View { TextField(p, text: b).textFieldStyle(.roundedBorder) }
    private func editor(_ b: Binding<String>, _ p: String) -> some View {
        TextField(p, text: b, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...10)
    }
}

/// Reecrit le CV en visant une offre precise.
///
/// Rien n'est ecrit automatiquement dans le CV: la proposition s'affiche a
/// cote et l'utilisateur applique s'il est d'accord. Un modele qui reecrit
/// tout seul l'experience de quelqu'un finit par lui inventer un passe.
struct CVOptimiserSheet: View {
    @Binding var summary: String
    @Binding var experience: String
    @Binding var skills: String
    @Environment(\.dismiss) private var dismiss

    @State private var offer = ""
    @State private var result = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("L'offre visée") {
                    TextField("Colle ici le texte de l'annonce…", text: $offer, axis: .vertical)
                        .lineLimit(4...12)
                }
                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            if busy { ProgressView().controlSize(.small) }
                            Text(busy ? "Analyse…" : "Proposer une version adaptée")
                        }
                    }
                    .disabled(busy || offer.trimmingCharacters(in: .whitespaces).count < 30)
                } footer: {
                    Text("Colle au moins quelques lignes de l'annonce pour que l'analyse ait du sens.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.footnote) }
                }
                if !result.isEmpty {
                    Section("Proposition") {
                        TextEditor(text: $result).frame(minHeight: 220)
                        Button("Remplacer mon profil par ce texte") {
                            summary = result
                            dismiss()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
            .navigationTitle("Adapter à l'offre").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }

    private func run() async {
        busy = true; error = nil
        defer { busy = false }
        let sys = """
        Tu aides à adapter un CV à une offre d'emploi. Réponds en français.         Réécris UNIQUEMENT le paragraphe de profil, en 3 à 4 lignes, en         reprenant le vocabulaire de l'annonce quand il correspond vraiment au         parcours. N'INVENTE aucune expérience, aucun diplôme, aucun chiffre         absent du CV fourni. Termine par une ligne "Mots-clés à ajouter :"         listant les termes de l'annonce absents du CV.
        """
        let ask = """
        OFFRE :
        \(offer)

        PROFIL ACTUEL :
        \(summary)

        EXPÉRIENCE :
        \(experience)

        COMPÉTENCES :
        \(skills)
        """
        switch await AIText.ask(system: sys, user: ask, maxTokens: 600, temperature: 0.3) {
        case .success(let t): result = t
        case .failure(let e): error = e.message
        }
    }
}

// MARK: - Skill gap

struct SkillGapView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var gaps: [SkillGap]
    @State private var showAdd = false
    private var roles: [String] { Array(Set(gaps.map { $0.targetRole })).sorted() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    if gaps.isEmpty {
                        EmptyState(icon: "checklist", title: "Aucun objectif de poste", message: "Définis un poste cible et les compétences requises, coche celles que tu as.")
                    } else {
                        ForEach(roles, id: \.self) { role in
                            let group = gaps.filter { $0.targetRole == role }
                            let have = group.filter { $0.acquired }.count
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { SectionHeader(title: role, subtitle: "\(have)/\(group.count) compétences"); Spacer(); Text("\(group.isEmpty ? 0 : have*100/group.count)%").font(.headline).foregroundStyle(.careerTint) }
                                ProgressView(value: Double(have), total: Double(max(1,group.count))).tint(.careerTint)
                                ForEach(group) { g in
                                    Button { g.acquired.toggle() } label: {
                                        HStack(alignment: .top) {
                                            Image(systemName: g.acquired ? "checkmark.circle.fill" : "circle").foregroundStyle(g.acquired ? .green : Theme.textSecondary)
                                            VStack(alignment: .leading) {
                                                Text(g.skill).foregroundStyle(Theme.textPrimary)
                                                if !g.acquired && !g.plan.isEmpty { Text("Plan : \(g.plan)").font(.caption).foregroundStyle(.careerTint) }
                                            }
                                            Spacer()
                                        }
                                    }
                                    .contextMenu { Button(role: .destructive) { ctx.delete(g) } label: { Label("Supprimer", systemImage: "trash") } }
                                }
                            }.card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Compétences manquantes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { SkillGapEditor(existingRoles: roles) }
    }
}

struct SkillGapEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let existingRoles: [String]
    @State private var role = ""; @State private var skill = ""; @State private var plan = ""; @State private var acquired = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Poste cible (ex: Lead iOS)", text: $role)
                if !existingRoles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(existingRoles, id: \.self) { r in Button(r) { role = r }.buttonStyle(.bordered).tint(.careerTint).font(.caption) } } }
                }
                TextField("Compétence", text: $skill)
                Toggle("Déjà acquise", isOn: $acquired)
                if !acquired { TextField("Plan pour l'acquérir", text: $plan, axis: .vertical).lineLimit(2...4) }
            }
            .navigationTitle("Compétence").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(SkillGap(targetRole: role, skill: skill, acquired: acquired, plan: plan)); dismiss() }.disabled(role.isEmpty || skill.isEmpty) }
            }
        }
    }
}

// MARK: - Mock interview

/// Entrainement a l'entretien: des questions, des trames, et un vrai retour
/// sur la reponse qu'on vient d'ecrire.
///
/// Avant, l'ecran affichait la question et le conseil, puis annoncait que le
/// retour sur la reponse "arrivait bientot". C'etait la seule partie qui fait
/// progresser: relire un conseil generique n'apprend rien, se faire dire que
/// sa propre reponse n'a pas de resultat chiffre, si.
struct MockInterviewView: View {
    @State private var index = 0
    @State private var showAnswer = false
    @State private var myAnswer = ""
    @State private var feedback = ""
    @State private var busy = false
    @State private var error: String?
    @State private var aiReady = false
    @FocusState private var writing: Bool

    private let questions = [
        "Présente-toi en 2 minutes.",
        "Quelle est ta plus grande réussite professionnelle ?",
        "Parle-moi d'un échec et ce que tu en as appris.",
        "Pourquoi ce poste et cette entreprise ?",
        "Où te vois-tu dans 5 ans ?",
        "Décris une situation de conflit et comment tu l'as gérée.",
        "Quelles sont tes faiblesses ?",
        "Pourquoi devrions-nous te choisir toi ?"
    ]
    private let tips = [
        "Structure : qui je suis → mon parcours → pourquoi je suis là. 90 secondes max.",
        "Méthode STAR : Situation, Tâche, Action, Résultat chiffré.",
        "Montre la leçon et l'action corrective, pas la culpabilité.",
        "Connecte tes valeurs à la mission de la boîte. Cite un fait précis sur eux.",
        "Ambition réaliste alignée avec l'évolution du poste.",
        "STAR encore : reste factuel, valorise l'écoute et la solution.",
        "Une vraie faiblesse + le plan concret pour la corriger.",
        "3 arguments : compétence clé, fit culturel, valeur ajoutée unique."
    ]

    /// Assez de matiere pour que le retour ait un sens. En dessous, le modele
    /// ne ferait que repeter le conseil generique deja affiche.
    private var longEnough: Bool {
        myAnswer.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    Text("Question \(index+1)/\(questions.count)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(questions[index])
                        .font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center).padding()
                        .frame(maxWidth: .infinity, minHeight: 130).card()

                    if showAnswer {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Comment cartonner", systemImage: "lightbulb.fill")
                                .font(.subheadline.bold()).foregroundStyle(.careerTint)
                            Text(tips[index]).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    Button(showAnswer ? "Masquer le conseil" : "Voir le conseil") {
                        withAnimation { showAnswer.toggle() }
                    }
                    .buttonStyle(.bordered).tint(.careerTint)

                    answerCard

                    HStack {
                        Button { go(-1) } label: { Image(systemName: "chevron.left").padding() }
                            .disabled(index == 0)
                            .accessibilityLabel("Question précédente")
                        Spacer()
                        PrimaryButton(title: "Question suivante", icon: "chevron.right", tint: .careerTint) { go(1) }
                    }
                }.padding()
            }
        }
        .navigationTitle("Mock interview").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("OK") { writing = false }
            }
        }
        .task { aiReady = await MainActor.run { AIText.isConfigured } }
    }

    // MARK: - Ma reponse

    @ViewBuilder private var answerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ta réponse",
                          subtitle: "Écris-la comme tu la dirais à l'oral")
            TextField("Réponds ici…", text: $myAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...12)
                .focused($writing)

            if aiReady {
                Button {
                    writing = false
                    Task { await critique() }
                } label: {
                    HStack {
                        if busy { ProgressView().controlSize(.small) }
                        Text(busy ? "Analyse…" : "Analyser ma réponse")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.careerTint)
                .disabled(busy || !longEnough)

                if !longEnough && !myAnswer.isEmpty {
                    Text("Écris encore quelques mots pour que l'analyse soit utile.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("Ajoute une clé dans Profil › Coach pour faire analyser tes réponses.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if !feedback.isEmpty {
                Divider()
                Label("Retour de ton coach", systemImage: "text.bubble.fill")
                    .font(.subheadline.bold()).foregroundStyle(.careerTint)
                Text(feedback).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Changer de question remet la copie a zero: garder la reponse d'avant
    /// sous une nouvelle question ferait analyser le mauvais texte.
    private func go(_ step: Int) {
        if step < 0 { index = max(0, index - 1) }
        else { index = (index + 1) % questions.count }
        showAnswer = false
        myAnswer = ""
        feedback = ""
        error = nil
        writing = false
    }

    private func critique() async {
        busy = true; error = nil
        defer { busy = false }
        let sys = """
        Tu es un recruteur expérimenté qui prépare un candidat à un entretien. \
        Réponds en français, en tutoyant, en 120 mots maximum. \
        Donne exactement trois parties, dans cet ordre et avec ces titres : \
        "Ce qui marche :", "Ce qui manque :", "Ta réponse réécrite :". \
        Juge la structure (méthode STAR), la présence d'un résultat concret et \
        chiffré, et la longueur pour un oral. \
        N'invente aucun fait, aucun chiffre et aucune expérience qui ne soit \
        pas dans la réponse du candidat : s'il manque un chiffre, dis-lui d'en \
        ajouter un, ne le fabrique pas.
        """
        let ask = """
        QUESTION POSÉE :
        \(questions[index])

        RÉPONSE DU CANDIDAT :
        \(myAnswer)
        """
        switch await AIText.ask(system: sys, user: ask, maxTokens: 450, temperature: 0.3) {
        case .success(let t): feedback = t
        case .failure(let e): error = e.message
        }
    }
}

// MARK: - Job match scaffold

// MARK: - Matching d'offres (recherche RÉELLE, API publique gratuite sans clé)

struct JobPosting: Identifiable, Decodable {
    var id: String { slug }
    let slug: String
    let title: String
    let company_name: String
    let location: String
    let remote: Bool
    let url: String
    let tags: [String]
    let job_types: [String]
}

private struct ArbeitnowResponse: Decodable { let data: [JobPosting] }

enum JobSearchService {
    /// Flux public gratuit, sans clé (offres tech/remote, majoritairement Europe).
    static func fetch() async throws -> [JobPosting] {
        let url = URL(string: "https://www.arbeitnow.com/api/job-board-api")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ArbeitnowResponse.self, from: data).data
    }
}

struct JobMatchView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query private var skills: [SkillGap]

    @State private var query = ""
    @State private var remoteOnly = false
    @State private var all: [JobPosting] = []
    @State private var loading = false
    @State private var errorText: String?

    /// Compétences ciblées de l'utilisateur (module « Compétences manquantes »).
    private var mySkills: [String] {
        Array(Set(skills.map { $0.skill.lowercased() }.filter { $0.count > 1 }))
    }

    private func score(_ job: JobPosting) -> Int {
        let hay = (job.title + " " + job.tags.joined(separator: " ")).lowercased()
        return mySkills.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
    }

    private var filtered: [JobPosting] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all
            .filter { !remoteOnly || $0.remote }
            .filter { job in
                q.isEmpty || {
                    let hay = (job.title + " " + job.company_name + " " + job.location + " " + job.tags.joined(separator: " ")).lowercased()
                    return hay.contains(q)
                }()
            }
            .sorted { score($0) > score($1) }
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                searchBar
                if loading && all.isEmpty {
                    Spacer(); ProgressView("Recherche d'offres…"); Spacer()
                } else if let errorText, all.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text(errorText).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Réessayer") { Task { await load() } }.buttonStyle(.borderedProminent).tint(.careerTint)
                    }.padding(30)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if filtered.isEmpty {
                                Text("Aucune offre ne correspond.").font(.footnote).foregroundStyle(.secondary).padding(.top, 40)
                            }
                            ForEach(filtered) { job in jobCard(job) }
                        }.padding(Theme.pad)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .navigationTitle("Matching d'offres").navigationBarTitleDisplayMode(.inline)
        .task { if all.isEmpty { await load() } }
    }

    private var searchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Poste, techno, ville…", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Effacer la recherche") }
            }
            .padding(10).background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Toggle("Télétravail uniquement", isOn: $remoteOnly).font(.subheadline).tint(.careerTint)
            if !mySkills.isEmpty {
                Text("★ = correspond à tes compétences suivies").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.pad)
        .background(Theme.background)
    }

    private func jobCard(_ job: JobPosting) -> some View {
        let s = score(job)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(job.company_name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if s > 0 {
                    Text("★ \(s)").font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.careerTint, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Label(job.location.isEmpty ? "—" : job.location, systemImage: "mappin.and.ellipse")
                if job.remote { Label("Remote", systemImage: "house") }
            }.font(.caption).foregroundStyle(.secondary)
            if !job.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(job.tags.prefix(6), id: \.self) { t in
                            Text(t).font(.caption2).foregroundStyle(.careerTint)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.careerTint.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { if let u = URL(string: job.url) { openURL(u) } } label: {
                    Label("Voir l'offre", systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold))
                }.buttonStyle(.borderedProminent).tint(.careerTint)
                Button { track(job) } label: {
                    Label("Suivre", systemImage: "tray.and.arrow.down").font(.subheadline)
                }.buttonStyle(.bordered).tint(.careerTint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func track(_ job: JobPosting) {
        ctx.insert(JobApplication(company: job.company_name, role: job.title, status: "Repéré", url: job.url))
        do { try ctx.save() } catch { AppLog.data.error("track JobApplication save failed: \(error.localizedDescription, privacy: .public)") }
        Haptics.soft()
    }

    private func load() async {
        loading = true; errorText = nil
        do { all = try await JobSearchService.fetch() }
        catch { errorText = "Impossible de charger les offres (vérifie ta connexion)." }
        loading = false
    }
}
