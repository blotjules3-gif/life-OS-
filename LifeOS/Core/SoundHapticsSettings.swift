//
//  SoundHapticsSettings.swift
//
//  Réglages Sons & vibrations.
//  Les deux interrupteurs pilotent des clés déjà lues ailleurs :
//    - timerSoundEnabled → TabataView (bips de transition)
//    - hapticsEnabled    → CountdownTimer / Haptics (retours haptiques)
//  Sans cet écran ces deux clés existaient sans aucun moyen de les changer.
//

import SwiftUI

struct SoundHapticsSettingsView: View {
    @AppStorage("timerSoundEnabled") private var timerSound = true
    @AppStorage("hapticsEnabled")    private var haptics = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $timerSound) {
                    Label("Sons du minuteur", systemImage: "timer")
                }
                Button {
                    TabataSound.shared.work()
                } label: {
                    Label("Tester le son", systemImage: "play.circle.fill")
                }
                .disabled(!timerSound)
            } header: {
                Text("Minuteur")
            } footer: {
                Text("Bips au décompte, au début d'effort ou de repos, et en fin de séance (Tabata, HIIT). Ils sortent sur l'enceinte, les écouteurs ou le Bluetooth connecté, même en silencieux.")
            }

            Section {
                Toggle(isOn: $haptics.animation()) {
                    Label("Vibrations", systemImage: "iphone.radiowaves.left.and.right")
                }
                .onChange(of: haptics) { _, on in if on { Haptics.tap() } }
            } footer: {
                Text("Retours haptiques dans toute l'app : appuis, validations, transitions du minuteur.")
            }
        }
        .navigationTitle("Sons & vibrations")
        .navigationBarTitleDisplayMode(.inline)
    }
}
