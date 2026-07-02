import SwiftUI
import UserNotifications

// MARK: - Question model

private enum QType {
    case bool
    case hour
    case weekday       // 1=lundi … 7=dimanche
    case monthDay      // 1-31
    case intStep(min: Int, max: Int, step: Int)
}

private struct Q: Identifiable {
    let id = UUID()
    let text: String
    let key: String
    let type: QType
    var gatedBy: String? = nil  // nil = toujours visible ; sinon visible seulement si UserDefaults[gatedBy] == true
}

// MARK: - Questions par module

private func questions(for module: AppCategory) -> [Q] {
    switch module {

    case .sleep: return [
        Q(text: "À quelle heure tu te lèves normalement ?", key: "wakeupHour", type: .hour),
        Q(text: "À quelle heure tu veux te coucher ?", key: "bedHour", type: .hour),
        Q(text: "Tu veux un bilan chaque matin après le réveil ?", key: "notif_sleep_morning_enabled", type: .bool),
        Q(text: "À quelle heure ce bilan matin ?", key: "notif_sleep_morning_hour", type: .hour, gatedBy: "notif_sleep_morning_enabled"),
        Q(text: "Tu veux un rappel pour aller te coucher ?", key: "notif_sleep_bedtime_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel coucher ?", key: "notif_sleep_bedtime_hour", type: .hour, gatedBy: "notif_sleep_bedtime_enabled"),
    ]

    case .fitness: return [
        Q(text: "À quelle heure ta séance commence ?", key: "sportHour", type: .hour),
        Q(text: "Tu veux un rappel avant ta séance ?", key: "notif_fitness_enabled", type: .bool),
        Q(text: "À quelle heure tu veux ce rappel sport ?", key: "notif_fitness_hour", type: .hour, gatedBy: "notif_fitness_enabled"),
    ]

    case .nutrition: return [
        Q(text: "Tu pratiques le jeûne intermittent ?", key: "nutrition_fasting_enabled", type: .bool),
        Q(text: "À quelle heure commence ta fenêtre alimentaire ?", key: "nutrition_fasting_start_hour", type: .hour, gatedBy: "nutrition_fasting_enabled"),
        Q(text: "À quelle heure se termine ta fenêtre alimentaire ?", key: "nutrition_fasting_end_hour", type: .hour, gatedBy: "nutrition_fasting_enabled"),
        Q(text: "Tu veux un rappel pour noter ton petit-déjeuner ?", key: "notif_nutrition_breakfast_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel petit-déjeuner ?", key: "notif_nutrition_breakfast_hour", type: .hour, gatedBy: "notif_nutrition_breakfast_enabled"),
        Q(text: "Tu veux un rappel pour noter ton déjeuner ?", key: "notif_nutrition_lunch_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel déjeuner ?", key: "notif_nutrition_lunch_hour", type: .hour, gatedBy: "notif_nutrition_lunch_enabled"),
        Q(text: "Tu veux un rappel pour noter ton dîner ?", key: "notif_nutrition_dinner_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel dîner ?", key: "notif_nutrition_dinner_hour", type: .hour, gatedBy: "notif_nutrition_dinner_enabled"),
        Q(text: "Tu veux un bilan calories en fin de journée ?", key: "notif_nutrition_review_enabled", type: .bool),
        Q(text: "À quelle heure ce bilan calories ?", key: "notif_nutrition_review_hour", type: .hour, gatedBy: "notif_nutrition_review_enabled"),
        Q(text: "Tu prends des compléments alimentaires ?", key: "nutrition_supplements_enabled", type: .bool),
        Q(text: "Tu veux un rappel pour tes compléments du matin ?", key: "notif_supplement_morning_enabled", type: .bool, gatedBy: "nutrition_supplements_enabled"),
        Q(text: "À quelle heure ce rappel compléments matin ?", key: "notif_supplement_morning_hour", type: .hour, gatedBy: "notif_supplement_morning_enabled"),
        Q(text: "Tu veux un rappel pour tes compléments du soir ?", key: "notif_supplement_evening_enabled", type: .bool, gatedBy: "nutrition_supplements_enabled"),
        Q(text: "À quelle heure ce rappel compléments soir ?", key: "notif_supplement_evening_hour", type: .hour, gatedBy: "notif_supplement_evening_enabled"),
    ]

    case .mind: return [
        Q(text: "Tu veux un rappel pour ta session bien-être ?", key: "notif_mind_session_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel bien-être ?", key: "notif_mind_session_hour", type: .hour, gatedBy: "notif_mind_session_enabled"),
        Q(text: "Tu veux un check-in humeur quotidien ?", key: "notif_mind_mood_enabled", type: .bool),
        Q(text: "À quelle heure ce check-in humeur ?", key: "notif_mind_mood_hour", type: .hour, gatedBy: "notif_mind_mood_enabled"),
    ]

    case .productivity: return [
        Q(text: "Tu veux un point sur tes priorités le matin ?", key: "notif_productivity_morning_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel matin ?", key: "notif_productivity_morning_hour", type: .hour, gatedBy: "notif_productivity_morning_enabled"),
        Q(text: "Tu veux un bilan de tes tâches le soir ?", key: "notif_productivity_evening_enabled", type: .bool),
        Q(text: "À quelle heure ce bilan soir ?", key: "notif_productivity_evening_hour", type: .hour, gatedBy: "notif_productivity_evening_enabled"),
        Q(text: "Tu veux un rappel pour tes habitudes ?", key: "notif_habits_enabled", type: .bool),
        Q(text: "À quelle heure voir tes habitudes ?", key: "notif_habits_hour", type: .hour, gatedBy: "notif_habits_enabled"),
    ]

    case .finance: return [
        Q(text: "Quel jour du mois tu reçois ton salaire ?", key: "finance_salary_day", type: .monthDay),
        Q(text: "Tu veux un bilan budget le jour de ton salaire ?", key: "notif_finance_monthly_enabled", type: .bool),
        Q(text: "À quelle heure ce bilan mensuel ?", key: "notif_finance_monthly_hour", type: .hour, gatedBy: "notif_finance_monthly_enabled"),
        Q(text: "Tu veux un bilan budget hebdomadaire ?", key: "notif_finance_weekly_enabled", type: .bool),
        Q(text: "Quel jour de la semaine ?", key: "finance_review_weekday", type: .weekday, gatedBy: "notif_finance_weekly_enabled"),
        Q(text: "À quelle heure ce bilan hebdo ?", key: "notif_finance_weekly_hour", type: .hour, gatedBy: "notif_finance_weekly_enabled"),
    ]

    case .invest: return [
        Q(text: "Tu investis régulièrement chaque mois (DCA) ?", key: "invest_dca_enabled", type: .bool),
        Q(text: "Quel jour du mois tu veux investir ?", key: "invest_dca_day", type: .monthDay, gatedBy: "invest_dca_enabled"),
        Q(text: "Tu veux un rappel pour ton investissement mensuel ?", key: "notif_invest_dca_enabled", type: .bool, gatedBy: "invest_dca_enabled"),
        Q(text: "À quelle heure ce rappel investissement ?", key: "notif_invest_dca_hour", type: .hour, gatedBy: "notif_invest_dca_enabled"),
        Q(text: "Tu veux une revue portfolio hebdomadaire ?", key: "notif_invest_weekly_enabled", type: .bool),
        Q(text: "Quel jour de la semaine ?", key: "invest_review_weekday", type: .weekday, gatedBy: "notif_invest_weekly_enabled"),
        Q(text: "À quelle heure cette revue portfolio ?", key: "notif_invest_weekly_hour", type: .hour, gatedBy: "notif_invest_weekly_enabled"),
    ]

    case .career: return [
        Q(text: "Tu es en recherche d'emploi active ?", key: "career_job_searching", type: .bool),
        Q(text: "Tu veux un rappel hebdomadaire pour tes candidatures ?", key: "notif_career_weekly_enabled", type: .bool, gatedBy: "career_job_searching"),
        Q(text: "Quel jour de la semaine ?", key: "career_review_weekday", type: .weekday, gatedBy: "notif_career_weekly_enabled"),
        Q(text: "À quelle heure ce rappel carrière ?", key: "notif_career_weekly_hour", type: .hour, gatedBy: "notif_career_weekly_enabled"),
    ]

    case .learning: return [
        Q(text: "Tu veux un rappel quotidien pour ta session d'apprentissage ?", key: "notif_learning_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel apprentissage ?", key: "notif_learning_hour", type: .hour, gatedBy: "notif_learning_enabled"),
    ]

    case .cycle: return [
        Q(text: "Tu veux tracker ton cycle chaque jour ?", key: "notif_cycle_daily_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel cycle ?", key: "notif_cycle_daily_hour", type: .hour, gatedBy: "notif_cycle_daily_enabled"),
        Q(text: "Tu veux être prévenue avant tes règles ?", key: "notif_cycle_pms_enabled", type: .bool),
        Q(text: "Combien de jours avant tu veux être prévenue ?", key: "cycle_pms_advance_days", type: .intStep(min: 1, max: 7, step: 1), gatedBy: "notif_cycle_pms_enabled"),
        Q(text: "À quelle heure cette alerte règles ?", key: "notif_cycle_pms_hour", type: .hour, gatedBy: "notif_cycle_pms_enabled"),
    ]

    case .home: return [
        Q(text: "Tu veux un rappel hebdomadaire pour le ménage ?", key: "notif_home_cleaning_enabled", type: .bool),
        Q(text: "Quel jour de la semaine ménage ?", key: "home_cleaning_weekday", type: .weekday, gatedBy: "notif_home_cleaning_enabled"),
        Q(text: "À quelle heure ce rappel ménage ?", key: "notif_home_cleaning_hour", type: .hour, gatedBy: "notif_home_cleaning_enabled"),
        Q(text: "Tu veux un rappel pour faire les courses ?", key: "notif_home_groceries_enabled", type: .bool),
        Q(text: "Quel jour tu fais tes courses ?", key: "home_groceries_weekday", type: .weekday, gatedBy: "notif_home_groceries_enabled"),
        Q(text: "À quelle heure ce rappel courses ?", key: "notif_home_groceries_hour", type: .hour, gatedBy: "notif_home_groceries_enabled"),
    ]

    case .admin: return [
        Q(text: "Tu veux un rappel hebdomadaire pour l'admin ?", key: "notif_admin_enabled", type: .bool),
        Q(text: "Quel jour de la semaine ?", key: "admin_session_weekday", type: .weekday, gatedBy: "notif_admin_enabled"),
        Q(text: "À quelle heure ce rappel admin ?", key: "notif_admin_hour", type: .hour, gatedBy: "notif_admin_enabled"),
    ]

    case .looks: return [
        Q(text: "Tu as une routine soin le matin ?", key: "looks_has_morning_routine", type: .bool),
        Q(text: "Tu veux un rappel pour ta routine matin ?", key: "notif_looks_morning_enabled", type: .bool, gatedBy: "looks_has_morning_routine"),
        Q(text: "À quelle heure ce rappel routine matin ?", key: "notif_looks_morning_hour", type: .hour, gatedBy: "notif_looks_morning_enabled"),
        Q(text: "Tu as une routine soin le soir ?", key: "looks_has_evening_routine", type: .bool),
        Q(text: "Tu veux un rappel pour ta routine soir ?", key: "notif_looks_evening_enabled", type: .bool, gatedBy: "looks_has_evening_routine"),
        Q(text: "À quelle heure ce rappel routine soir ?", key: "notif_looks_evening_hour", type: .hour, gatedBy: "notif_looks_evening_enabled"),
    ]

    case .social: return [
        Q(text: "Tu veux un rappel pour garder contact avec ton réseau ?", key: "notif_social_enabled", type: .bool),
        Q(text: "Quel jour de la semaine ?", key: "social_contact_weekday", type: .weekday, gatedBy: "notif_social_enabled"),
        Q(text: "À quelle heure ce rappel social ?", key: "notif_social_hour", type: .hour, gatedBy: "notif_social_enabled"),
    ]

    case .medical: return [
        Q(text: "Tu prends des médicaments le matin ?", key: "medical_med_morning_enabled", type: .bool),
        Q(text: "Tu veux un rappel pour tes médicaments du matin ?", key: "notif_medical_morning_enabled", type: .bool, gatedBy: "medical_med_morning_enabled"),
        Q(text: "À quelle heure ce rappel médicaments matin ?", key: "notif_medical_morning_hour", type: .hour, gatedBy: "notif_medical_morning_enabled"),
        Q(text: "Tu prends des médicaments le midi ?", key: "medical_med_noon_enabled", type: .bool),
        Q(text: "Tu veux un rappel pour tes médicaments du midi ?", key: "notif_medical_noon_enabled", type: .bool, gatedBy: "medical_med_noon_enabled"),
        Q(text: "À quelle heure ce rappel médicaments midi ?", key: "notif_medical_noon_hour", type: .hour, gatedBy: "notif_medical_noon_enabled"),
        Q(text: "Tu prends des médicaments le soir ?", key: "medical_med_evening_enabled", type: .bool),
        Q(text: "Tu veux un rappel pour tes médicaments du soir ?", key: "notif_medical_evening_enabled", type: .bool, gatedBy: "medical_med_evening_enabled"),
        Q(text: "À quelle heure ce rappel médicaments soir ?", key: "notif_medical_evening_hour", type: .hour, gatedBy: "notif_medical_evening_enabled"),
        Q(text: "Tu veux un rappel pour mesurer tes constantes ?", key: "notif_medical_vitals_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel constantes ?", key: "notif_medical_vitals_hour", type: .hour, gatedBy: "notif_medical_vitals_enabled"),
    ]

    case .mobility: return [
        Q(text: "Tu veux un rappel pour partir à l'heure le matin ?", key: "notif_mobility_departure_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel départ ?", key: "notif_mobility_departure_hour", type: .hour, gatedBy: "notif_mobility_departure_enabled"),
        Q(text: "Tu veux un rappel hebdomadaire pour faire le plein ?", key: "notif_mobility_fuel_enabled", type: .bool),
        Q(text: "Quel jour de la semaine ce rappel carburant ?", key: "mobility_fuel_weekday", type: .weekday, gatedBy: "notif_mobility_fuel_enabled"),
        Q(text: "À quelle heure ce rappel carburant ?", key: "notif_mobility_fuel_hour", type: .hour, gatedBy: "notif_mobility_fuel_enabled"),
    ]

    case .travel: return [
        Q(text: "Tu veux un rappel pour préparer ta valise avant un voyage ?", key: "notif_travel_packing_enabled", type: .bool),
        Q(text: "Combien de jours avant le départ ce rappel valise ?", key: "travel_packing_advance_days", type: .intStep(min: 1, max: 14, step: 1), gatedBy: "notif_travel_packing_enabled"),
        Q(text: "Tu veux un rappel la veille du départ ?", key: "notif_travel_departure_eve_enabled", type: .bool),
        Q(text: "À quelle heure ce rappel veille de départ ?", key: "notif_travel_departure_eve_hour", type: .hour, gatedBy: "notif_travel_departure_eve_enabled"),
    ]
    }
}

