import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var deviceToken: String?
  private var tokenCompletion: ((String?) -> Void)?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set up MethodChannel for push token retrieval
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.lumie.app/push",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "getDeviceToken" {
        self?.requestPushToken(application: application, result: result)
      } else {
        result(FlutterMethodNotImplemented)
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
}
