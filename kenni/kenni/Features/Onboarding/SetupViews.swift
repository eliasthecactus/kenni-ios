import SwiftUI
import UserNotifications
import SwiftData
import LocalAuthentication
import UIKit

// MARK: - App lock setup

struct LockSetupView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(AppLockManager.self) private var lock
    @State private var usePIN = false
    @State private var pin = ""
    @State private var pinRepeat = ""
    @State private var pinError: String?

    var body: some View {
        VStack(spacing: 24) {
            OnboardingHeader(
                systemImage: lock.biometryType == .faceID ? "faceid" : "touchid",
                title: L("Protect your identity"),
                subtitle: L("KENNI locks itself and asks again before anything is signed in your name."))

            if !usePIN && lock.deviceAuthAvailable {
                Spacer()
                Button(lock.biometryType == .faceID ? L("Enable Face ID") : L("Enable Touch ID")) {
                    Task {
                        if await lock.unlockWithDeviceAuth(reason: L("Protect KENNI with biometrics")) {
                            lock.method = .deviceAuth
                            model.lockConfigured()
                        }
                    }
                }
                .buttonStyle(KenniPrimaryButtonStyle())
                Button(L("Use a KENNI PIN instead")) { usePIN = true }
                    .buttonStyle(KenniSecondaryButtonStyle())
            } else {
                GradientBorderCard {
                    VStack(spacing: 12) {
                        SecureField(L("Choose a 6-digit PIN"), text: $pin)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        SecureField(L("Repeat the PIN"), text: $pinRepeat)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        if let pinError {
                            Text(pinError)
                                .font(.footnote)
                                .foregroundStyle(Color.kenniCoral)
                        }
                    }
                }
                Spacer()
                Button(L("Set PIN")) { savePIN() }
                    .buttonStyle(KenniPrimaryButtonStyle(isEnabled: pin.count == 6))
                    .disabled(pin.count != 6)
                if lock.deviceAuthAvailable {
                    Button(L("Use Face ID instead")) { usePIN = false }
                        .buttonStyle(KenniSecondaryButtonStyle())
                }
            }
        }
        .padding(24)
        .background(Color.kenniBackground)
        .onAppear { usePIN = !lock.deviceAuthAvailable }
    }

    private func savePIN() {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            pinError = L("The PIN must be exactly 6 digits.")
            return
        }
        guard pin == pinRepeat else {
            pinError = L("The PINs don't match.")
            return
        }
        do {
            try lock.setPIN(pin)
            model.lockConfigured()
        } catch {
            pinError = L("Couldn't save the PIN. Please try again.")
        }
    }
}

// MARK: - Profile

struct ProfileSetupView: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 24) {
            OnboardingHeader(
                systemImage: "person.crop.circle.fill",
                title: L("Who are you?"),
                subtitle: L("Your name is only shared with people you exchange keys with — never with a server."))

            TextField(L("Your name"), text: $model.name)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
                .textContentType(.name)

            Spacer()
            Button(L("Continue")) { model.profileDone() }
                .buttonStyle(KenniPrimaryButtonStyle(isEnabled: !model.name.trimmingCharacters(in: .whitespaces).isEmpty))
                .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(24)
        .background(Color.kenniBackground)
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 24) {
            OnboardingHeader(
                systemImage: "bell.badge.fill",
                title: L("Verification requests arrive as notifications"),
                subtitle: L("When someone checks if it's really you — on a call, in a chat, anywhere — your phone must be able to tell you instantly."))

            // iOS only shows the system prompt once ever. If it was denied before,
            // explain that it now has to be switched on in Settings.
            if status == .denied {
                Label {
                    Text(L("Notifications are turned off for KENNI. Turn them on in Settings so requests can reach you."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(Color.kenniAmber)
                }
                .padding(14)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(KenniPrimaryButtonStyle())
            Button(L("Not now")) { model.notificationsDone() }
                .buttonStyle(KenniSecondaryButtonStyle())
        }
        .padding(24)
        .background(Color.kenniBackground)
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
    }

    private var isGranted: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private var primaryTitle: String {
        if isGranted { return L("Continue") }
        if status == .denied { return L("Open Settings") }
        return L("Enable notifications")
    }

    private func primaryAction() {
        if isGranted {
            model.notificationsDone()
            return
        }
        if status == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return // they'll return; status refreshes and the button becomes Continue
        }
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            model.notificationsDone()
        }
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - Done

struct DoneView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @State private var saveError = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(KenniGradient.primary)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(L("You're set, %@!", model.name))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            if let identity = model.draft {
                FingerprintBadge(fingerprint: identity.fingerprint)
                Text(L("This is your KENNI fingerprint. People who know you can compare it with the one on their screen."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            if saveError {
                Text(L("Something went wrong while saving. Please try again."))
                    .font(.footnote)
                    .foregroundStyle(Color.kenniCoral)
            }
            Button(L("Start using KENNI")) { finish() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
        .padding(24)
        .background(Color.kenniBackground)
        .navigationBarBackButtonHidden()
    }

    private func finish() {
        guard let identity = model.draft else { return }
        let trimmed = model.name.trimmingCharacters(in: .whitespaces)
        do {
            try identityStore.adopt(identity, name: trimmed, iCloudBackup: model.iCloudBackup)
            // Upsert: a soft reset can leave an old profile behind.
            if let existing = try modelContext.fetch(FetchDescriptor<UserProfile>()).first {
                existing.name = trimmed
            } else {
                modelContext.insert(UserProfile(name: trimmed))
            }
            try modelContext.save()
            // Freshly onboarded — don't slam the lock screen in their face.
            lock.isLocked = false
        } catch {
            saveError = true
        }
    }
}
