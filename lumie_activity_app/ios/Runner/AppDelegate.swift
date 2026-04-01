import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var deviceToken: String?
  private var tokenCompletion: ((String?) -> Void)?
  private var notificationChannel: FlutterMethodChannel?

  private func forwardNotification(
    method: String,
    userInfo: [AnyHashable: Any],
    delay: TimeInterval = 0
  ) {
    let send: () -> Void = { [weak self] in
      self?.notificationChannel?.invokeMethod(method, arguments: userInfo)
    }

    if delay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        send()
      }
    } else {
      DispatchQueue.main.async {
        send()
      }
    }
  }

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
      let aps = notification["aps"] as? [String: Any]
      let hasAlert = aps?["alert"] != nil
      let method = hasAlert ? "onNotificationTap" : "onNotificationReceived"
      // Defer until Flutter is ready — send after a short delay
      forwardNotification(method: method, userInfo: notification, delay: 1.5)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestPushToken(application: UIApplication, result: @escaping FlutterResult) {
    // If we already have a token, return it immediately
    if let token = deviceToken {
      NSLog("[PUSHDBG] Returning cached APNs token: %@", token)
      result(token)
      return
    }

    NSLog("[PUSHDBG] Requesting APNs permission...")
    // Request permission and register
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, error in
      guard granted else {
        NSLog("[PUSHDBG] APNs permission denied or error: %@", error?.localizedDescription ?? "unknown")
        DispatchQueue.main.async { result(nil) }
        return
      }
      NSLog("[PUSHDBG] APNs permission granted, registering for remote notifications...")
      DispatchQueue.main.async {
        self.tokenCompletion = { token in
          NSLog("[PUSHDBG] APNs token received: %@", token ?? "nil")
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
    NSLog("[PUSHDBG] APNs registration successful, token: %@", token)
    self.deviceToken = token
    tokenCompletion?(token)
    tokenCompletion = nil
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[PUSHDBG] APNs registration failed: %@", error.localizedDescription)
    tokenCompletion?(nil)
    tokenCompletion = nil
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // APNs payload has type/request_id at root level, not nested in data
    let notificationType = userInfo["type"] as? String ?? "unknown"
    let requestId = userInfo["request_id"] as? String ?? "none"
    if notificationType == "ring_command" {
      NSLog("[RingCommand] 📬 Received in background: request_id=%@", requestId)
    }
    forwardNotification(method: "onNotificationReceived", userInfo: userInfo)
    completionHandler(.newData)
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Called when user taps a notification (app in background or terminated)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let notificationType = userInfo["type"] as? String ?? "unknown"
    let requestId = userInfo["request_id"] as? String ?? "none"
    if notificationType == "ring_command" {
      NSLog("[RingCommand] 👆 Tapped: request_id=%@", requestId)
    }
    forwardNotification(method: "onNotificationTap", userInfo: userInfo)
    completionHandler()
  }

  /// Called when notification arrives while app is in foreground — show it
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    let notificationType = userInfo["type"] as? String ?? "unknown"
    let requestId = userInfo["request_id"] as? String ?? "none"
    if notificationType == "ring_command" {
      NSLog("[RingCommand] 🎯 Foreground: request_id=%@", requestId)
    }
    forwardNotification(method: "onNotificationReceived", userInfo: userInfo)
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
