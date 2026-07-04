import SwiftUI
import SwiftData

/// Outgoing live check: sign a request, relay it, and wait for the contact's
/// signed answer. The verdict is decided on THIS phone by checking the answer
/// signature against the stored contact key.
struct VerifyCallView: View {
    @Bindable var contact: Contact
    @Environment(IdentityStore.self) private var identityStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case sending
        case waiting(secondsLeft: Int)
        case verified
        case denied
        case invalid
        case timeout
        case unreachable
        case failed(String)
    }

    @State private var phase: Phase = .sending
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch phase {
                case .sending, .waiting:
                    waiting
                case .verified:
                    result(icon: "checkmark.seal.fill", style: AnyShapeStyle(KenniGradient.cool),
                           title: L("It's really %@", contact.name),
                           text: L("Their device signed the confirmation seconds ago. You can trust this conversation."))
                case .denied:
                    result(icon: "exclamationmark.octagon.fill", style: AnyShapeStyle(Color.kenniCoral),
                           title: L("%@ says: that's NOT them!", contact.name),
                           text: L("Stop the conversation. Someone is impersonating them."))
                case .invalid:
                    result(icon: "exclamationmark.octagon.fill", style: AnyShapeStyle(Color.kenniCoral),
                           title: L("Invalid answer"),
                           text: L("The reply wasn't correctly signed with %@'s key. Treat this as a warning.", contact.name))
                case .timeout:
                    result(icon: "clock.badge.questionmark", style: AnyShapeStyle(Color.kenniAmber),
                           title: L("No answer"),
                           text: L("No reply within 90 seconds. Try the offline codes, or reach them on a channel you already trust."))
                case .unreachable:
                    result(icon: "wifi.slash", style: AnyShapeStyle(Color.kenniAmber),
                           title: L("%@ can't be reached", contact.name),
                           text: L("They haven't enabled notifications yet, or you are offline. The offline codes always work."))
                case .failed(let message):
                    result(icon: "exclamationmark.triangle.fill", style: AnyShapeStyle(Color.kenniAmber),
                           title: L("Something went wrong"), text: message)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kenniBackground)
            .navigationTitle(L("Live check"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .task { await run() }
        .onDisappear { pollTask?.cancel() }
    }

    private var waiting: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.kenniCard, lineWidth: 6)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(KenniGradient.brand, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(KenniGradient.brand)
            }
            Text(L("Asking %@ to confirm it's really them…", contact.name))
                .font(.headline)
                .multilineTextAlignment(.center)
            if case .waiting(let seconds) = phase {
                Text(L("%d s", seconds))
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Cancel")) { dismiss() }
                .buttonStyle(KenniSecondaryButtonStyle())
        }
    }

    private var progress: Double {
        if case .waiting(let seconds) = phase {
            return Double(seconds) / VerifyRequestEnvelope.ttl
        }
        return 1
    }

    private func result(icon: String, style: AnyShapeStyle, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(style)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Done")) { dismiss() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
    }

    private func run() async {
        guard let identity = identityStore.identity else { return }
        let api = APIClient(identity: identity)
        let envelope: VerifyRequestEnvelope
        do {
            envelope = try VerifyRequestEnvelope.make(identity: identity, to: contact.idKey)
            try await api.sendVerifyRequest(envelope)
        } catch APIError.http(404, _) {
            phase = .unreachable
            return
        } catch {
            phase = .unreachable
            return
        }

        let deadline = Date(timeIntervalSince1970: envelope.ts + VerifyRequestEnvelope.ttl)
        phase = .waiting(secondsLeft: Int(VerifyRequestEnvelope.ttl))
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            phase = .waiting(secondsLeft: max(0, Int(deadline.timeIntervalSinceNow)))
            guard let status = try? await api.status(reqID: envelope.reqID) else { continue }
            if let payload = status.responsePayload {
                settle(payload: payload, request: envelope)
                return
            }
        }
        record(succeeded: false)
        phase = .timeout
    }

    private func settle(payload: String, request: VerifyRequestEnvelope) {
        guard let answer = VerifyAnswerEnvelope(payloadString: payload),
              answer.isValid(request: request, responderKey: contact.idKey) else {
            record(succeeded: false)
            phase = .invalid
            return
        }
        record(succeeded: answer.answer)
        phase = answer.answer ? .verified : .denied
    }

    private func record(succeeded: Bool) {
        modelContext.insert(VerificationRecord(contactIdKey: contact.idKey,
                                               kind: .call, succeeded: succeeded))
        try? modelContext.save()
    }
}
