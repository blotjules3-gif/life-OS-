import SwiftUI
import SwiftData

// MARK: - Modèles Unifiés pour la Timeline 24H

enum TimelineItemKind {
    case habit(Habit)
    case task(TodoItem)
}

struct TimelineItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: Int
    let hour: Int
    let minute: Int
    let isDone: Bool
    let streak: Int
    let kind: TimelineItemKind

    var timeFormatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var minuteOfDay: Int {
        hour * 60 + minute
    }

    var timeRatio: CGFloat {
        CGFloat(minuteOfDay) / 1440.0
    }
}

struct TimelineCluster: Identifiable {
    let id: String
    let averageMinute: Int
    let items: [TimelineItem]

    var timeRatio: CGFloat {
        CGFloat(averageMinute) / 1440.0
    }
}

// MARK: - HabitTrackerTimelineView

struct HabitTrackerTimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.colorScheme) private var colorScheme
    @Query private var allHabits: [Habit]
    @Query private var allTodos: [TodoItem]

    var showHeader: Bool = true
    var isEmbedded: Bool = false

    // État temporel temps réel
    @State private var now = Date.now
    private let liveTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    // Modales de création / édition
    @State private var showNewHabitSheet = false
    @State private var showNewTodoSheet = false
    @State private var targetHourForNewItem: Int = 9
    @State private var editingHabit: Habit? = nil
    @State private var showSlotActionDialog = false
    @State private var selectedSlotHour: Int = 12

    // Tâches et Habitudes actives du jour
    private var activeHabits: [Habit] {
        allHabits.filter { !$0.isPending && !$0.isArchived && $0.isActive(on: now) }
    }

    private var todayTodos: [TodoItem] {
        allTodos.filter { todo in
            if let due = todo.due {
                return Calendar.current.isDate(due, inSameDayAs: now) || (!todo.done && due < now)
            }
            if let block = todo.blockStart {
                return Calendar.current.isDate(block, inSameDayAs: now)
            }
            return todo.applies(to: now)
        }
    }

    // Conversion en éléments unifiés de timeline
    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []

        // 1. Habitudes
        for h in activeHabits {
            let isDone = h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: now) }
            var streak = 0
            var checkDay = Calendar.current.startOfDay(for: now)
            if !isDone {
                checkDay = Calendar.current.date(byAdding: .day, value: -1, to: checkDay) ?? checkDay
            }
            while h.completions.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: checkDay) }) {
                streak += 1
                checkDay = Calendar.current.date(byAdding: .day, value: -1, to: checkDay) ?? checkDay
            }

            items.append(
                TimelineItem(
                    id: "habit-\(h.persistentModelID)",
                    title: h.name,
                    subtitle: nil,
                    icon: h.icon,
                    colorHex: h.colorHex,
                    hour: min(max(h.scheduledHour, 0), 23),
                    minute: min(max(h.scheduledMinute, 0), 59),
                    isDone: isDone,
                    streak: streak,
                    kind: .habit(h)
                )
            )
        }

        // 2. Tâches du jour (qui ont un horaire prévu)
        for t in todayTodos {
            var taskHour = 10
            var taskMinute = 0
            if let block = t.blockStart {
                taskHour = Calendar.current.component(.hour, from: block)
                taskMinute = Calendar.current.component(.minute, from: block)
            } else if let due = t.due {
                taskHour = Calendar.current.component(.hour, from: due)
                taskMinute = Calendar.current.component(.minute, from: due)
            } else {
                // Tâche non horodatée : on ne surcharge pas la frise
                continue
            }

            items.append(
                TimelineItem(
                    id: "task-\(t.persistentModelID)",
                    title: t.title,
                    subtitle: t.project.isEmpty ? nil : t.project,
                    icon: "checklist",
                    colorHex: 0x618EF1,
                    hour: min(max(taskHour, 0), 23),
                    minute: min(max(taskMinute, 0), 59),
                    isDone: t.done,
                    streak: 0,
                    kind: .task(t)
                )
            )
        }

        return items.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    // Regroupement par clusters pour éviter les chevauchements verticaux
    private var timelineClusters: [TimelineCluster] {
        let sorted = timelineItems
        guard !sorted.isEmpty else { return [] }

        var clusters: [TimelineCluster] = []
        var currentBatch: [TimelineItem] = [sorted[0]]

        for item in sorted.dropFirst() {
            if let last = currentBatch.last, (item.minuteOfDay - last.minuteOfDay) <= 45 {
                currentBatch.append(item)
            } else {
                let avg = currentBatch.map(\.minuteOfDay).reduce(0, +) / currentBatch.count
                clusters.append(TimelineCluster(id: "cluster-\(avg)-\(currentBatch[0].id)", averageMinute: avg, items: currentBatch))
                currentBatch = [item]
            }
        }

        if !currentBatch.isEmpty {
            let avg = currentBatch.map(\.minuteOfDay).reduce(0, +) / currentBatch.count
            clusters.append(TimelineCluster(id: "cluster-\(avg)-\(currentBatch[0].id)", averageMinute: avg, items: currentBatch))
        }

        return clusters
    }

    // Calcul du temps actuel
    private var currentMinuteOfDay: Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        return h * 60 + m
    }

    private var currentTimeRatio: CGFloat {
        CGFloat(currentMinuteOfDay) / 1440.0
    }

    private var currentTimeFormatted: String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        return String(format: "%02d:%02d", h, m)
    }

    // Statistiques du jour
    private var validatedCount: Int {
        timelineItems.filter(\.isDone).count
    }

    private var totalItemsCount: Int {
        timelineItems.count
    }

    // Détection des moments creux (plages libres >= 3h)
    private var freeSlots: [Int] {
        let occupiedHours = Set(timelineItems.map(\.hour))
        // Cherche des heures claires dans les créneaux typiques d'activité (8h à 22h)
        return [9, 11, 14, 16, 18, 20].filter { !occupiedHours.contains($0) && !occupiedHours.contains($0 - 1) && !occupiedHours.contains($0 + 1) }
    }

    var body: some View {
        ZStack {
            if !isEmbedded {
                Theme.background.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if showHeader {
                    // En-tête Apple Preview supérieur avec statistiques et actions rapides
                    headerToolbar
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                }

                // Frise chronologique 24H continue SANS DÉFILEMENT
                GeometryReader { geo in
                    let totalHeight = geo.size.height
                    let timelineTop: CGFloat = 20
                    let timelineBottom: CGFloat = totalHeight - 20
                    let effectiveHeight = max(timelineBottom - timelineTop, 100)

                    ZStack(alignment: .topLeading) {
                        // 1. Grille d'arrière-plan et marqueurs horaires 0h - 24h
                        hoursBackgroundGrid(
                            totalHeight: totalHeight,
                            timelineTop: timelineTop,
                            effectiveHeight: effectiveHeight,
                            width: geo.size.width
                        )

                        // 2. Créneaux libres suggérés ("Ajouter dans les moments creux")
                        freeSlotsOverlay(
                            timelineTop: timelineTop,
                            effectiveHeight: effectiveHeight,
                            width: geo.size.width
                        )

                        // 3. Éléments (Habitudes & Tâches) positionnés à leur heure exacte
                        itemsOverlay(
                            timelineTop: timelineTop,
                            effectiveHeight: effectiveHeight,
                            width: geo.size.width
                        )

                        // 4. Curseur Heure Actuelle avec Flèche en Temps Réel
                        currentTimeIndicator(
                            timelineTop: timelineTop,
                            effectiveHeight: effectiveHeight,
                            width: geo.size.width
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Clic direct sur la frise pour ajouter un élément à cette heure !
                        let tappedRatio = (location.y - timelineTop) / effectiveHeight
                        let clampedRatio = min(max(tappedRatio, 0.0), 1.0)
                        let hour = Int(round(clampedRatio * 24.0))
                        selectedSlotHour = min(max(hour, 0), 23)
                        showSlotActionDialog = true
                        Haptics.tap()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .onReceive(liveTimer) { _ in
            now = Date.now
        }
        .confirmationDialog(
            "Créneau de \(String(format: "%02dh00", selectedSlotHour))",
            isPresented: $showSlotActionDialog,
            titleVisibility: .visible
        ) {
            Button("Ajouter une habitude à \(selectedSlotHour)h") {
                targetHourForNewItem = selectedSlotHour
                showNewHabitSheet = true
            }
            Button("Ajouter une tâche à \(selectedSlotHour)h") {
                targetHourForNewItem = selectedSlotHour
                showNewTodoSheet = true
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce créneau est libre. Planifie une habitude ou une tâche pour enrichir ta journée.")
        }
        .sheet(isPresented: $showNewHabitSheet) {
            HabitEditor(initialHour: targetHourForNewItem)
        }
        .sheet(item: $editingHabit) { h in
            HabitEditor(editingHabit: h)
        }
        .sheet(isPresented: $showNewTodoSheet) {
            TodoEditor(initialDue: targetDateForNewTodo)
        }
    }

    private var targetDateForNewTodo: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = targetHourForNewItem
        comps.minute = 0
        return cal.date(from: comps) ?? now
    }

    // MARK: - En-tête Toolbar

    private var headerToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text("Habit Tracker 24h")
                        .font(AppFont.sans(size: 20, weight: .black))
                        .foregroundStyle(Color.primary)
                }

                HStack(spacing: 6) {
                    Text("\(validatedCount) sur \(totalItemsCount) validés")
                        .font(AppFont.body(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.85))

                    Text("·")
                        .foregroundStyle(Color.secondary)

                    Text("Minuit à 24h · Vue continue")
                        .font(AppFont.body(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }

            Spacer()

            // Boutons d'ajout rapide dans les moments libres
            HStack(spacing: 8) {
                Button {
                    targetHourForNewItem = Calendar.current.component(.hour, from: now)
                    showNewHabitSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Habitude")
                            .font(AppFont.heading(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .applePreviewPill(height: 34)

                Button {
                    targetHourForNewItem = Calendar.current.component(.hour, from: now)
                    showNewTodoSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checklist")
                            .font(.system(size: 12, weight: .bold))
                        Text("Tâche")
                            .font(AppFont.heading(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .applePreviewPill(height: 34)
            }
        }
    }

    // MARK: - Grille d'Arrière-Plan & Marqueurs Horaires (0h - 24h)

    private func hoursBackgroundGrid(
        totalHeight: CGFloat,
        timelineTop: CGFloat,
        effectiveHeight: CGFloat,
        width: CGFloat
    ) -> some View {
        // Principaux repères : 00h (Minuit), 04h, 08h, 12h (Midi), 16h, 20h, 24h
        let markerHours = [0, 4, 8, 12, 16, 20, 24]

        return ZStack(alignment: .topLeading) {
            // Axe vertical de la timeline
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.primary.opacity(0.12), location: 0.0),
                            .init(color: Color.primary.opacity(0.20), location: 0.5),
                            .init(color: Color.primary.opacity(0.12), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: effectiveHeight)
                .position(x: 58, y: timelineTop + effectiveHeight / 2)

            // Lignes horaires de repère et libellés
            ForEach(markerHours, id: \.self) { hour in
                let ratio = CGFloat(hour) / 24.0
                let y = timelineTop + ratio * effectiveHeight
                let isNoon = (hour == 12)
                let isMidnight = (hour == 0 || hour == 24)

                Group {
                    // Libellé de l'heure
                    HStack(spacing: 4) {
                        Text(hourLabel(for: hour))
                            .font(AppFont.body(size: isNoon || isMidnight ? 11 : 10, weight: isNoon ? .black : .bold))
                            .foregroundStyle(isNoon ? Color.primary : Color.secondary.opacity(0.85))
                            .frame(width: 48, alignment: .trailing)

                        // Petit tiret marqueur
                        Rectangle()
                            .fill(isNoon ? Color.primary.opacity(0.60) : Color.primary.opacity(0.20))
                            .frame(width: isNoon ? 10 : 6, height: isNoon ? 2 : 1)
                    }
                    .position(x: 27, y: y)

                    // Ligne horizontale translucide de fond
                    Rectangle()
                        .fill(isNoon ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                        .frame(width: max(width - 66, 0), height: isNoon ? 1.5 : 0.8)
                        .position(x: 60 + max(width - 66, 0) / 2, y: y)
                }
            }
        }
    }

    private func hourLabel(for hour: Int) -> String {
        switch hour {
        case 0: return "00:00"
        case 12: return "12:00"
        case 24: return "24:00"
        default: return String(format: "%02dh", hour)
        }
    }

    // MARK: - Curseur Heure Actuelle avec Flèche en Temps Réel

    private func currentTimeIndicator(
        timelineTop: CGFloat,
        effectiveHeight: CGFloat,
        width: CGFloat
    ) -> some View {
        let y = timelineTop + currentTimeRatio * effectiveHeight

        return Group {
            // Ligne horizontale lumineuse marquant le moment présent
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.85),
                            Color.primary.opacity(0.40),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(width - 60, 0), height: 1.5)
                .position(x: 60 + max(width - 60, 0) / 2, y: y)

            // Badge avec l'heure actuelle et la FLÈCHE pointant vers la droite
            HStack(spacing: 4) {
                // Pastille de l'heure
                Text(currentTimeFormatted)
                    .font(AppFont.heading(size: 11, weight: .black))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white : Color.primary)
                    )

                // La flèche pointant vers l'axe de la journée
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                    .offset(x: -2)
            }
            .position(x: 32, y: y)
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
    }

    // MARK: - Créneaux Libres Détectés

    private func freeSlotsOverlay(
        timelineTop: CGFloat,
        effectiveHeight: CGFloat,
        width: CGFloat
    ) -> some View {
        ForEach(freeSlots.prefix(2), id: \.self) { slotHour in
            let ratio = CGFloat(slotHour) / 24.0
            let y = timelineTop + ratio * effectiveHeight

            Button {
                selectedSlotHour = slotHour
                showSlotActionDialog = true
                Haptics.tap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Créneau libre \(slotHour)h · Ajouter")
                        .font(AppFont.body(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.secondary.opacity(0.70))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
            }
            .buttonStyle(.plain)
            .position(x: 150, y: y)
        }
    }

    // MARK: - Éléments Positionnés (Clusters d'Habitudes & Tâches)

    private func itemsOverlay(
        timelineTop: CGFloat,
        effectiveHeight: CGFloat,
        width: CGFloat
    ) -> some View {
        ForEach(timelineClusters) { cluster in
            let y = timelineTop + cluster.timeRatio * effectiveHeight
            let availableWidth = max(width - 76, 120)

            HStack(spacing: 8) {
                ForEach(cluster.items) { item in
                    timelineItemCard(item: item)
                }
            }
            .frame(width: availableWidth, alignment: .leading)
            .position(x: 68 + availableWidth / 2, y: y)
        }
    }

    // MARK: - Carte Élément (Habitude ou Tâche) Liquid Glass Apple Preview

    private func timelineItemCard(item: TimelineItem) -> some View {
        HStack(spacing: 8) {
            // Bouton de validation rapide (Cochable immédiatement)
            Button {
                toggleItemDone(item)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(item.isDone ? Color.primary : Color.secondary.opacity(0.40))
            }
            .buttonStyle(.plain)

            // Icône
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: UInt(item.colorHex)).opacity(item.isDone ? 0.20 : 0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary)
            }

            // Titre & Heure
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(AppFont.sans(size: 12, weight: .bold))
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    .strikethrough(item.isDone, color: Color.secondary.opacity(0.40))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.timeFormatted)
                        .font(AppFont.body(size: 9, weight: .semibold))
                        .foregroundStyle(Color.secondary)

                    if item.streak > 0 {
                        Text("· 🔥 \(item.streak)")
                            .font(AppFont.body(size: 9, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.80))
                    }
                }
            }

            Spacer(minLength: 0)

            // Clic sur options / édition pour les habitudes
            if case .habit(let h) = item.kind {
                Button {
                    editingHabit = h
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(0.60))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .applePreviewCard(cornerRadius: 14)
    }

    // MARK: - Validation Rapide

    private func toggleItemDone(_ item: TimelineItem) {
        Haptics.tap()
        switch item.kind {
        case .habit(let habit):
            if let idx = habit.completions.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }) {
                habit.completions.remove(at: idx)
            } else {
                habit.completions.append(HabitCompletion(date: now))
            }
            do {
                try ctx.save()
            } catch {
                AppLog.data.error("save habit completion error: \(error.localizedDescription)")
            }

        case .task(let todo):
            todo.done.toggle()
            do {
                try ctx.save()
            } catch {
                AppLog.data.error("save task done error: \(error.localizedDescription)")
            }
        }
    }
}
