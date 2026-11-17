import Flutter
import UIKit
import UserNotifications
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String,
       !mapsKey.isEmpty,
       !mapsKey.hasPrefix("$(") {
      GMSServices.provideAPIKey(mapsKey)
    }
    GeneratedPluginRegistrant.register(with: self)

    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(0)
      } else {
        UIApplication.shared.applicationIconBadgeNumber = 0
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
