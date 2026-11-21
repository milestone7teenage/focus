import SwiftUI

/// Компактный modal/sheet для создания/редактирования задачи.
/// Разовые: название + DatePicker (дата ограничена от сегодня).
/// Регулярные: название + TimePicker.
public struct TaskEditor: View {
    public enum Mode: Sendable {
        case createOneTime
        case createRegular
        case editOneTime(existing: OneTimeTaskDraft)
        case editRegular(existing: RegularTaskDraft)
    }

    public struct OneTimeTaskDraft: Sendable {
        var title: String
        var scheduledAt: Date
    }

    public struct RegularTaskDraft: Sendable {
        var title: String
        var localHour: Int
        var localMinute: Int
    }

    // MARK: - Input

    let mode: Mode
    let onSave: (OneTimeTaskDraft?) -> Void
    let onSaveRegular: (RegularTaskDraft?) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var title: String = ""
    @State private var scheduledAt: Date = .now
    @State private var localHour: Int = 9
    @State private var localMinute: Int = 0
    @FocusState private var isTitleFocused: Bool

    // MARK: - Computed

    private var isOneTime: Bool {
        switch mode {
        case .createOneTime, .editOneTime: return true
        case .createRegular, .editRegular: return false
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    public init(
        mode: Mode,
        onSave: @escaping (OneTimeTaskDraft?) -> Void,
        onSaveRegular: @escaping (RegularTaskDraft?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onSaveRegular = onSaveRegular
        self.onCancel = onCancel

        // Initialize state from mode
        switch mode {
        case .createOneTime:
            _scheduledAt = State(initialValue: Date(timeIntervalSinceNow: 3600).roundedToNextQuarterHour())
        case .createRegular:
            _localHour = State(initialValue: 9)
            _localMinute = State(initialValue: 0)
        case .editOneTime(let draft):
            _title = State(initialValue: draft.title)
            _scheduledAt = State(initialValue: draft.scheduledAt)
        case .editRegular(let draft):
            _title = State(initialValue: draft.title)
            _localHour = State(initialValue: draft.localHour)
            _localMinute = State(initialValue: draft.localMinute)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Section {
                            TextField("Название", text: $title, axis: .vertical)
                                .font(DesignSystem.taskTitleFont)
                                .focused($isTitleFocused)
                                .lineLimit(3...6)
                                .textInputAutocapitalization(.sentences)
                        } header: {
                            Text("Название")
                                .font(DesignSystem.taskMetaFont)
                                .foregroundStyle(DesignSystem.secondaryText)
                        }

                        if isOneTime {
                            Section {
                                DatePicker(
                                    "Дата и время",
                                    selection: $scheduledAt,
                                    in: CalendarPolicy.minimumOneTimeDate()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .environment(\.locale, Locale.current)
                            } header: {
                                Text("Когда напомнить")
                                    .font(DesignSystem.taskMetaFont)
                                    .foregroundStyle(DesignSystem.secondaryText)
                            }
                        } else {
                            Section {
                                DatePicker(
                                    "Время",
                                    selection: Binding(
                                        get: { dateFromComponents(hour: localHour, minute: localMinute) },
                                        set: { newDate in
                                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                            localHour = comps.hour ?? 9
                                            localMinute = comps.minute ?? 0
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.wheel)
                                .environment(\.locale, Locale.current)
                            } header: {
                                Text("Ежедневно в")
                                    .font(DesignSystem.taskMetaFont)
                                    .foregroundStyle(DesignSystem.secondaryText)
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                }

                // Закреплённая панель кнопок (доступна всегда)
                VStack {
                    Divider()
                    HStack {
                        Button("Отмена", action: onCancel)
                            .font(DesignSystem.buttonFont)
                            .foregroundStyle(DesignSystem.primaryText)
                            .frame(maxWidth: .infinity)

                        Button("Сохранить") {
                            if isOneTime {
                                onSave(OneTimeTaskDraft(title: title.trimmingCharacters(in: .whitespacesAndNewlines), scheduledAt: scheduledAt))
                            } else {
                                onSaveRegular(RegularTaskDraft(title: title.trimmingCharacters(in: .whitespacesAndNewlines), localHour: localHour, localMinute: localMinute))
                            }
                        }
                        .font(DesignSystem.buttonFont)
                        .foregroundStyle(canSave ? DesignSystem.primaryText : DesignSystem.secondaryText)
                        .frame(maxWidth: .infinity)
                        .disabled(!canSave)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DesignSystem.cardBackground)
                }
            }
            .navigationTitle(isOneTime ? "Разовая задача" : "Регулярная задача")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isTitleFocused = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func dateFromComponents(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - CalendarPolicy extension for minimum date

extension CalendarPolicy {
    /// Минимальная дата для разовой задачи: начало текущего локального дня.
    static func minimumOneTimeDate() -> Date {
        Calendar.current.startOfDay(for: .now)
    }
}

// MARK: - Date extension

extension Date {
    /// Округляет до ближайших 15 минут в будущем.
    func roundedToNextQuarterHour() -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: self)
        let remainder = minute % 15
        let addMinutes = remainder == 0 ? 0 : (15 - remainder)
        return calendar.date(byAdding: .minute, value: addMinutes, to: self) ?? self
    }
}
