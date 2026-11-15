import Foundation
import UserNotifications
import SwiftUI

/// AppDelegate для ранней установки UNUserNotificationCenterDelegate.
/// Гарантирует, что делегат установлен до обработки любых уведомлений,
/// включая холодный запуск из выгруженного состояния.
public final class AppDelegate: NSObject, UIApplicationDelegate {
    private var actionHandler: NotificationActionHandler?

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Делегат будет установлен через FocusApp.init() после создания сервисов
        return true
    }

    /// Установить обработчик действий уведомлений (вызывается из FocusApp.init).
    public func setNotificationActionHandler(_ handler: NotificationActionHandler) {
        self.actionHandler = handler
        UNUserNotificationCenter.current().delegate = handler
    }
}