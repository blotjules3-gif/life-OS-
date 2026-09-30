import SwiftUI

// MARK: - Trilingo : un vrai parcours quotidien
//
// 1. Questionnaire obligatoire (langue, objectif, experience, temps, rappel).
// 2. Test de placement adaptatif ou depart debutant.
// 3. Seance du jour: revisions espacees par competence, puis phrases nouvelles vues
//    en lecture, ecriture, ecoute et oral.
// Les cours viennent de Tatoeba (phrases et traductions humaines), voir
// `tools/trilingo/build_courses.py`.

struct TrilingoView: View {
    @StateObject private var store = TrilingoStore.shared
    @State private var editing = false

    var body: some View {
        Group {
            if store.needsSetup || editing {
                TrilingoSetupView(existing: store.profile) { editing = false }
            } else if let course = store.course, let progress = store.progress {
                if !progress.placementDone {
                    TrilingoPlacementView(course: course)
                } else {
                    TrilingoHomeView(course: course, onEdit: { editing = true })
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Trilingo").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Questionnaire obligatoire

struct TrilingoSetupView: View {
    let existing: TrilingoProfile?
    var onDone: () -> Void
    @StateObject private var store = TrilingoStore.shared
    @State private var target = ""
    @State private var goal = "voyage"
    @State private var experience = "jamais"
    @State private var minutes = 10
    @State private var reminderOn = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var error: String?

    private var manifest: TrilingoManifest? { TrilingoLibrary.manifest() }

    var body: some View {
        Form {
            Section {
                Text(existing == nil
                     ? "Avant ton premier cours : quelques réponses pour construire ton parcours. Elles restent modifiables ensuite."
                     : "Modifie ton parcours. Chaque langue garde sa propre progression.")
                    .font(.callout)
            }
            Section("Je veux apprendre") {
                ForEach(orderedLanguages) { lang in
                    let entry = manifest?.courses[lang.code]
                    Button { if entry != nil { target = lang.code } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(lang.name) · \(lang.native)").foregroundStyle(entry == nil ? .secondary : .primary)
                                Text(coverage(entry)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if target == lang.code { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.learnTint) }
                        }
                    }
                    .disabled(entry == nil)
                }
            }
            Section("Mon objectif") {
                Picker("Objectif", selection: $goal) {
                    ForEach(["voyage", "travail", "études", "culture", "famille", "autre"], id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            Section("Mon niveau") {
                Picker("Expérience", selection: $experience) {
                    Text("Jamais étudié").tag("jamais"); Text("Quelques bases").tag("bases"); Text("Intermédiaire").tag("intermediaire")
                }.pickerStyle(.segmented)
            }
            Section("Temps par jour") {
                Picker("Minutes", selection: $minutes) { ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) min").tag($0) } }
                    .pickerStyle(.segmented)
                Text("\(TrilingoEngine.newPerSession(minutes)) phrases nouvelles par séance, plus les révisions du jour.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Rappel quotidien") {
                Toggle("Me le rappeler chaque jour", isOn: $reminderOn)
                if reminderOn { DatePicker("Heure", selection: $reminderTime, displayedComponents: .hourAndMinute) }
                Text("Pas de rappel un jour où la séance est déjà faite.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) } }
            Section {
                Button { save() } label: { Text(existing == nil ? "Commencer" : "Enregistrer").frame(maxWidth: .infinity) }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).disabled(target.isEmpty)
                if existing != nil { Button("Annuler", role: .cancel) { onDone() } }
            }
            if let m = manifest {
                Section("Couverture réelle") {
                    let complete = m.courses.values.filter { $0.status == "complet" }.count
                    Text("\(complete) cours complets (180 jours et plus) depuis le français, \(m.courses.values.filter { $0.status == "partiel" }.count) partiels. Les autres langues ne sont pas encore produites : elles ne sont pas proposées.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            guard let e = existing else { return }
            target = e.target; goal = e.goal; experience = e.experience; minutes = e.dailyMinutes; reminderOn = e.reminderOn
            reminderTime = Calendar.current.date(bySettingHour: e.reminderHour, minute: e.reminderMinute, second: 0, of: Date()) ?? reminderTime
        }
    }

    private var orderedLanguages: [TrilingoLanguage] {
        let m = manifest?.courses ?? [:]
        func rank(_ l: TrilingoLanguage) -> Int { m[l.code]?.status == "complet" ? 0 : m[l.code] != nil ? 1 : 2 }
        return TrilingoLanguages.all.filter { $0.code != "fra" }.sorted { (rank($0), $0.name) < (rank($1), $1.name) }
    }

    private func coverage(_ e: TrilingoManifest.Entry?) -> String {
        guard let e else { return "Cours pas encore produit" }
        if e.status == "complet" { return "Cours complet · \(e.days) jours" }
        return e.days >= TrilingoCourse.fullDays
            ? "Cours partiel · \(e.days) jours, corpus réduit (\(e.pairs) phrases) : progression moins régulière"
            : "Cours partiel · \(e.days) jours seulement"
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        var p = existing ?? TrilingoProfile(target: target, goal: goal, experience: experience, dailyMinutes: minutes,
                                            reminderOn: reminderOn, reminderHour: c.hour ?? 19, reminderMinute: c.minute ?? 0)
        p.target = target; p.goal = goal; p.experience = experience; p.dailyMinutes = minutes
        p.reminderOn = reminderOn; p.reminderHour = c.hour ?? 19; p.reminderMinute = c.minute ?? 0
        do {
            try store.saveProfile(p)
            if experience == "jamais", store.progress?.placementDone == false {
                try store.update { $0.placementDone = true; $0.placementDay = 1 }
            }
            let name = TrilingoLanguages.named(target)?.name ?? target
            let done = store.progress?.completedDates.contains(TrilingoEngine.dayKey(Date())) == true
            Task {
                if reminderOn { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
                await TrilingoReminders.reschedule(p, doneToday: done, languageName: name)
            }
            onDone()
        } catch { self.error = "Enregistrement impossible : \(error.localizedDescription)" }
    }
}

// MARK: - Placement

struct TrilingoPlacementView: View {
    let course: TrilingoCourse
    @StateObject private var store = TrilingoStore.shared
    @State private var started = false
    @State private var probeIndex = 0
    @State private var question = 0
    @State private var results: [Int: Int] = [:]
    @State private var picked: String?
    @State private var finished = false
    @State private var rng = SeededRNG(seed: 7)

    private var probes: [Int] { TrilingoEngine.placementProbes(course) }
    private var language: TrilingoLanguage? { TrilingoLanguages.named(course.target) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !started {
                    Text("Où commencer ?").font(.title2.bold())
                    Text("Un test court (3 phrases par palier) estime ton niveau. Il s'arrête dès qu'un palier devient trop difficile.")
                        .foregroundStyle(.secondary)
                    Button { started = true } label: { Text("Tester mon niveau").frame(maxWidth: .infinity) }
                        .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                    Button { commit(1) } label: { Text("Je débute complètement").frame(maxWidth: .infinity) }
                        .buttonStyle(LifeOSGlassButtonStyle())
                } else if finished {
                    let start = TrilingoEngine.placementStart(results: results, probes: probes)
                    Text("Niveau estimé : \(TrilingoEngine.level(course, day: start))").font(.title2.bold())
                    Text(start == 1 ? "Tu commences au premier jour du cours." : "Tu commences au jour \(start) sur \(course.days.count). Les phrases d'avant sont supposées connues ; les révisions te les feront revoir si besoin.")
                        .foregroundStyle(.secondary)
                    Button { commit(start) } label: { Text("Commencer").frame(maxWidth: .infinity) }
                        .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                } else if let item = currentItem {
                    Text("Palier \(probeIndex + 1) sur \(probes.count) · phrase \(question + 1) sur 3").font(.caption).foregroundStyle(.secondary)
                    Text(item.t).font(.title3.bold()).environment(\.layoutDirection, language?.rtl == true ? .rightToLeft : .leftToRight)
                    Text("Que veut dire cette phrase ?").foregroundStyle(.secondary)
                    ForEach(options(for: item), id: \.self) { o in
                        Button { answer(o, item) } label: { Text(o).frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(LifeOSGlassButtonStyle())
                    }
                }
            }
            .padding(Theme.pad)
        }
    }

    private var currentItem: TrilingoItem? {
        guard probes.indices.contains(probeIndex) else { return nil }
        let day = course.days[probes[probeIndex] - 1]
        return day.items.indices.contains(question * 3) ? day.items[question * 3] : day.items.first
    }

    private func options(for item: TrilingoItem) -> [String] {
        var seeded = SeededRNG(seed: UInt64(item.tid))
        let others = course.allItems.filter { $0.tid != item.tid }.shuffled(using: &seeded).prefix(3).map(\.s)
        return ([item.s] + others).shuffled(using: &seeded)
    }

    private func answer(_ o: String, _ item: TrilingoItem) {
        let d = probes[probeIndex]
        if o == item.s { results[d, default: 0] += 1 } else { results[d] = results[d] ?? 0 }
        if question < 2 { question += 1; return }
        if (results[d] ?? 0) >= 2, probeIndex + 1 < probes.count { probeIndex += 1; question = 0 } else { finished = true }
    }

    private func commit(_ start: Int) {
        try? store.update { $0.placementDone = true; $0.placementDay = start }
    }
}

// MARK: - Accueil du cours

struct TrilingoHomeView: View {
    let course: TrilingoCourse
    var onEdit: () -> Void
    @StateObject private var store = TrilingoStore.shared
    @State private var session: [TrilingoExercise]?
    @State private var mistakesOnly = false

    private var language: TrilingoLanguage? { TrilingoLanguages.named(course.target) }
    private var today: String { TrilingoEngine.dayKey(Date()) }
    private var caps: TrilingoCapabilities {
        let bcp = language?.bcp47 ?? "en-US"
        return TrilingoCapabilities(audio: TrilingoSpeech.hasVoice(bcp), speech: TrilingoSpeech.speechAvailable(bcp))
    }

    var body: some View {
        let p = store.progress ?? TrilingoProgress(target: course.target)
        let perDay = course.days.first?.items.count ?? 12
        let currentDay = min(course.days.count, max(p.placementDay, p.nextItem / perDay + 1))
        let doneToday = p.completedDates.contains(today)
        let due = TrilingoEngine.dueReviews(p, today: today).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(language?.name ?? course.target).font(.title.bold())
                    Spacer()
                    Label("\(p.streak) j", systemImage: "flame.fill").foregroundStyle(Theme.warning).font(.headline)
                }
                Text("Jour \(currentDay) sur \(course.days.count) · unité \(course.days[currentDay - 1].unit) · niveau \(course.days[currentDay - 1].level)")
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(currentDay), total: Double(course.days.count)).tint(Color.learnTint)

                VStack(alignment: .leading, spacing: 10) {
                    Text(doneToday ? "Séance du jour faite" : "Séance du jour").font(.headline)
                    Text("\(min(due, TrilingoEngine.reviewLimit(store.profile?.dailyMinutes ?? 10))) révision(s) · \(TrilingoEngine.newPerSession(store.profile?.dailyMinutes ?? 10)) phrases nouvelles · environ \(store.profile?.dailyMinutes ?? 10) min")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        mistakesOnly = false
                        session = TrilingoEngine.session(course: course, progress: p, today: today, minutes: store.profile?.dailyMinutes ?? 10, caps: caps)
                    } label: { Label(doneToday ? "Continuer quand même" : "Commencer", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(LifeOSGlassButtonStyle(prominent: !doneToday))
                    if !caps.audio {
                        Label("Pas de voix \(language?.name.lowercased() ?? "") sur cet appareil : les exercices d'écoute sont remplacés. Réglages > Accessibilité > Contenu énoncé > Voix pour en ajouter une.", systemImage: "speaker.slash")
                            .font(.caption).foregroundStyle(Theme.warning)
                    } else if !caps.speech {
                        Label("Reconnaissance vocale indisponible pour cette langue : pas d'exercice oral.", systemImage: "mic.slash").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                if !p.mistakes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Carnet d'erreurs").font(.headline)
                        Text("\(p.mistakes.count) phrase(s) à retravailler.").font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            mistakesOnly = true
                            let items = course.allItems.filter { p.mistakes.contains($0.tid) }
                            var rng = SeededRNG(seed: 3)
                            session = items.prefix(15).map { TrilingoEngine.exercise(for: .writing, item: $0, pool: course.allItems, review: true, noSpaces: course.noSpaces ?? false, caps: caps, rng: &rng) }
                        } label: { Label("Revoir mes erreurs", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                            .buttonStyle(LifeOSGlassButtonStyle())
                    }
                    .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }

                skillsCard(p)

                VStack(alignment: .leading, spacing: 6) {
                    Button("Modifier mon parcours (langue, objectif, temps, rappel)") { onEdit() }.multilineTextAlignment(.leading)
                    Button("Refaire le test de niveau") { try? store.update { $0.placementDone = false } }
                    Text(course.license + " Version du cours : \(course.version).").font(.caption2).foregroundStyle(.secondary)
                    if !course.isComplete {
                        Text(course.days.count >= TrilingoCourse.fullDays
                             ? "Cours partiel : peu de phrases traduites disponibles pour cette langue, la progression est moins régulière."
                             : "Cours partiel : \(course.days.count) jours disponibles, moins que les 180 d'un cours complet.")
                            .font(.caption2).foregroundStyle(Theme.warning)
                    }
                    Text("Progression gardée sur cet appareil et dans la sauvegarde complète. Pas de synchronisation en ligne : il n'y a pas encore de compte LifeOS.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.pad)
        }
        .fullScreenCover(isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } })) {
            if let s = session, let lang = language {
                TrilingoSessionView(course: course, language: lang, exercises: s, countsAsDay: !mistakesOnly) { session = nil }
            }
        }
    }

    private func skillsCard(_ p: TrilingoProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compétences").font(.headline)
            ForEach(TrilingoSkill.allCases, id: \.self) { sk in
                let states = p.srs.filter { $0.key.hasSuffix("|\(sk.rawValue)") }.map(\.value)
                let solid = states.filter { $0.box >= 3 }.count
                HStack {
                    Text(sk.rawValue.capitalized)
                    Spacer()
                    Text(states.isEmpty ? "pas encore travaillé" : "\(solid) acquise(s) sur \(states.count)").foregroundStyle(.secondary).monospacedDigit()
                }.font(.subheadline)
            }
            Text("« Acquise » : réussie plusieurs fois de suite, à des jours différents.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// MARK: - Seance

struct TrilingoSessionView: View {
    let course: TrilingoCourse
    let language: TrilingoLanguage
    let exercises: [TrilingoExercise]
    let countsAsDay: Bool
    var onClose: () -> Void
    @StateObject private var store = TrilingoStore.shared
    @StateObject private var speech = TrilingoSpeech.shared
    @State private var index = 0
    @State private var built: [String] = []
    @State private var typed = ""
    @State private var chosen: String?
    @State private var verdict: Bool?
    @State private var correctCount = 0
    @State private var done = false
    @State private var micError: String?

    private var today: String { TrilingoEngine.dayKey(Date()) }
    private var noSpaces: Bool { course.noSpaces ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProgressView(value: Double(index), total: Double(max(exercises.count, 1))).tint(Color.learnTint)
                if done { summary } else if exercises.indices.contains(index) { exerciseView(exercises[index]) }
                Spacer()
            }
            .padding(Theme.pad)
            .background(Theme.background)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { speech.stopListening(); onClose() } } }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder private func exerciseView(_ e: TrilingoExercise) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title(e)).font(.caption).foregroundStyle(.secondary)
            switch e.kind {
            case .intro:
                target(e.item.t)
                if let tr = e.item.tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
                audioButtons(e.item)
                Text(e.item.s).font(.title3).foregroundStyle(.secondary)
                Button { next(nil, e) } label: { Text("J'ai compris").frame(maxWidth: .infinity) }.buttonStyle(LifeOSGlassButtonStyle(prominent: true))
            case .chooseMeaning, .listenChoose:
                if e.kind == .chooseMeaning { target(e.item.t) } else { audioButtons(e.item) }
                ForEach(e.options, id: \.self) { o in
                    Button { guard verdict == nil else { return }; chosen = o; verdict = (o == e.item.s) } label: {
                        HStack {
                            Text(o).frame(maxWidth: .infinity, alignment: .leading)
                            if verdict != nil && o == e.item.s { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }
                            else if verdict == false && chosen == o { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger) }
                        }
                    }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: chosen == o))
                    .tint(verdict == nil ? Color.learnTint : (o == e.item.s ? Theme.success : (chosen == o ? Theme.danger : Color.learnTint)))
                }
            case .build:
                Text(e.item.s).font(.title3.bold())
                Text(built.joined(separator: noSpaces ? "" : " ")).font(.title3).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(10).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)
                FlowTiles(tiles: e.tiles, used: built) { tile in
                    if let i = built.firstIndex(of: tile), built.filter({ $0 == tile }).count >= e.tiles.filter({ $0 == tile }).count { built.remove(at: i) } else { built.append(tile) }
                }
                if !built.isEmpty && verdict == nil { Button("Effacer") { built = [] }.font(.caption) }
            case .dictation, .translate:
                if e.kind == .dictation { audioButtons(e.item) } else { Text(e.item.s).font(.title3.bold()) }
                TextField(e.kind == .dictation ? "Écris ce que tu entends" : "Écris la phrase en \(language.name.lowercased())", text: $typed, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)
            case .speak:
                target(e.item.t)
                if let tr = e.item.tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
                audioButtons(e.item)
                Button {
                    if speech.listening { speech.stopListening() }
                    else { Task { if await speech.requestSpeechPermission() { do { try speech.startListening(bcp47: language.bcp47) } catch { micError = error.localizedDescription } } else { micError = "Micro ou reconnaissance vocale refusés : Réglages > LifeOS." } } }
                } label: { Label(speech.listening ? "J'ai fini" : "Parler", systemImage: speech.listening ? "stop.circle" : "mic.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                if !speech.heard.isEmpty { Text("Compris : « \(speech.heard) »").font(.callout) }
                if let micError { Text(micError).font(.caption).foregroundStyle(Theme.warning) }
                Text("La reconnaissance vérifie qu'on te comprend, pas la finesse de ta prononciation.").font(.caption2).foregroundStyle(.secondary)
                Button("Passer (pas de micro maintenant)") { verdict = nil; next(nil, e) }.font(.caption)
            }
            if e.kind != .intro { checkArea(e) }
        }
    }

    private func target(_ t: String) -> some View {
        Text(t).font(.title2.bold()).multilineTextAlignment(language.rtl ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: language.rtl ? .trailing : .leading)
            .environment(\.layoutDirection, language.rtl ? .rightToLeft : .leftToRight)
    }

    private func audioButtons(_ item: TrilingoItem) -> some View {
        HStack {
            Button { speech.play(item, language: language) } label: { Label("Écouter", systemImage: "speaker.wave.2.fill") }
            Button { speech.play(item, language: language, slow: true) } label: { Label("Lentement", systemImage: "tortoise.fill") }
        }
        .buttonStyle(LifeOSGlassButtonStyle())
    }

    @ViewBuilder private func checkArea(_ e: TrilingoExercise) -> some View {
        if let v = verdict {
            VStack(alignment: .leading, spacing: 6) {
                Label(v ? "Juste" : "Pas tout à fait", systemImage: v ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(v ? Theme.success : Theme.danger).font(.headline)
                if !v || e.kind == .speak { Text([e.item.t, e.item.tr, e.item.s].compactMap { $0 }.joined(separator: "\n")).font(.callout) }
                Button { next(v, e) } label: { Text("Continuer").frame(maxWidth: .infinity) }.buttonStyle(LifeOSGlassButtonStyle(prominent: true))
            }
        } else if e.kind != .chooseMeaning && e.kind != .listenChoose {
            Button { verdict = check(e) } label: { Text("Vérifier").frame(maxWidth: .infinity) }
                .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                .disabled(e.kind == .build ? built.isEmpty : (e.kind == .speak ? speech.heard.isEmpty : typed.isEmpty))
        }
    }

    private func check(_ e: TrilingoExercise) -> Bool {
        switch e.kind {
        case .build: return TrilingoEngine.similarity(e.item.t, built.joined(separator: noSpaces ? "" : " "), noSpaces: noSpaces) >= 0.99
        case .dictation, .translate: return TrilingoEngine.similarity(e.item.t, typed, noSpaces: noSpaces) >= 0.85
        case .speak: speech.stopListening(); return TrilingoEngine.similarity(e.item.t, speech.heard, noSpaces: noSpaces) >= 0.7
        default: return false
        }
    }

    private func next(_ correct: Bool?, _ e: TrilingoExercise) {
        if let c = correct {
            if c { correctCount += 1 }
            try? store.update { TrilingoEngine.record(&$0, exercise: e, correct: c, today: today) }
        }
        built = []; typed = ""; chosen = nil; verdict = nil; speech.heard = ""
        if index + 1 < exercises.count { index += 1 } else { finish() }
    }

    private func finish() {
        if countsAsDay {
            try? store.update { TrilingoEngine.finish(&$0, session: exercises, today: today, perDay: course.days.first?.items.count ?? 12) }
        }
        done = true
        let name = language.name
        let profile = store.profile
        Task { await TrilingoReminders.reschedule(profile, doneToday: true, languageName: name) }
        Haptics.medium()
    }

    private var summary: some View {
        let graded = exercises.filter { $0.kind != .intro }.count
        return VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Color.learnTint)
            Text("Séance terminée").font(.title2.bold())
            Text("\(correctCount) réponse(s) justes sur \(graded).").foregroundStyle(.secondary)
            Text("Série : \(store.progress?.streak ?? 0) jour(s).").font(.headline)
            Button { onClose() } label: { Text("Fermer").frame(maxWidth: .infinity) }.buttonStyle(LifeOSGlassButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity)
    }

    private func title(_ e: TrilingoExercise) -> String {
        let r = e.isReview ? "Révision · " : ""
        switch e.kind {
        case .intro: return "Nouvelle phrase"
        case .chooseMeaning: return r + "Que veut dire cette phrase ?"
        case .listenChoose: return r + "Écoute et choisis le sens"
        case .build: return r + "Reconstruis la phrase"
        case .dictation: return r + "Dictée"
        case .translate: return r + "Traduis sans aide"
        case .speak: return r + "Dis la phrase à voix haute"
        }
    }
}

/// Etiquettes a toucher pour reconstruire une phrase: chaque etiquette prend la
/// largeur de son mot et les lignes se remplissent (une grille coupait "To-davía").
struct FlowTiles: View {
    let tiles: [String]
    let used: [String]
    var onTap: (String) -> Void
    var body: some View {
        TrilingoFlowLayout(spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                let taken = used.filter { $0 == t }.count >= tiles.filter { $0 == t }.count
                Button { onTap(t) } label: { Text(t).lineLimit(1).fixedSize() }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: taken))
                    .opacity(taken ? 0.45 : 1)
            }
        }
    }
}

struct TrilingoFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
