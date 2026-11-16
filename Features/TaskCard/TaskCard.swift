import SwiftUI

/// Карточка задачи (TaskCard) — многострочное отображение названия, даты/времени,
/// состояния SEEN, Long Press (~0.6 сек) выполнение, свайп влево удаление,
/// свайп вправо Snooze, Accessibility actions.
public struct TaskCard: View {
    // MARK: - Configuration

    public struct Configuration {
        let title: String
        let subtitle: String
        let isSeen: Bool
        let showsTomorrowBadge: Bool
        let onComplete: () -> Void
        let onSnooze: () -> Void
        let onDelete: () -> Void
        let onUndo: () -> Void
        let onDismissUndo: () -> Void

        public init(
            title: String,
            subtitle: String,
            isSeen: Bool = false,
            showsTomorrowBadge: Bool = false,
            onComplete: @escaping () -> Void,
            onSnooze: @escaping () -> Void,
            onDelete: @escaping () -> Void,
            onUndo: @escaping () -> Void,
            onDismissUndo: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.isSeen = isSeen
            self.showsTomorrowBadge = showsTomorrowBadge
            self.onComplete = onComplete
            self.onSnooze = onSnooze
            self.onDelete = onDelete
            self.onUndo = onUndo
            self.onDismissUndo = onDismissUndo
        }
    }

    // MARK: - State

    let configuration: Configuration

    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var pressTask: Swift.Task<Void, Never>?
    @State private var dragOffset: CGSize = .zero
    @State private var showUndo = false
    @State private var isCompleting = false

    // MARK: - Body

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // Background card
            cardBackground

            // Content
            cardContent
                .opacity(configuration.isSeen ? 0.6 : 1.0)

            // Progress fill on long press
            if isPressing && progress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(DesignSystem.progressFill.opacity(0.15))
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: DesignSystem.longPressDuration), value: progress)
                }
                .allowsHitTesting(false)
            }

            // Undo banner (swipe left)
            if showUndo {
                UndoBanner(
                    message: "Удалено",
                    onUndo: {
                        configuration.onUndo()
                        showUndo = false
                    },
                    onDismiss: {
                        configuration.onDismissUndo()
                        showUndo = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            // Long Press для выполнения — не блокирует скролл и свайпы.
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .simultaneousGesture(
            // Horizontal swipe для Snooze (right) и Delete (left) с undo
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    handleSwipeChanged(value)
                }
                .onEnded { value in
                    handleSwipeEnded(value)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(configuration.isSeen ? [.isSelected] : [])
        .accessibilityAction(named: "Выполнить") {
            configuration.onComplete()
        }
        .accessibilityAction(named: "Отложить на 30 мин") {
            configuration.onSnooze()
        }
        .accessibilityAction(named: "Удалить") {
            configuration.onDelete()
            // Undo через accessibility не реализуем здесь — снимок создаётся в TaskManager
        }
    }

    // MARK: - Subviews

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(DesignSystem.cardBackground)
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.cardSpacing) {
            // Title + Seen indicator
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(configuration.title)
                    .font(DesignSystem.taskTitleFont)
                    .foregroundStyle(DesignSystem.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)

                if configuration.isSeen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DesignSystem.seenIndicator)
                        .accessibilityLabel("Просмотрено")
                }

                Spacer(minLength: 8)
            }

            // Subtitle (time/date) + tomorrow badge
            HStack(spacing: 8) {
                Text(configuration.subtitle)
                    .font(DesignSystem.taskMetaFont)
                    .foregroundStyle(DesignSystem.secondaryText)

                if configuration.showsTomorrowBadge {
                    Text("Завтра")
                        .font(DesignSystem.taskMetaFont.weight(.medium))
                        .foregroundStyle(DesignSystem.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(DesignSystem.tertiaryBackground)
                        .clipShape(Capsule())
                }

                Spacer()
            }
        }
        .padding(DesignSystem.cardPadding)
    }

    // MARK: - Drag handling (Long Press progress)

    private func handleDragChanged(_ value: DragGesture.Value) {
        let translation = value.translation
        let distance = sqrt(translation.width * translation.width + translation.height * translation.height)

        // Отмена прогресса при смещении пальца > 10pt — позволяем скролл/свайпы.
        if distance > 10 {
            cancelProgress()
            return
        }

        if !isPressing {
            startPress()
        }

        // Прогресс заполнения за 0.6 сек.
        let elapsed = Date().timeIntervalSince(pressStartTime)
        progress = min(elapsed / DesignSystem.longPressDuration, 1.0)

        if progress >= 1.0 && !isCompleting {
            complete()
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        cancelProgress()
    }

    @State private var pressStartTime = Date()

    private func startPress() {
        isPressing = true
        isCompleting = false
        pressStartTime = Date()
        progress = 0

        // Тактильный отклик в начале нажатия
        DesignSystem.impactLight.prepare()
        DesignSystem.impactLight.impactOccurred()

        pressTask = Swift.Task {
            try? await Swift.Task.sleep(for: .seconds(DesignSystem.longPressDuration + 0.1))
            guard !Swift.Task.isCancelled else { return }
            await MainActor.run { cancelProgress() }
        }
    }

    private func cancelProgress() {
        guard isPressing else { return }
        pressTask?.cancel()
        pressTask = nil
        isPressing = false
        progress = 0
    }

    private func complete() {
        guard !isCompleting else { return }
        isCompleting = true
        progress = 1.0

        // Тактильный отклик при завершении
        DesignSystem.impactMedium.impactOccurred()

        withAnimation(.easeOut(duration: 0.2)) {
            progress = 0
        }

        pressTask?.cancel()
        pressTask = nil
        isPressing = false

        configuration.onComplete()
    }

    // MARK: - Swipe handling (Snooze right, Delete left)

    private func handleSwipeChanged(_ value: DragGesture.Value) {
        if showUndo { return }

        let translation = value.translation.width
        // Порог для свайпа
        if abs(translation) > 50 {
            dragOffset = CGSize(width: translation, height: 0)
        }
    }

    private func handleSwipeEnded(_ value: DragGesture.Value) {
        let translation = value.translation.width
        let velocity = value.velocity.width

        if translation < -80 || velocity < -500 {
            // Swipe left — Delete
            triggerDelete()
        } else if translation > 80 || velocity > 500 {
            // Swipe right — Snooze
            triggerSnooze()
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = .zero
        }
    }

    private func triggerDelete() {
        configuration.onDelete()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showUndo = true
        }
    }

    private func triggerSnooze() {
        // Тактильный отклик для snooze
        DesignSystem.impactLight.impactOccurred()
        configuration.onSnooze()
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = configuration.title
        if !configuration.subtitle.isEmpty {
            label += ", \(configuration.subtitle)"
        }
        if configuration.isSeen {
            label += ", просмотрено"
        }
        if configuration.showsTomorrowBadge {
            label += ", завтра"
        }
        return label
    }
}