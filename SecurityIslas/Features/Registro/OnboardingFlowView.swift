//
//  OnboardingFlowView.swift
//  SecurityIslas
//

import SwiftUI

struct OnboardingFlowView: View {
    @State private var model: OnboardingModel
    @Environment(AppContainer.self) private var container

    init(model: OnboardingModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(model: model)
                .navigationDestination(for: OnboardingRoute.self) { route in
                    switch route {
                    case .phone: PhoneNumberView(model: model)
                    case .code: VerificationCodeView(model: model)
                    case .existingAccount: ExistingAccountView(model: model)
                    case .deviceLimit: DeviceLimitView(model: model)
                    case .fraccionamiento: FraccionamientoView(model: model)
                    case .home: HomeRegistrationView(model: model)
                    }
                }
        }
        .onChange(of: container.pendingInviteCode, initial: true) { _, code in
            guard let code else { return }
            model.inviteCode = code
            container.pendingInviteCode = nil
        }
    }
}
