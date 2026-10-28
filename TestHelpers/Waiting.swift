import Foundation
import XCTest

/// How long UI tests wait for something to show. Every wait checks right away and then every
/// `UIWait.interval`, so these are only how long to keep trying before failing.
enum UIWait {
    /// Most screens and sheets show within this.
    static let standard: TimeInterval = 3
    /// The app's first launch, and anything that needs the network, such as the course list.
    static let slow: TimeInterval = 15
    static let interval: TimeInterval = 0.05

    /// Checks `condition` right away, then every `interval`, until it is true or `timeout` passes.
    @MainActor
    @discardableResult
    static func until(timeout: TimeInterval = standard, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
        return true
    }
}

extension XCUIElement {
    /// Waits for the element to exist. Unlike `waitForExistence`, which takes a second even when
    /// the element is already there, it returns as soon as the element shows.
    @MainActor
    func waitToExist(timeout: TimeInterval = UIWait.standard) -> Bool {
        UIWait.until(timeout: timeout) { exists }
    }

    /// Waits for the element to go away, returning as soon as it does.
    @MainActor
    func waitToVanish(timeout: TimeInterval = UIWait.standard) -> Bool {
        UIWait.until(timeout: timeout) { !exists }
    }
}
