import SwiftUI

struct BusinessIdentificationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var phase: Phase = .idle
    @FocusState private var pinIsFocused: Bool

    private enum Phase: Equatable {
        case idle
        case loading
        case invalidPIN
        case rateLimited
        case unavailable
        case identified(APIClient.Business)
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .identified(let business) = phase {
                    BusinessOverview(business: business) {
                        pin = ""
                        phase = .idle
                        pinIsFocused = true
                    }
                } else {
                    pinEntry
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kenniBackground)
            .navigationTitle(L("Identify a business"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .tint(.kenniBlue)
    }

    private var pinEntry: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(
                    systemImage: "building.2.crop.circle",
                    title: L("Identify an approved business"),
                    subtitle: L("Enter the six-digit PIN shared by the business to see its verified profile."),
                    gradient: KenniGradient.cool)
                    .padding(.top, 34)

                GradientBorderCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Business PIN"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(L("6-digit PIN"), text: $pin)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($pinIsFocused)
                            .onChange(of: pin) { _, value in
                                pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                if isError { phase = .idle }
                            }
                            .onSubmit { identify() }
                            .padding(.vertical, 8)
                            .accessibilityLabel(L("Business PIN"))
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.kenniAmber)
                        .multilineTextAlignment(.center)
                }

                Button(action: identify) {
                    if phase == .loading {
                        ProgressView()
                            .tint(.kenniInk)
                    } else {
                        Text(L("Identify business"))
                    }
                }
                .buttonStyle(KenniPrimaryButtonStyle(isEnabled: canSubmit))
                .disabled(!canSubmit)

                Label(L("Only businesses added by KENNI administrators can be identified."),
                      systemImage: "checkmark.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { pinIsFocused = true }
    }

    private var canSubmit: Bool {
        pin.count == 6 && phase != .loading
    }

    private var isError: Bool {
        switch phase {
        case .invalidPIN, .rateLimited, .unavailable: true
        default: false
        }
    }

    private var errorMessage: String? {
        switch phase {
        case .invalidPIN:
            L("No approved business matches this PIN.")
        case .rateLimited:
            L("Too many attempts. Please wait a minute and try again.")
        case .unavailable:
            L("Business identification is unavailable right now.")
        default:
            nil
        }
    }

    private func identify() {
        guard canSubmit else { return }
        pinIsFocused = false
        phase = .loading
        let submittedPIN = pin
        Task {
            do {
                phase = .identified(try await APIClient.identifyBusiness(pin: submittedPIN))
            } catch APIError.http(404, _) {
                phase = .invalidPIN
                pinIsFocused = true
            } catch APIError.http(429, _) {
                phase = .rateLimited
            } catch {
                phase = .unavailable
            }
        }
    }
}

private struct BusinessOverview: View {
    let business: APIClient.Business
    let identifyAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                logo
                    .padding(.top, 28)

                VStack(spacing: 8) {
                    Label(L("Approved business"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KenniGradient.cool)
                    Text(business.name)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }

                GradientBorderCard {
                    VStack(alignment: .leading, spacing: 20) {
                        detailRow(systemImage: "mappin.and.ellipse", title: L("Address")) {
                            Text(business.address)
                        }
                        if let websiteURL = business.websiteURL {
                            Divider()
                            detailRow(systemImage: "globe", title: L("Website")) {
                                Link(websiteURL.host() ?? websiteURL.absoluteString,
                                     destination: websiteURL)
                            }
                        }
                    }
                }

                Text(L("This profile was approved by KENNI and revealed with the business's private PIN."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(L("Identify another business"), action: identifyAnother)
                    .buttonStyle(KenniSecondaryButtonStyle())
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var logo: some View {
        AsyncImage(url: business.logoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "building.2.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .foregroundStyle(KenniGradient.cool)
            }
        }
        .frame(width: 112, height: 112)
        .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(KenniGradient.cool.opacity(0.6), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func detailRow<Content: View>(systemImage: String, title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(KenniGradient.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                content()
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
    }
}
