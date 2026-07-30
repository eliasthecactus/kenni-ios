import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Query private var profiles: [UserProfile]
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var showSettings = false
    @State private var showExchange = false
    @State private var showBusinessIdentification = false
    @State private var search = ""

    private var profile: UserProfile? { profiles.first }

    private var filteredContacts: [Contact] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    identityCard
                    businessIdentificationButton
                    contactsSection
                }
                .padding(20)
            }
            .background(Color.kenniBackground)
            .navigationTitle(greeting)
            .searchable(text: $search, prompt: L("Search contacts"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExchange = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showExchange) { ExchangeView() }
            .sheet(isPresented: $showBusinessIdentification) {
                BusinessIdentificationView()
            }
            .navigationDestination(for: Contact.self) { contact in
                ContactDetailView(contact: contact)
            }
        }
        .tint(.kenniBlue)
    }

    private var greeting: String {
        if let name = profile?.name, !name.isEmpty {
            return L("Hi %@", name)
        }
        return "KENNI"
    }

    private var identityCard: some View {
        GradientBorderCard {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.name ?? "")
                        .font(.headline)
                    if let identity = identityStore.identity {
                        Text(identity.fingerprint)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showExchange = true
                } label: {
                    Image(systemName: "qrcode")
                        .font(.title2)
                        .foregroundStyle(KenniGradient.brand)
                }
            }
        }
    }

    private var businessIdentificationButton: some View {
        Button {
            showBusinessIdentification = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(KenniGradient.cool)
                    .frame(width: 44, height: 44)
                    .background(Color.kenniBackground, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Identify a business"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("View an approved business profile with its PIN."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(KenniGradient.cool.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contactsSection: some View {
        if contacts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(KenniGradient.cool)
                Text(L("No contacts yet"))
                    .font(.headline)
                Text(L("Exchange keys with someone you trust — face to face is best."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L("Add your first contact")) { showExchange = true }
                    .buttonStyle(KenniPrimaryButtonStyle())
                    .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 20))
        } else {
            VStack(spacing: 10) {
                ForEach(filteredContacts, id: \.persistentModelID) { contact in
                    NavigationLink(value: contact) {
                        ContactRow(contact: contact)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 14) {
            if let data = contact.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
            } else {
                Text(contact.initials)
                    .font(.subheadline.bold())
                    .frame(width: 46, height: 46)
                    .background(Color.kenniBackground, in: Circle())
                    .overlay(Circle().strokeBorder(KenniGradient.cool.opacity(0.5), lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(contact.fingerprint)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TrustBadge(level: contact.trustLevel)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 16))
    }
}
