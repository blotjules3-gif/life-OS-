import SwiftUI
import SwiftData
import AVFoundation
import Combine
import AudioToolbox
import Speech
import Charts
import EventKit
import UserNotifications

// MARK: - Hub Sommeil

extension ShapeStyle where Self == Color { static var sleepTint: Color { AppCategory.sleep.tint } }

// Sleep Circle (BedtimeCalculatorView) et la saisie des nuits vivent dans
// SleepDashboard.swift, avec leur logique pure.

// MARK: - Power nap: logique

/// Duree libre et fondu du paysage sonore.
enum NapPlan {
    static let range = 5...180
    static let presets = [10, 20, 26, 45, 90]

    static func clamp(_ m: Int) -> Int { min(range.upperBound, max(range.lowerBound, m)) }

    static func advice(_ m: Int) -> String {
        switch m {
        case ..<30: return "\(m) min : recharge sans inertie de sommeil. Idéal en après-midi."
        case 85...95: return "\(m) min : un cycle complet, réveil naturel. Évite le coup de barre."
        default: return "\(m) min : entre 30 et 85 min, le réveil peut tomber en plein sommeil profond. Si tu te réveilles groggy, vise moins de 30 min ou 90 min."
        }
    }

    /// Volume plein, puis baisse lineaire pendant les `fadeSeconds` dernieres secondes.
    static func fadeVolume(remaining: Int, fadeSeconds: Int = 60, base: Float) -> Float {
        guard fadeSeconds > 0, remaining < fadeSeconds else { return base }
        return base * Float(max(0, remaining)) / Float(fadeSeconds)
    }
}

/// Sons systeme fournis par iOS (aucun fichier audio a nous). Ils suivent le
/// volume de la sonnerie; ecran verrouille, c'est la notification qui sonne.
enum NapWakeSound: String, CaseIterable, Identifiable {
    case none, soft1, soft2, soft3
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Notification seule"
        case .soft1: return "Son doux 1"
        case .soft2: return "Son doux 2"
        case .soft3: return "Son doux 3"
        }
    }
    var systemID: SystemSoundID? {
        switch self {
        case .none: return nil
        case .soft1: return 1008
        case .soft2: return 1021
        case .soft3: return 1034
        }
    }
    /// Trois fois, espaces: un reveil qui insiste sans claquer.
    static let repeats = 3
    static let gap: TimeInterval = 4
}

/// Historique des siestes, sans doublon de fin.
enum NapLog {
    /// Ferme la sieste ouverte la plus recente, une seule: la fin du compte a
    /// rebours puis un retour a l'ecran ne peuvent pas la clore deux fois.
    @discardableResult
    static func close(_ sessions: [NapSession], at date: Date, completed: Bool) -> NapSession? {
        guard let open = sessions.filter({ $0.end == nil }).max(by: { $0.start < $1.start }) else { return nil }
        open.end = max(open.start, date)
        open.completed = completed
        return open
    }

    /// Siestes restees ouvertes alors qu'aucun compte a rebours ne tourne (app
    /// tuee, ou fin pendant que l'ecran etait ferme): closes a l'heure prevue
    /// si elle est passee. Si un compte a rebours tourne, la plus recente reste.
    @discardableResult
    static func recover(_ sessions: [NapSession], now: Date, timerActive: Bool) -> [NapSession] {
        var open = sessions.filter { $0.end == nil }.sorted { $0.start > $1.start }
        if timerActive, !open.isEmpty { open.removeFirst() }
        for s in open {
            let ended = s.plannedEnd <= now
            s.end = ended ? s.plannedEnd : max(s.start, now)
            s.completed = ended
        }
        return open
    }

    static func summary(_ sessions: [NapSession]) -> (count: Int, completed: Int, averageMinutes: Double?) {
        let done = sessions.compactMap(\.actualMinutes)
        return (done.count, sessions.filter { $0.end != nil && $0.completed }.count,
                done.isEmpty ? nil : done.reduce(0, +) / Double(done.count))
    }
}

// MARK: - Power nap: ecran

struct PowerNapView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \NapSession.start, order: .reverse) private var naps: [NapSession]
    @State private var engine = CountdownEngine(key: "nap")
    @AppStorage(SleepKeys.napMinutes) private var minutes = 20
    @AppStorage(SleepKeys.napWakeSound) private var wakeSoundRaw = NapWakeSound.soft1.rawValue
    @AppStorage(SleepKeys.napSoundscape) private var soundscapeRaw = ""
    @StateObject private var noise = NoiseEngine()
    @State private var started = false
    @State private var baseVolume: Float = 0.6
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var wakeSound: NapWakeSound { NapWakeSound(rawValue: wakeSoundRaw) ?? .soft1 }
    private var soundscape: NoiseKind? { NoiseKind(rawValue: soundscapeRaw) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 24) {
                    if !started { setupCard }
                    TimerDial(engine: engine, tint: .sleepTint,
                              caption: started ? "Sieste en cours" : "\(minutes) min")
                    controls
                    if noise.failed { Text("Le paysage sonore n'a pas pu démarrer.").font(.caption).foregroundStyle(Theme.warning) }
                    if noise.interrupted { Text("Son coupé par un appel ou une autre app.").font(.caption).foregroundStyle(Theme.warning) }
                    historyCard
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .navigationTitle("Power nap").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // L'ecran doit REPRENDRE la session persistee. Sans ca, revenir sur l'ecran
            // pendant une sieste en cours affichait "Demarrer la sieste" alors que le
            // compte a rebours tournait toujours, et le bouton en relancait une seconde.
            started = engine.isRunning || engine.remaining > 0
            // Fin de sieste ecran ouvert: revenir a l'etat de depart au lieu de
            // laisser un bouton "Reprendre" sur une sieste terminee.
            engine.onFinish = { finishNap() }
            engine.refresh()
            // Sieste finie app fermee: la fiche restait ouverte pour toujours.
            NapLog.recover(naps, now: .now, timerActive: engine.isRunning || engine.remaining > 0)
        }
        .onReceive(tick) { _ in
            guard engine.isRunning, noise.isPlaying else { return }
            noise.volume = NapPlan.fadeVolume(remaining: engine.remaining, base: baseVolume)
        }
        .onDisappear { if !engine.isRunning { noise.stop() } }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("Durée : \(minutes) min", value: $minutes, in: NapPlan.range, step: 5)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NapPlan.presets, id: \.self) { m in
                        Button("\(m) min") { minutes = m }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background((minutes == m ? Color.sleepTint : Theme.bg2).opacity(minutes == m ? 0.25 : 1), in: Capsule())
                            .foregroundStyle(minutes == m ? Color.sleepTint : Theme.textPrimary)
                            .buttonStyle(.plain)
                    }
                }
            }
            Text(NapPlan.advice(minutes)).font(.footnote).foregroundStyle(Theme.textSecondary)
            Picker("Paysage sonore", selection: $soundscapeRaw) {
                Text("Silence").tag("")
                ForEach(NoiseKind.allCases) { k in Text(k.label).tag(k.rawValue) }
            }
            if soundscape != nil {
                Text("Le son baisse doucement pendant la dernière minute, puis s'arrête.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Picker("Réveil", selection: $wakeSoundRaw) {
                    ForEach(NapWakeSound.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
                if let id = wakeSound.systemID {
                    Button { AudioServicesPlaySystemSound(id) } label: { Image(systemName: "speaker.wave.2") }
                        .accessibilityLabel("Écouter le son")
                }
            }
            Text("Son système d'iOS, répété 3 fois si l'écran est ouvert. Écran verrouillé, c'est la notification qui sonne.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if !started {
                PrimaryButton(title: "Démarrer la sieste", icon: "play.fill", tint: .sleepTint) { startNap() }
            } else {
                PrimaryButton(title: engine.isRunning ? "Pause" : "Reprendre",
                              icon: engine.isRunning ? "pause.fill" : "play.fill", tint: .sleepTint) {
                    if engine.isRunning {
                        engine.pause()
                        noise.stop()
                        // En pause, l'heure de fin n'a plus de sens.
                        NotificationManager.shared.cancel(id: "nap")
                    } else {
                        engine.resume()
                        // resume() ne fait rien si la sieste est deja finie:
                        // reprogrammer quand meme posait un faux "Réveil" 1 s plus tard.
                        if engine.isRunning {
                            scheduleWake(seconds: TimeInterval(max(1, engine.remaining)))
                            playSoundscape()
                        } else {
                            started = false
                        }
                    }
                }
                PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) {
                    engine.stop(); started = false
                    noise.stop()
                    NotificationManager.shared.cancel(id: "nap")
                    NapLog.close(naps, at: .now, completed: false)
                }
            }
        }
    }

    private var historyCard: some View {
        let done = naps.filter { $0.end != nil }
        let sum = NapLog.summary(done)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Historique des siestes",
                          subtitle: done.isEmpty ? nil : "\(sum.count) sieste\(sum.count > 1 ? "s" : "") · \(sum.completed) allée\(sum.completed > 1 ? "s" : "") au bout"
                          + (sum.averageMinutes.map { " · \(Int($0.rounded())) min en moyenne" } ?? ""))
            if done.isEmpty {
                Text("Tes siestes apparaîtront ici.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(done.prefix(20)) { n in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(Int((n.actualMinutes ?? 0).rounded())) min sur \(n.plannedMinutes) prévues\(n.soundscape.isEmpty ? "" : " · \(NoiseKind(rawValue: n.soundscape)?.label ?? n.soundscape)")")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: n.completed ? "checkmark.circle.fill" : "stop.circle")
                        .foregroundStyle(n.completed ? Theme.success : Theme.textSecondary)
                        .accessibilityLabel(n.completed ? "Allée au bout" : "Arrêtée avant")
                    Menu {
                        Button(role: .destructive) { ctx.delete(n) } label: { Label("Supprimer", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary) }
                }
            }
        }
        .card()
    }

    private func startNap() {
        minutes = NapPlan.clamp(minutes)
        // Une fiche ouverte d'avant (app tuee) ne doit pas recevoir la fin de celle-ci.
        NapLog.recover(naps, now: .now, timerActive: false)
        ctx.insert(NapSession(plannedMinutes: minutes, soundscape: soundscapeRaw))
        engine.start(seconds: minutes * 60)
        // Le reveil est programme MAINTENANT, pour l'heure de fin: une app
        // suspendue ne peut pas organiser son propre reveil a l'instant voulu.
        scheduleWake(seconds: TimeInterval(minutes * 60))
        playSoundscape()
        started = true
    }

    private func scheduleWake(seconds: TimeInterval) {
        NotificationManager.shared.scheduleAfter(
            id: "nap", title: "Réveil",
            body: "Ta sieste est terminée, debout en douceur !",
            seconds: seconds)
    }

    private func playSoundscape() {
        guard let k = soundscape else { return }
        noise.volume = NapPlan.fadeVolume(remaining: engine.remaining, base: baseVolume)
        noise.play(k)
    }

    private func finishNap() {
        started = false
        noise.stop()
        NapLog.close(naps, at: .now, completed: true)
        // La notification a deja ete posee; ecran ouvert on ajoute le son doux.
        if let id = wakeSound.systemID, UIApplication.shared.applicationState == .active {
            for i in 0..<NapWakeSound.repeats {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * NapWakeSound.gap) {
                    AudioServicesPlaySystemSound(id)
                }
            }
        }
    }
}

