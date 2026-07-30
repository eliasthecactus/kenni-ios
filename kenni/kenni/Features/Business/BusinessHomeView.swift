import SwiftUI

struct BusinessHomeView: View {
    @Environment(BusinessCredentialStore.self) private var businessStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConfirmation = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Group {
                if let installation = businessStore.installation {
                    if installation.status == .revoked {
                        revokedView(installation)
                    } else {
                        activeView(installation)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kenniBackground)
            .navigationTitle(L("Business mode"))
        }
        .tint(.kenniBlue)
        .sheet(isPresented: $showConfirmation) {
            BusinessConfirmCustomerView()
        }
        .task { await businessStore.refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await businessStore.refreshStatus() } }
        }
        .confirmationDialog(L("Log out this business device?"),
                            isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(L("Log out"), role: .destructive) { businessStore.logout() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The device credential will be deleted. A new admin invitation is required to enroll it again."))
        }
    }

    private func activeView(_ installation: BusinessInstallation) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                businessLogo(installation.business)
                    .padding(.top, 28)
                VStack(spacing: 8) {
                    Label(L("Active business device"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KenniGradient.cool)
                    Text(installation.business.name)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(installation.deviceLabel)
                        .foregroundStyle(.secondary)
                }

                GradientBorderCard {
                    VStack(spacing: 14) {
                        Label(L("Ready to confirm your business"),
                              systemImage: "person.text.rectangle.fill")
                            .font(.headline)
                        Text(L("Scan a customer's fresh KENNI challenge. The API checks that this device is still active before issuing a one-time response."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showConfirmation = true
                        } label: {
                            Label(L("Confirm for a customer"),
                                  systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(KenniPrimaryButtonStyle())
                    }
                }

                Button(L("Log out business device")) { confirmLogout = true }
                    .buttonStyle(KenniSecondaryButtonStyle(foreground: .kenniCoral))
            }
            .padding(24)
        }
    }

    private func revokedView(_ installation: BusinessInstallation) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(Color.kenniCoral)
            Text(L("This business device was revoked"))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(L("It can no longer create confirmations for %@.", installation.business.name))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let revokedAt = installation.revokedAt {
                Text(L("Revoked %@", revokedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(L("Log out")) { confirmLogout = true }
                .buttonStyle(KenniPrimaryButtonStyle(fill: .kenniCoral, foreground: .white))
        }
        .padding(24)
    }

    private func businessLogo(_ business: BusinessProfile) -> some View {
        AsyncImage(url: business.logoURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "building.2.fill")
                    .resizable().scaledToFit().padding(24)
                    .foregroundStyle(KenniGradient.cool)
            }
        }
        .frame(width: 112, height: 112)
        .background(Color.kenniCard,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(KenniGradient.cool.opacity(0.6), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct BusinessConfirmCustomerView: View {
    @Environment(BusinessCredentialStore.self) private var businessStore
    @Environment(AppLockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var response: IssuedBusinessConfirmation?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Group {
                if let response {
                    VStack(spacing: 20) {
                        Text(L("Let the customer scan this one-time response."))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        QRCodeView(content: response.responseURL)
                            .frame(maxWidth: 280)
                        Label(L("Expires in 90 seconds"), systemImage: "timer")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(L("Done")) { dismiss() }
                            .buttonStyle(KenniPrimaryButtonStyle())
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 12) {
                        ScannerView(prompt: L("Scan the customer's business challenge.")) {
                            respond(to: $0)
                        }
                        if isWorking { ProgressView() }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.kenniCoral)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .background(Color.kenniBackground)
            .navigationTitle(L("Confirm business"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
        .tint(.kenniBlue)
    }

    private func respond(to value: String) {
        guard !isWorking, let challenge = BusinessChallengeLink(text: value) else {
            errorMessage = L("That is not a valid KENNI business challenge.")
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            guard await lock.unlockWithDeviceAuth(
                reason: L("Confirm that you represent the business")) else {
                errorMessage = L("Confirmation cancelled.")
                return
            }
            guard let client = businessStore.installation?.client else {
                errorMessage = L("This business device is no longer active.")
                return
            }
            do {
                response = try await client.issueConfirmation(challenge: challenge.challenge)
            } catch APIError.http(410, _) {
                await businessStore.refreshStatus()
                errorMessage = L("This business device has been revoked.")
            } catch {
                errorMessage = L("Could not create a confirmation. Check your connection.")
            }
        }
    }
}
