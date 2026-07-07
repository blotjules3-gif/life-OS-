import SwiftUI
import SwiftData

struct SleepCheckSheet: View {
    let onContinue: () -> Void

    @Environment(\.modelContext) private var ctx
    @AppStorage("todayEnergyScore") private var todayEnergyScore = 0
    @AppStorage("todayEnergyLabel") private var todayEnergyLabel = ""

    @State private var step = 1
    @State private var quality = 0
    @State private var hours = 7
    @State private var note = ""
    @State private var mood = 0
    @State private var fatigue = 0
    @State private var appeared = false
    @State private var submitting = false
    @State private var displayScore = 0

    private let qualities: [(label: String, icon: String, color: Color)] = [
        ("Terrible", "cloud.rain.fill", Color(hex: 0xF1746C)),
        ("Mauvais",  "cloud.fill",      Color(hex: 0xE0A23C)),
        ("Correct",  "cloud.sun.fill",  Color(hex: 0x4CC38A).opacity(0.7)),
        ("Bien",     "sun.max.fill",    Color(hex: 0x4CC38A)),
        ("Excellent","sparkles",        Color(hex: 0x3CB2E0)),
    ]
    private let moodEmoji = ["😞", "😕", "😐", "🙂", "😄"]
    private let eIcons    = ["bolt.slash","minus.circle","equal.circle","bolt","bolt.fill"]
    private let eLabels   = ["Épuisé","Faible","Correct","Bien","Plein"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if step == 1 {
                    sleepStep
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                if step == 2 {
                    feelStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                if step == 3 {
                    revealStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(duration: 0.38, bounce: 0.08), value: step)
            .onAppear { withAnimation(.spring(duration: 0.45, bounce: 0.1)) { appeared = true } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onContinue() }.foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Étape 1 : Sommeil

    private var sleepStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                stepHeader(icon: "moon.stars.fill", color: Color(hex: 0x6C7BF1),
                           title: "Comment tu as dormi ?",
                           subtitle: "Cette info personnalise ton briefing")
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(duration: 0.5, bounce: 0.3), value: appeared)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { i in
                        let q = qualities[i - 1]; let sel = quality == i
                        Button {
                            withAnimation(.spring(duration: 0.25, bounce: 0.35)) { quality = i }
                            Haptics.tap()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: q.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(sel ? q.color : Color.secondary.opacity(0.4))
                                    .scaleEffect(sel ? 1.15 : 1)
                                Text(q.label)
                                    .font(.system(size: 10, weight: sel ? .semibold : .regular))
                                    .foregroundStyle(sel ? q.color : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .fill(sel ? q.color.opacity(0.1) : Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .stroke(sel ? q.color.opacity(0.5) : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
                .animation(.spring(duration: 0.5).delay(0.16), value: appeared)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Heures de sommeil", systemImage: "clock.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        Button { if hours > 1 { hours -= 1; Haptics.tap() } } label: {
                            Image(systemName: "minus").font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48).contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .buttonStyle(LifeOSPressStyle())
                        Text("\(hours)h")
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.38, bounce: 0.1), value: hours)
                        Button { if hours < 14 { hours += 1; Haptics.tap() } } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48).contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .buttonStyle(LifeOSPressStyle())
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).animation(.spring(duration: 0.5).delay(0.22), value: appeared)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Note rapide (optionnel)", systemImage: "text.alignleft")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("Cauchemar, réveil nocturne, rêve…", text: $note, axis: .vertical)
                        .font(.system(size: 14)).lineLimit(3)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).animation(.spring(duration: 0.5).delay(0.28), value: appeared)

                VStack(spacing: 10) {
                    Button {
                        saveSleep()
                        withAnimation(.spring(duration: 0.35)) { step = 2 }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Continuer").font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right").font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(quality > 0 ? Color.accentColor : Color.secondary.opacity(0.2),
                                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .foregroundStyle(quality > 0 ? .white : .secondary)
                    }
                    .buttonStyle(LifeOSPressStyle()).disabled(quality == 0)

                    Button { onContinue() } label: {
                        Text("Passer").font(.system(size: 14)).foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }.buttonStyle(LifeOSPressStyle())
                }
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0).animation(.spring(duration: 0.5).delay(0.34), value: appeared)

                Spacer(minLength: 20)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Étape 2 : Humeur + Énergie

    private var feelStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    stepHeader(icon: "face.smiling.fill", color: Color(hex: 0xFF9F0A),
                               title: "Comment tu te sens ?",
                               subtitle: "2 questions rapides")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Humeur du matin")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        HStack(spacing: 0) {
                            ForEach(1...5, id: \.self) { s in
                                Button {
                                    withAnimation(.spring(duration: 0.2, bounce: 0.4)) { mood = s }
                                    Haptics.soft()
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(moodEmoji[s - 1]).font(.system(size: 32))
                                            .scaleEffect(mood == s ? 1.25 : 0.9)
                                            .opacity(mood == 0 || mood == s ? 1 : 0.35)
                                        Circle().fill(mood == s ? Color.accentColor : Color.clear)
                                            .frame(width: 5, height: 5)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Niveau d'énergie")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { s in
                                let sel = (6 - s) == fatigue
                                Button {
                                    withAnimation(.spring(duration: 0.2, bounce: 0.3)) { fatigue = 6 - s }
                                    Haptics.soft()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: eIcons[s - 1])
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundStyle(sel ? Color(hex: 0x4CC38A) : Color.secondary.opacity(0.4))
                                            .scaleEffect(sel ? 1.15 : 1)
                                        Text(eLabels[s - 1])
                                            .font(.system(size: 10, weight: sel ? .semibold : .regular))
                                            .foregroundStyle(sel ? Color(hex: 0x4CC38A) : .secondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                        .fill(sel ? Color(hex: 0x4CC38A).opacity(0.1) : Theme.card))
                                }.buttonStyle(LifeOSPressStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 24)
            }

            VStack(spacing: 10) {
                Button { submitAndReveal() } label: {
                    Group {
                        if submitting {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill").font(.system(size: 14))
                                Text("Voir mon score").font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(mood > 0 && fatigue > 0 ? Color.accentColor : Color.secondary.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .foregroundStyle(mood > 0 && fatigue > 0 ? .white : .secondary)
                }
                .buttonStyle(LifeOSPressStyle())
                .disabled(mood == 0 || fatigue == 0 || submitting)

                Button { onContinue() } label: {
                    Text("Passer").font(.system(size: 14)).foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }.buttonStyle(LifeOSPressStyle())
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
            .background(Theme.bg)
        }
    }

    // MARK: - Étape 3 : Révélation du score

    private var revealStep: some View {
        let sc = scoreColor
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 36) {
                ZStack {
                    Circle().stroke(sc.opacity(0.12), lineWidth: 12).frame(width: 180, height: 180)
                    Circle()
                        .trim(from: 0, to: CGFloat(displayScore) / 100)
                        .stroke(sc, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 1.2, bounce: 0.0), value: displayScore)
                    VStack(spacing: 2) {
                        Text("\(displayScore)")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(sc)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 1.2, bounce: 0.0), value: displayScore)
                        Text("/ 100").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 8) {
                    Text(todayEnergyLabel.isEmpty ? "—" : todayEnergyLabel)
                        .font(.system(size: 26, weight: .bold))
                    Text(scoreMessage)
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button { onContinue() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill").font(.system(size: 14))
                    Text("Lancer mon briefing").font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(sc, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(LifeOSPressStyle())
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .onAppear { animateScore() }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(color)
            }
            Text(title).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var scoreColor: Color {
        switch todayEnergyScore {
        case 85...100: return Color(hex: 0x4CC38A)
        case 70..<85:  return Color(hex: 0x5DCFA8)
        case 50..<70:  return Color(hex: 0xFF9F0A)
        case 30..<50:  return Color(hex: 0xE07B3C)
        default:       return Color(hex: 0xF1746C)
        }
    }

    private var scoreMessage: String {
        switch todayEnergyScore {
        case 85...100: return "Excellente forme. Tu es prêt(e) à tout."
        case 70..<85:  return "Belle énergie. Bonne journée en vue."
        case 50..<70:  return "Énergie correcte. Rythme doux pour commencer."
        case 30..<50:  return "Besoin de récupérer. Sois indulgent(e) avec toi."
        default:       return "Journée difficile. L'essentiel, pas le surplus."
        }
    }

    private func saveSleep() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSleepCheckDate")
        UserDefaults.standard.set(quality, forKey: "lastSleepQuality")
        UserDefaults.standard.set(hours, forKey: "lastSleepHours")
        let dream = DreamEntry(
            title: "Nuit du \(Date.now.formatted(.dateTime.day().month()))",
            text: note,
            mood: quality
        )
        ctx.insert(dream)
        do { try ctx.save() } catch { print("[SwiftData] saveDream failed: \(error)") }
    }

    private func submitAndReveal() {
        submitting = true
        Task {
            if let result = try? await AgentAPI.shared.logCheckin(
                sleepQuality: quality > 0 ? quality : nil,
                sleepHours: Double(hours),
                mood: mood > 0 ? mood : nil,
                fatigue: fatigue > 0 ? fatigue : nil
            ) {
                await MainActor.run {
                    todayEnergyScore = result.energy_score ?? 0
                    todayEnergyLabel = result.label ?? ""
                }
            }
            await MainActor.run {
                submitting = false
                if mood > 0 { ctx.insert(MoodEntry(score: mood, note: "")) }
                withAnimation(.spring(duration: 0.35)) { step = 3 }
            }
        }
    }

    private func animateScore() {
        let target = todayEnergyScore
        guard target > 0 else { return }
        withAnimation(.spring(duration: 1.2, bounce: 0.0)) { displayScore = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { Haptics.tap() }
    }
}
