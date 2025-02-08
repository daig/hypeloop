import SwiftUI
import UIKit

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

class ShakeDetectingWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            print("🔔 ShakeDetectingWindow: Shake detected!")
            // Post a notification that a shake was detected.
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

// Add a UIViewController that can become first responder
class ShakeResponderViewController: UIViewController {
    override var canBecomeFirstResponder: Bool {
        print("🎯 ShakeResponderViewController: canBecomeFirstResponder called")
        return true
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            print("📱 ShakeResponderViewController: Shake detected!")
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("👋 ShakeResponderViewController: View appeared, becoming first responder")
        becomeFirstResponder()
    }
}

// Add a SwiftUI wrapper for the shake responder
struct ShakeResponder: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeResponderViewController {
        let vc = ShakeResponderViewController()
        vc.becomeFirstResponder()
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ShakeResponderViewController, context: Context) {
    }
}