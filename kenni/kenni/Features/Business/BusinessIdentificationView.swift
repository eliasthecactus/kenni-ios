import SwiftUI

struct BusinessIdentificationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var phase: Phase = .enteringPIN
    @FocusState private var pinFocused: Bool

    private enum Phase: Equatable {
        case enteringPIN
        case verifying
        case verified(BusinessProfile)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .enteringPIN:
                    pinEntryView
                case .verifying:
                    VStack(spacing: 18) {
                        ProgressView()
                        Text(L("Checking the business PIN…"))
                            .foregroundStyle(.secondary)
                    }
                case .verified(let business):
                    BusinessVerificationResult(business: business) { reset() }
                case .failed(let message):
                    failureView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kenniBackground)
            .navigationTitle(L("Verify a business"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .tint(.kenniBlue)
    }

    private var pinEntryView: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(
                    systemImage: "building.2.crop.circle",
                    title: L("Verify an approved business"),
                    subtitle: L("Ask the representative for their current one-time KENNI PIN, then enter it below."),
                    gradient: KenniGradient.cool)
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text(L("Business PIN"))
                        .font(.headline)
                    TextField("", text: $pin,
                              prompt: Text("000000").foregroundStyle(.tertiary))
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .tracking(8)
                        .multilineTextAlignment(.center)
                        .focused($pinFocused)
                        .accessibilityLabel(Text(L("6-digit PIN")))
                        .padding(.vertical, 18)
                        .background(Color.kenniCard,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(KenniGradient.cool.opacity(0.7), lineWidth: 1.5))
                        .onChange(of: pin) { _, value in
                            pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        }
                }

                Button {
                    verify()
                } label: {
                    Label(L("Verify business"), systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(KenniPrimaryButtonStyle(isEnabled: pin.count == 6))
                .disabled(pin.count != 6)

                Text(L("PINs expire after 90 seconds and work only once. KENNI checks the issuing device's revocation status online."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .onAppear { pinFocused = true }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Color.kenniCoral)
            Text(L("Business verification failed"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Try again")) { reset() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
        .padding(24)
    }

    private func verify() {
        guard pin.count == 6 else { return }
        let submittedPIN = pin
        pinFocused = false
        phase = .verifying
        Task {
            do {
                phase = .verified(try await BusinessAPIClient.verifyBusiness(pin: submittedPIN))
            } catch APIError.http(410, _) {
                phase = .failed(L("The PIN is invalid, expired, already used, or came from a revoked device."))
            } catch {
                phase = .failed(L("The PIN could not be checked. Make sure you are online and try again."))
            }
        }
    }

    private func reset() {
        pin = ""
        phase = .enteringPIN
        pinFocused = true
    }
}

private struct BusinessVerificationResult: View {
    let business: BusinessProfile
    let verifyAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                logo.padding(.top, 28)
                VStack(spacing: 8) {
                    Label(L("Verified active business device"),
                          systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KenniGradient.cool)
                    Text(business.name)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(L("Verified just now"))
                        .foregroundStyle(.secondary)
                }

                GradientBorderCard {
                    VStack(alignment: .leading, spacing: 20) {
                        detailRow(systemImage: "mappin.and.ellipse", title: L("Address")) {
                            Text(business.address)
                        }
                        if let websiteURL = business.websiteURL {
                            Divider()
                            detailRow(systemImage: "globe", title: L("Website")) {
                                Link(websiteURL.host ?? websiteURL.absoluteString,
                                     destination: websiteURL)
                            }
                        }
                    }
                }

                Text(L("KENNI checked that this PIN was issued by an enrolled device for this approved business and that the device has not been revoked."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(L("Verify another business"), action: verifyAnother)
                    .buttonStyle(KenniSecondaryButtonStyle())
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var logo: some View {
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

    private func detailRow<Content: View>(systemImage: String, title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3).foregroundStyle(KenniGradient.brand).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                content().font(.body.weight(.medium)).foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
    }
}
