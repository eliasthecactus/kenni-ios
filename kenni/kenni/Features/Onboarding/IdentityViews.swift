import SwiftUI

// MARK: - Recovery phrase display

struct RecoveryPhraseView: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(
                    systemImage: "square.grid.3x3.fill",
                    title: L("Your recovery phrase"),
                    subtitle: L("These 12 words are your identity. Write them down on paper and keep them somewhere safe."))

                if let words = model.draft?.mnemonic, words.count == 12 {
                    GradientBorderCard {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: 10) {
                            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, alignment: .trailing)
                                    Text(word)
                                        .font(.system(.body, design: .monospaced, weight: .semibold))
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.kenniBackground.opacity(0.6),
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                Label {
                    Text(L("Anyone with these words can become you — and without them, a lost phone can mean a lost identity. KENNI has no reset button. Don't screenshot them."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.kenniAmber)
                }
                .padding(14)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))

                Button(L("I wrote them down")) { model.path.append(.confirmPhrase) }
                    .buttonStyle(KenniPrimaryButtonStyle())
            }
            .padding(24)
        }
        .background(Color.kenniBackground)
        .navigationBarBackButtonHidden()
    }
}

// MARK: - Confirm 3 random words

struct PhraseConfirmView: View {
    @Environment(OnboardingModel.self) private var model
    @State private var quizzes: [(position: Int, options: [String])] = []
    @State private var current = 0
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 24) {
            OnboardingHeader(
                systemImage: "checklist",
                title: L("Quick check"),
                subtitle: L("Prove your phrase is really written down — pick the right words."))

            if current < quizzes.count {
                let quiz = quizzes[current]
                VStack(spacing: 16) {
                    Text(L("Which is word #%d?", quiz.position + 1))
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 10) {
                        ForEach(quiz.options, id: \.self) { option in
                            Button {
                                choose(option, for: quiz.position)
                            } label: {
                                Text(option)
                                    .font(.system(.body, design: .monospaced, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(KenniSecondaryButtonStyle())
                        }
                    }
                    if wrong {
                        Text(L("Not quite — check your written phrase."))
                            .font(.footnote)
                            .foregroundStyle(Color.kenniCoral)
                    }
                }
            }

            ProgressView(value: Double(current), total: Double(max(quizzes.count, 1)))
                .tint(.kenniCyan)
            Spacer()
        }
        .padding(24)
        .background(Color.kenniBackground)
        .onAppear(perform: buildQuizzes)
    }

    private func buildQuizzes() {
        guard quizzes.isEmpty, let words = model.draft?.mnemonic, words.count == 12,
              BIP39.wordlist.count == 2048 else { return }
        let positions = Array(0..<12).shuffled().prefix(3)
        quizzes = positions.map { position in
            var options: Set<String> = [words[position]]
            while options.count < 6 {
                if let candidate = BIP39.wordlist.randomElement(), !words.contains(candidate) {
                    options.insert(candidate)
                }
            }
            return (position, options.shuffled())
        }
    }

    private func choose(_ option: String, for position: Int) {
        guard let words = model.draft?.mnemonic else { return }
        if option == words[position] {
            wrong = false
            if current + 1 < quizzes.count {
                current += 1
            } else {
                model.phraseConfirmed()
            }
        } else {
            wrong = true
        }
    }
}

// MARK: - iCloud Keychain backup choice

struct ICloudBackupView: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 24) {
            OnboardingHeader(
                systemImage: "icloud.fill",
                title: L("Back up to iCloud Keychain?"),
                subtitle: L("Your key is stored end-to-end encrypted in your personal iCloud Keychain. If you lose this phone, a new iPhone restores it automatically."))

            GradientBorderCard {
                Toggle(isOn: $model.iCloudBackup) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("iCloud Keychain backup"))
                            .font(.headline)
                        Text(L("Recommended — you can change this anytime in settings."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.kenniCyan)
            }

            if !model.iCloudBackup {
                Label {
                    Text(L("Without iCloud, your written recovery phrase is the only way back into your identity."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.kenniAmber)
                }
                .padding(14)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
            Button(L("Continue")) { model.backupChosen() }
                .buttonStyle(KenniPrimaryButtonStyle())
        }
        .padding(24)
        .background(Color.kenniBackground)
    }
}

// MARK: - Restore (iCloud chooser or phrase — phrase path is fully offline)

struct RestoreView: View {
    @Environment(OnboardingModel.self) private var model
    @State private var found: [StoredIdentity] = []
    @State private var phraseText = ""
    @State private var phraseError: String?

    private var typedWords: [String] {
        phraseText.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(
                    systemImage: "arrow.counterclockwise.circle.fill",
                    title: L("Welcome back"),
                    subtitle: found.count > 1
                        ? L("Choose which identity to restore, or enter a recovery phrase.")
                        : L("Restore from iCloud Keychain or with your 12-word recovery phrase."))

                if !found.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { index, record in
                            identityRow(record, isMostRecent: index == 0)
                        }
                    }
                    dividerOr
                }

                phraseEntry
            }
            .padding(24)
        }
        .background(Color.kenniBackground)
        .onAppear { found = SeedVault.allIdentities() }
    }

    private func identityRow(_ record: StoredIdentity, isMostRecent: Bool) -> some View {
        Button {
            guard let identity = try? KenniIdentity(entropy: record.entropy) else { return }
            model.restored(identity: identity, record: record, fromICloud: true)
        } label: {
            GradientBorderCard {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(KenniGradient.cool)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(record.name.isEmpty ? L("KENNI identity") : record.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if isMostRecent {
                                Text(L("Last used"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(KenniGradient.cool, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(KenniIdentity.fingerprint(of: Data(base64URLEncoded: record.id) ?? Data()))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(L("Used %@", record.lastUsedAt.formatted(.relative(presentation: .named))))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var dividerOr: some View {
        HStack {
            VStack { Divider() }
            Text(L("or")).font(.footnote).foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }

    private var phraseEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Enter your recovery phrase"))
                .font(.headline)
            TextEditor(text: $phraseText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 110)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Text(L("%d of 12 words", typedWords.count))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let phraseError {
                Text(phraseError)
                    .font(.footnote)
                    .foregroundStyle(Color.kenniCoral)
            }
            Button(L("Restore from phrase")) { restoreFromPhrase() }
                .buttonStyle(KenniPrimaryButtonStyle(isEnabled: typedWords.count == 12))
                .disabled(typedWords.count != 12)
        }
    }

    private func restoreFromPhrase() {
        do {
            let identity = try KenniIdentity(mnemonic: typedWords)
            phraseError = nil
            // Reuse the stored name/last-used if this identity is already known here.
            let record = SeedVault.identity(id: identity.idString)
            model.restored(identity: identity, record: record, fromICloud: false)
        } catch BIP39Error.unknownWord(let word) {
            phraseError = L("\"%@\" is not a valid recovery word.", word)
        } catch BIP39Error.checksumMismatch {
            phraseError = L("That phrase doesn't check out — one or more words are in the wrong place.")
        } catch {
            phraseError = L("That phrase doesn't check out — one or more words are in the wrong place.")
        }
    }
}
