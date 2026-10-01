import Foundation
import SwiftData
import SwiftUI

/// Resume JSON lisible d'une PARTIE des donnees (pas une sauvegarde: voir FullBackup).
/// Aucun réseau : le fichier est écrit dans tmp puis partagé via ShareLink.
enum DataExporter {

    struct Result {
        let url: URL
        let sections: [(label: String, count: Int)]
        var total: Int { sections.reduce(0) { $0 + $1.count } }
    }

    static func export(_ ctx: ModelContext) throws -> Result {
        var root: [String: Any] = [:]
        var sections: [(String, Int)] = []

        func add(_ key: String, _ label: String, _ rows: [[String: Any]]) {
            guard !rows.isEmpty else { return }
            root[key] = rows
            sections.append((label, rows.count))
        }

        // Santé
        add("humeur", "Humeur", try ctx.fetch(FetchDescriptor<MoodEntry>()).map {
            ["date": iso($0.date), "score": $0.score, "note": $0.note, "gratitude": $0.gratitude]
        })
        add("eau", "Hydratation", try ctx.fetch(FetchDescriptor<WaterEntry>()).map {
            ["date": iso($0.date), "ml": $0.amountML]
        })
        add("repas", "Repas", try ctx.fetch(FetchDescriptor<FoodEntry>()).map {
            ["date": iso($0.date), "nom": $0.name, "kcal": $0.calories,
             "proteines": $0.protein, "glucides": $0.carbs, "lipides": $0.fat, "repas": $0.meal]
        })
        add("jeunes", "Jeûnes", try ctx.fetch(FetchDescriptor<FastingSession>()).map {
            ["debut": iso($0.start), "fin": iso($0.end), "objectifHeures": $0.targetHours]
        })
        add("reves", "Rêves", try ctx.fetch(FetchDescriptor<DreamEntry>()).map {
            ["date": iso($0.date), "titre": $0.title, "texte": $0.text, "humeur": $0.mood]
        })
        // L'historique du cycle manquait: l'export disait "tes donnees" sans
        // un seul jour de regles.
        add("cycle", "Cycle", try ctx.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)])).map {
            ["date": iso($0.date), "flux": $0.flow, "symptomes": $0.symptoms,
             "humeur": $0.mood, "note": $0.note]
        })
        add("pas", "Pas", try ctx.fetch(FetchDescriptor<StepEntry>()).map {
            ["jour": iso($0.day), "pas": $0.steps]
        })
        add("sport", "Séances de sport", try ctx.fetch(FetchDescriptor<WorkoutSet>()).map {
            ["date": iso($0.date), "exercice": $0.exercise, "poidsKg": $0.weightKg,
             "reps": $0.reps, "rpe": $0.rpe]
        })

        // Santé médicale
        add("mesures", "Mesures santé", try ctx.fetch(FetchDescriptor<VitalRecord>()).map {
            ["date": iso($0.date), "type": $0.type, "valeur": $0.value,
             "valeur2": $0.value2 ?? NSNull(), "unite": $0.unit, "notes": $0.notes]
        })
        add("medicaments", "Médicaments", try ctx.fetch(FetchDescriptor<Medication>()).map {
            ["nom": $0.name, "dosage": $0.dosage, "frequence": $0.frequency,
             "debut": iso($0.startDate), "fin": iso($0.endDate), "actif": $0.active, "notes": $0.notes]
        })
        add("vaccins", "Vaccins", try ctx.fetch(FetchDescriptor<Vaccination>()).map {
            ["nom": $0.name, "date": iso($0.date), "rappel": iso($0.nextDueDate),
             "lot": $0.lot, "notes": $0.notes]
        })
        add("rdvMedicaux", "RDV médicaux", try ctx.fetch(FetchDescriptor<MedicalAppointment>()).map {
            ["date": iso($0.date), "specialite": $0.specialty, "medecin": $0.doctorName,
             "lieu": $0.location, "prochain": iso($0.nextDate), "notes": $0.notes]
        })

        // Habitudes & organisation
        add("habitudes", "Habitudes", try ctx.fetch(FetchDescriptor<Habit>()).map {
            ["nom": $0.name, "creee": iso($0.createdAt), "archivee": $0.isArchived,
             "module": $0.moduleTag,
             "completions": $0.completions.map { iso($0.date) }]
        })
        add("taches", "Tâches", try ctx.fetch(FetchDescriptor<TodoItem>()).map {
            ["titre": $0.title, "notes": $0.notes, "echeance": iso($0.due),
             "faite": $0.done, "priorite": $0.priority, "projet": $0.project]
        })
        add("notes", "Notes", try ctx.fetch(FetchDescriptor<Note>()).map {
            ["titre": $0.title, "texte": $0.body, "tags": $0.tags, "creee": iso($0.created)]
        })
        add("souvenirs", "Souvenirs du coach", try ctx.fetch(FetchDescriptor<MemoryEntry>()).map {
            ["contenu": $0.content, "categorie": $0.category, "source": $0.source,
             "cree": iso($0.created), "epingle": $0.isPinned]
        })

        // Finances
        add("comptes", "Comptes", try ctx.fetch(FetchDescriptor<Account>()).map {
            ["nom": $0.name, "type": $0.kind, "solde": $0.balance]
        })
        add("transactions", "Transactions", try ctx.fetch(FetchDescriptor<Txn>()).map {
            ["date": iso($0.date), "montant": $0.amount, "categorie": $0.category,
             "compte": $0.account, "note": $0.note]
        })
        add("budgets", "Budgets", try ctx.fetch(FetchDescriptor<Envelope>()).map {
            ["nom": $0.name, "budgetMensuel": $0.monthlyBudget, "depense": $0.spent]
        })
        add("abonnements", "Abonnements", try ctx.fetch(FetchDescriptor<Subscription>()).map {
            ["nom": $0.name, "montant": $0.amount, "cycle": $0.cycle,
             "prochaine": iso($0.nextDate), "actif": $0.active]
        })
        add("epargne", "Objectifs d'épargne", try ctx.fetch(FetchDescriptor<SavingsGoal>()).map {
            ["nom": $0.name, "objectif": $0.target, "actuel": $0.current, "parMois": $0.monthly]
        })
        // Loop 24 audit m2 — UserGoal unifié (Goal-Plan architecture)
        add("objectifs_vie", "Objectifs personnels", try ctx.fetch(FetchDescriptor<UserGoal>()).map { g in
            var d: [String: Any] = [
                "titre": g.title,
                "type": g.kindRaw,
                "cible": g.targetValue,
                "unite": g.targetUnit,
                "statut": g.statusRaw,
                "cree": iso(g.createdAt),
                "planApplique": g.appliedPlanSummary
            ]
            if let deadline = g.deadline { d["echeance"] = iso(deadline) }
            if g.monthlyBudget > 0 { d["budgetMensuel"] = g.monthlyBudget }
            if !g.constraints.isEmpty { d["contraintes"] = g.constraints }
            return d
        })

        var payload: [String: Any] = [
            "app": "LifeOS",
            "exporteLe": iso(Date()),
            "version": 1
        ]
        payload["donnees"] = root

        let data = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.prettyPrinted, .sortedKeys])
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeOS-export-\(df.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return Result(url: url, sections: sections)
    }

    private static func iso(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return ISO8601DateFormatter().string(from: date)
    }
}

