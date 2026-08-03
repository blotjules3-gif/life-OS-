import SwiftUI
import SwiftData

/// Écran alternatif à l'onboarding long — 1 seule question, activation en 30s.
///
/// Displayed depuis `OnboardingWelcome` via le bouton « Démarrage rapide ».
/// Le user pose son objectif principal, on l'amène direct dans l'app avec :
/// - 3 modules activés
/// - 3 habitudes seed
/// - Défauts sains + notifs intelligentes on
struct QuickStartView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let onDone: () -> Void

    @State private var selected: OnboardingGoal?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.06), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                choices
                Spacer()
                ctaBar
            }
            .padding(.horizontal, 24)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("Démarrage express")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .kerning(1.5)
                .padding(.top, 40)
            Text("En 30 secondes")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Text("Choisis ta priorité — on configure LifeOS pour toi automatiquement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private var choices: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingGoal.allCases) { goal in
                Button {
                    selected = goal
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(selected == goal ? goal.tint : goal.tint.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: goal.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selected == goal ? .white : goal.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(shortDescription(for: goal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selected == goal ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected == goal ? goal.tint : Color.secondary.opacity(0.3))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(selected == goal ? goal.tint : Color.clear, lineWidth: 2)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaBar: some View {
        VStack(spacing: 10) {
            Button {
                guard let goal = selected else { return }
                QuickStart.apply(goal: goal.rawValue, ctx: ctx)
                onDone()
            } label: {
                Text("Créer mon LifeOS")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(selected != nil ? Color.accentColor : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(.white)
            }
            .disabled(selected == nil)

            Button {
                dismiss()
            } label: {
                Text("Configuration détaillée à la place")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 32)
    }

    private func shortDescription(for goal: OnboardingGoal) -> String {
        switch goal {
        case .health:      return "Sommeil, sport, nutrition — récup et forme"
        case .performance: return "PR, protéines, sleep 8h — pousser plus loin"
        case .money:       return "Budget, invest, apprentissage financier"
        case .mind:        return "Méditation, journaling, hygiène numérique"
        case .habits:      return "Routines simples, cohérence quotidienne"
        }
    }
}
