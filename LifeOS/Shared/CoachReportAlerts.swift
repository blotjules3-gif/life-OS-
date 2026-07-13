import SwiftUI

// Signalement d'un message coach (Guideline App Store 1.2).
// Mutualise le double alert "confirmer / merci" partagé entre ModuleChatView
// et AIAssistantView : chacune passe simplement son type de message et l'ID
// de conversation courant.

extension View {
    func coachReportAlerts<M: Identifiable>(
        for target: Binding<M?>,
        content: @escaping (M) -> String,
        conversationID: @escaping () -> String?
    ) -> some View {
        modifier(CoachReportAlerts(target: target, content: content, conversationID: conversationID))
    }
}

private struct CoachReportAlerts<M: Identifiable>: ViewModifier {
    @Binding var target: M?
    let content: (M) -> String
    let conversationID: () -> String?
    @State private var didSubmit = false

    func body(content view: Content) -> some View {
        view
            .alert(
                "Signaler cette réponse ?",
                isPresented: Binding(
                    get: { target != nil },
                    set: { if !$0 { target = nil } }
                ),
                presenting: target
            ) { msg in
                Button("Signaler", role: .destructive) { submit(msg) }
                Button("Annuler", role: .cancel) { target = nil }
            } message: { _ in
                Text("Nous relisons chaque signalement pour bloquer les réponses inappropriées.")
            }
            .alert("Signalement envoyé", isPresented: $didSubmit) {
                Button("OK") { didSubmit = false }
            } message: {
                Text("Merci, nous allons relire cette réponse.")
            }
    }

    private func submit(_ message: M) {
        let text = content(message)
        let convID = conversationID()
        target = nil
        Haptics.tap()
        Task {
            try? await AgentAPI.shared.reportMessage(
                conversationID: convID,
                messageContent: text,
                reason: "user_flagged"
            )
            didSubmit = true
        }
    }
}
