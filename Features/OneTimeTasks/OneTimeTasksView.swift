import SwiftUI

/// Экран вкладки «Разовые» задачи.
public struct OneTimeTasksView: View {
    @ObservedObject var viewModel: OneTimeTasksViewModel
    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: OneTimeTasksViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    if viewModel.tasks.isEmpty {
                        // Combined empty state with permission banner
                        combinedEmptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.tasks) { item in
                            TaskCard(
                                configuration: TaskCard.Configuration(
                                    title: item.title,
                                    subtitle: item.formattedDate,
                                    isSeen: item.isSeen,
                                    showsTomorrowBadge: item.isTomorrow,
                                    onComplete: { Task { await viewModel.onComplete(item.id) } },
                                    onSnooze: { Task { await viewModel.onSnooze(item.id) } },
                                    onDelete: { Task { await viewModel.onDelete(item.id) } },
                                    onUndo: { Task { await viewModel.onUndo() } },
                                    onDismissUndo: { viewModel.onDismissUndo() }
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.onTaskTap(item) }
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
                        Button(action: { viewModel.onAdd() }) {
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
                if viewModel.showUndoBanner {
                    UndoBanner(
                        message: "Удалено",
                        onUndo: { viewModel.onUndo() },
                        onDismiss: { viewModel.onDismissUndo() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $viewModel.showCreateSheet) {
            TaskEditor(
                mode: .createOneTime,
                onSave: { draft in
                    if let draft {
                        Task {
                            try? await viewModel.manager.createOneTime(title: draft.title, scheduledAt: draft.scheduledAt)
                            await viewModel.load()
                        }
                    }
                },
                onSaveRegular: { _ in },
                onCancel: { viewModel.showCreateSheet = false }
            )
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task {
                await viewModel.refreshNotificationStatus()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.refreshNotificationStatus() }
            }
        }
    }

    // MARK: - Combined Empty State

    private var combinedEmptyState: some View {
        VStack(spacing: DesignSystem.sectionSpacing) {
            // Permission banner (only when not authorized)
            if viewModel.notificationAuthorizationStatus == .notDetermined {
                permissionBanner
            } else if viewModel.notificationAuthorizationStatus == .denied {
                deniedBanner
            }

            // Empty state
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

    private var permissionBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DesignSystem.primaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Уведомления отключены")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryText)

                    Text("Напоминания не сработают без разрешения.")
                        .font(DesignSystem.taskMetaFont)
                        .foregroundStyle(DesignSystem.secondaryText)
                }

                Spacer()

                Button(action: { Task { await viewModel.requestNotificationPermission() } }) {
                    Text("Разрешить")
                        .font(DesignSystem.buttonFont)
                        .foregroundStyle(DesignSystem.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DesignSystem.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(DesignSystem.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.cardBackground)
            .overlay(
                Rectangle()
                    .fill(DesignSystem.separator)
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
    }

    private var deniedBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DesignSystem.tertiaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Уведомления запрещены")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryText)

                    Text("Включите их в настройках, чтобы напоминания работали.")
                        .font(DesignSystem.taskMetaFont)
                        .foregroundStyle(DesignSystem.secondaryText)
                }

                Spacer()

                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Настройки")
                        .font(DesignSystem.buttonFont)
                        .foregroundStyle(DesignSystem.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DesignSystem.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(DesignSystem.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.cardBackground)
            .overlay(
                Rectangle()
                    .fill(DesignSystem.separator)
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
    }
}