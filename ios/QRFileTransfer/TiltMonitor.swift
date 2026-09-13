import SwiftUI
import CoreMotion

final class TiltMonitor: ObservableObject {
    @Published var isTilted = false

    private let manager = CMMotionManager()
    private let threshold = 35.0 * .pi / 180.0

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.2
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let pitch = abs(motion.attitude.pitch)
            let roll = abs(motion.attitude.roll)
            self.isTilted = max(pitch, roll) > self.threshold
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}