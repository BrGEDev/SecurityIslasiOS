//
//  RootView.swift
//  SecurityIslas
//
//  Cambia de raíz según el estado de la sesión.
//

import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .launching:
                LaunchView()
            case .signedOut:
                OnboardingFlowView(model: OnboardingModel(
                    auth: container.auth,
                    registration: container.registration,
                    devices: container.devices,
                    session: session
                ))
            case .pendingApproval(let profile):
                PendingApprovalView(profile: profile)
            case .needsSetup(let profile, let returningUser):
                SetupFlowView(profile: profile, returningUser: returningUser)
            case .active(let profile):
                MainTabView(profile: profile)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .task {
            await session.bootstrap()
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color.accentColor, in: .rect(cornerRadius: 22))
        }
        .accessibilityLabel(AppInfo.name)
    }
}
