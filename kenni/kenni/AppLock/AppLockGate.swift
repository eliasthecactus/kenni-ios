import SwiftUI

/// Wraps the main app content and blocks it behind Face ID / PIN.
/// Locks again when the app goes to background; re-prompts automatically on return.
struct AppLockGate<Content: View>: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            // Lock when leaving; the LockScreen re-prompts itself on the way back.
            if phase == .background { lock.lock() }
        }
    }
}

struct LockScreen: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var pin = ""
    @State private var pinFailed = false
    @State private var showRetry = false
    @State private var isPrompting = false

    var body: some View {
        ZStack {
            Color.kenniBackground.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(KenniGradient.primary)
                Text("KENNI")
                    .font(.largeTitle.bold())
                    .tracking(4)

                if lock.method == .pin {
                    pinField
                } else if showRetry {
                    // Only appears if the automatic prompt was cancelled or failed.
                    Button {
                        Task { await unlock() }
                    } label: {
                        Label(L("Unlock"), systemImage: "faceid")
                    }
                    .buttonStyle(KenniPrimaryButtonStyle())
                    .frame(maxWidth: 220)
                }
                Spacer()
                Spacer()
            }
            .padding()
        }
        // Fires on first appearance (cold launch)…
        .task { await unlock() }
        // …and every time the app comes back to the foreground while still locked.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, lock.isLocked {
                Task { await unlock() }
            }
        }
    }

    private var pinField: some View {
        VStack(spacing: 12) {
            SecureField(L("Enter your KENNI PIN"), text: $pin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .multilineTextAlignment(.center)
                .onChange(of: pin) { _, value in
                    pinFailed = false
                    if value.count == 6 && !lock.verifyPIN(value) {
                        pinFailed = true
                        pin = ""
                    }
                }
            if pinFailed {
                Text(L("Wrong PIN. Try again."))
                    .font(.footnote)
                    .foregroundStyle(Color.kenniCoral)
            }
        }
    }

    private func unlock() async {
        guard lock.method != .pin, lock.isLocked, !isPrompting else { return }
        isPrompting = true
        defer { isPrompting = false }
        let ok = await lock.unlockWithDeviceAuth(reason: L("Unlock KENNI"))
        // If the sheet was dismissed/cancelled, surface a button to try again.
        if !ok { showRetry = true }
    }
}
