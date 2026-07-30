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
                        Label(L("Ready to verify your business"),
                              systemImage: "person.text.rectangle.fill")
                            .font(.headline)
                        Text(L("Create a one-time PIN and give it to the customer. KENNI checks that this device is still active before issuing the PIN."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showConfirmation = true
                        } label: {
                            Label(L("Create verification PIN"),
                                  systemImage: "number.square.fill")
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
    @State private var issuedPIN: IssuedBusinessPIN?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let issuedPIN {
                    OnboardingHeader(
                        systemImage: "number.square.fill",
                        title: L("Give this PIN to the customer"),
                        subtitle: L("The customer enters it in KENNI to see your verified business profile."),
                        gradient: KenniGradient.cool)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(
                            0, issuedPIN.expiresAt - Int(context.date.timeIntervalSince1970))
                        VStack(spacing: 14) {
                            Text(formatted(issuedPIN.pin))
                                .font(.system(size: 54, weight: .bold, design: .monospaced))
                                .tracking(5)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .textSelection(.enabled)
                            if seconds > 0 {
                                Label(L("%@ seconds remaining", String(seconds)),
                                      systemImage: "timer")
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(L("This PIN has expired."),
                                      systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.kenniCoral)
                            }
                        }
                    }

                    Text(L("The PIN works once. Creating a new PIN immediately invalidates this one."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await issuePIN() }
                    } label: {
                        if isWorking { ProgressView().tint(.kenniInk) }
                        else { Text(L("Create new PIN")) }
                    }
                    .buttonStyle(KenniSecondaryButtonStyle())
                    .disabled(isWorking)
                } else if isWorking {
                    Spacer()
                    ProgressView()
                    Text(L("Creating verification PIN…"))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Spacer()
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(KenniGradient.cool)
                    Text(L("Could not create a verification PIN"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                    Button(L("Try again")) { Task { await issuePIN() } }
                        .buttonStyle(KenniPrimaryButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kenniBackground)
            .navigationTitle(L("Verify business"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .tint(.kenniBlue)
        .task {
            if issuedPIN == nil, errorMessage == nil {
                await issuePIN()
            }
        }
    }

    @MainActor
    private func issuePIN() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
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
            issuedPIN = try await client.issueVerificationPIN()
        } catch APIError.http(410, _) {
            await businessStore.refreshStatus()
            errorMessage = L("This business device has been revoked.")
        } catch {
            errorMessage = L("Could not create a verification PIN. Check your connection.")
        }
    }

    private func formatted(_ pin: String) -> String {
        guard pin.count == 6 else { return pin }
        return "\(pin.prefix(3)) \(pin.suffix(3))"
    }
}
