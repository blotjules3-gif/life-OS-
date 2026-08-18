import SwiftUI
import SwiftData

/// Vue liste des conversations passées, groupées par jour.
///
/// Chaque `AIMessage` a une date. On les groupe par `startOfDay`, on trie par
/// date décroissante et on affiche le premier message user comme titre du jour.
/// Tap → replay read-only de la journée.
struct CoachHistoryView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \AIMessage.date, order: .reverse) private var allMessages: [AIMessage]

    private struct Day: Identifiable {
        let id: Date
        let messages: [AIMessage]

        var displayDate: String {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            if Calendar.current.isDateInToday(id) { return "Aujourd'hui" }
            if Calendar.current.isDateInYesterday(id) { return "Hier" }
            fmt.dateFormat = "EEEE d MMMM"
            return fmt.string(from: id).capitalized
        }

        var preview: String {
            let userMsg = messages.first(where: { $0.role == "user" })
            let text = userMsg?.text ?? messages.first?.text ?? "Conversation"
            return String(text.prefix(80))
        }

        var count: Int { messages.count }
    }

    private var days: [Day] {
        let grouped = Dictionary(grouping: allMessages) { msg in
            Calendar.current.startOfDay(for: msg.date)
        }
        return grouped
            .map { Day(id: $0.key, messages: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    emptyState
                } else {
                    dayList
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Aucune conversation")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tes conversations avec le coach apparaîtront ici jour par jour.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private var dayList: some View {
        List(days) { day in
            NavigationLink {
                CoachHistoryDayView(dayLabel: day.displayDate, messages: day.messages)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(day.displayDate)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(day.count) msg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(day.preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Replay read-only d'une journée de conversation.
private struct CoachHistoryDayView: View {
    let dayLabel: String
    let messages: [AIMessage]

    @AppStorage(AppStorageKeys.appTheme) private var appThemeRaw = "classic"
    private var accent: Color { (AppTheme(rawValue: appThemeRaw) ?? .classic).accent }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(messages) { msg in
                    AIAssistantMessageRow(
                        message: AIAssistantViewModel.DisplayMessage(from: msg),
                        accent: accent,
                        reveal: false
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(dayLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}
