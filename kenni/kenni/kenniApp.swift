import SwiftUI
import SwiftData
import UIKit

@main
struct kenniApp: App {
    @UIApplicationDelegateAdaptor(PushManager.self) private var pushManager
    @State private var identityStore: IdentityStore
    @State private var appLock: AppLockManager
    @State private var router = AppRouter()
    @State private var network = NetworkMonitor()

    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            UserProfile.self,
            Contact.self,
            VerificationRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            sharedModelContainer = try ModelContainer(for: schema,
                                                      configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let store = IdentityStore()
        let lock = AppLockManager()
        #if DEBUG
        if DemoMode.isActive {
            DemoMode.seed(identityStore: store, container: sharedModelContainer)
            lock.isLocked = false
        }
        #endif
        _identityStore = State(initialValue: store)
        _appLock = State(initialValue: lock)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(identityStore)
                .environment(appLock)
                .environment(router)
                .environment(network)
                .environment(LanguageStore.shared)
                .preferredColorScheme(.dark)
                .onAppear {
                    pushManager.router = router
                    pushManager.identityProvider = { [weak identityStore] in
                        identityStore?.identity
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

struct RootView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            #if DEBUG
            if DemoMode.isActive, let screen = DemoMode.screen {
                DemoScreenHost(screen: screen)
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
        .onOpenURL { url in
            // kenni://x?b=<bundle> — the identity card is embedded in the link and
            // opens the app directly (no server, no website).
            if let param = Self.exchangeBundleParam(from: url) {
                router.incomingBundleParam = param
            }
        }
        .sheet(item: $router.incomingRequestID) { requestID in
            IncomingRequestView(requestID: requestID)
                .interactiveDismissDisabled()
        }
        .sheet(item: $router.incomingBundleParam) { param in
            AddFromLinkView(bundleParam: param)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if identityStore.isOnboarded, identityStore.identity != nil {
                AppLockGate {
                    HomeView()
                }
                .task {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                OnboardingFlow()
            }
        }
    }

    /// Extracts the embedded identity-card parameter from an exchange link.
    /// Accepts the app's own scheme (`kenni://x?b=…`) and, as a bonus, the
    /// benavo.ch universal-link form (`https://benavo.ch/x?b=…`).
    static func exchangeBundleParam(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let isCustomScheme = url.scheme == IdentityBundle.urlScheme && components.host == "x"
        let isUniversalLink = components.path == "/x"
        guard isCustomScheme || isUniversalLink,
              let param = components.queryItems?.first(where: { $0.name == "b" })?.value,
              !param.isEmpty else {
            return nil
        }
        return param
    }
}

// Lets plain String ids drive SwiftUI sheets.
extension String: @retroactive Identifiable {
    public var id: String { self }
}
