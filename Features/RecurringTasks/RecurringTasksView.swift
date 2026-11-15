import SwiftUI

/// Экран вкладки «Регулярные» задачи.
public struct RecurringTasksView: View {
    // MARK: - Input

    let templates: [RegularTaskItem]
    let onTaskTap: (RegularTaskItem) -> Void
    let onComplete: (UUID) -> Void
    let onSnooze: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onUndo: () -> Void
    let onDismissUndo: () -> Void
    let onAdd: () -> Void

    // MARK: - State

    @State private var showEditor = false
    @State private var undoItem: RegularTaskItem?
    @State private var showUndoBanner = false

    // MARK: - Body

    public init(
        templates: [RegularTaskItem],
        onTaskTap: @escaping (RegularTaskItem) -> Void,
        onComplete: @escaping (UUID) -> Void,
        onSnooze: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onUndo: @escaping () -> Void,
        onDismissUndo: @escaping () -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.templates = templates
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
                if templates.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(templates) { item in
                        TaskCard(
                            configuration: TaskCard.Configuration(
                                title: item.title,
                                subtitle: item.formattedTime,
                                isSeen: item.isSeen,
                                showsTomorrowBadge: false,
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
                    .accessibilityLabel("Добавить регулярную задачу")
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
                mode: .createRegular,
                onSave: { _ in },
                onSaveRegular: { draft in
                    if let draft { /* сохранение через VM */ }
                    showEditor = false
                },
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
            Image(systemName: "repeat.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DesignSystem.tertiaryText)

            VStack(spacing: 8) {
                Text("Регулярных задач нет")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryText)

                Text("Нажмите «+», чтобы создать ежедневное напоминание.")
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

/// Прослойка для UI — регулярная задача с текущим дневным экземпляром.
public struct RegularTaskItem: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let localHour: Int
    public let localMinute: Int
    public let isEnabled: Bool
    public let instanceState: ReminderState?
    public let instanceSnoozedUntil: Date?

    public init(
        id: UUID,
        title: String,
        localHour: Int,
        localMinute: Int,
        isEnabled: Bool,
        instanceState: ReminderState? = nil,
        instanceSnoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.localHour = localHour
        self.localMinute = localMinute
        self.isEnabled = isEnabled
        self.instanceState = instanceState
        self.instanceSnoozedUntil = instanceSnoozedUntil
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        let date = Calendar.current.date(bySettingHour: localHour, minute: localMinute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }

    var isSeen: Bool {
        instanceState == .seen
    }
}