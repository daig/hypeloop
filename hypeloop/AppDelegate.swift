import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Create our custom window.
        self.window = ShakeDetectingWindow(frame: UIScreen.main.bounds)
        return true
    }
}