// MARK: - Coucher progressif: logique

/// Checklist du soir: le soir continue apres minuit (jusqu'a 6 h).
enum EveningRoutine {
    /// Elements de depart: les conseils deja affiches par l'ecran avant, rendus
    /// cochables. L'utilisateur peut les modifier ou les supprimer.
    static let defaultItems: [(title: String, detail: String)] = [
        ("Active Night Shift / mode nuit", "Réglages › Affichage › Night Shift : réduit la lumière bleue."),
        ("Pose les écrans 45 min avant", "La lumière bleue retarde la mélatonine."),
        ("Baisse les lumières", "Lumière chaude < 100 lux le soir."),
        ("Chambre à 18-19°C", "Le froid facilite l'endormissement."),
    ]
    static let dayStartHour = 6

    static func eveningDay(for date: Date, cal: Calendar = .current) -> Date {
        cal.startOfDay(for: date.addingTimeInterval(-TimeInterval(dayStartHour * 3600)))
    }

    static func toggled(_ done: [String], _ title: String) -> [String] {
        done.contains(title) ? done.filter { $0 != title } : done + [title]
    }

    /// Seuls les elements encore dans la liste comptent.
    static func progress(done: [String], items: [String]) -> (done: Int, total: Int) {
        (Set(done).intersection(Set(items)).count, items.count)
    }

    /// Titre propre et pas deja present (sans tenir compte des majuscules).
    static func cleanTitle(_ raw: String, existing: [String]) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !existing.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return nil }
        return t
    }
}

extension SleepDebt {
    /// Les `days` derniers matins (aujourd'hui compris). nil = nuit non notee.
    static func window(_ nights: [(date: Date, hours: Double)], days: Int,
                       now: Date = .now, cal: Calendar = .current) -> [Double?] {
        let today = cal.startOfDay(for: now)
        return (0..<max(0, days)).reversed().map { off in
            guard let d = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            return nights.filter { cal.isDate($0.date, inSameDayAs: d) }.map(\.hours).max()
        }
    }
}

/// Coucher conseille, regle annoncee a l'ecran:
/// coucher = reveil vise - besoin de sommeil - delai d'endormissement,
/// decompression 45 min avant. Pas une prediction d'energie.
enum BedtimePlan {
    struct Plan: Equatable {
        let bedMinutes: Int
        let windDownMinutes: Int
        let sleepMinutes: Int
        let latency: Int
    }
    static let windDownLead = 45

    static func wrap(_ m: Int) -> Int { ((m % 1440) + 1440) % 1440 }

    static func suggest(wakeMinutes: Int, needHours: Double, latencyMinutes: Int) -> Plan {
        let need = Int((max(0, needHours) * 60).rounded())
        let lat = SleepCycles.clampLatency(latencyMinutes)
        let bed = wrap(wakeMinutes - need - lat)
        return Plan(bedMinutes: bed, windDownMinutes: wrap(bed - windDownLead), sleepMinutes: need, latency: lat)
    }

    static func label(_ m: Int) -> String { String(format: "%02d:%02d", wrap(m) / 60, wrap(m) % 60) }

    /// Premier rendez-vous demain qui commence avant le reveil vise.
    static func earliestConflict(eventStarts: [Date], wake: Date) -> Date? {
        eventStarts.filter { $0 < wake }.min()
    }

    /// Lire l'agenda demande la cle d'acces complet dans Info.plist. Sans
    /// elle, iOS ferme l'app a la demande: on ne propose rien.
    static var calendarReadAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }
}

// MARK: - Coucher progressif: ecran

