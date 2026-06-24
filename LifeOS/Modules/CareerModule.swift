import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var careerTint: Color { AppCategory.career.tint } }

// MARK: - Hub Carrière

struct CareerHubView: View {
    var body: some View {
        HubScaffold(category: .career) {
            ToolRow(icon: "tray.full.fill", title: "Suivi des candidatures",
                    subtitle: "Pipeline par statut", tint: .careerTint) { ApplicationsView() }
            ToolRow(icon: "doc.text.fill", title: "Générateur de CV",
                    subtitle: "Remplis → exporte", tint: .careerTint) { CVBuilderView() }
            ToolRow(icon: "checklist.checked", title: "Compétences manquantes",
                    subtitle: "Gap + plan pour combler", tint: .careerTint) { SkillGapView() }
            ToolRow(icon: "mic.fill", title: "Mock interview",
                    subtitle: "Entraînement entretien", tint: .careerTint) { MockInterviewView() }
            ToolRow(icon: "magnifyingglass", title: "Matching d'offres",
                    subtitle: "LinkedIn / Indeed — à brancher", tint: .careerTint) { JobMatchScaffold() }
        }
    }
}

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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
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
    @AppStorage("cvName") private var name = ""
    @AppStorage("cvTitle") private var title = ""
    @AppStorage("cvContact") private var contact = ""
    @AppStorage("cvSummary") private var summary = ""
    @AppStorage("cvExperience") private var experience = ""
    @AppStorage("cvEducation") private var education = ""
    @AppStorage("cvSkills") private var skills = ""

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
                    IntegrationNotice(text: "L'optimiseur de CV par IA (réécriture orientée poste, scoring ATS) se branche en envoyant ce texte + l'offre ciblée à un modèle de langage qui renvoie une version optimisée. Le contenu structuré est déjà prêt.")
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Générateur de CV").navigationBarTitleDisplayMode(.inline)
    }
    private func group<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { SectionHeader(title: t); c() }.card()
    }
    private func field(_ p: String, _ b: Binding<String>) -> some View { TextField(p, text: b).textFieldStyle(.roundedBorder) }
    private func editor(_ b: Binding<String>, _ p: String) -> some View {
        TextField(p, text: b, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...10)
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
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

struct MockInterviewView: View {
    @State private var index = 0
    @State private var showAnswer = false
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
    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 22) {
                Text("Question \(index+1)/\(questions.count)").font(.caption).foregroundStyle(Theme.textSecondary)
                Text(questions[index]).font(.title3.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center).padding()
                    .frame(maxWidth: .infinity, minHeight: 140).card()
                if showAnswer {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Comment cartonner", systemImage: "lightbulb.fill").font(.subheadline.bold()).foregroundStyle(.careerTint)
                        Text(tips[index]).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                }
                Button(showAnswer ? "Masquer le conseil" : "Voir le conseil") { withAnimation { showAnswer.toggle() } }
                    .buttonStyle(.bordered).tint(.careerTint)
                HStack {
                    Button { index = max(0, index-1); showAnswer = false } label: { Image(systemName: "chevron.left").padding() }.disabled(index == 0)
                    Spacer()
                    PrimaryButton(title: "Question suivante", icon: "chevron.right", tint: .careerTint) { index = (index+1) % questions.count; showAnswer = false }
                }
                IntegrationNotice(text: "Le mock interview « live » avec feedback IA sur tes réponses (ton, contenu, hésitations) se branche en enregistrant ta réponse vocale → transcription → analyse par un modèle de langage. Les questions et trames de réponse sont déjà là.")
            }.padding()
        }
        .navigationTitle("Mock interview").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Job match scaffold

struct JobMatchScaffold: View {
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 56)).foregroundStyle(.careerTint).padding(.top, 30)
                    Text("Matching d'offres").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    IntegrationNotice(text: "LinkedIn et Indeed ne donnent pas d'API publique ouverte pour lister/matcher les offres (CGU strictes). Options réelles : l'API LinkedIn Talent (entreprise, payante), des agrégateurs d'offres (Adzuna API gratuite, Jooble), ou la saisie de tes critères + matching contre ces flux. Ton profil (compétences, candidatures) est déjà structuré pour alimenter le matching.")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Branchable gratuitement").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("• Adzuna API (offres FR, gratuit avec clé)").font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                        Text("• Matching : compare tes compétences (module Skill gap) aux intitulés").font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Matching d'offres").navigationBarTitleDisplayMode(.inline)
    }
}
