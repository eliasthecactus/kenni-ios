import SwiftUI

struct BusinessIdentificationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var challenge = BusinessAPIClient.makeChallenge()
    @State private var phase: Phase = .showingChallenge

    private enum Phase: Equatable {
        case showingChallenge
        case scanningResponse
        case verifying
        case verified(BusinessProfile)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .showingChallenge:
                    challengeView
                case .scanningResponse:
                    ScannerView(prompt: L("Scan the one-time response on the business device.")) {
                        verify(responseURL: $0)
                    }
                case .verifying:
                    VStack(spacing: 18) {
                        ProgressView()
                        Text(L("Checking the business device…"))
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

    private var challengeView: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(
                    systemImage: "building.2.crop.circle",
                    title: L("Verify an approved business"),
                    subtitle: L("Let the representative scan this fresh challenge with their enrolled KENNI business device."),
                    gradient: KenniGradient.cool)
                    .padding(.top, 24)

                QRCodeView(content: BusinessChallengeLink(challenge: challenge).urlString)
                    .frame(maxWidth: 280)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))

                VStack(spacing: 8) {
                    Label(L("Fresh one-time challenge"), systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                    Text(L("The response works only for this screen and expires after 90 seconds."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    phase = .scanningResponse
                } label: {
                    Label(L("Scan business response"), systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(KenniPrimaryButtonStyle())
            }
            .padding(24)
        }
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

    private func verify(responseURL: String) {
        phase = .verifying
        let expectedChallenge = challenge
        Task {
            do {
                phase = .verified(try await BusinessAPIClient.verifyConfirmation(
                    responseURL: responseURL, challenge: expectedChallenge))
            } catch APIError.http(410, _) {
                phase = .failed(L("The response expired, was already used, or came from a revoked device."))
            } catch {
                phase = .failed(L("The response could not be checked. Make sure you are online and try again."))
            }
        }
    }

    private func reset() {
        challenge = BusinessAPIClient.makeChallenge()
        phase = .showingChallenge
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

                Text(L("KENNI checked that the responding device is enrolled for this approved business and has not been revoked."))
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
