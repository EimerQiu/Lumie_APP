import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var deviceToken: String?
  private var tokenCompletion: ((String?) -> Void)?
  private var notificationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Become the notification center delegate so we can handle taps
    UNUserNotificationCenter.current().delegate = self

    // Set up MethodChannel for push token retrieval and notification events
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.lumie.app/push",
      binaryMessenger: controller.binaryMessenger
    )
    notificationChannel = channel

    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "getDeviceToken" {
        self?.requestPushToken(application: application, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Check if the app was launched from a notification
    if let notification = launchOptions?[.remoteNotification] as? [String: Any] {
      // Defer until Flutter is ready — send after a short delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        self?.notificationChannel?.invokeMethod("onNotificationTap", arguments: notification)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestPushToken(application: UIApplication, result: @escaping FlutterResult) {
    // If we already have a token, return it immediately
    if let token = deviceToken {
      result(token)
      return
    }

    // Request permission and register
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, error in
      guard granted else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      DispatchQueue.main.async {
        self.tokenCompletion = { token in
          result(token)
        }
        application.registerForRemoteNotifications()
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    self.deviceToken = token
    tokenCompletion?(token)
    tokenCompletion = nil
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    tokenCompletion?(nil)
    tokenCompletion = nil
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Called when user taps a notification (app in background or terminated)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    notificationChannel?.invokeMethod("onNotificationTap", arguments: userInfo)
    completionHandler()
  }

  /// Called when notification arrives while app is in foreground — show it
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
