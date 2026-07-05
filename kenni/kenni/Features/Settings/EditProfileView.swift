import SwiftUI
import SwiftData

/// Edit the user's own name after onboarding. Changes are local — the new name
/// reaches a contact only the next time you share your code with them.
struct EditProfileView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var name = ""
    @State private var loaded = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TextField(L("Your name"), text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
                    .textContentType(.name)

                Label {
                    Text(L("People you already exchanged keys with keep your old name until you share your code with them again."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.kenniBlue)
                }
                .padding(14)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))

                Button(L("Save")) { save() }
                    .buttonStyle(KenniPrimaryButtonStyle(
                        isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
        }
        .background(Color.kenniBackground)
        .navigationTitle(L("Your name"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            name = profile?.name ?? ""
            loaded = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let profile {
            profile.name = trimmed
        } else {
            modelContext.insert(UserProfile(name: trimmed))
        }
        try? modelContext.save()
        // Keep the vault's display name (shown in the restore chooser) in step.
        identityStore.updateStoredName(trimmed)
        dismiss()
    }
}
