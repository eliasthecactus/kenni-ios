import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Edit the user's own name and photo after onboarding. Changes are local — they
/// reach a contact only the next time you share your code with them.
struct EditProfileView: View {
    @Environment(IdentityStore.self) private var identityStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var name = ""
    @State private var avatarData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack {
                        if let avatarData, let image = UIImage(data: avatarData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 110, height: 110)
                    .background(Color.kenniCard)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(KenniGradient.primary.opacity(0.7), lineWidth: 2))
                }
                .onChange(of: photoItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            avatarData = data
                        }
                    }
                }

                TextField(L("Your name"), text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
                    .textContentType(.name)

                Label {
                    Text(L("People you already exchanged keys with keep your old name and photo until you share your code with them again."))
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
        .navigationTitle(L("Name & photo"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            name = profile?.name ?? ""
            avatarData = profile?.avatarData
            loaded = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let profile {
            profile.name = trimmed
            profile.avatarData = avatarData
        } else {
            modelContext.insert(UserProfile(name: trimmed, avatarData: avatarData))
        }
        try? modelContext.save()
        // Keep the vault's display name (shown in the restore chooser) in step.
        identityStore.updateStoredName(trimmed)
        dismiss()
    }
}
