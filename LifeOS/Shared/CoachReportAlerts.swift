import SwiftUI

// Guideline App Store 1.2 — signalement d'un message coach (confirmation + accusé).

extension View {
    func coachReportAlerts<M: Identifiable>(
        for target: Binding<M?>,
        messageText: @escaping (M) -> String,
        conversationID: @escaping () -> String?
    ) -> some View {
        modifier(CoachReportAlerts(target: target, messageText: messageText, conversationID: conversationID))
    }
}

private struct CoachReportAlerts<M: Identifiable>: ViewModifier {
    @Binding var target: M?
    let messageText: (M) -> String
    let conversationID: () -> String?
    @State private var didSubmit = false

    func body(content: Content) -> some View {
        content
            .alert(
                "Signaler cette réponse ?",
                isPresented: Binding(
                    get: { target != nil },
                    set: { if !$0 { target = nil } }
                ),
                presenting: target
            ) { message in
                Button("Signaler", role: .destructive) { submit(message) }
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
        let text = messageText(message)
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
