import SwiftUI

/// Монохромная плашка Undo («Удалено · Отменить»), выезжающая снизу на 3 секунды.
/// Используется при свайпе влево по карточке.
public struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    public init(
        message: String = "Удалено",
        onUndo: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: DesignSystem.cardSpacing) {
            Text(message)
                .font(DesignSystem.bannerFont)
                .foregroundStyle(DesignSystem.primaryText)

            Spacer()

            Button("Отменить", action: onUndo)
                .font(DesignSystem.buttonFont)
                .foregroundStyle(DesignSystem.primaryText)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Отменить удаление")
        }
        .padding(.horizontal, DesignSystem.cardPadding)
        .padding(.vertical, 12)
        .background(DesignSystem.cardBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.separator)
                .frame(height: 0.5),
            alignment: .top
        )
        .offset(y: isVisible ? 0 : 100)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            isVisible = true
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func dismiss() async {
        withAnimation(.easeInOut(duration: DesignSystem.swipeAnimationDuration)) {
            isVisible = false
        }
        try? await Task.sleep(for: .seconds(0.3))
        onDismiss()
    }
}