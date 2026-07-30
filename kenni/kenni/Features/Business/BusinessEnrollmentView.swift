import SwiftUI
import UIKit

struct BusinessEnrollmentView: View {
    @Environment(BusinessCredentialStore.self) private var businessStore
    @Environment(\.dismiss) private var dismiss
    @State private var linkText: String
    @State private var isScanning = false
    @State private var isEnrolling = false
    @State private var errorMessage: String?

    init(link: BusinessEnrollmentLink? = nil) {
        _linkText = State(initialValue: link.map {
            "kenni://business/enroll?token=\($0.token)"
        } ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    ScannerView(prompt: L("Scan the enrollment QR from your administrator.")) {
                        scanned($0)
                    }
                } else {
                    enrollmentForm
                }
            }
            .background(Color.kenniBackground)
            .navigationTitle(L("Business setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
        .tint(.kenniBlue)
        .task {
            if !linkText.isEmpty { await enroll() }
        }
    }

    private var enrollmentForm: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(
                    systemImage: "building.2.crop.circle",
                    title: L("Set up a business device"),
                    subtitle: L("Scan the one-time QR created by your KENNI administrator. This device will receive its own revocable business credential."),
                    gradient: KenniGradient.cool)
                    .padding(.top, 24)

                Button {
                    isScanning = true
                } label: {
                    Label(L("Scan enrollment QR"), systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(KenniPrimaryButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Or paste the enrollment link"))
                        .font(.headline)
                    TextEditor(text: $linkText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 100)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(Color.kenniCard,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.12)))
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.kenniAmber)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await enroll() }
                } label: {
                    if isEnrolling { ProgressView().tint(.kenniInk) }
                    else { Text(L("Enroll this device")) }
                }
                .buttonStyle(KenniPrimaryButtonStyle(
                    isEnabled: !linkText.isEmpty && !isEnrolling))
                .disabled(linkText.isEmpty || isEnrolling)

                Text(L("Enrollment links work once and expire after seven days."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    private func scanned(_ value: String) {
        guard BusinessEnrollmentLink(text: value) != nil else {
            isScanning = false
            errorMessage = L("That is not a valid KENNI business enrollment QR.")
            return
        }
        linkText = value
        isScanning = false
        Task { await enroll() }
    }

    @MainActor
    private func enroll() async {
        guard !isEnrolling else { return }
        guard let link = BusinessEnrollmentLink(text: linkText) else {
            errorMessage = L("That is not a valid KENNI business enrollment link.")
            return
        }
        isEnrolling = true
        errorMessage = nil
        defer { isEnrolling = false }
        do {
            try await businessStore.enroll(link: link)
            dismiss()
        } catch APIError.http(409, _), APIError.http(410, _) {
            errorMessage = L("This enrollment link has expired or was already used.")
        } catch {
            errorMessage = L("Enrollment failed. Check your connection and try again.")
        }
    }
}

extension Notification.Name {
    static let kenniDeviceDidShake = Notification.Name("kenni.deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: .kenniDeviceDidShake, object: nil)
    }
}