struct WindDownView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \EveningChecklistItem.order) private var items: [EveningChecklistItem]
    @Query(sort: \EveningChecklistDay.day, order: .reverse) private var days: [EveningChecklistDay]
    @Query(sort: \SleepNight.date, order: .reverse) private var nights: [SleepNight]
    @AppStorage(AppStorageKeys.windDownHour) private var hour = 22
    @AppStorage(AppStorageKeys.windDownMinute) private var minute = 30
    @AppStorage(AppStorageKeys.windDownEnabled) private var enabled = false
    @AppStorage(AppStorageKeys.wakeupHour) private var wakeupHour = 7
    @AppStorage(AppStorageKeys.wakeupMinute) private var wakeupMinute = 0
    @AppStorage(AppStorageKeys.sleepGoalHours) private var sleepGoal = 8.0
    @AppStorage(SleepKeys.fallAsleepMinutes) private var latency = 15
    @AppStorage(SleepKeys.rizeWakeMinutes) private var rizeWake = -1
    @AppStorage(SleepKeys.rizeSeeded) private var seeded = false
    @State private var time = Date()
    @State private var targetWake = Date()
    @State private var newItem = ""
    @State private var notifDenied = false
    @State private var calendarNote: String?
    @State private var checkingCalendar = false

    private let cal = Calendar.current
    private var wakeMinutes: Int { rizeWake >= 0 ? rizeWake : wakeupHour * 60 + wakeupMinute }
    private var plan: BedtimePlan.Plan { BedtimePlan.suggest(wakeMinutes: wakeMinutes, needHours: sleepGoal, latencyMinutes: latency) }
    private var today: Date { EveningRoutine.eveningDay(for: .now) }
    private var todayRecord: EveningChecklistDay? { days.first { cal.isDate($0.day, inSameDayAs: today) } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    planCard
                    reminderCard
                    debtCard
                    checklistCard
                    if days.contains(where: { !cal.isDate($0.day, inSameDayAs: today) }) { historyCard }
                    if BedtimePlan.calendarReadAvailable { calendarCard }
                    IntegrationNotice(text: "Pour couper les notifications la nuit, règle le Focus Sommeil dans Réglages › Concentration › Sommeil. LifeOS ne peut pas l'activer à ta place.")
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Coucher progressif").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            time = cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            targetWake = cal.date(bySettingHour: wakeMinutes / 60, minute: wakeMinutes % 60, second: 0, of: .now) ?? .now
            seedIfNeeded()
        }
    }

    // MARK: Coucher conseille

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ton coucher conseillé")
            DatePicker("Réveil visé", selection: $targetWake, displayedComponents: .hourAndMinute)
                .onChange(of: targetWake) { _, v in rizeWake = SleepLogRules.minutes(v) }
            Stepper("Besoin de sommeil : \(fmtH(sleepGoal))", value: $sleepGoal, in: 5...11, step: 0.25)
            Stepper("Je m'endors en \(latency) min", value: $latency, in: SleepCycles.latencyRange, step: 5)
            HStack(spacing: 12) {
                metric(BedtimePlan.label(plan.bedMinutes), "Au lit", "bed.double.fill")
                metric(BedtimePlan.label(plan.windDownMinutes), "Décompression", "moon.haze.fill")
            }
            Text("Règle LifeOS : réveil visé moins besoin de sommeil moins délai d'endormissement, décompression 45 min avant. Un calcul simple, pas une prédiction de ton énergie.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if !enabled || hour * 60 + minute != plan.windDownMinutes {
                PrimaryButton(title: "Caler mon rappel sur \(BedtimePlan.label(plan.windDownMinutes))", icon: "bell", tint: .sleepTint) {
                    time = cal.date(bySettingHour: plan.windDownMinutes / 60, minute: plan.windDownMinutes % 60, second: 0, of: .now) ?? time
                    enable()
                }
            }
        }
        .card()
    }

    private func metric(_ v: String, _ l: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.sleepTint)
            Text(v).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: Rappel

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Rappel de coucher progressif", isOn: Binding(get: { enabled }, set: { on in
                if on { enable() } else { enabled = false; NotificationManager.shared.cancel(id: "winddown") }
            }))
            .tint(.sleepTint)
            DatePicker("Heure du rappel", selection: $time, displayedComponents: .hourAndMinute)
                .onChange(of: time) { _, _ in if enabled { schedule() } }
            if notifDenied {
                Text("Notifications refusées : le rappel ne peut pas sonner.").font(.caption).foregroundStyle(Theme.warning)
                Button("Ouvrir les réglages") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }.font(.caption.bold())
            }
        }
        .card()
    }

    private func enable() {
        Task {
            if await NotificationManager.shared.requestAuthorization() {
                notifDenied = false
                enabled = true
                schedule()
            } else {
                enabled = false
                notifDenied = true
            }
        }
    }

    private func schedule() {
        let c = cal.dateComponents([.hour, .minute], from: time)
        hour = c.hour ?? 22; minute = c.minute ?? 30
        NotificationManager.shared.scheduleDaily(id: "winddown", title: "Heure de décompresser",
            body: "Baisse les lumières, mode nuit ON, écrans en pause. Au lit dans 45 min.", hour: hour, minute: minute)
    }

    // MARK: Dette 14 nuits

    private var debtCard: some View {
        let window = SleepDebt.window(nights.map { ($0.date, $0.hours) }, days: 14)
        let (debt, counted) = SleepDebt.compute(hours: window, goal: sleepGoal)
        let maxV = max(sleepGoal, window.compactMap { $0 }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Dette de sommeil · 14 nuits",
                          subtitle: "\(counted) nuit\(counted > 1 ? "s" : "") notée\(counted > 1 ? "s" : "") sur 14. Les nuits non notées ne comptent pas.")
            if counted == 0 {
                Text("Note tes nuits dans Sleep Circle ou le tableau Sommeil pour voir ta dette.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                Text(debt < 0.1 ? "À jour" : "-\(fmtH(debt))")
                    .font(.title2.bold()).foregroundStyle(debt > 3 ? Theme.danger : Theme.textPrimary)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(window.enumerated()), id: \.offset) { _, h in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(h == nil ? AnyShapeStyle(Color.primary.opacity(0.08))
                                  : AnyShapeStyle((h ?? 0) >= sleepGoal * 0.9 ? Color.sleepTint : Theme.warning))
                            .frame(height: max(4, 60 * CGFloat(h ?? 0) / CGFloat(maxV)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 64, alignment: .bottom)
                .accessibilityLabel("Barres des 14 dernières nuits")
                if debt >= 0.5 {
                    Text("Te coucher un peu plus tôt quelques soirs aide à la rembourser. LifeOS ne décale pas ton heure tout seul.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .card()
    }

    // MARK: Checklist

    private var checklistCard: some View {
        let titles = items.map(\.title)
        let done = todayRecord?.doneTitles ?? []
        let p = EveningRoutine.progress(done: done, items: titles)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Checklist du soir", subtitle: items.isEmpty ? nil : "\(p.done) / \(p.total) ce soir")
            ForEach(items) { item in
                let checked = done.contains(item.title)
                Button { toggle(item.title) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(checked ? Theme.success : Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                .strikethrough(checked)
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(checked ? "fait" : "à faire")
                .contextMenu {
                    Button(role: .destructive) { ctx.delete(item) } label: { Label("Retirer de la checklist", systemImage: "trash") }
                }
            }
            HStack {
                TextField("Ajouter une étape (ex. tisane)", text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addItem)
                Button(action: addItem) { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(EveningRoutine.cleanTitle(newItem, existing: titles) == nil)
                    .accessibilityLabel("Ajouter l'étape")
            }
            if !items.isEmpty {
                Text("Appui long sur une étape pour la retirer.").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private func toggle(_ title: String) {
        Haptics.tap()
        if let r = todayRecord {
            r.doneTitles = EveningRoutine.toggled(r.doneTitles, title)
            r.totalItems = items.count
        } else {
            ctx.insert(EveningChecklistDay(day: today, doneTitles: [title], totalItems: items.count))
        }
    }

    private func addItem() {
        guard let t = EveningRoutine.cleanTitle(newItem, existing: items.map(\.title)) else { return }
        ctx.insert(EveningChecklistItem(title: t, order: (items.map(\.order).max() ?? -1) + 1))
        newItem = ""
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        guard items.isEmpty else { return }
        for (i, d) in EveningRoutine.defaultItems.enumerated() {
            ctx.insert(EveningChecklistItem(title: d.title, detail: d.detail, order: i))
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Soirs précédents")
            ForEach(days.filter { !cal.isDate($0.day, inSameDayAs: today) }.prefix(14)) { d in
                HStack {
                    Text(d.day.formatted(.dateTime.weekday(.wide).day().month())).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(d.doneTitles.count) / \(max(d.totalItems, d.doneTitles.count))").font(.subheadline.bold())
                        .foregroundStyle(d.doneTitles.count >= d.totalItems && d.totalItems > 0 ? Theme.success : Theme.textSecondary)
                }
            }
        }
        .card()
    }

    // MARK: Agenda (lecture seule)

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ton agenda de demain")
            Text("LifeOS lit seulement l'heure de ton premier rendez-vous de demain matin, sans rien modifier.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if let calendarNote { Text(calendarNote).font(.subheadline).foregroundStyle(Theme.textPrimary) }
            PrimaryButton(title: checkingCalendar ? "Lecture…" : "Vérifier demain matin", icon: "calendar", tint: .sleepTint) {
                Task { await checkCalendar() }
            }
            .disabled(checkingCalendar)
        }
        .card()
    }

    private func checkCalendar() async {
        checkingCalendar = true
        defer { checkingCalendar = false }
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            calendarNote = "Accès à l'agenda refusé. Tu peux l'autoriser dans Réglages › Confidentialité › Calendriers."
            return
        }
        let start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let end = start.addingTimeInterval(14 * 3600)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay }
        let wake = cal.date(byAdding: .minute, value: wakeMinutes, to: start) ?? start
        guard let first = events.map(\.startDate).min() else {
            calendarNote = "Aucun rendez-vous demain avant 14 h."
            return
        }
        if let c = BedtimePlan.earliestConflict(eventStarts: events.map(\.startDate), wake: wake) {
            calendarNote = "Premier rendez-vous à \(c.formatted(date: .omitted, time: .shortened)), avant ton réveil visé (\(BedtimePlan.label(wakeMinutes))). Avance ton réveil visé pour recalculer ton coucher."
        } else {
            calendarNote = "Premier rendez-vous à \(first.formatted(date: .omitted, time: .shortened)), après ton réveil visé : rien à changer."
        }
    }

    private func fmtH(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60)h\(m % 60 == 0 ? "" : String(format: "%02d", m % 60))"
    }
}

// MARK: - Journal de rêves: logique

/// Tags et recherche (sans accents ni majuscules).
enum DreamSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
    }

    /// "Lucide, vol ,#famille, lucide" -> ["Lucide", "vol", "famille"].
    static func parseTags(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for part in raw.split(whereSeparator: { $0 == "," || $0 == "#" || $0 == "\n" }) {
            let t = part.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if seen.insert(fold(t)).inserted { out.append(t) }
        }
        return out
    }

    /// Chaque mot doit se trouver dans le titre, le texte, la transcription
    /// ou un tag. "#mot" = tag exact.
    static func matches(title: String, text: String, tags: [String], transcript: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let hay = fold([title, text, transcript].joined(separator: " "))
        let ftags = tags.map(fold)
        return q.split(separator: " ").allSatisfy { raw in
            let w = String(raw)
            if w.hasPrefix("#") {
                let t = fold(String(w.dropFirst()))
                return t.isEmpty || ftags.contains(t)
            }
            let f = fold(w)
            return hay.contains(f) || ftags.contains { $0.contains(f) }
        }
    }

    static func tagCounts(_ lists: [[String]]) -> [(tag: String, count: Int)] {
        var counts: [String: (tag: String, count: Int)] = [:]
        for t in lists.flatMap({ $0 }) {
            let k = fold(t)
            counts[k] = (counts[k]?.tag ?? t, (counts[k]?.count ?? 0) + 1)
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }
}

/// Fichiers audio d'un reve modifie: que garder, que supprimer. Rien n'est
/// efface avant "Enregistrer": annuler laisse l'ancienne note intacte.
enum DreamAudioPlan {
    static func resolve(existing: String?, recorded: String?, removeExisting: Bool) -> (keep: String?, delete: [String]) {
        if let recorded { return (recorded, [existing].compactMap { $0 }.filter { $0 != recorded }) }
        if removeExisting { return (nil, [existing].compactMap { $0 }) }
        return (existing, [])
    }
}

enum DreamPlayback {
    static func clamp(_ t: TimeInterval, duration: TimeInterval) -> TimeInterval { min(max(0, t), max(0, duration)) }
    static func label(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

/// Rappels "reality check" a heures choisies, jamais la nuit.
enum RealityCheck {
    static let allowedHours = 8...22
    static let idPrefix = "reality-"

    static func parse(_ raw: String) -> [Int] {
        Array(Set(raw.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { allowedHours.contains($0) })).sorted()
    }
    static func serialize(_ hours: [Int]) -> String {
        parse(hours.map(String.init).joined(separator: ",")).map(String.init).joined(separator: ",")
    }
    static func id(_ h: Int) -> String { "\(idPrefix)\(h)" }

    static func requests(hours: [Int]) -> [UNNotificationRequest] {
        parse(hours.map(String.init).joined(separator: ",")).map { h in
            let c = UNMutableNotificationContent()
            c.title = "Reality check"
            c.body = "Es-tu en train de rêver ? Regarde tes mains, relis un texte."
            c.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: h, minute: 0), repeats: true)
            return UNNotificationRequest(identifier: id(h), content: c, trigger: trigger)
        }
    }
}

/// Transcription de la note vocale, sur l'appareil seulement (rien n'est envoye).
enum DreamTranscription {
    enum Failure: Error, Equatable { case denied, restricted, unavailable, noOnDevice, noAudio, empty }

    static func message(_ f: Failure) -> String {
        switch f {
        case .denied: return "Reconnaissance vocale refusée. Autorise LifeOS dans Réglages › Confidentialité › Reconnaissance vocale."
        case .restricted: return "La reconnaissance vocale est bloquée sur cet appareil."
        case .unavailable: return "La reconnaissance vocale n'est pas disponible pour le moment."
        case .noOnDevice: return "La transcription sur l'appareil n'est pas disponible pour ta langue. Rien n'est envoyé ailleurs, donc pas de transcription."
        case .noAudio: return "Aucune note vocale à transcrire."
        case .empty: return "Aucune parole reconnue dans la note."
        }
    }

    static func failure(for status: SFSpeechRecognizerAuthorizationStatus) -> Failure? {
        switch status {
        case .authorized: return nil
        case .restricted: return .restricted
        default: return .denied
        }
    }

    static func locale() -> Locale {
        let preferred = Locale(identifier: Locale.preferredLanguages.first ?? "fr-FR")
        return SFSpeechRecognizer.supportedLocales().contains(preferred) ? preferred : Locale(identifier: "fr-FR")
    }

    static func transcribe(fileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw Failure.noAudio }
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        if let f = failure(for: status) { throw f }
        guard let rec = SFSpeechRecognizer(locale: locale()), rec.isAvailable else { throw Failure.unavailable }
        guard rec.supportsOnDeviceRecognition else { throw Failure.noOnDevice }
        let req = SFSpeechURLRecognitionRequest(url: fileURL)
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = false
        let once = ResumeOnce()
        let text: String = try await withCheckedThrowingContinuation { cont in
            let task = rec.recognitionTask(with: req) { result, error in
                if let result, result.isFinal {
                    if once.claim() { cont.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    if once.claim() { cont.resume(throwing: error) }
                }
            }
            once.keep(task)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        return trimmed
    }

    /// Le rappel de Speech peut arriver plusieurs fois: on ne repond qu'une fois.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var task: SFSpeechRecognitionTask?
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
        func keep(_ t: SFSpeechRecognitionTask) { lock.lock(); task = t; lock.unlock() }
    }
}

/// Infos compagnon d'un reve.
enum DreamStore {
    static func details(for d: DreamEntry, in all: [DreamDetails]) -> DreamDetails? {
        all.first { $0.dream?.persistentModelID == d.persistentModelID }
    }
    static func fetchDetails(for d: DreamEntry, in ctx: ModelContext) -> DreamDetails? {
        details(for: d, in: (try? ctx.fetch(FetchDescriptor<DreamDetails>())) ?? [])
    }
    static func upsert(for d: DreamEntry, in ctx: ModelContext) -> DreamDetails {
        if let x = fetchDetails(for: d, in: ctx) { return x }
        let x = DreamDetails(dream: d)
        ctx.insert(x)
        return x
    }
    /// Reve, note vocale et infos compagnon partent ensemble.
    static func delete(_ d: DreamEntry, in ctx: ModelContext) {
        AudioRecorder.removeFile(named: d.audioFilename)
        if let x = fetchDetails(for: d, in: ctx) { ctx.delete(x) }
        ctx.delete(d)
    }
}

/// Lecteur unique des notes vocales: pause, reprise, position.
@MainActor
@Observable
final class DreamPlayer {
    static let shared = DreamPlayer()
    private(set) var file: String?
    private(set) var isPlaying = false
    private(set) var current: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorFile: String?
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func isCurrent(_ name: String?) -> Bool { name != nil && name == file }

    func toggle(_ name: String) {
        if file == name, let p = player {
            if p.isPlaying { pause() } else { resume() }
            return
        }
        stop()
        errorFile = nil
        let url = AudioRecorder.docsURL.appendingPathComponent(name)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            player = p; file = name; duration = p.duration; current = 0
            resume()
        } catch {
            errorFile = name
        }
    }

    func pause() { player?.pause(); isPlaying = false; ticker?.invalidate(); ticker = nil }

    func resume() {
        guard let p = player else { return }
        p.play(); isPlaying = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func seek(_ t: TimeInterval) {
        guard let p = player else { return }
        p.currentTime = DreamPlayback.clamp(t, duration: p.duration)
        current = p.currentTime
    }

    func stop() {
        player?.stop(); player = nil
        ticker?.invalidate(); ticker = nil
        isPlaying = false; file = nil; current = 0; duration = 0
    }

    /// Le fichier va etre efface: on ne le garde pas ouvert.
    func stopIfPlaying(_ name: String?) { if isCurrent(name) { stop() } }

    private func tick() {
        guard let p = player else { return }
        current = p.currentTime
        if !p.isPlaying, isPlaying {
            // Fin de lecture: retour au debut, pret a rejouer.
            isPlaying = false; current = 0
            ticker?.invalidate(); ticker = nil
        }
    }
}

// MARK: - Journal de rêves (texte + voix)

struct DreamJournalView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DreamEntry.date, order: .reverse) private var dreams: [DreamEntry]
    @Query private var details: [DreamDetails]
    @AppStorage(SleepKeys.realityHours) private var realityRaw = ""
    @State private var showAdd = false
    @State private var editing: DreamEntry?
    @State private var query = ""
    @State private var tagFilter: String?
    @State private var showReality = false

    private var filtered: [DreamEntry] {
        dreams.filter { d in
            let x = DreamStore.details(for: d, in: details)
            let tags = x?.tags ?? []
            if let tagFilter, !tags.contains(where: { DreamSearch.fold($0) == DreamSearch.fold(tagFilter) }) { return false }
            return DreamSearch.matches(title: d.title, text: d.text, tags: tags, transcript: x?.transcript ?? "", query: query)
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    realityCard
                    if dreams.isEmpty {
                        EmptyState(icon: "cloud.moon", title: "Aucun rêve noté",
                                   message: "Au réveil, capture ton rêve à la voix avant qu'il s'efface.",
                                   actionTitle: "Noter un rêve") { showAdd = true }
                    } else {
                        tagBar
                        if filtered.isEmpty {
                            Text("Aucun rêve ne correspond.").font(.subheadline).foregroundStyle(Theme.textSecondary).padding(.top, 20)
                        }
                        ForEach(filtered) { d in
                            DreamCard(dream: d, details: DreamStore.details(for: d, in: details)) { editing = d }
                        }
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Journal de rêves").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Chercher un rêve ou #tag")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter")
        } }
        .sheet(isPresented: $showAdd) { DreamEditor() }
        .sheet(item: $editing) { d in DreamEditor(dream: d) }
        .sheet(isPresented: $showReality) { RealityCheckSheet() }
        .onDisappear { DreamPlayer.shared.stop() }
    }

    private var realityCard: some View {
        let hours = RealityCheck.parse(realityRaw)
        return Button { showReality = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.sleepTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reality checks").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(hours.isEmpty ? "Aucun rappel" : hours.map { "\($0) h" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var tagBar: some View {
        let tags = DreamSearch.tagCounts(details.filter { $0.dream != nil }.map(\.tags))
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.tag) { t in
                        let on = tagFilter.map { DreamSearch.fold($0) == DreamSearch.fold(t.tag) } ?? false
                        Button { tagFilter = on ? nil : t.tag } label: {
                            Text("#\(t.tag) · \(t.count)").font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(on ? Color.sleepTint.opacity(0.25) : Theme.bg2, in: Capsule())
                                .foregroundStyle(on ? Color.sleepTint : Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }
}

struct DreamCard: View {
    @Environment(\.modelContext) private var ctx
    let dream: DreamEntry
    let details: DreamDetails?
    var onEdit: () -> Void = {}
    @State private var transcribing = false
    @State private var transcribeError: String?
    @State private var confirmDelete = false
    private var player: DreamPlayer { DreamPlayer.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dream.title.isEmpty ? "Rêve" : dream.title)
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(repeating: "•", count: max(0, min(5, dream.mood)))).foregroundStyle(.sleepTint)
                    .accessibilityLabel("Intensité \(dream.mood) sur 5")
            }
            Text(dream.date, style: .date).font(.caption).foregroundStyle(Theme.textSecondary)
            if !dream.text.isEmpty {
                Text(dream.text).font(.subheadline).foregroundStyle(Theme.textPrimary.opacity(0.9))
            }
            if let tags = details?.tags, !tags.isEmpty {
                Text(tags.map { "#\($0)" }.joined(separator: " ")).font(.caption.weight(.semibold)).foregroundStyle(.sleepTint)
            }
            if let t = details?.transcript, !t.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcription").font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
                    Text(t).font(.footnote).foregroundStyle(Theme.textPrimary.opacity(0.85)).lineLimit(6)
                }
            }
            if let name = dream.audioFilename { playerRow(name) }
            if let transcribeError { Text(transcribeError).font(.caption).foregroundStyle(Theme.warning) }
            HStack {
                if dream.audioFilename != nil, (details?.transcript ?? "").isEmpty {
                    Button { Task { await transcribe() } } label: {
                        Label(transcribing ? "Transcription…" : "Transcrire", systemImage: "text.bubble")
                    }
                    .disabled(transcribing)
                    .foregroundStyle(.sleepTint)
                }
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .accessibilityLabel("Modifier le rêve")
                    .foregroundStyle(Theme.textSecondary)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Supprimer le rêve")
                    .foregroundStyle(Theme.danger.opacity(0.8))
            }
        }
        .card()
        .confirmationDialog("Supprimer ce rêve et sa note vocale ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                player.stopIfPlaying(dream.audioFilename)
                DreamStore.delete(dream, in: ctx)
            }
        }
    }

    @ViewBuilder private func playerRow(_ name: String) -> some View {
        let active = player.isCurrent(name)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button { player.toggle(name) } label: {
                    Image(systemName: active && player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title2)
                }
                .foregroundStyle(.sleepTint)
                .accessibilityLabel(active && player.isPlaying ? "Pause" : "Écouter")
                if active {
                    Slider(value: Binding(get: { player.current }, set: { player.seek($0) }),
                           in: 0...max(player.duration, 0.1))
                        .tint(.sleepTint)
                        .accessibilityLabel("Position de lecture")
                    Text("\(DreamPlayback.label(player.current)) / \(DreamPlayback.label(player.duration))")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Note vocale").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            if player.errorFile == name {
                Text("Lecture impossible : le fichier audio est introuvable ou abîmé.").font(.caption).foregroundStyle(Theme.warning)
            }
        }
    }

    private func transcribe() async {
        guard let name = dream.audioFilename else { return }
        transcribing = true; transcribeError = nil
        defer { transcribing = false }
        do {
            let text = try await DreamTranscription.transcribe(fileURL: AudioRecorder.docsURL.appendingPathComponent(name))
            let x = DreamStore.upsert(for: dream, in: ctx)
            x.transcript = text
            x.transcribedAt = .now
        } catch let f as DreamTranscription.Failure {
            transcribeError = DreamTranscription.message(f)
        } catch {
            transcribeError = "Transcription impossible : \(error.localizedDescription)"
        }
    }
}

