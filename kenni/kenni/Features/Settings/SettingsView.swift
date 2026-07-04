import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss

    @State private var iCloudBackup = false
    @State private var revealedPhrase: [String]?
    @State private var showReset = false
    @State private var lockMethod: AppLockManager.Method?
    @State private var showSetPIN = false
    @State private var lockError: String?

    private let benavoURL = URL(string: "https://benavo.ch")!
    private let featureRequestURL = URL(string: "mailto:kenni@benavo.ch?subject=KENNI%20feature%20request")!

    var body: some View {
        NavigationStack {
            List {
                profileSection
                languageSection
                lockSection
                backupSection
                phraseSection
                feedbackSection
                aboutSection
                resetSection
            }
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .onAppear {
            iCloudBackup = identityStore.iCloudEnabledForActive
            lockMethod = lock.method
        }
        .onDisappear { revealedPhrase = nil }
        .fullScreenCover(isPresented: $showReset) { ResetView() }
        .sheet(isPresented: $showSetPIN) {
            SetPINSheet { pin in
                do {
                    try lock.setPIN(pin)
                    lockMethod = .pin
                    lockError = nil
                } catch {
                    lockError = L("Couldn't save the PIN. Please try again.")
                }
            }
        }
    }

    // MARK: App lock

    private var lockSection: some View {
        Section {
            LabeledContent(L("Unlock method"), value: methodName)

            if lock.deviceAuthAvailable, lockMethod == .pin {
                Button {
                    Task { await enableDeviceAuth() }
                } label: {
                    Label(lock.biometryType == .faceID ? L("Use Face ID")
                          : lock.biometryType == .touchID ? L("Use Touch ID")
                          : L("Use device passcode"),
                          systemImage: lock.biometryType == .touchID ? "touchid" : "faceid")
                }
            }

            if lockMethod == .pin {
                Button {
                    showSetPIN = true
                } label: {
                    Label(L("Change PIN"), systemImage: "number")
                }
            } else {
                Button {
                    showSetPIN = true
                } label: {
                    Label(L("Set a KENNI PIN"), systemImage: "number")
                }
            }

            if let lockError {
                Text(lockError).font(.footnote).foregroundStyle(Color.kenniCoral)
            }
        } header: {
            Text(L("App lock"))
        } footer: {
            Text(L("KENNI locks itself and asks again before anything is signed in your name."))
        }
    }

    private var methodName: String {
        switch lockMethod {
        case .deviceAuth:
            switch lock.biometryType {
            case .faceID: L("Face ID")
            case .touchID: L("Touch ID")
            default: L("Device passcode")
            }
        case .pin: L("KENNI PIN")
        case .none: L("Not set")
        }
    }

    private func enableDeviceAuth() async {
        let label = lock.biometryType == .faceID ? L("Enable Face ID")
                  : lock.biometryType == .touchID ? L("Enable Touch ID")
                  : L("Enable device passcode")
        if await lock.switchToDeviceAuth(reason: label) {
            lockMethod = .deviceAuth
            lockError = nil
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        Section(L("Your identity")) {
            NavigationLink {
                EditProfileView()
            } label: {
                Label(L("Name & photo"), systemImage: "person.crop.circle")
            }
            LabeledContent(L("Fingerprint"),
                           value: identityStore.identity?.fingerprint ?? "—")
                .font(.system(.body, design: .monospaced))
        }
    }

    private var languageSection: some View {
        Section(L("Language")) {
            LanguageRow()
        }
    }

    // MARK: Backup

    private var backupSection: some View {
        Section {
            HStack {
                Label {
                    Text(iCloudBackup ? L("Backed up to iCloud Keychain")
                                      : L("Stored on this device only"))
                } icon: {
                    Image(systemName: iCloudBackup ? "checkmark.icloud.fill" : "iphone")
                        .foregroundStyle(iCloudBackup ? Color.kenniCyan : Color.kenniAmber)
                }
                Spacer()
            }
            Toggle(L("iCloud Keychain backup"), isOn: $iCloudBackup)
                .tint(.kenniCyan)
                .onChange(of: iCloudBackup) { _, enabled in
                    identityStore.setICloudBackupForActive(enabled)
                }
        } header: {
            Text(L("Backup & sync"))
        } footer: {
            Text(iCloudBackup
                 ? L("This identity syncs to your other devices through iCloud Keychain, end-to-end encrypted.")
                 : L("Without iCloud, your written recovery phrase is the only way back into your identity."))
        }
    }

    // MARK: Recovery phrase

    private var phraseSection: some View {
        Section(L("Recovery phrase")) {
            if let words = revealedPhrase {
                Text(words.joined(separator: "  "))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .textSelection(.disabled)
                Button(L("Hide")) { revealedPhrase = nil }
            } else {
                Button {
                    Task { await reveal() }
                } label: {
                    Label(L("Show recovery phrase"), systemImage: "eye.fill")
                }
            }
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        Section(L("Feedback")) {
            Link(destination: featureRequestURL) {
                Label(L("Request a feature"), systemImage: "lightbulb")
            }
            Link(destination: benavoURL) {
                HStack {
                    Label(L("More apps by benavo"), systemImage: "square.grid.2x2")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section(L("About")) {
            LabeledContent(L("Version"),
                           value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
            Link(destination: URL(string: "https://benavo.ch/apps/kenni")!) {
                Label(L("Privacy & how it works"), systemImage: "hand.raised")
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showReset = true
            } label: {
                Label(L("Reset app"), systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text(L("Start over — either keep your keys for later or wipe everything."))
        }
    }

    private func reveal() async {
        if lock.method == .pin {
            revealedPhrase = identityStore.identity?.mnemonic
        } else if await lock.unlockWithDeviceAuth(reason: L("Show recovery phrase")) {
            revealedPhrase = identityStore.identity?.mnemonic
        }
    }
}

/// Small sheet to set or change the 6-digit KENNI PIN.
struct SetPINSheet: View {
    let onSet: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var repeatPin = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                OnboardingHeader(
                    systemImage: "number",
                    title: L("Choose a 6-digit PIN"),
                    subtitle: L("KENNI locks itself and asks again before anything is signed in your name."))

                GradientBorderCard {
                    VStack(spacing: 12) {
                        SecureField(L("Choose a 6-digit PIN"), text: $pin)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        SecureField(L("Repeat the PIN"), text: $repeatPin)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(Color.kenniCoral)
                        }
                    }
                }

                Spacer()
                Button(L("Set PIN")) { save() }
                    .buttonStyle(KenniPrimaryButtonStyle(isEnabled: pin.count == 6))
                    .disabled(pin.count != 6)
            }
            .padding(24)
            .background(Color.kenniBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            error = L("The PIN must be exactly 6 digits.")
            return
        }
        guard pin == repeatPin else {
            error = L("The PINs don't match.")
            return
        }
        onSet(pin)
        dismiss()
    }
}
