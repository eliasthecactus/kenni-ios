import SwiftUI
import SwiftData
import CryptoKit

/// Opens when a benavo.ch/x?b=<bundle> link lands in the app. The identity card
/// is embedded in the link, so this works fully offline — no server fetch.
struct AddFromLinkView: View {
    let bundleParam: String
    @Environment(IdentityStore.self) private var identityStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var contacts: [Contact]

    enum Phase {
        case preview(IdentityBundle)
        case added(String)
        case invalid
        case ownCode
    }

    @State private var phase: Phase = .invalid

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch phase {
                case .preview(let bundle):
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 52))
                        .foregroundStyle(KenniGradient.cool)
                    Text(bundle.name)
                        .font(.title2.bold())
                    FingerprintBadge(fingerprint: bundle.fingerprint)
                    Text(L("Received via link. A link is a good start — scanning each other in person makes it trustworthy."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                    Button(L("Add contact")) { add(bundle) }
                        .buttonStyle(KenniPrimaryButtonStyle())
                case .added(let name):
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(KenniGradient.cool)
                        .symbolEffect(.bounce, options: .nonRepeating)
                    Text(L("%@ added — now let them scan you.", name))
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Spacer()
                    Button(L("Done")) { dismiss() }
                        .buttonStyle(KenniPrimaryButtonStyle())
                case .ownCode:
                    infoState(icon: "person.crop.circle.badge.questionmark",
                              title: L("That's your own code"),
                              text: L("This link is yours — share it with someone else so they can add you."))
                case .invalid:
                    infoState(icon: "exclamationmark.triangle.fill",
                              title: L("This link isn't valid"),
                              text: L("Ask them to share a fresh KENNI link or code."))
                }
            }
            .padding(24)
            .background(Color.kenniBackground)
            .navigationTitle(L("Add contact"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: decode)
    }

    private func infoState(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color.kenniAmber)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Close")) { dismiss() }
                .buttonStyle(KenniSecondaryButtonStyle())
        }
    }

    private func decode() {
        guard let bundle = IdentityBundle(linkParam: bundleParam) else {
            phase = .invalid
            return
        }
        guard bundle.id != identityStore.identity?.signingKey.publicKey.rawRepresentation else {
            phase = .ownCode
            return
        }
        phase = .preview(bundle)
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
                                            name: bundle.name, pairwiseSecret: secret,
                                            method: .link))
            }
            try modelContext.save()
            phase = .added(bundle.name)
        } catch {
            phase = .invalid
        }
    }
}
