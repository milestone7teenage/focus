import SwiftUI

/// Design System: строгий iOS монохром для светлой и тёмной системных тем.
/// Ноль ярких акцентов, градиентов, glassmorphism.
public enum DesignSystem {
    // MARK: - Colors

    /// Основной фон: системный `.systemBackground` (белый в light, чёрный в dark).
    public static let background = Color(.systemBackground)

    /// Вторичный фон для карточек: `.secondarySystemBackground`.
    public static let cardBackground = Color(.secondarySystemBackground)

    /// Третичный фон для вложенных элементов: `.tertiarySystemBackground`.
    public static let tertiaryBackground = Color(.tertiarySystemBackground)

    /// Основной текст: `.label` (чёрный в light, белый в dark).
    public static let primaryText = Color(.label)

    /// Вторичный текст: `.secondaryLabel` (серый).
    public static let secondaryText = Color(.secondaryLabel)

    /// Третичный текст: `.tertiaryLabel` (более бледный серый).
    public static let tertiaryText = Color(.tertiaryLabel)

    /// Разделители: `.separator` (адаптивный серый).
    public static let separator = Color(.separator)

    /// Прогресс-бар выполнения (монохром): использует `.label` для видимости в обеих темах.
    public static let progressFill = Color(.label)

    /// Индикатор SEEN: вторичный текст.
    public static let seenIndicator = Color(.secondaryLabel)

    // MARK: - Typography

    /// Заголовок карточки: body, weight .semibold, Dynamic Type.
    public static let taskTitleFont = Font.system(.body, design: .default).weight(.semibold)

    /// Время/дата в карточке: caption, Dynamic Type.
    public static let taskMetaFont = Font.system(.caption, design: .default)

    /// Текст UndoBanner: body, Dynamic Type.
    public static let bannerFont = Font.system(.body, design: .default)

    /// Кнопка Undo: body, weight .medium.
    public static let buttonFont = Font.system(.body, design: .default).weight(.medium)

    // MARK: - Spacing

    public static let cardPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 8
    public static let sectionSpacing: CGFloat = 24
    public static let listRowSpacing: CGFloat = 12

    // MARK: - Animation

    /// Длительность анимации прогресса Long Press (~0.6 сек).
    public static let longPressDuration: Double = 0.6

    /// Длительность анимации свайпа/плашки.
    public static let swipeAnimationDuration: Double = 0.25

    // MARK: - Haptics

    @MainActor
    public static let impactLight = UIImpactFeedbackGenerator(style: .light)

    @MainActor
    public static let impactMedium = UIImpactFeedbackGenerator(style: .medium)

    @MainActor
    public static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Accessibility

    public static let minimumTapTarget: CGFloat = 44
}