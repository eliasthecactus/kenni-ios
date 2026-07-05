import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct ContactDetailView: View {
    @Bindable var contact: Contact
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkMonitor.self) private var network
    @Query private var records: [VerificationRecord]

    @State private var showVerifyInPerson = false
    @State private var showLiveCheck = false
    @State private var showOfflineCodes = false
    @State private var confirmDelete = false
    @State private var photoItem: PhotosPickerItem?

    private var history: [VerificationRecord] {
        records
            .filter { $0.contactIdKey == contact.idKey }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                actions
                if !history.isEmpty { historySection }
                deleteButton
            }
            .padding(20)
        }
        .background(Color.kenniBackground)
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVerifyInPerson) {
            VerifyInPersonView(contact: contact)
        }
        .sheet(isPresented: $showLiveCheck) {
            VerifyCallView(contact: contact)
        }
        .sheet(isPresented: $showOfflineCodes) {
            OfflineVerifyView(contact: contact)
        }
        .confirmationDialog(L("Remove this contact?"), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button(L("Remove contact"), role: .destructive) {
                modelContext.delete(contact)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text(L("You'll need to exchange keys again to verify each other."))
        }
    }

    private var header: some View {
        GradientBorderCard {
            VStack(spacing: 12) {
                // A photo you add yourself, stored only on this device, to
                // recognise the contact at a glance. Tap to choose, long-press
                // to remove.
                PhotosPicker(selection: $photoItem, matching: .images) {
                    contactAvatar
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.kenniCyan)
                        }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if contact.avatarData != nil {
                        Button(role: .destructive) {
                            contact.avatarData = nil
                            try? modelContext.save()
                        } label: {
                            Label(L("Remove photo"), systemImage: "trash")
                        }
                    }
                }
                .onChange(of: photoItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            contact.avatarData = Self.downscaled(data)
                            try? modelContext.save()
                        }
                    }
                }
                Text(contact.name)
                    .font(.title3.bold())
                TrustBadge(level: contact.trustLevel)
                if contact.trustLevel != .verified {
                    Text(L("Only an in-person check marks this contact as Verified."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showVerifyInPerson = true
                    } label: {
                        Label(L("Verify in person"), systemImage: "person.badge.shield.checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(KenniGradient.cool, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                FingerprintBadge(fingerprint: contact.fingerprint)
            }
        }
    }

    @ViewBuilder private var contactAvatar: some View {
        if let data = contact.avatarData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
        } else {
            Text(contact.initials)
                .font(.title.bold())
                .frame(width: 72, height: 72)
                .background(Color.kenniBackground, in: Circle())
                .overlay(Circle().strokeBorder(KenniGradient.cool.opacity(0.7),
                                               lineWidth: 2))
        }
    }

    /// Contact photos live in the local SwiftData store — shrink to a thumbnail
    /// so a full-res pick doesn't bloat the database.
    private static func downscaled(_ data: Data, maxEdge: CGFloat = 256) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxEdge / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }

    private var actions: some View {
        VStack(spacing: 10) {
            ActionRow(icon: "person.fill.checkmark", tint: KenniGradient.brand,
                      title: L("Live check"),
                      subtitle: network.isOnline
                          ? L("They confirm on their phone — signed, in seconds.")
                          : L("Needs an internet connection."),
                      enabled: network.isOnline) { showLiveCheck = true }
            ActionRow(icon: "dial.low", tint: KenniGradient.warm,
                      title: L("Offline codes"),
                      subtitle: L("Spoken codes, no internet needed."),
                      enabled: true) { showOfflineCodes = true }
            // "Verify in person" lives in the header now, shown only while the
            // contact isn't verified yet — once verified it's not needed again.
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("History"))
                .font(.headline)
            ForEach(history, id: \.persistentModelID) { record in
                HStack {
                    Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(record.succeeded ? Color.kenniCyan : Color.kenniCoral)
                    Text(label(for: record.kind))
                        .font(.subheadline)
                    Spacer()
                    Text(record.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(for kind: VerificationKind) -> String {
        switch kind {
        case .inPerson: L("Verified in person")
        case .call: L("Live check passed")
        case .offline: L("Verified with offline codes")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label(L("Remove contact"), systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(KenniSecondaryButtonStyle())
        .foregroundStyle(Color.kenniCoral)
    }
}

/// A contact is either Verified (you confirmed in person) or not yet — that's the
/// only distinction that matters. "Exchanged" was noise: every contact is exchanged.
struct TrustBadge: View {
    let level: TrustLevel

    var body: some View {
        if level == .verified {
            Label(L("Verified"), systemImage: "checkmark.seal.fill")
                .badgeStyle(background: AnyShapeStyle(KenniGradient.cool),
                            foreground: AnyShapeStyle(.white))
        } else {
            Label(L("Not verified"), systemImage: "shield")
                .badgeStyle(background: AnyShapeStyle(Color.kenniCard),
                            foreground: AnyShapeStyle(.secondary))
        }
    }
}

private extension View {
    func badgeStyle(background: AnyShapeStyle, foreground: AnyShapeStyle) -> some View {
        self.font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }
}

private struct ActionRow: View {
    let icon: String
    let tint: LinearGradient
    let title: String
    let subtitle: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Text inside a Button defaults to centered multiline alignment;
                // force leading so wrapped subtitles line up under the title.
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? 1 : 0.55)
        }
        .disabled(!enabled)
    }
}
