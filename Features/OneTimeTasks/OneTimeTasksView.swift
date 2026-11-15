import SwiftUI

/// Экран вкладки «Разовые» задачи.
public struct OneTimeTasksView: View {
    // MARK: - Input

    let tasks: [OneTimeTaskItem]
    let onTaskTap: (OneTimeTaskItem) -> Void
    let onComplete: (UUID) -> Void
    let onSnooze: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onUndo: () -> Void
    let onDismissUndo: () -> Void
    let onAdd: () -> Void

    // MARK: - State

    @State private var showEditor = false
    @State private var undoItem: OneTimeTaskItem?
    @State private var showUndoBanner = false

    // MARK: - Body

    public init(
        tasks: [OneTimeTaskItem],
        onTaskTap: @escaping (OneTimeTaskItem) -> Void,
        onComplete: @escaping (UUID) -> Void,
        onSnooze: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onUndo: @escaping () -> Void,
        onDismissUndo: @escaping () -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.tasks = tasks
        self.onTaskTap = onTaskTap
        self.onComplete = onComplete
        self.onSnooze = onSnooze
        self.onDelete = onDelete
        self.onUndo = onUndo
        self.onDismissUndo = onDismissUndo
        self.onAdd = onAdd
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            List {
                if tasks.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(tasks) { item in
                        TaskCard(
                            configuration: TaskCard.Configuration(
                                title: item.title,
                                subtitle: item.formattedDate,
                                isSeen: item.isSeen,
                                showsTomorrowBadge: item.isTomorrow,
                                onComplete: { onComplete(item.id) },
                                onSnooze: { onSnooze(item.id) },
                                onDelete: {
                                    undoItem = item
                                    onDelete(item.id)
                                },
                                onUndo: {
                                    onUndo()
                                    showUndoBanner = false
                                },
                                onDismissUndo: {
                                    onDismissUndo()
                                    showUndoBanner = false
                                }
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .contentShape(Rectangle())
                        .onTapGesture { onTaskTap(item) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.background)

            // Floating Add Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(DesignSystem.primaryText)
                            .frame(width: 56, height: 56)
                            .background(DesignSystem.cardBackground)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .accessibilityLabel("Добавить разовую задачу")
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }

            // Undo Banner
            if showUndoBanner {
                UndoBanner(
                    message: "Удалено",
                    onUndo: {
                        onUndo()
                        showUndoBanner = false
                    },
                    onDismiss: {
                        onDismissUndo()
                        showUndoBanner = false
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showEditor) {
            TaskEditor(
                mode: .createOneTime,
                onSave: { draft in
                    if let draft { /* сохранение через VM */ }
                    showEditor = false
                },
                onSaveRegular: { _ in },
                onCancel: { showEditor = false }
            )
        }
        .onChange(of: undoItem) { _, new in
            if new != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showUndoBanner = true
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.sectionSpacing) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DesignSystem.tertiaryText)

            VStack(spacing: 8) {
                Text("Разовых задач нет")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryText)

                Text("Нажмите «+», чтобы создать напоминание на конкретную дату и время.")
                    .font(DesignSystem.taskMetaFont)
                    .foregroundStyle(DesignSystem.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - View Model Item

/// Прослойка для UI — легкая модель без SwiftData зависимостей.
public struct OneTimeTaskItem: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let scheduledAt: Date
    public let isSeen: Bool

    public init(id: UUID, title: String, scheduledAt: Date, isSeen: Bool) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.isSeen = isSeen
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.locale = Locale.current
        return formatter.string(from: scheduledAt)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(scheduledAt)
    }
}