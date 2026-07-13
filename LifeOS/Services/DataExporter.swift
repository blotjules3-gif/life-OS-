import Foundation
import SwiftData
import SwiftUI

/// Export JSON local de toutes les données importantes de l'utilisateur.
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

/// Feuille de préparation + partage de l'export.
struct DataExportSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var result: DataExporter.Result?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    ready(result)
                } else if failed {
                    ContentUnavailableView(
                        "Export impossible",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Une erreur est survenue pendant la préparation du fichier. Réessaie.")
                    )
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Préparation de ton export…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Exporter mes données")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            do { result = try DataExporter.export(ctx) }
            catch { failed = true }
        }
    }

    private func ready(_ result: DataExporter.Result) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(result.total) entrées prêtes")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Fichier JSON lisible — tes données restent sur ton appareil.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Contenu") {
                    ForEach(result.sections, id: \.label) { section in
                        HStack {
                            Text(section.label)
                            Spacer()
                            Text("\(section.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            ShareLink(item: result.url) {
                Label("Partager le fichier", systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}
