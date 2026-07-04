import SwiftUI
import SwiftData

/// Reset flow with two clearly-warned options:
/// - Start fresh:  wipes keys (device + iCloud Keychain), contacts and profile.
/// - Re-run setup: keeps your keys so you can restore them; just redoes onboarding.
struct ResetView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    OnboardingHeader(
                        systemImage: "arrow.counterclockwise",
                        title: L("Reset KENNI"),
                        subtitle: L("Pick how far you want to go. Read carefully — one option cannot be undone."))

                    option(
                        icon: "arrow.triangle.2.circlepath",
                        tint: KenniGradient.cool,
                        title: L("Re-run setup"),
                        body: L("Keeps your keys safe in the Keychain. You can create a new identity or restore an existing one. Your contacts on this device stay."),
                        button: L("Re-run setup"),
                        destructive: false) {
                            identityStore.reset(wipeKeychain: false)
                            dismiss()
                        }

                    option(
                        icon: "trash",
                        tint: KenniGradient.warm,
                        title: L("Start completely fresh"),
                        body: L("Erases every identity from this device and from iCloud Keychain, plus all contacts. Without your written recovery phrase this cannot be undone."),
                        button: L("Erase everything"),
                        destructive: true) {
                            confirmWipe = true
                        }
                }
                .padding(24)
            }
            .background(Color.kenniBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .confirmationDialog(L("Erase everything?"), isPresented: $confirmWipe,
                                titleVisibility: .visible) {
                Button(L("Erase everything"), role: .destructive) { wipeEverything() }
            } message: {
                Text(L("This deletes all identities and contacts on this device and in iCloud Keychain. This cannot be undone."))
            }
        }
    }

    private func option(icon: String, tint: LinearGradient, title: String, body: String,
                        button: String, destructive: Bool,
                        action: @escaping () -> Void) -> some View {
        GradientBorderCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(button, action: action)
                    .buttonStyle(destructive
                                 ? AnyButtonStyle(KenniSecondaryButtonStyle(foreground: .kenniCoral))
                                 : AnyButtonStyle(KenniPrimaryButtonStyle()))
            }
        }
    }

    private func wipeEverything() {
        // Purge SwiftData: profile, contacts, verification history.
        try? modelContext.delete(model: UserProfile.self)
        try? modelContext.delete(model: Contact.self)
        try? modelContext.delete(model: VerificationRecord.self)
        try? modelContext.save()
        identityStore.reset(wipeKeychain: true)
        dismiss()
    }
}

/// Small type eraser so a computed property can return either button style.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { config in AnyView(style.makeBody(configuration: config)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
