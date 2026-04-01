import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override var window: UIWindow? {
    get {
      if let scene = UIApplication.shared.connectedScenes
          .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
        return scene.windows.first(where: { $0.isKeyWindow })
            ?? scene.windows.first
      }
      return super.window
    }
    set {
      super.window = newValue
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
