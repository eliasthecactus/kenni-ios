import SwiftUI

/// A scalable language chooser: a tappable row that pushes a searchable list with
/// a checkmark on the current language. Adding a language only means extending
/// `AppLanguage` — no layout changes here.
struct LanguageRow: View {
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        NavigationLink {
            LanguageList()
        } label: {
            HStack {
                Label(L("Language"), systemImage: "globe")
                Spacer()
                Text("\(languageStore.language.flag) \(languageStore.language.nativeName)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LanguageList: View {
    @Environment(LanguageStore.self) private var languageStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var languages: [AppLanguage] {
        guard !search.isEmpty else { return AppLanguage.allCases }
        return AppLanguage.allCases.filter {
            $0.nativeName.localizedCaseInsensitiveContains(search)
                || $0.englishName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            ForEach(languages) { lang in
                Button {
                    languageStore.language = lang
                    dismiss()
                } label: {
                    HStack {
                        Text(lang.flag)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lang.nativeName).foregroundStyle(.primary)
                            if lang.englishName != lang.nativeName {
                                Text(lang.englishName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if lang == languageStore.language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .tint(.kenniCyan)
            }
        }
        .searchable(text: $search, prompt: L("Search languages"))
        .navigationTitle(L("Language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Compact variant for the onboarding welcome screen: a pill that opens the list.
struct LanguagePickerButton: View {
    @Environment(LanguageStore.self) private var languageStore
    @State private var showList = false

    var body: some View {
        Button {
            showList = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text("\(languageStore.language.flag) \(languageStore.language.nativeName)")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showList) {
            NavigationStack {
                LanguageList()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("Done")) { showList = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
