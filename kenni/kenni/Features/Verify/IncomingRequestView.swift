import SwiftUI
import SwiftData
import CryptoKit

/// Full-screen prompt when someone asks "is it really you?". Answering signs
/// the reply with the identity key — behind Face ID.
struct IncomingRequestView: View {
    let requestID: String
    @Environment(IdentityStore.self) private var identityStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @Query private var contacts: [Contact]

    enum Phase {
        case loading
        case prompt(VerifyRequestEnvelope, Contact?)
        case answered(Bool)
        case expired
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch phase {
                case .loading:
                    ProgressView()
                case .prompt(let envelope, let contact):
                    prompt(envelope: envelope, contact: contact)
                case .answered(let saidYes):
                    done(saidYes: saidYes)
                case .expired:
                    info(icon: "clock.badge.xmark",
                         title: L("This request expired"),
                         text: L("Verification requests are only valid for 90 seconds."))
                case .failed:
                    info(icon: "exclamationmark.triangle.fill",
                         title: L("Couldn't load the request"),
                         text: L("Check your connection and try again from the notification."))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kenniBackground)
            .navigationTitle(L("Is it really you?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Close")) { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func prompt(envelope: VerifyRequestEnvelope, contact: Contact?) -> some View {
        Spacer()
        if let contact {
            Text(contact.initials)
                .font(.title.bold())
                .frame(width: 84, height: 84)
                .background(Color.kenniCard, in: Circle())
                .overlay(Circle().strokeBorder(KenniGradient.brand.opacity(0.7), lineWidth: 2))
            Text(L("%@ wants to be sure it's really you.", contact.name))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(L("Are you in contact with them right now — call, chat or in person?"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task { await answer(true, envelope: envelope) }
                } label: {
                    Label(L("Yes, it's me"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(KenniPrimaryButtonStyle(fill: .kenniCyan))

                Button {
                    Task { await answer(false, envelope: envelope) }
                } label: {
                    Label(L("No, that's not me"), systemImage: "xmark.octagon.fill")
                }
                .buttonStyle(KenniSecondaryButtonStyle(foreground: .kenniCoral))
            }
        } else {
            // Unknown key: no stored contact to anchor trust — don't engage.
            Image(systemName: "questionmark.circle.dashed")
                .font(.system(size: 64))
                .foregroundStyle(Color.kenniAmber)
            Text(L("Request from someone not in your contacts"))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            FingerprintBadge(fingerprint: KenniIdentity.fingerprint(of: envelope.from))
            Text(L("KENNI only verifies people you exchanged keys with. It's safest to ignore this."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Ignore")) { dismiss() }
                .buttonStyle(KenniSecondaryButtonStyle())
        }
    }

    private func done(saidYes: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: saidYes ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(saidYes ? AnyShapeStyle(KenniGradient.cool)
                                         : AnyShapeStyle(Color.kenniCoral))
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(saidYes ? L("Confirmed — signed by your key")
                         : L("Alarm sent — they've been warned"))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Done")) { dismiss() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
    }

    private func info(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.kenniAmber)
            Text(title)
                .font(.title3.bold())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Close")) { dismiss() }
                .buttonStyle(KenniSecondaryButtonStyle())
        }
    }

    private func load() async {
        guard let identity = identityStore.identity else {
            phase = .failed
            return
        }
        do {
            let status = try await APIClient(identity: identity).status(reqID: requestID)
            guard status.status != "expired" else {
                phase = .expired
                return
            }
            guard let envelope = VerifyRequestEnvelope(payloadString: status.requestPayload),
                  envelope.to == identity.signingKey.publicKey.rawRepresentation,
                  envelope.isValid(expectedFrom: nil) else {
                phase = .failed
                return
            }
            let contact = contacts.first { $0.idKey == envelope.from }
            phase = .prompt(envelope, contact)
        } catch {
            phase = .failed
        }
    }

    private func answer(_ saidYes: Bool, envelope: VerifyRequestEnvelope) async {
        guard let identity = identityStore.identity else { return }
        // Signing "it's me" in your name is exactly what the biometric gate is for.
        guard await lock.unlockWithDeviceAuth(reason: L("Confirm that it is really you")) else {
            return
        }
        do {
            let answer = try VerifyAnswerEnvelope.make(request: envelope, answer: saidYes,
                                                       identity: identity)
            try await APIClient(identity: identity).respond(reqID: envelope.reqID,
                                                            payload: answer.payloadString)
            phase = .answered(saidYes)
        } catch {
            phase = .failed
        }
    }
}
