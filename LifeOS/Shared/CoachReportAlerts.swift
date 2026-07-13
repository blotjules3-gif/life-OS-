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
        // Depuis Option C, les signalements sont écrits en local dans un
        // fichier JSON du sandbox app. Ils peuvent être partagés/exportés par
        // l'utilisateur via l'écran d'export. Aucun réseau, aucun envoi tiers.
        writeLocalReport(content: text, conversationID: convID, reason: "user_flagged")
        didSubmit = true
    }

    private func writeLocalReport(content: String, conversationID: String?, reason: String) {
        let entry: [String: Any] = [
            "reported_at": ISO8601DateFormatter().string(from: Date()),
            "conversation_id": conversationID ?? "",
            "reason": reason,
            "content": String(content.prefix(4000))
        ]
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return }
        let file = dir.appendingPathComponent("coach_reports.jsonl")
        var line = (try? JSONSerialization.data(withJSONObject: entry)) ?? Data()
        line.append(0x0A) // newline
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file, options: .atomic)
        }
    }
}
