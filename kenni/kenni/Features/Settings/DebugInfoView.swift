import SwiftUI

/// Hidden diagnostics screen, reached by tapping the Settings "Version" row
/// seven times. Shows only data that lives on this device already — its own
/// public key (the same value the relay stores as `key_id`), its APNs token,
/// and the last registration result. Nothing here comes from the server.
struct DebugInfoView: View {
    @Environment(IdentityStore.self) private var identityStore
    @State private var manualResult: String?
    @State private var registering = false

    var body: some View {
        List {
            Section {
                field("Fingerprint", identityStore.identity?.fingerprint ?? "—")
                field("Key ID",
                      identityStore.identity?.idString ?? "—")
            } header: {
                Text("Identity")
            } footer: {
                Text("The fingerprint is a hash of the Key ID")
            }

            Section("Push") {
                field("APNs token", PushDebug.token ?? "not received yet")
                field("APNs environment", apnsEnvironment)
                field("Last registration", PushDebug.status ?? "never")
                field("Server", APIClient.baseURL.absoluteString)
            }

            Section {
                Button {
                    Task { await reRegister() }
                } label: {
                    HStack {
                        Label("Re-register this device", systemImage: "arrow.clockwise")
                        if registering {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(registering)
                if let manualResult {
                    Text(manualResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Xcode/dev builds ship the sandbox entitlement; TestFlight & App Store
    /// builds are re-signed for production. This mirrors which APNs endpoint the
    /// server must use for this device's token.
    private var apnsEnvironment: String {
        #if DEBUG
        "development (sandbox)"
        #else
        "production"
        #endif
    }

    /// Long-press any value to copy it.
    @ViewBuilder private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func reRegister() async {
        guard let identity = identityStore.identity else {
            manualResult = "No identity on this device yet."
            return
        }
        guard let token = PushDebug.token else {
            manualResult = "No APNs token yet — grant notification permission first."
            return
        }
        registering = true
        defer { registering = false }
        do {
            try await APIClient(identity: identity).registerDevice(apnsToken: token)
            PushDebug.setStatus("Registered ✓ (manual)")
            manualResult = "Registered ✓"
        } catch {
            PushDebug.setStatus("Failed: \(error.localizedDescription)")
            manualResult = "Failed: \(error)"
        }
    }
}
