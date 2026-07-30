import Foundation
import UIKit
import UserNotifications
import Observation
import os

/// Client-side push diagnostics, persisted so the hidden Settings debug screen
/// can read them. Everything here is this device's own data (its APNs token and
/// last registration result) — nothing that comes from the server.
enum PushDebug {
    private static let tokenKey = "kenni.debug.apnsToken"
    private static let statusKey = "kenni.debug.registration"

    static var token: String? { UserDefaults.standard.string(forKey: tokenKey) }
    static var status: String? { UserDefaults.standard.string(forKey: statusKey) }

    static func setToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
    static func setStatus(_ status: String) {
        UserDefaults.standard.set("\(status) — \(Date().formatted(date: .abbreviated, time: .shortened))",
                                  forKey: statusKey)
    }
}

/// App-wide navigation triggers coming from outside SwiftUI (pushes, links).
@Observable
final class AppRouter {
    /// Set when a verification push arrives — RootView presents the incoming screen.
    var incomingRequestID: String?
    /// Set when a benavo.ch/x?b=<bundle> link opens the app. The identity card
    /// rides inside the link, so opening it needs no server.
    var incomingBundleParam: String?
    var businessEnrollmentLink: BusinessEnrollmentLink?
    var businessRevoked = false
}

final class PushManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var router: AppRouter?
    var identityProvider: (() -> KenniIdentity?)? {
        didSet { registerPendingTokenIfPossible() }
    }
    var businessProvider: (() -> BusinessInstallation?)? {
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
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
        PushDebug.setToken(token)
        registerPendingTokenIfPossible()
    }

    func registerPendingTokenIfPossible() {
        guard let token = pendingToken else { return }
        if let client = businessProvider?()?.client {
            Task {
                do {
                    try await client.registerAPNSToken(token)
                    PushDebug.setStatus("Business device registered ✓")
                } catch {
                    PushDebug.setStatus("Failed: \(error.localizedDescription)")
                }
            }
            return
        }
        guard let identity = identityProvider?() else { return }
        Task {
            do {
                try await APIClient(identity: identity).registerDevice(apnsToken: token)
                PushDebug.setStatus("Registered ✓")
                Logger(subsystem: "ch.benavo.kenni", category: "push")
                    .info("device token registered with relay")
            } catch {
                PushDebug.setStatus("Failed: \(error.localizedDescription)")
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
        let kind = userInfo["kind"] as? String
        if kind == "businessRevoked" {
            router?.businessRevoked = true
            return
        }
        guard kind == "request", let requestID = userInfo["requestID"] as? String else {
            return
        }
        router?.incomingRequestID = requestID
    }
}
