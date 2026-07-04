import Foundation
import UIKit
import UserNotifications
import Observation
import os

/// App-wide navigation triggers coming from outside SwiftUI (pushes, links).
@Observable
final class AppRouter {
    /// Set when a verification push arrives — RootView presents the incoming screen.
    var incomingRequestID: String?
    /// Set when a benavo.ch/x?b=<bundle> link opens the app. The identity card
    /// rides inside the link, so opening it needs no server.
    var incomingBundleParam: String?
}

final class PushManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var router: AppRouter?
    var identityProvider: (() -> KenniIdentity?)? {
        didSet { registerPendingTokenIfPossible() }
    }

    /// The token can arrive before the identity is wired up (or before onboarding
    /// finishes) — keep it and retry whenever either side becomes ready.
    private var pendingToken: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pendingToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        registerPendingTokenIfPossible()
    }

    func registerPendingTokenIfPossible() {
        guard let token = pendingToken, let identity = identityProvider?() else { return }
        Task {
            do {
                try await APIClient(identity: identity).registerDevice(apnsToken: token)
                Logger(subsystem: "ch.benavo.kenni", category: "push")
                    .info("device token registered with relay")
            } catch {
                Logger(subsystem: "ch.benavo.kenni", category: "push")
                    .error("device registration failed: \(error)")
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected without the push entitlement — everything else still works.
        Logger(subsystem: "ch.benavo.kenni", category: "push")
            .warning("APNs registration failed: \(error.localizedDescription)")
    }

    // Tapping the notification (or receiving it in foreground) routes to the request.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        route(userInfo: response.notification.request.content.userInfo)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        route(userInfo: notification.request.content.userInfo)
        return [.banner, .sound]
    }

    private func route(userInfo: [AnyHashable: Any]) {
        guard let requestID = userInfo["requestID"] as? String else { return }
        let kind = userInfo["kind"] as? String
        if kind == "request" {
            router?.incomingRequestID = requestID
        }
        // kind == "response": the waiting VerifyCallView is already polling.
    }
}
