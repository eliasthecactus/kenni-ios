import SwiftUI

// MARK: - Screen 1: logo, tagline, language

struct WelcomeView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(KenniGradient.primary)
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(spacing: 8) {
                Text("KENNI")
                    .font(.system(size: 44, weight: .black))
                    .tracking(6)
                Text(L("Know who's really there."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            VStack(spacing: 16) {
                LanguagePickerButton()
                Button(L("Get started")) { model.path.append(.story) }
                    .buttonStyle(KenniPrimaryButtonStyle())
            }
        }
        .padding(24)
        .background(Color.kenniBackground)
    }
}

// MARK: - Screen 2: the three-page story

private struct StoryPage: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let text: String
    let gradient: LinearGradient
}

struct StoryView: View {
    @Environment(OnboardingModel.self) private var model
    @State private var page = 0

    private var pages: [StoryPage] {
        [
            StoryPage(id: 0, icon: "waveform.badge.exclamationmark",
                      title: L("Anyone can be faked"),
                      text: L("Scammers use AI to clone voices, chats and even video calls. \"Hi, it's me — I'm in trouble\" is no longer proof of anything."),
                      gradient: KenniGradient.warm),
            StoryPage(id: 1, icon: "key.horizontal.fill",
                      title: L("Your key can't"),
                      text: L("With KENNI, you and the people you trust exchange personal keys — ideally face to face, with a quick QR scan. No accounts, no passwords."),
                      gradient: KenniGradient.primary),
            StoryPage(id: 2, icon: "checkmark.seal.fill",
                      title: L("One tap: is it really them?"),
                      text: L("Something feels off? Tap the contact in KENNI. Their phone asks them to confirm — with a signature only their device can create."),
                      gradient: KenniGradient.cool),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { p in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: p.icon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(p.gradient)
                            .frame(height: 90)
                        Text(p.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text(p.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        Spacer()
                        Spacer()
                    }
                    .padding(24)
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page < 2 ? L("Continue") : L("I get it")) {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    model.path.append(.choice)
                }
            }
            .buttonStyle(KenniPrimaryButtonStyle())
            .padding(24)
        }
        .background(Color.kenniBackground)
    }
}

// MARK: - Screen 3: new or returning

struct ChoiceView: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingHeader(
                systemImage: "person.crop.circle.badge.questionmark",
                title: L("Have you used KENNI before?"),
                subtitle: L("Your identity is a key that only you hold. It can be restored — but never recreated."))
            Spacer()
            VStack(spacing: 12) {
                Button(L("I'm new here")) { model.startNew() }
                    .buttonStyle(KenniPrimaryButtonStyle())
                Button(L("I already have a KENNI identity")) { model.startRestore() }
                    .buttonStyle(KenniSecondaryButtonStyle())
            }
        }
        .padding(24)
        .background(Color.kenniBackground)
    }
}
