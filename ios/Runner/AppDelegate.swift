import FirebaseCore
import FirebaseMessaging
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure natively before registering: the APNs device token can arrive
    // ahead of the Dart-side Firebase.initializeApp, and Messaging.messaging()
    // raises if no default app exists yet.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    excludeLocalDataFromBackup()
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Explicit APNs -> FCM hand-off. Under the implicit-engine delegate flow
  // Firebase's swizzled hooks do not reliably receive the device token, which
  // leaves getAPNSToken() null and push registration dark for the session.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs registration failed: \(error.localizedDescription)")
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  /// Health data (user_data.db: medications, conditions, allergies, Health
  /// History photos) stays on this device, matching Android's
  /// allowBackup="false" + data_extraction_rules. Marking the two containers
  /// excludes them and everything created inside them, now or later, from
  /// iCloud and computer backups (Apple QA1719). The bundled catalog and
  /// interaction DBs in Documents are regenerable, so Apple's data-storage
  /// guidelines want them out of backups too.
  private func excludeLocalDataFromBackup() {
    let fileManager = FileManager.default
    for directory in [
      FileManager.SearchPathDirectory.documentDirectory,
      .applicationSupportDirectory,
    ] {
      guard var url = fileManager.urls(for: directory, in: .userDomainMask).first else {
        continue
      }
      do {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
      } catch {
        NSLog("Backup exclusion failed for \(url.lastPathComponent): \(error.localizedDescription)")
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