// MARK: - View

struct ModuleSetupView: View {
    let module: AppCategory
    @Environment(\.dismiss) private var dismiss

    @State private var rawIndex = 0
    @State private var boolVal = false
    @State private var hourVal = 8
    @State private var weekdayVal = 1
    @State private var monthDayVal = 1
    @State private var intStepVal = 1

    private let ud = UserDefaults.standard

    private var qs: [Q] { questions(for: module) }

    // Questions visibles compte tenu des réponses actuelles en UserDefaults
    private var visible: [Q] {
        qs.filter { q in
            guard let gate = q.gatedBy else { return true }
            return ud.object(forKey: gate) as? Bool ?? false
        }
    }

    private var currentQ: Q? {
        guard rawIndex < visible.count else { return nil }
        return visible[rawIndex]
    }

    private var progress: Double {
        guard !visible.isEmpty else { return 1 }
        return Double(rawIndex) / Double(visible.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                        Rectangle()
                            .fill(module.tint)
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 3)

                if let q = currentQ {
                    questionBody(q)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .id(q.id)
                } else {
                    doneView
                }
            }
            .navigationTitle(module.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Passer") { advance(saving: false) }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Question layout

    @ViewBuilder
    private func questionBody(_ q: Q) -> some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: module.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(module.tint)
                    .frame(width: 56, height: 56)
                    .background(module.tint.opacity(0.12), in: Circle())

                Text(q.text)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            answerControl(for: q)

            Spacer()

            if case .bool = q.type {
                EmptyView()
            } else {
                Button {
                    saveAndAdvance(q)
                } label: {
                    Text(rawIndex + 1 < visible.count ? "Suivant" : "Terminer")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(module.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { preloadAnswer(q) }
    }

    @ViewBuilder
    private func answerControl(for q: Q) -> some View {
        switch q.type {
        case .bool:
            HStack(spacing: 16) {
                boolButton(label: "Non", value: false, q: q)
                boolButton(label: "Oui", value: true, q: q)
            }
            .padding(.horizontal, 24)

        case .hour:
            HStack(spacing: 0) {
                Picker("", selection: $hourVal) {
                    ForEach(0..<24) { h in
                        Text(String(format: "%02d:00", h)).tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 140)
            .padding(.horizontal, 32)

        case .weekday:
            let days = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
            Picker("", selection: $weekdayVal) {
                ForEach(1...7, id: \.self) { i in
                    Text(days[i - 1]).tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            .padding(.horizontal, 32)

        case .monthDay:
            Picker("", selection: $monthDayVal) {
                ForEach(1...31, id: \.self) { d in
                    Text("Le \(d)").tag(d)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            .padding(.horizontal, 32)

        case .intStep(let min, let max, let step):
            VStack(spacing: 12) {
                Text("\(intStepVal)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(module.tint)
                    .contentTransition(.numericText())

                Stepper("", value: $intStepVal, in: min...max, step: step)
                    .labelsHidden()
            }
        }
    }

    private func boolButton(label: String, value: Bool, q: Q) -> some View {
        Button {
            ud.set(value, forKey: q.key)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                // Recompute visible after saving
                rawIndex = min(rawIndex + 1, visible.count)
            }
            if rawIndex >= visible.count {
                finalize()
            }
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    value ? module.tint : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(value ? .white : .primary)
        }
    }

    // MARK: - Navigation

    private func preloadAnswer(_ q: Q) {
        switch q.type {
        case .bool:
            boolVal = ud.object(forKey: q.key) as? Bool ?? false
        case .hour:
            let stored = ud.integer(forKey: q.key)
            hourVal = (0..<24).contains(stored) ? stored : 8
        case .weekday:
            let stored = ud.integer(forKey: q.key)
            weekdayVal = (1...7).contains(stored) ? stored : 1
        case .monthDay:
            let stored = ud.integer(forKey: q.key)
            monthDayVal = (1...31).contains(stored) ? stored : 1
        case .intStep(let min, _, _):
            let stored = ud.integer(forKey: q.key)
            intStepVal = stored > 0 ? stored : min
        }
    }

    private func saveAndAdvance(_ q: Q) {
        switch q.type {
        case .bool:
            ud.set(boolVal, forKey: q.key)
        case .hour:
            ud.set(hourVal, forKey: q.key)
        case .weekday:
            ud.set(weekdayVal, forKey: q.key)
        case .monthDay:
            ud.set(monthDayVal, forKey: q.key)
        case .intStep:
            ud.set(intStepVal, forKey: q.key)
        }
        advance(saving: true)
    }

    private func advance(saving: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            rawIndex += 1
        }
        if rawIndex >= visible.count {
            finalize()
        }
    }

    private func finalize() {
        ContextualNotifications.shared.reschedule()
        // Auto-dismiss après un bref délai pour que la vue "Tout est prêt" soit visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            dismiss()
        }
    }

    // MARK: - Done screen

    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(module.tint)

            VStack(spacing: 8) {
                Text("Tout est prêt")
                    .font(.system(size: 24, weight: .bold))
                Text("Tes notifications \(module.title.lowercased()) sont configurées.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button("Fermer") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(module.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }
}