struct DreamEditor: View {
    var dream: DreamEntry? = nil

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var mood = 3
    @State private var tagsText = ""
    @State private var transcript = ""
    @State private var originalTranscript = ""
    @State private var existingAudio: String?
    @State private var removeExisting = false
    @State private var recorder = AudioRecorder()
    @State private var saved = false
    @State private var loaded = false
    @State private var transcribing = false
    @State private var transcribeError: String?

    /// Note vocale qui restera apres "Enregistrer".
    private var audioAfterSave: String? {
        DreamAudioPlan.resolve(existing: existingAudio, recorded: recorder.filename, removeExisting: removeExisting).keep
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rêve") {
                    TextField("Titre", text: $title)
                    TextField("Décris ton rêve…", text: $text, axis: .vertical).lineLimit(4...8)
                }
                Section {
                    TextField("lucide, vol, famille", text: $tagsText)
                        .textInputAutocapitalization(.never)
                } header: { Text("Tags") } footer: {
                    let tags = DreamSearch.parseTags(tagsText)
                    if !tags.isEmpty { Text(tags.map { "#\($0)" }.joined(separator: " ")) }
                }
                Section("Note vocale") {
                    if existingAudio != nil, recorder.filename == nil {
                        Toggle("Supprimer la note existante", isOn: $removeExisting)
                    }
                    Button {
                        if recorder.isRecording { recorder.stop() } else { Task { await recorder.start() } }
                    } label: {
                        Label(recorder.isRecording ? "Arrêter l'enregistrement"
                              : (existingAudio != nil ? "Remplacer par un nouvel enregistrement" : "Enregistrer ma voix"),
                              systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .foregroundStyle(recorder.isRecording ? Theme.danger : .sleepTint)
                    }
                    if let error = recorder.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                    } else if recorder.filename != nil && !recorder.isRecording {
                        Text(existingAudio != nil ? "Nouvelle note prête : elle remplacera l'ancienne à l'enregistrement."
                             : "Note vocale enregistrée").font(.caption).foregroundStyle(Theme.success)
                    }
                }
                if audioAfterSave != nil || !transcript.isEmpty {
                    Section {
                        if !transcript.isEmpty {
                            TextField("Transcription", text: $transcript, axis: .vertical).lineLimit(2...8)
                            Button("Ajouter au texte du rêve") {
                                text = text.isEmpty ? transcript : text + "\n" + transcript
                            }
                        }
                        if audioAfterSave != nil {
                            Button(transcribing ? "Transcription…" : "Transcrire la note vocale") { Task { await transcribe() } }
                                .disabled(transcribing || recorder.isRecording)
                        }
                        if let transcribeError { Text(transcribeError).font(.caption).foregroundStyle(Theme.warning) }
                    } header: { Text("Transcription") } footer: {
                        Text("Faite sur ton téléphone, rien n'est envoyé.")
                    }
                }
                Section("Ressenti") {
                    Stepper("Intensité : \(mood)/5", value: $mood, in: 1...5)
                }
            }
            .navigationTitle(dream == nil ? "Nouveau rêve" : "Modifier le rêve").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { recorder.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            // Fermeture par glissement: sans ca, la note vocale restait sur
            // le disque sans aucun reve pour la pointer.
            .onDisappear { if !saved { recorder.cancel() } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let d = dream else { return }
        title = d.title; text = d.text; mood = min(5, max(1, d.mood)); existingAudio = d.audioFilename
        if let x = DreamStore.fetchDetails(for: d, in: ctx) {
            tagsText = x.tags.joined(separator: ", ")
            transcript = x.transcript
            originalTranscript = x.transcript
        }
    }

    private func transcribe() async {
        guard let name = audioAfterSave else { return }
        transcribing = true; transcribeError = nil
        defer { transcribing = false }
        do {
            transcript = try await DreamTranscription.transcribe(fileURL: AudioRecorder.docsURL.appendingPathComponent(name))
        } catch let f as DreamTranscription.Failure {
            transcribeError = DreamTranscription.message(f)
        } catch {
            transcribeError = "Transcription impossible : \(error.localizedDescription)"
        }
    }

    private func save() {
        if recorder.isRecording { recorder.stop() }
        saved = true
        let plan = DreamAudioPlan.resolve(existing: existingAudio, recorded: recorder.filename, removeExisting: removeExisting)
        for f in plan.delete {
            DreamPlayer.shared.stopIfPlaying(f)
            AudioRecorder.removeFile(named: f)
        }
        let entry: DreamEntry
        if let d = dream {
            d.title = title; d.text = text; d.mood = mood; d.audioFilename = plan.keep
            entry = d
        } else {
            entry = DreamEntry(title: title, text: text, mood: mood, audioFilename: plan.keep)
            ctx.insert(entry)
        }
        // Note remplacee ou supprimee: l'ancienne transcription ne la decrit plus,
        // sauf si elle vient d'etre refaite ou corrigee ici.
        let audioChanged = plan.keep != existingAudio
        let finalTranscript = (audioChanged && transcript == originalTranscript) ? "" : transcript
        let tags = DreamSearch.parseTags(tagsText)
        if !tags.isEmpty || !finalTranscript.isEmpty || DreamStore.fetchDetails(for: entry, in: ctx) != nil {
            let x = DreamStore.upsert(for: entry, in: ctx)
            x.tags = tags
            if x.transcript != finalTranscript { x.transcript = finalTranscript; x.transcribedAt = finalTranscript.isEmpty ? nil : .now }
        }
        dismiss()
    }
}

