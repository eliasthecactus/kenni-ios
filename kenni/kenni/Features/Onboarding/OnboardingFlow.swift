import SwiftUI

struct OnboardingFlow: View {
    @State private var model = OnboardingModel()

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            WelcomeView()
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .story: StoryView()
                    case .choice: ChoiceView()
                    case .phrase: RecoveryPhraseView()
                    case .confirmPhrase: PhraseConfirmView()
                    case .icloudBackup: ICloudBackupView()
                    case .restore: RestoreView()
                    case .lockSetup: LockSetupView()
                    case .profile: ProfileSetupView()
                    case .notifications: NotificationsView()
                    case .done: DoneView()
                    }
                }
        }
        .environment(model)
        .tint(.kenniBlue)
    }
}
