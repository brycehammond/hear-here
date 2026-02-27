import Foundation
import Network
import Observation

/// Observable wrapper around `NWPathMonitor` for tracking network connectivity.
///
/// Publishes the current connectivity state so the UI can show offline banners
/// and services can queue operations until connectivity returns.
///
/// ## Usage
/// Inject via SwiftUI `@Environment` and observe `isConnected` to conditionally
/// display UI or defer network operations.
@Observable
final class NetworkMonitor: @unchecked Sendable {
    /// Whether the device currently has network connectivity.
    private(set) var isConnected: Bool = true

    /// Whether the current connection is expensive (e.g., cellular).
    private(set) var isExpensive: Bool = false

    /// Whether the current connection is constrained (e.g., Low Data Mode).
    private(set) var isConstrained: Bool = false

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    /// Creates a network monitor and starts observing connectivity changes.
    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "app.hearhere.networkmonitor")
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Private

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }
}