struct RealityCheckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SleepKeys.realityHours) private var raw = ""
    @State private var selected: Set<Int> = []
    @State private var denied = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choisis les heures où LifeOS te demande si tu rêves. À force de te poser la question le jour, tu finis par te la poser en rêve.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        ForEach(Array(RealityCheck.allowedHours), id: \.self) { h in
                            let on = selected.contains(h)
                            Button { if on { selected.remove(h) } else { selected.insert(h) } } label: {
                                Text("\(h) h").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(on ? Color.sleepTint.opacity(0.25) : Theme.bg2, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(on ? Color.sleepTint : Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    Text("Entre 8 h et 22 h seulement : jamais pendant ta nuit.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if denied {
                        Text("Notifications refusées : les rappels ne peuvent pas sonner.").font(.caption).foregroundStyle(Theme.warning)
                        Button("Ouvrir les réglages") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }.font(.caption.bold())
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(Theme.pad)
            }
            .background(Theme.background)
            .navigationTitle("Reality checks").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { Task { await save() } }.disabled(saving) }
            }
            .onAppear { selected = Set(RealityCheck.parse(raw)) }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let hours = Array(selected)
        if !hours.isEmpty {
            guard await NotificationManager.shared.requestAuthorization() else { denied = true; return }
        }
        await NotificationManager.shared.replacePending(prefix: RealityCheck.idPrefix, with: RealityCheck.requests(hours: hours))
        raw = RealityCheck.serialize(hours)
        dismiss()
    }
}

