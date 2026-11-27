import UIKit

extension Notification.Name {
    /// Posted on a device shake (and by the scenario-mode "Simulate shake" button). The single
    /// entry point for shake-to-report; `FeedbackCenter` observes it.
    static let pathStatDeviceDidShake = Notification.Name("com.yesh0907.PATHStat.deviceDidShake")
}

extension UIWindow {
    /// Shake events travel up the responder chain to the window when no view handles them.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .pathStatDeviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
