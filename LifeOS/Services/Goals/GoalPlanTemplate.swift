import Foundation

/// Templates de plan par type d'objectif — génère un `GoalPlan` complet à
/// partir d'un `UserGoal`.
///
/// **Règle produit** : templates cohérents, générateurs neutres (pas de
/// partenaire hardcodé). Si un partenaire s'ajoute au catalogue plus tard,
/// le moteur peut enrichir dynamiquement les recommandations.
///
/// Loop 24.
@MainActor
enum GoalPlanTemplate {

    /// Point d'entrée principal — retourne le plan pour un objectif donné.
    /// C1 audit — enrichit le plan avec les recommandations partenaires
    /// disponibles APRÈS génération du plan neutre.
    static func plan(for goal: UserGoal) -> GoalPlan {
        let basePlan: GoalPlan = {
            switch goal.kind {
            case .weightLoss:      return weightLossPlan(goal)
            case .muscleGain:      return muscleGainPlan(goal)
            case .sleepBetter:     return sleepBetterPlan(goal)
            case .moreProductive:  return moreProductivePlan(goal)
            case .eatBetter:       return eatBetterPlan(goal)
            case .saveMoney:       return saveMoneyPlan(goal)
            case .reduceStress:    return reduceStressPlan(goal)
            case .fitnessGeneral:  return fitnessGeneralPlan(goal)
            case .custom:          return customPlan(goal)
            }
        }()
        return enrichWithPartners(basePlan, goal: goal)
    }

    /// C1 audit fix — ajoute des recommandations partenaires si le catalogue
    /// en contient (Phase 2+). Catalogue vide → aucune modif du plan.
    /// Neutralité produit : les partenaires viennent APRÈS les recos neutres,
    /// jamais à leur place. UI marque clairement "Offre partenaire".
    private static func enrichWithPartners(_ plan: GoalPlan, goal: UserGoal) -> GoalPlan {
        var enriched = plan.recommendations
        for moduleRaw in plan.modulesToActivate {
            let partners = PartnerCatalog.shared.partners(for: moduleRaw)
            for p in partners where p.capabilities.contains(.canRecommend) {
                enriched.append(Recommendation(
                    title: p.displayName,
                    rationale: p.description,
                    effort: .low,
                    estimatedCostEUR: nil,
                    partnerID: p.id,
                    actionKey: p.capabilities.contains(.canRedirect) ? "open:\(p.externalURL?.absoluteString ?? "")" : nil
                ))
            }
        }
        return GoalPlan(
            goalKind: plan.goalKind,
            title: plan.title,
            summary: plan.summary,
            modulesToActivate: plan.modulesToActivate,
            habits: plan.habits,
            reminders: plan.reminders,
            profileFields: plan.profileFields,
            recommendations: enriched
        )
    }

    // MARK: - Templates individuels