/// Enregistreur audio minimal pour le journal de rêves.
@MainActor
@Observable
final class AudioRecorder {
    static var docsURL: URL { AppPaths.documents }
    private var recorder: AVAudioRecorder?
    var isRecording = false
    var filename: String?
    /// Message montre a la place d'un faux "Note vocale enregistrée".
    var errorMessage: String?

    /// Avant: permission jamais demandee, erreurs avalees par try?, et l'ecran
    /// disait "enregistrée" pour un fichier qui n'existait pas.
    func start() async {
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Micro refusé. Autorise LifeOS dans Réglages › Confidentialité › Micro."
            return
        }
        // Un second enregistrement remplace le premier: l'ancien fichier
        // restait orphelin sur le disque.
        discardCurrent()
        let name = "dream-\(Int(Date().timeIntervalSince1970)).m4a"
        let url = Self.docsURL.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record() else {
                errorMessage = "L'enregistrement n'a pas pu démarrer."
                Self.removeFile(named: name)
                return
            }
            recorder = r
            isRecording = true
            filename = name
        } catch {
            errorMessage = "L'enregistrement n'a pas pu démarrer : \(error.localizedDescription)"
            Self.removeFile(named: name)
        }
    }
    func stop() { recorder?.stop(); isRecording = false }
    func cancel() { discardCurrent() }

    private func discardCurrent() {
        recorder?.stop()
        recorder = nil
        Self.removeFile(named: filename)
        isRecording = false
        filename = nil
    }

    /// Efface une note vocale du disque. Sans nom ou fichier absent: rien.
    nonisolated static func removeFile(named name: String?, in dir: URL = AppPaths.documents) {
        guard let name, !name.isEmpty else { return }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Score de récupération

/// Score de recuperation, pur et testable.
enum RecoveryScore {
    /// Au-dela, la mesure n'est plus celle de ce matin: pas de score "du jour".
    static let maxAge: TimeInterval = 36 * 3600

    static func isFresh(_ date: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(date) <= maxAge
    }

    /// Heuristique simple : HRV élevée + FC repos basse => meilleure récup.
    /// Avant: la DERNIERE mesure, meme vieille de plusieurs mois, faisait le
    /// score du jour. Une mesure perimee ne donne plus de score.
    static func score(hrv: (value: Double, date: Date)?, rhr: (value: Double, date: Date)?,
                      now: Date = .now) -> Int? {
        guard let hrv, let rhr, isFresh(hrv.date, now: now), isFresh(rhr.date, now: now) else { return nil }
        let hrvScore = min(100, max(0, (hrv.value / 80.0) * 100))
        let rhrScore = min(100, max(0, (1 - (rhr.value - 40) / 50) * 100))
        return Int((hrvScore * 0.6 + rhrScore * 0.4).rounded())
    }
}

/// Ligne de base personnelle sur 30 jours de mesures DATEES (VFC, FC repos).
/// Modele LifeOS: ni Whoop, ni un avis medical.
enum RecoveryBaseline {
    static let windowDays = 30
    static let minDays = 7
    static let keepDays = 120
    static let hrvWeight = 0.6
    static let rhrWeight = 0.4

    struct Stat: Equatable {
        let mean: Double
        let sd: Double
        let days: Int
    }

    struct Contribution: Equatable, Identifiable {
        let id: String
        let label: String
        let points: Double
        let maxPoints: Double
        let explanation: String
    }

    struct Result: Equatable {
        let score: Int
        let personal: Bool
        let calibrationDays: Int
        let contributions: [Contribution]
    }

    static func isDuplicate(kind: String, date: Date, existing: [(kind: String, date: Date)]) -> Bool {
        existing.contains { $0.kind == kind && abs($0.date.timeIntervalSince(date)) < 60 }
    }

    static func isExpired(_ date: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(date) > Double(keepDays) * 86_400
    }

    /// Une valeur par jour (moyenne du jour) sur les 30 jours AVANT le jour
    /// mesure: la mesure du jour ne se compare pas a elle-meme.
    static func stat(_ samples: [(value: Double, date: Date)], before: Date, cal: Calendar = .current) -> (stat: Stat?, days: Int) {
        let dayOfSample = cal.startOfDay(for: before)
        let from = dayOfSample.addingTimeInterval(-Double(windowDays) * 86_400)
        let inWindow = samples.filter { $0.value > 0 && $0.date >= from && cal.startOfDay(for: $0.date) < dayOfSample }
        let byDay = Dictionary(grouping: inWindow) { cal.startOfDay(for: $0.date) }
            .mapValues { v in v.reduce(0) { $0 + $1.value } / Double(v.count) }
        let vals = Array(byDay.values)
        guard vals.count >= minDays else { return (nil, vals.count) }
        let mean = vals.reduce(0, +) / Double(vals.count)
        let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(vals.count)
        return (Stat(mean: mean, sd: variance.squareRoot(), days: vals.count), vals.count)
    }

    /// 50 = ta moyenne; chaque ecart-type au-dessus (VFC) ou au-dessous (FC) vaut 20.
    static func component(value: Double, stat s: Stat, inverted: Bool) -> Double {
        let z = (value - s.mean) / max(s.sd, s.mean * 0.05, 0.0001)
        return min(100, max(0, 50 + (inverted ? -20 : 20) * z))
    }

    private static func pct(_ v: Double, _ mean: Double) -> String {
        let p = Int(((v - mean) / mean * 100).rounded())
        return p >= 0 ? "+\(p) %" : "\(p) %"
    }

    static func evaluate(hrv: (value: Double, date: Date)?, rhr: (value: Double, date: Date)?,
                         hrvHistory: [(value: Double, date: Date)], rhrHistory: [(value: Double, date: Date)],
                         now: Date = .now, cal: Calendar = .current) -> Result? {
        guard let hrv, let rhr, RecoveryScore.isFresh(hrv.date, now: now), RecoveryScore.isFresh(rhr.date, now: now) else { return nil }
        let hb = stat(hrvHistory, before: hrv.date, cal: cal)
        let rb = stat(rhrHistory, before: rhr.date, cal: cal)
        let calibration = min(hb.days, rb.days)
        let hp = hrvWeight * 100, rp = rhrWeight * 100
        if let h = hb.stat, let r = rb.stat {
            let hc = component(value: hrv.value, stat: h, inverted: false)
            let rc = component(value: rhr.value, stat: r, inverted: true)
            let contributions = [
                Contribution(id: "hrv", label: "VFC", points: hrvWeight * hc, maxPoints: hp,
                             explanation: "\(Int(hrv.value.rounded())) ms, ta moyenne sur \(h.days) jours : \(Int(h.mean.rounded())) ms (\(pct(hrv.value, h.mean))). Plus haute que d'habitude = mieux récupéré."),
                Contribution(id: "rhr", label: "FC au repos", points: rhrWeight * rc, maxPoints: rp,
                             explanation: "\(Int(rhr.value.rounded())) bpm, ta moyenne sur \(r.days) jours : \(Int(r.mean.rounded())) bpm (\(pct(rhr.value, r.mean))). Plus basse que d'habitude = mieux récupéré."),
            ]
            return Result(score: Int((hrvWeight * hc + rhrWeight * rc).rounded()), personal: true,
                          calibrationDays: calibration, contributions: contributions)
        }
        // Pas encore 7 jours de mesures: memes reperes fixes qu'avant, annonces comme tels.
        let hc = min(100, max(0, (hrv.value / 80.0) * 100))
        let rc = min(100, max(0, (1 - (rhr.value - 40) / 50) * 100))
        let contributions = [
            Contribution(id: "hrv", label: "VFC", points: hrvWeight * hc, maxPoints: hp,
                         explanation: "\(Int(hrv.value.rounded())) ms comparée à un repère fixe de 80 ms, en attendant ta ligne de base."),
            Contribution(id: "rhr", label: "FC au repos", points: rhrWeight * rc, maxPoints: rp,
                         explanation: "\(Int(rhr.value.rounded())) bpm comparée à un repère fixe de 40 à 90 bpm, en attendant ta ligne de base."),
        ]
        return Result(score: Int((hc * hrvWeight + rc * rhrWeight).rounded()), personal: false,
                      calibrationDays: calibration, contributions: contributions)
    }
}

struct RecoveryScoreView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \RecoveryReading.measuredAt) private var readings: [RecoveryReading]
    @Query(sort: \SleepNight.date, order: .reverse) private var nights: [SleepNight]
    @AppStorage(AppStorageKeys.sleepGoalHours) private var sleepGoal = 8.0
    @State private var hrv: (value: Double, date: Date)?
    @State private var rhr: (value: Double, date: Date)?
    @State private var loading = true

    private func history(_ kind: String) -> [(value: Double, date: Date)] {
        readings.filter { $0.kind == kind }.map { ($0.value, $0.measuredAt) }
    }
    private var result: RecoveryBaseline.Result? {
        RecoveryBaseline.evaluate(hrv: hrv, rhr: rhr, hrvHistory: history("hrv"), rhrHistory: history("rhr"))
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    Label("Modèle LifeOS, pas un score Whoop", systemImage: "info.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.bg2, in: Capsule())
                    if loading {
                        ProgressView().tint(.sleepTint).padding(.top, 40)
                    } else if let result {
                        ZStack {
                            ProgressRing(progress: Double(result.score) / 100, lineWidth: 16, tint: scoreColor(result.score))
                            VStack {
                                Text("\(result.score)").font(.system(size: 54, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                Text("Récupération").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 200, height: 200).padding(.top, 6)
                        Text(result.personal
                             ? "Comparé à ta ligne de base perso (\(result.calibrationDays) jours de mesures)."
                             : "Calibration : \(result.calibrationDays) / \(RecoveryBaseline.minDays) jours de mesures. D'ici là, comparaison à des repères fixes.")
                            .font(.caption).foregroundStyle(result.personal ? Theme.success : Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        Text(advice(result.score)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        contributionsCard(result)
                        tiles
                    } else if hrv != nil || rhr != nil {
                        // Des mesures existent mais pas assez recentes (ou une
                        // seule des deux): on les montre datees, sans score.
                        EmptyState(icon: "clock.arrow.circlepath", title: "Pas de mesure récente",
                                   message: "Le score demande la VFC et la FC au repos des dernières 36 h. Porte ton Apple Watch la nuit pour l'obtenir.")
                        tiles
                    } else {
                        EmptyState(icon: "heart.slash", title: "Pas de données santé",
                                   message: "Autorise LifeOS à lire la VFC et la FC au repos dans l'app Santé (Partage › Apps › LifeOS). Ces mesures viennent d'une Apple Watch.")
                    }
                    if readings.count > 1 { trendCard }
                    sleepContextCard
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Score de récupération").navigationBarTitleDisplayMode(.inline)
        .task {
            _ = await HealthService.shared.requestAuthorization()
            hrv = await HealthService.shared.hrvSample()
            rhr = await HealthService.shared.restingHeartRateSample()
            remember()
            loading = false
        }
    }

    /// Chaque mesure datee lue dans Sante est gardee: c'est elle qui construit
    /// la ligne de base, jour apres jour. Les plus vieilles que 120 jours partent.
    private func remember() {
        let existing = readings.map { (kind: $0.kind, date: $0.measuredAt) }
        for (kind, sample) in [("hrv", hrv), ("rhr", rhr)] {
            guard let sample, sample.value > 0,
                  !RecoveryBaseline.isDuplicate(kind: kind, date: sample.date, existing: existing) else { continue }
            ctx.insert(RecoveryReading(kind: kind, value: sample.value, measuredAt: sample.date))
        }
        for r in readings where RecoveryBaseline.isExpired(r.measuredAt) { ctx.delete(r) }
    }

    private func contributionsCard(_ r: RecoveryBaseline.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "D'où vient ce score")
            ForEach(r.contributions) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(Int(c.points.rounded())) / \(Int(c.maxPoints)) pts").font(.subheadline.bold()).foregroundStyle(.sleepTint)
                    }
                    ProgressView(value: c.points, total: c.maxPoints).tint(.sleepTint)
                    Text(c.explanation).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Text("Poids : VFC 60 %, FC au repos 40 %. Mesures d'Apple Santé, une seule par type et par jour dans la ligne de base.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private var trendCard: some View {
        let from = Date().addingTimeInterval(-Double(RecoveryBaseline.windowDays) * 86_400)
        let recent = readings.filter { $0.measuredAt >= from }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tendance 30 jours", subtitle: "Mesures gardées à chaque ouverture de l'écran.")
            trendChart(recent.filter { $0.kind == "hrv" }, title: "VFC (ms)", tint: .sleepTint)
            trendChart(recent.filter { $0.kind == "rhr" }, title: "FC au repos (bpm)", tint: Theme.danger)
        }
        .card()
    }

    @ViewBuilder private func trendChart(_ pts: [RecoveryReading], title: String, tint: Color) -> some View {
        if !pts.isEmpty {
            Text(title).font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            Chart(pts) { p in
                LineMark(x: .value("Jour", p.measuredAt), y: .value(title, p.value)).foregroundStyle(tint)
                PointMark(x: .value("Jour", p.measuredAt), y: .value(title, p.value)).foregroundStyle(tint)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 110)
        }
    }

    /// Contexte sommeil, affiche a cote du score sans entrer dans le calcul.
    private var sleepContextCard: some View {
        let window = SleepDebt.window(nights.map { ($0.date, $0.hours) }, days: 14)
        let (debt, counted) = SleepDebt.compute(hours: window, goal: sleepGoal)
        let last = window.last ?? nil
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ton sommeil noté", subtitle: "Affiché pour contexte, pas compté dans le score.")
            HStack(spacing: 12) {
                StatTile(value: last.map(fmtH) ?? "-", label: "Cette nuit", icon: "moon.fill", tint: .sleepTint)
                StatTile(value: counted == 0 ? "-" : (debt < 0.1 ? "à jour" : "-\(fmtH(debt))"),
                         label: "Dette · \(counted)/14 nuits", icon: "hourglass", tint: Theme.learning)
            }
        }
        .card()
    }

    private var tiles: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                StatTile(value: hrv.map { "\(Int($0.value)) ms" } ?? "-", label: "HRV (SDNN)", icon: "waveform.path.ecg")
                StatTile(value: rhr.map { "\(Int($0.value))" } ?? "-", label: "FC repos", icon: "heart.fill", tint: Theme.danger)
            }
            // Chaque valeur avec sa date: une mesure ancienne ne passe plus
            // pour celle du jour.
            Text(measuredLine)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var measuredLine: String {
        func d(_ date: Date) -> String { date.formatted(.relative(presentation: .named)) }
        var parts: [String] = []
        if let hrv { parts.append("VFC mesurée \(d(hrv.date))") }
        if let rhr { parts.append("FC repos \(d(rhr.date))") }
        return parts.joined(separator: " · ")
    }
    private func fmtH(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60)h\(m % 60 == 0 ? "" : String(format: "%02d", m % 60))"
    }
    private func scoreColor(_ s: Int) -> Color { s >= 66 ? Theme.success : (s >= 40 ? Theme.learning : Theme.danger) }
    private func advice(_ s: Int) -> String {
        s >= 66 ? "Bien récupéré. Tu peux pousser fort aujourd'hui"
        : s >= 40 ? "Récup moyenne. Entraînement modéré conseillé."
        : "Faible récup. Privilégie repos, mobilité et sommeil."
    }
}
