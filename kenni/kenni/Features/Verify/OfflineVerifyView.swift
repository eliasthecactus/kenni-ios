import SwiftUI
import SwiftData

/// Spoken 6-digit codes — verification with zero connectivity on both sides,
/// powered by the pairwise secret from the key exchange.
struct OfflineVerifyView: View {
    @Bindable var contact: Contact
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Role { case checking, answering }

    @State private var role: Role = .checking
    // Checking
    @State private var challenge = OfflineCodes.randomChallenge()
    @State private var theirReply = ""
    @State private var attempts = 0
    @State private var checkResult: Bool?
    // Answering
    @State private var theirChallenge = ""
    @State private var myResponse: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("", selection: $role) {
                    Text(L("I'm checking")).tag(Role.checking)
                    Text(L("I'm answering")).tag(Role.answering)
                }
                .pickerStyle(.segmented)

                switch role {
                case .checking: checking
                case .answering: answering
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.kenniBackground)
            .navigationTitle(L("Offline codes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    // MARK: I'm checking them

    @ViewBuilder
    private var checking: some View {
        if let checkResult {
            resultView(success: checkResult)
        } else {
            VStack(spacing: 18) {
                stepLabel(1, L("Read this code to %@:", contact.name))
                codeDisplay(challenge, gradient: KenniGradient.brand)
                stepLabel(2, L("Type the 6-digit reply they read back:"))
                TextField("000000", text: $theirReply)
                    .keyboardType(.numberPad)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: theirReply) { _, value in
                        if value.count == 6 { check() }
                    }
                if attempts > 0 {
                    Text(L("Wrong code (%d of 3 tries)", attempts))
                        .font(.footnote)
                        .foregroundStyle(Color.kenniCoral)
                }
                Text(L("Works completely without internet — on both phones."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func check() {
        let expected = OfflineCodes.response(secret: contact.pairwiseSecret, challenge: challenge)
        if theirReply == expected {
            record(succeeded: true)
            checkResult = true
        } else {
            attempts += 1
            theirReply = ""
            if attempts >= 3 {
                record(succeeded: false)
                checkResult = false
            }
        }
    }

    // MARK: I'm answering their challenge

    @ViewBuilder
    private var answering: some View {
        if let myResponse {
            VStack(spacing: 18) {
                stepLabel(2, L("Read this reply back to them:"))
                codeDisplay(myResponse, gradient: KenniGradient.cool)
            }
        } else {
            VStack(spacing: 18) {
                stepLabel(1, L("Type the code %@ reads to you:", contact.name))
                TextField("000000", text: $theirChallenge)
                    .keyboardType(.numberPad)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 14))
                Button(L("Compute my reply")) {
                    Task { await respond() }
                }
                .buttonStyle(KenniPrimaryButtonStyle(isEnabled: theirChallenge.count == 6))
                .disabled(theirChallenge.count != 6)
            }
        }
    }

    private func respond() async {
        guard await lock.unlockWithDeviceAuth(reason: L("Confirm that it is really you")) else {
            return
        }
        myResponse = OfflineCodes.response(secret: contact.pairwiseSecret,
                                           challenge: theirChallenge)
    }

    // MARK: Shared bits

    private func stepLabel(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 26, height: 26)
                .background(KenniGradient.brand, in: Circle())
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func codeDisplay(_ code: String, gradient: LinearGradient) -> some View {
        Text(code.map(String.init).joined(separator: " "))
            .font(.system(size: 40, weight: .black, design: .monospaced))
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(gradient, lineWidth: 2))
    }

    private func resultView(success: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: success ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(success ? AnyShapeStyle(KenniGradient.cool)
                                         : AnyShapeStyle(Color.kenniCoral))
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(success ? L("It's really %@", contact.name) : L("Code check failed"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(success
                 ? L("Only their device can compute that reply.")
                 : L("Three wrong codes. Whoever you're talking to can't prove they're %@.", contact.name))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Done")) { dismiss() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
    }

    private func record(succeeded: Bool) {
        modelContext.insert(VerificationRecord(contactIdKey: contact.idKey,
                                               kind: .offline, succeeded: succeeded))
        try? modelContext.save()
    }
}