    private static func weightLossPlan(_ goal: UserGoal) -> GoalPlan {
        let target = goal.targetValue > 0 ? " (\(Int(goal.targetValue)) kg)" : ""
        return GoalPlan(
            goalKind: .weightLoss,
            title: "Perdre du poids\(target)",
            summary: "Sport 3x/sem + tracking nutrition + hydratation + pesée hebdo.",
            modulesToActivate: ["fitness", "nutrition"],
            habits: [
                HabitTemplate(name: "Séance sport", icon: "figure.strengthtraining.traditional",
                             moduleTag: "fitness", scheduledHour: 18, scheduledMinute: 0,
                             rationale: "3x/semaine — priorité déficit calorique + préserver muscle"),
                HabitTemplate(name: "Marche 8 000 pas", icon: "figure.walk",
                             moduleTag: "fitness", scheduledHour: 12, scheduledMinute: 30,
                             rationale: "Booster la dépense quotidienne sans fatigue"),
                HabitTemplate(name: "Pesée du matin", icon: "scalemass",
                             moduleTag: "fitness", scheduledHour: 7, scheduledMinute: 30,
                             rationale: "Tracking hebdo — ne pas se fier au jour par jour"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Hydratation", message: "Un grand verre d'eau — bois régulier.",
                    categoryRaw: "nutrition", frequencyRaw: "everyXHours",
                    hour: 8, minute: 0, intervalHours: 2,
                    windowStartHour: 8, windowEndHour: 20,
                    weekdayMask: 127, specificHours: []
                ),
            ],
            profileFields: goal.targetValue > 0 ? [
                ProfileFieldTemplate(
                    fieldID: "body.targetWeightKg",
                    value: computeTargetWeight(delta: -goal.targetValue),
                    onlyIfMissing: true
                )
            ] : [],
            recommendations: [
                Recommendation(
                    title: "Marche quotidienne 8 000 pas",
                    rationale: "Boost dépense calorique sans fatigue, complémentaire aux séances.",
                    effort: .low, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
                Recommendation(
                    title: "Prioriser protéines (~1.6g/kg)",
                    rationale: "Préserve la masse musculaire pendant la perte de poids.",
                    effort: .medium, estimatedCostEUR: nil, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func muscleGainPlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .muscleGain,
            title: "Prendre du muscle",
            summary: "Programme PPL 4x/sem + surplus calorique + protéines + sommeil.",
            modulesToActivate: ["fitness", "nutrition", "sleep"],
            habits: [
                HabitTemplate(name: "Séance push", icon: "figure.strengthtraining.traditional",
                             moduleTag: "fitness", scheduledHour: 18, scheduledMinute: 30,
                             rationale: "Semaine 1: Push (pecs/épaules/triceps)"),
                HabitTemplate(name: "Séance pull", icon: "figure.strengthtraining.traditional",
                             moduleTag: "fitness", scheduledHour: 18, scheduledMinute: 30,
                             rationale: "Semaine 1: Pull (dos/biceps)"),
                HabitTemplate(name: "Séance legs", icon: "figure.strengthtraining.functional",
                             moduleTag: "fitness", scheduledHour: 18, scheduledMinute: 30,
                             rationale: "Semaine 1: Legs (jambes/fessiers)"),
                HabitTemplate(name: "Repas protéiné", icon: "fork.knife",
                             moduleTag: "nutrition", scheduledHour: 12, scheduledMinute: 30,
                             rationale: "Cible ~1.8g protéines/kg de poids corporel"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Pesée du matin", message: "Suivi hebdo — moyenne sur 7 jours.",
                    categoryRaw: "fitness", frequencyRaw: "daily",
                    hour: 7, minute: 30, intervalHours: 2,
                    windowStartHour: 7, windowEndHour: 7,
                    weekdayMask: 127, specificHours: []
                ),
            ],
            profileFields: goal.targetValue > 0 ? [
                ProfileFieldTemplate(
                    fieldID: "body.targetWeightKg",
                    value: computeTargetWeight(delta: goal.targetValue),
                    onlyIfMissing: true
                )
            ] : [],
            recommendations: [
                Recommendation(
                    title: "Surplus calorique modéré (+250 kcal/j)",
                    rationale: "Prise de masse propre sans gras excessif.",
                    effort: .medium, estimatedCostEUR: nil, partnerID: nil, actionKey: nil
                ),
                Recommendation(
                    title: "Sommeil 8h+ par nuit",
                    rationale: "La récupération conditionne 40% du gain musculaire.",
                    effort: .medium, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func sleepBetterPlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .sleepBetter,
            title: "Mieux dormir",
            summary: "Routine du soir + coucher régulier + éviter écrans + respiration.",
            modulesToActivate: ["sleep", "mind"],
            habits: [
                HabitTemplate(name: "Routine coucher", icon: "moon.stars",
                             moduleTag: "sleep", scheduledHour: 22, scheduledMinute: 0,
                             rationale: "Rituel 30 min avant dodo — signal circadien"),
                HabitTemplate(name: "Respiration 4-7-8", icon: "wind",
                             moduleTag: "mind", scheduledHour: 22, scheduledMinute: 30,
                             rationale: "5 min — abaisse le rythme cardiaque"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Écrans off", message: "1h avant de dormir — lumière bleue = mélatonine coupée.",
                    categoryRaw: "sleep", frequencyRaw: "daily",
                    hour: 22, minute: 0, intervalHours: 2,
                    windowStartHour: 22, windowEndHour: 22,
                    weekdayMask: 127, specificHours: []
                ),
                ReminderTemplate(
                    title: "Prépare-toi au sommeil", message: "Douche tiède, lumières tamisées, respire.",
                    categoryRaw: "sleep", frequencyRaw: "daily",
                    hour: 22, minute: 30, intervalHours: 2,
                    windowStartHour: 22, windowEndHour: 22,
                    weekdayMask: 127, specificHours: []
                ),
            ],
            profileFields: [
                ProfileFieldTemplate(fieldID: "bedHour", value: "23", onlyIfMissing: true),
            ],
            recommendations: [
                Recommendation(
                    title: "Chambre fraîche (18-19°C) + noire complète",
                    rationale: "Facteur qualité sommeil profond le plus impactant.",
                    effort: .low, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func moreProductivePlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .moreProductive,
            title: "Plus productif / focus",
            summary: "Deep work matin + micro-pauses + méditation + coucher tôt.",
            modulesToActivate: ["productivity", "mind"],
            habits: [
                HabitTemplate(name: "Méditation matin", icon: "brain.head.profile",
                             moduleTag: "mind", scheduledHour: 7, scheduledMinute: 0,
                             rationale: "10 min avant les notifs — pose le focus"),
                HabitTemplate(name: "Deep work bloc 1", icon: "checkmark.circle",
                             moduleTag: "productivity", scheduledHour: 9, scheduledMinute: 0,
                             rationale: "90 min sans interruption sur la tâche prioritaire"),
                HabitTemplate(name: "Bilan écrans soir", icon: "iphone",
                             moduleTag: "productivity", scheduledHour: 21, scheduledMinute: 0,
                             rationale: "Check screen time — ajuster le lendemain"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Pause écran", message: "Regarde au loin 20 sec. Bouge.",
                    categoryRaw: "productivity", frequencyRaw: "everyXHours",
                    hour: 9, minute: 0, intervalHours: 1,
                    windowStartHour: 9, windowEndHour: 18,
                    weekdayMask: 31, specificHours: []
                ),
            ],
            profileFields: [],
            recommendations: [
                Recommendation(
                    title: "Notifications silencieuses le matin",
                    rationale: "Focus matin sanctuarisé = 3x plus productif que fragmenté.",
                    effort: .low, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func eatBetterPlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .eatBetter,
            title: "Mieux manger",
            summary: "3 repas + tracking + protéines + eau + limiter transformé.",
            modulesToActivate: ["nutrition"],
            habits: [
                HabitTemplate(name: "Petit-déj protéiné", icon: "sunrise",
                             moduleTag: "nutrition", scheduledHour: 8, scheduledMinute: 0,
                             rationale: "Cale la journée + satiété + énergie"),
                HabitTemplate(name: "Bilan alimentation soir", icon: "list.bullet.clipboard",
                             moduleTag: "nutrition", scheduledHour: 21, scheduledMinute: 0,
                             rationale: "Log rapide de ce que tu as mangé"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Hydratation", message: "Un verre d'eau.",
                    categoryRaw: "nutrition", frequencyRaw: "everyXHours",
                    hour: 8, minute: 0, intervalHours: 2,
                    windowStartHour: 8, windowEndHour: 20,
                    weekdayMask: 127, specificHours: []
                ),
            ],
            profileFields: [],
            recommendations: [
                Recommendation(
                    title: "Prépare tes lunchs le dimanche",
                    rationale: "Batch cooking = tu contrôles vraiment ce que tu manges en semaine.",
                    effort: .medium, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func saveMoneyPlan(_ goal: UserGoal) -> GoalPlan {
        let target = goal.targetValue > 0 ? " (\(Int(goal.targetValue))€/mois)" : ""
        return GoalPlan(
            goalKind: .saveMoney,
            title: "Économiser\(target)",
            summary: "Budget mensuel + tracking dépenses + revue hebdo + suppression abonnements inutiles.",
            modulesToActivate: ["finance"],
            habits: [
                HabitTemplate(name: "Note du jour dépenses", icon: "eurosign.circle",
                             moduleTag: "finance", scheduledHour: 21, scheduledMinute: 0,
                             rationale: "Tracking rapide = visibilité"),
                HabitTemplate(name: "Revue budget hebdo", icon: "chart.bar",
                             moduleTag: "finance", scheduledHour: 20, scheduledMinute: 0,
                             rationale: "Chaque dimanche — ajuster tes catégories"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Ai-je vraiment besoin de ça ?",
                    message: "Avant un achat non-essentiel, respire 5 min.",
                    categoryRaw: "finance", frequencyRaw: "daily",
                    hour: 12, minute: 0, intervalHours: 2,
                    windowStartHour: 12, windowEndHour: 12,
                    weekdayMask: 127, specificHours: []
                ),
            ],
            profileFields: [],
            recommendations: [
                Recommendation(
                    title: "Audit tes abonnements récurrents",
                    rationale: "Le plus gros gisement d'économie caché — 50 à 200€/mois moyen.",
                    effort: .low, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
                Recommendation(
                    title: "Compare les prix avant de racheter récurrent",
                    rationale: "Assurance, mutuelle, opérateur : renégociation annuelle = 200-500€/an.",
                    effort: .medium, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func reduceStressPlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .reduceStress,
            title: "Gérer le stress",
            summary: "Méditation quotidienne + respiration + journal du soir + sport.",
            modulesToActivate: ["mind", "fitness"],
            habits: [
                HabitTemplate(name: "Méditation 10 min", icon: "brain.head.profile",
                             moduleTag: "mind", scheduledHour: 7, scheduledMinute: 30,
                             rationale: "Rituel matin — baseline calme"),
                HabitTemplate(name: "Marche 20 min", icon: "figure.walk",
                             moduleTag: "fitness", scheduledHour: 12, scheduledMinute: 30,
                             rationale: "Décompression midi + lumière naturelle"),
                HabitTemplate(name: "Journal soir", icon: "book",
                             moduleTag: "mind", scheduledHour: 21, scheduledMinute: 30,
                             rationale: "3 choses positives + 1 apprentissage"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Respire", message: "3 respirations profondes. Relâche les épaules.",
                    categoryRaw: "mind", frequencyRaw: "everyXHours",
                    hour: 9, minute: 0, intervalHours: 3,
                    windowStartHour: 9, windowEndHour: 18,
                    weekdayMask: 31, specificHours: []
                ),
            ],
            profileFields: [],
            recommendations: []
        )
    }

    private static func fitnessGeneralPlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .fitnessGeneral,
            title: "Reprendre le sport",
            summary: "2 séances/sem semaine 1, augmenter progressivement + marche + étirements.",
            modulesToActivate: ["fitness"],
            habits: [
                HabitTemplate(name: "Séance sport", icon: "figure.run",
                             moduleTag: "fitness", scheduledHour: 18, scheduledMinute: 0,
                             rationale: "Commence 2x/sem, augmente à 4x/sem sur 4 semaines"),
                HabitTemplate(name: "Étirements soir", icon: "figure.flexibility",
                             moduleTag: "fitness", scheduledHour: 21, scheduledMinute: 30,
                             rationale: "5 min — évite les courbatures qui découragent"),
            ],
            reminders: [
                ReminderTemplate(
                    title: "Bouge 5 min", message: "Sort de ta chaise, marche un peu.",
                    categoryRaw: "fitness", frequencyRaw: "everyXHours",
                    hour: 9, minute: 0, intervalHours: 3,
                    windowStartHour: 9, windowEndHour: 18,
                    weekdayMask: 31, specificHours: []
                ),
            ],
            profileFields: [
                ProfileFieldTemplate(fieldID: "fitness.gymFrequency", value: "2", onlyIfMissing: true),
            ],
            recommendations: [
                Recommendation(
                    title: "Commence sans matériel à la maison",
                    rationale: "Réduit la friction — le plus dur est de commencer.",
                    effort: .low, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    private static func customPlan(_ goal: UserGoal) -> GoalPlan {
        GoalPlan(
            goalKind: .custom,
            title: goal.title.isEmpty ? "Objectif personnel" : goal.title,
            summary: "Objectif personnalisé — précise-moi ce que tu veux exactement pour un vrai plan.",
            modulesToActivate: [],
            habits: [],
            reminders: [],
            profileFields: [],
            recommendations: [
                Recommendation(
                    title: "Décris précisément ton objectif",
                    rationale: "Plus tu précises (durée, magnitude, contraintes), plus je peux construire un plan concret.",
                    effort: .low, estimatedCostEUR: 0, partnerID: nil, actionKey: nil
                ),
            ]
        )
    }

    // MARK: - Helpers

    /// Calcule le target weight à partir du delta demandé + poids actuel profil.
    /// Retourne "" si aucun poids actuel connu → onlyIfMissing skip l'écriture.
    private static func computeTargetWeight(delta: Double) -> String {
        guard let current = ProfileStore.shared.field("body.currentWeightKg"),
              let currentKg = Double(current.valueString) else {
            return ""
        }
        return String(format: "%.1f", currentKg + delta)
    }
}
