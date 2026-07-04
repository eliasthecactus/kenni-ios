import SwiftUI
import SwiftData

/// In-person live verification:
/// - "Check them":   I show a challenge QR → they sign it → I scan the response
///                   and verify it against the key I stored at exchange time.
/// - "Prove it's you": I scan their challenge → Face ID → my phone shows the signed response.
/// Fully offline on both sides.
struct VerifyInPersonView: View {
    @Bindable var contact: Contact
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Role { case checkThem, proveMe }
    enum CheckState { case showingChallenge, scanningResponse, success, failure }

    @State private var role: Role = .checkThem
    @State private var challenge: VerifyChallenge?
    @State private var checkState: CheckState = .showingChallenge
    @State private var myResponse: VerifyResponse?
    @State private var proveError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("", selection: $role) {
                    Text(L("Check them")).tag(Role.checkThem)
                    Text(L("Prove it's you")).tag(Role.proveMe)
                }
                .pickerStyle(.segmented)

                switch role {
                case .checkThem: checkThem
                case .proveMe: proveMe
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.kenniBackground)
            .navigationTitle(L("Verify in person"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .onAppear { challenge = try? VerifyChallenge.make() }
    }

    // MARK: Check them

    @ViewBuilder
    private var checkThem: some View {
        switch checkState {
        case .showingChallenge:
            if let challenge {
                VStack(spacing: 16) {
                    Text(L("1. Let %@ scan this challenge in their KENNI.", contact.name))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    QRCodeView(content: challenge.qrString)
                        .frame(maxWidth: 260)
                    Button(L("2. Scan their reply")) { checkState = .scanningResponse }
                        .buttonStyle(KenniPrimaryButtonStyle())
                }
            }
        case .scanningResponse:
            ScannerView(prompt: L("Scan the reply code on their screen.")) { code in
                verifyResponse(code)
            }
        case .success:
            resultView(success: true,
                       title: L("It's really %@", contact.name),
                       subtitle: L("Their device holds the private key you exchanged. Contact upgraded to Verified."))
        case .failure:
            resultView(success: false,
                       title: L("Verification failed"),
                       subtitle: L("That reply wasn't signed with %@'s key. Be careful.", contact.name))
        }
    }

    private func verifyResponse(_ code: String) {
        guard let challenge,
              let response = VerifyResponse(qrString: code),
              response.isValid(challenge: challenge, expectedKey: contact.idKey) else {
            checkState = .failure
            record(success: false)
            return
        }
        contact.trustLevel = .verified
        contact.verifiedAt = .now
        record(success: true)
        checkState = .success
    }

    private func record(success: Bool) {
        modelContext.insert(VerificationRecord(contactIdKey: contact.idKey,
                                               kind: .inPerson, succeeded: success))
        try? modelContext.save()
    }

    private func resultView(success: Bool, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: success ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(success ? AnyShapeStyle(KenniGradient.cool)
                                         : AnyShapeStyle(Color.kenniCoral))
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Done")) { dismiss() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
    }

    // MARK: Prove it's you

    @ViewBuilder
    private var proveMe: some View {
        if let myResponse {
            VStack(spacing: 16) {
                Text(L("Let them scan this reply."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                QRCodeView(content: myResponse.qrString)
                    .frame(maxWidth: 260)
            }
        } else {
            VStack(spacing: 12) {
                ScannerView(prompt: L("Scan the challenge on their screen.")) { code in
                    respond(to: code)
                }
                if let proveError {
                    Text(proveError)
                        .font(.footnote)
                        .foregroundStyle(Color.kenniCoral)
                }
            }
        }
    }

    private func respond(to code: String) {
        guard let scannedChallenge = VerifyChallenge(qrString: code) else {
            proveError = L("That's not a KENNI challenge code.")
            return
        }
        Task {
            // Signing in your name is exactly what Face ID is for.
            guard await lock.unlockWithDeviceAuth(reason: L("Confirm that it is really you")),
                  let identity = identityStore.identity else {
                proveError = L("Confirmation cancelled.")
                return
            }
            myResponse = try? VerifyResponse.make(challenge: scannedChallenge, identity: identity)
        }
    }
}
