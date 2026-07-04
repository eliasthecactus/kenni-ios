import Foundation
import Network
import Observation

/// Publishes whether the device currently has a usable network path. Uses the
/// system's `NWPathMonitor` — instant and local, so there's no need to ping the
/// API (which would itself require the network we're trying to test).
@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ch.benavo.kenni.network")

    /// Optimistic default so the UI isn't briefly "offline" at launch before the
    /// first path update arrives.
    var isOnline = true

    init() {
        #if DEBUG
        // Screenshot/testing aid: force the offline state.
        if ProcessInfo.processInfo.arguments.contains("--offline") {
            isOnline = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
