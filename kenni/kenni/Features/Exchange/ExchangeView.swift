import SwiftUI
import SwiftData
import CryptoKit
import UIKit

/// "Add contact" sheet: show my code / scan theirs. After scanning, offers to
/// show your own code back so the exchange becomes mutual.
struct ExchangeView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var contacts: [Contact]

    enum Tab { case myCode, scan }
    @State private var tab: Tab = .myCode
    @State private var scanned: IdentityBundle?
    @State private var scanError: String?
    @State private var justAddedName: String?
    @State private var copiedCode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("", selection: $tab) {
                    Text(L("My code")).tag(Tab.myCode)
                    Text(L("Scan")).tag(Tab.scan)
                }
                .pickerStyle(.segmented)

                if tab == .myCode {
                    myCode
                } else {
                    scanArea
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.kenniBackground)
            .navigationTitle(L("Add contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $scanned) { bundle in
                ContactPreviewSheet(bundle: bundle) { add(bundle) }
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: My code

    private var myCode: some View {
        VStack(spacing: 16) {
            if let justAddedName {
                Label(L("%@ added — now let them scan you.", justAddedName),
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.kenniCyan)
            }
            if let identity = identityStore.identity,
               let bundle = try? IdentityBundle.make(identity: identity,
                                                     name: profiles.first?.name ?? "") {
                QRCodeView(content: bundle.qrString)
                    .frame(maxWidth: 280)
                FingerprintBadge(fingerprint: identity.fingerprint)
                Text(L("Let the other person scan this with KENNI — ideally face to face. That's what makes the key trustworthy."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                shareLinkButton(bundle: bundle)
            }
        }
    }

    /// The link carries the identity card inside it, so sharing works fully
    /// offline — no server needed. Handy when you can't meet in person or the
    /// other device has no camera to scan the QR.
    @ViewBuilder
    private func shareLinkButton(bundle: IdentityBundle) -> some View {
        if let shareURL = bundle.shareURL {
            ShareLink(item: shareURL) {
                Label(L("Share my link"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(KenniSecondaryButtonStyle())
        }
        Button {
            UIPasteboard.general.string = bundle.qrString
            copiedCode = true
        } label: {
            Label(copiedCode ? L("Code copied") : L("Copy my code"),
                  systemImage: copiedCode ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(KenniSecondaryButtonStyle())
    }

    // MARK: Scan

    private var scanArea: some View {
        VStack(spacing: 12) {
            ScannerView(prompt: L("Point the camera at their KENNI code.")) { code in
                handle(code)
            }
            if let scanError {
                Text(scanError)
                    .font(.footnote)
                    .foregroundStyle(Color.kenniCoral)
            }
        }
    }

    private func handle(_ code: String) {
        scanError = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept a raw KENNI code, or a pasted share link (bundle rides in ?b=).
        let bundle = IdentityBundle(qrString: trimmed) ?? bundleFromLink(trimmed)
        if let bundle {
            guard bundle.id != identityStore.identity?.signingKey.publicKey.rawRepresentation else {
                scanError = L("That's your own code.")
                return
            }
            scanned = bundle
        } else if trimmed.hasPrefix(VerifyChallenge.qrPrefix) || trimmed.hasPrefix(VerifyResponse.qrPrefix) {
            scanError = L("That's a verification code — open the contact and use \"Verify in person\".")
        } else {
            scanError = L("That doesn't look like a valid KENNI code.")
        }
    }

    private func bundleFromLink(_ string: String) -> IdentityBundle? {
        guard let components = URLComponents(string: string),
              let param = components.queryItems?.first(where: { $0.name == "b" })?.value else {
            return nil
        }
        return IdentityBundle(linkParam: param)
    }

    private func add(_ bundle: IdentityBundle) {
        guard let identity = identityStore.identity else { return }
        do {
            if let existing = contacts.first(where: { $0.idKey == bundle.id }) {
                existing.name = bundle.name
                existing.kaKey = bundle.ka
            } else {
                let secret = try Pairwise.secret(myAgreementKey: identity.agreementKey,
                                                 theirAgreementKey: bundle.ka)
                modelContext.insert(Contact(idKey: bundle.id, kaKey: bundle.ka,
                                            name: bundle.name, pairwiseSecret: secret))
            }
            try modelContext.save()
            justAddedName = bundle.name
            scanned = nil
            tab = .myCode // nudge towards the mutual exchange
        } catch {
            scanned = nil
            scanError = L("Couldn't save this contact. Please try again.")
        }
    }
}

// `id` (the Ed25519 key) is unique per person, so it doubles as the Identifiable id.
extension IdentityBundle: Identifiable {}

private struct ContactPreviewSheet: View {
    let bundle: IdentityBundle
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(KenniGradient.cool)
            Text(bundle.name)
                .font(.title2.bold())
            FingerprintBadge(fingerprint: bundle.fingerprint)
            Text(L("Signature checked. If you're together, compare this fingerprint with their screen."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Add contact")) { onAdd() }
                .buttonStyle(KenniPrimaryButtonStyle())
            Button(L("Cancel")) { dismiss() }
                .buttonStyle(KenniSecondaryButtonStyle())
        }
        .padding(24)
        .background(Color.kenniBackground)
    }
}
