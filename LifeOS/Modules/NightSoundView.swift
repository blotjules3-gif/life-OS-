import SwiftUI
import AVFoundation

// MARK: - Ecoute nocturne (ecran)

struct NightSoundView: View {
    @StateObject private var listener = NightListener.shared
    @StateObject private var store = NightStore.shared
    @AppStorage("night.consent") private var consent = false
    @State private var keepDays = NightStore.shared.keepDays
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !consent { consentCard } else { controlCard }
                if !store.sessions.filter({ $0.end != nil }).isEmpty {
                    Text("Nuits enregistrées").font(.headline).padding(.leading, 4)
                    ForEach(store.sessions.filter { $0.end != nil }) { s in
                        NavigationLink { NightDetailView(session: s) } label: { nightRow(s) }.buttonStyle(.plain)
                    }
                }
                settingsCard
            }
            .padding(Theme.pad)
        }
        .background(Theme.background)
        .navigationTitle("Écoute nocturne").navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { now = $0 }
        .onAppear { store.purge() }
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Écouter ma nuit").font(.title3.bold())
            Text("Pendant que tu dors, le micro écoute sur ton téléphone et repère ronflements, toux, paroles, pleurs ou bruits forts. Seuls de courts extraits autour de chaque événement sont gardés, sur cet appareil, et effacés après la durée que tu choisis. Rien n'est envoyé.")
            Text("Ce sont des événements estimés par un classifieur sonore : ni un diagnostic, ni une mesure des phases du sommeil. En cas de doute sur ta santé, parle à un médecin.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                Task { if await listener.requestPermission() { consent = true } else { listener.error = "Micro refusé : Réglages > LifeOS > Micro." } }
            } label: { Text("J'accepte, autoriser le micro").frame(maxWidth: .infinity) }
                .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
            if let e = listener.error { Text(e).font(.caption).foregroundStyle(Theme.warning) }
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = listener.session {
                Text("Écoute en cours").font(.title3.bold())
                Text("Depuis \(s.start.formatted(date: .omitted, time: .shortened)) · \(Int(now.timeIntervalSince(s.start) / 60)) min").foregroundStyle(.secondary)
                if !listener.lastSound.isEmpty { Label("Dernier son repéré : \(listener.lastSound)", systemImage: "waveform").font(.subheadline) }
                Button(role: .destructive) { listener.stop() } label: { Label("Arrêter et voir ma nuit", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                Text("Laisse le téléphone branché, écran vers le bas, près du lit. L'écoute continue écran verrouillé ; un appel la met en pause et la reprend ensuite.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Prêt pour la nuit").font(.title3.bold())
                Button {
                    do { try listener.start() } catch { listener.error = error.localizedDescription }
                } label: { Label("Commencer l'écoute", systemImage: "moon.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                Text("Branche le téléphone : une nuit d'écoute consomme de la batterie.").font(.caption).foregroundStyle(.secondary)
            }
            if let e = listener.error { Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func nightRow(_ s: NightSession) -> some View {
        let sum = NightSounds.summary(s)
        return VStack(alignment: .leading, spacing: 4) {
            Text(s.start.formatted(date: .complete, time: .omitted)).font(.subheadline.weight(.semibold))
            Text("\(s.start.formatted(date: .omitted, time: .shortened)) → \(s.end?.formatted(date: .omitted, time: .shortened) ?? "?") · \(s.events.count) événement(s)")
                .font(.caption).foregroundStyle(.secondary)
            if !sum.isEmpty {
                Text(sum.prefix(3).map { "\($0.kind) ×\($0.count)" }.joined(separator: " · ")).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conservation").font(.headline)
            Picker("Garder les nuits", selection: $keepDays) {
                Text("7 jours").tag(7); Text("14 jours").tag(14); Text("30 jours").tag(30); Text("90 jours").tag(90)
            }
            .onChange(of: keepDays) { _, v in store.keepDays = v }
            Text("Les nuits plus anciennes et leurs extraits sont effacés automatiquement.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

struct NightDetailView: View {
    let session: NightSession
    @StateObject private var store = NightStore.shared
    @State private var player: AVAudioPlayer?
    @State private var playing: UUID?
    @Environment(\.dismiss) private var dismiss

    private var current: NightSession { store.sessions.first { $0.id == session.id } ?? session }

    var body: some View {
        let s = current
        List {
            Section("Résumé") {
                let sum = NightSounds.summary(s)
                if sum.isEmpty { Text("Aucun événement repéré cette nuit.").foregroundStyle(.secondary) }
                ForEach(sum, id: \.kind) { k in
                    HStack { Text(k.kind.capitalized); Spacer(); Text("\(k.count) · \(max(1, Int(k.minutes.rounded()))) min").foregroundStyle(.secondary) }
                }
                if !s.gaps.isEmpty {
                    Text("\(s.gaps.count) coupure(s) d'écoute (appel ou autre app audio) : ces moments ne sont pas couverts.").font(.caption).foregroundStyle(Theme.warning)
                }
                if let r = s.stoppedReason { Text("Arrêt : \(r)").font(.caption).foregroundStyle(Theme.warning) }
            }
            Section("Chronologie") {
                ForEach(s.events) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(e.start.formatted(date: .omitted, time: .shortened)) · \(e.kind)").font(.subheadline)
                            Text("\(max(1, Int(e.duration))) s · confiance \(Int(e.confidence * 100)) %").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let clip = e.clip {
                            Button { play(clip, id: e.id, in: s) } label: { Image(systemName: playing == e.id ? "stop.circle.fill" : "play.circle.fill").font(.title2) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(playing == e.id ? "Arrêter l'extrait" : "Écouter l'extrait")
                        }
                    }
                    .swipeActions { Button(role: .destructive) { try? store.deleteEvent(e, in: s) } label: { Label("Supprimer", systemImage: "trash") } }
                }
            }
            Section {
                Button(role: .destructive) { try? store.delete(s); dismiss() } label: { Text("Supprimer cette nuit et ses extraits") }
            } footer: {
                Text("Événements estimés par le classifieur sonore d'Apple, sur l'appareil. Pas un diagnostic.")
            }
        }
        .navigationTitle(s.start.formatted(date: .abbreviated, time: .omitted))
        .onDisappear { player?.stop() }
    }

    private func play(_ clip: String, id: UUID, in s: NightSession) {
        if playing == id { player?.stop(); playing = nil; return }
        let url = store.folder(s).appendingPathComponent(clip)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        playing = player == nil ? nil : id
    }
}
