import SwiftUI

struct OnboardingFlow: View {
    @State private var model = OnboardingModel()
    @State private var showBusinessQuestion = false
    @State private var showBusinessSetup = false

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
        .onReceive(NotificationCenter.default.publisher(for: .kenniDeviceDidShake)) { _ in
            showBusinessQuestion = true
        }
        .accessibilityAction(named: Text(L("Set up a business device"))) {
            showBusinessQuestion = true
        }
        .confirmationDialog(
            L("Set up this device for a business?"),
            isPresented: $showBusinessQuestion,
            titleVisibility: .visible
        ) {
            Button(L("Continue with business setup")) { showBusinessSetup = true }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("You will need the one-time QR or link created by a KENNI administrator."))
        }
        .sheet(isPresented: $showBusinessSetup) {
            BusinessEnrollmentView()
        }
        .environment(model)
        .tint(.kenniBlue)
    }
}
