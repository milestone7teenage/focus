import SwiftUI

/// Экран вкладки «Регулярные» задачи.
public struct RecurringTasksView: View {
    let templates: [RegularTaskItem]
    @Binding var showUndoBanner: Bool
    let onTaskTap: (RegularTaskItem) -> Void
    let onComplete: (UUID) -> Void
    let onSnooze: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onUndo: () -> Void
    let onDismissUndo: () -> Void
    let onAdd: () -> Void
    let notificationPermissionDenied: Bool

    public init(
        templates: [RegularTaskItem],
        showUndoBanner: Binding<Bool>,
        onTaskTap: @escaping (RegularTaskItem) -> Void,
        onComplete: @escaping (UUID) -> Void,
        onSnooze: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onUndo: @escaping () -> Void,
        onDismissUndo: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        notificationPermissionDenied: Bool
    ) {
        self.templates = templates
        self._showUndoBanner = showUndoBanner
        self.onTaskTap = onTaskTap
        self.onComplete = onComplete
        self.onSnooze = onSnooze
        self.onDelete = onDelete
        self.onUndo = onUndo
        self.onDismissUndo = onDismissUndo
        self.onAdd = onAdd
        self.notificationPermissionDenied = notificationPermissionDenied
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
                                onDelete: { onDelete(item.id) },
                                onUndo: { onUndo() },
                                onDismissUndo: { onDismissUndo() }
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
            .overlay {
                if notificationPermissionDenied && templates.isEmpty {
                    permissionOverlay
                }
            }

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
                    onUndo: { onUndo() },
                    onDismiss: { onDismissUndo() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

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

    private var permissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DesignSystem.tertiaryText)

            VStack(spacing: 8) {
                Text("Уведомления отключены")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryText)

                Text("Напоминания не сработают без разрешения на уведомления.")
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