/// Sauvegarde complete, restauration, et resume lisible.
///
/// Avant, cette feuille ne proposait que le JSON, presente comme "tes donnees".
/// Il ne couvrait qu'une partie des types et aucune photo: pas une sauvegarde.
struct DataExportSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var backupURL: URL?
    @State private var backupManifest: FullBackup.Manifest?
    @State private var working = false
    @State private var error: String?

    @State private var showImporter = false
    @State private var candidate: (url: URL, manifest: FullBackup.Manifest)?
    @State private var staged: FullBackup.Manifest?
    @State private var pending = FullBackup.hasPendingRestore()

    @State private var summary: DataExporter.Result?

    var body: some View {
        NavigationStack {
            List {
                backupSection
                restoreSection
                summarySection
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                }
            }
            .navigationTitle("Mes données")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
                switch result {
                case .success(let url): inspect(url)
                case .failure(let e): error = "Fichier non ouvert : \(e.localizedDescription)"
                }
            }
            .confirmationDialog("Remplacer les données de cet appareil ?",
                                isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
                                titleVisibility: .visible) {
                Button("Restaurer au prochain lancement", role: .destructive) { stage() }
                Button("Annuler", role: .cancel) { candidate = nil }
            } message: {
                if let m = candidate?.manifest {
                    Text("Sauvegarde du \(m.createdAt.formatted(date: .long, time: .shortened)) : \(m.totalRows) entrées, \(m.fileCount) fichiers. Les données actuelles seront mises de côté sur l'appareil, pas effacées.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Sauvegarde complete

    private var backupSection: some View {
        Section {
            if let url = backupURL, let m = backupManifest {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sauvegarde prête", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Text("\(m.totalRows) entrées, \(m.fileCount) fichiers, \(sizeText(url))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ShareLink(item: url) { Label("Enregistrer ou envoyer le fichier", systemImage: "square.and.arrow.up") }
            } else {
                Button { makeBackup() } label: {
                    HStack {
                        Label("Créer une sauvegarde complète", systemImage: "externaldrive.badge.checkmark")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working)
            }
        } header: {
            Text("Sauvegarde complète")
        } footer: {
            Text("Tout LifeOS dans un fichier : la base entière, les photos, les documents scannés et les réglages. Il permet de tout restaurer, sur cet appareil ou un autre. Tes clés d'API n'y sont pas incluses.")
        }
    }

    // MARK: Restauration

    private var restoreSection: some View {
        Section {
            if pending {
                Label(staged.map { "Restauration prête : \($0.totalRows) entrées, \($0.fileCount) fichiers." }
                      ?? "Une restauration est prête.", systemImage: "clock.arrow.circlepath")
                Text("Ferme complètement LifeOS puis rouvre-le pour l'appliquer.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Annuler la restauration", role: .destructive) {
                    FullBackup.cancelPendingRestore(); pending = false; staged = nil
                }
            } else {
                Button { showImporter = true } label: {
                    Label("Restaurer une sauvegarde…", systemImage: "arrow.counterclockwise.circle")
                }
            }
        } header: {
            Text("Restaurer")
        } footer: {
            Text("Le fichier est vérifié avant tout changement. Un fichier abîmé ou étranger est refusé.")
        }
    }

    // MARK: Resume lisible

    private var summarySection: some View {
        Section {
            if let summary {
                ShareLink(item: summary.url) {
                    Label("Partager le résumé (\(summary.total) entrées)", systemImage: "doc.text")
                }
            } else {
                Button { makeSummary() } label: { Label("Créer un résumé lisible (JSON)", systemImage: "doc.text") }
            }
        } header: {
            Text("Résumé lisible")
        } footer: {
            Text("Un fichier texte pour lire ou réutiliser une partie de tes données (repas, habitudes, finances, santé). Ce n'est pas une sauvegarde : il ne contient ni photos ni documents et ne se restaure pas.")
        }
    }

    // MARK: Actions

    private func makeBackup() {
        error = nil; working = true
        do { try ctx.save() } catch {
            working = false; self.error = "Enregistrement en cours impossible : \(error.localizedDescription)"; return
        }
        var loc = FullBackup.Locations.app
        if let url = ctx.container.configurations.first?.url { loc.store = url }
        let defaults = FullBackup.currentDefaults()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let stamp = Date().formatted(.iso8601.year().month().day())
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeOS-\(stamp).\(FullBackup.fileExtension)")
        Task.detached(priority: .userInitiated) {
            let result = Result { try FullBackup.make(at: loc, defaults: defaults, appVersion: version, to: out) }
            await MainActor.run {
                working = false
                switch result {
                case .success(let m): backupURL = out; backupManifest = m
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func inspect(_ url: URL) {
        error = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Copie locale: l'acces au fichier choisi ne dure pas jusqu'a la confirmation.
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).\(FullBackup.fileExtension)")
        do {
            try FileManager.default.copyItem(at: url, to: local)
            candidate = (local, try FullBackup.readManifest(local))
        } catch {
            try? FileManager.default.removeItem(at: local)
            self.error = error.localizedDescription
        }
    }

    private func stage() {
        guard let c = candidate else { return }
        candidate = nil; working = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try FullBackup.stageRestore(from: c.url, at: .app) }
            try? FileManager.default.removeItem(at: c.url)
            await MainActor.run {
                working = false
                switch result {
                case .success(let m): staged = m; pending = true
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func makeSummary() {
        do { summary = try DataExporter.export(ctx) }
        catch { self.error = "Résumé impossible : \(error.localizedDescription)" }
    }

    private func sizeText(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
