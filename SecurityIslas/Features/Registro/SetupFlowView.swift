//
//  SetupFlowView.swift
//  SecurityIslas
//
//  Pantallas 7 (Avisos y ubicación) y 8 (Face ID). Se muestran al aprobarse
//  el alta o al entrar con una cuenta existente en un iPhone nuevo.
//

import LocalAuthentication
import SwiftUI
import UIKit
import UserNotifications

struct SetupFlowView: View {
    let profile: UserProfile
    let returningUser: Bool

    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            PermissionsView(profile: profile, returningUser: returningUser) {
                path.append(8)
            }
            .navigationDestination(for: Int.self) { _ in
                FaceIDSetupView()
            }
        }
    }
}

/// 7: cada permiso se explica antes de que aparezca el aviso de iOS. La
/// ubicación se pide "al usarse la app"; "Siempre" se pide después, al
/// configurar el pánico. Si rechaza alguno puede continuar.
struct PermissionsView: View {
    let profile: UserProfile
    let returningUser: Bool
    let onContinue: () -> Void

    @Environment(AppContainer.self) private var container

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OnboardingHeader(
                    title: returningUser ? "Bienvenido de nuevo, \(profile.firstName)" : "¡Listo, \(profile.firstName)!",
                    subtitle: returningUser
                        ? "Activa estos permisos en este iPhone para que todo funcione."
                        : "Tu alta fue aprobada. Activa estos permisos para que todo funcione."
                )

                PermissionCard(
                    icon: "bell.fill",
                    tint: .red,
                    title: "Notificaciones",
                    detail: "Para avisarte al instante cuando llegue una visita o un servicio, aunque tengas un modo de concentración.",
                    isGranted: container.notifications.authorization == .authorized
                        || container.notifications.authorization == .provisional,
                    isDenied: container.notifications.authorization == .denied
                ) {
                    await container.notifications.requestAuthorization()
                }

                PermissionCard(
                    icon: "location.fill",
                    tint: .green,
                    title: "Ubicación",
                    detail: "Para abrir la pluma cuando estés cerca de la entrada.",
                    isGranted: container.location.authorization.isGranted,
                    isDenied: container.location.authorization == .denied
                ) {
                    container.location.requestWhenInUse()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .readableContentWidth()
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button("Continuar", action: onContinue)
                    .buttonStyle(.islasPrimary)
            }
        }
        .onAppear { container.notifications.refreshStatus() }
    }
}

private struct PermissionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let isGranted: Bool
    let isDenied: Bool
    let request: () async -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isGranted {
                StatusChip(text: "Activado", tint: .green)
            } else if isDenied {
                Button("Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
            } else {
                AsyncButton("Activar", action: request)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding()
        .cardBackground()
    }
}

/// 8: aquí se crea la llave del dispositivo, atada a Face ID (RF-67, RNF-05).
struct FaceIDSetupView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?

    private var biometryName: String { container.biometrics.biometryName }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: container.biometrics.biometryIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 96, height: 96)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Protege tu llave con \(biometryName)")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("Tu iPhone es la llave de tu casa. Te pediremos \(biometryName) para:")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 0) {
                    useRow("road.lanes", "Abrir la pluma")
                    Divider().padding(.leading, 48)
                    useRow("arrow.triangle.2.circlepath", "Recurrentes y autorizaciones automáticas")
                    Divider().padding(.leading, 48)
                    useRow("person", "Cambios en tu cuenta y tu familia")
                }
                .cardBackground()

                InlineError(message: errorMessage)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .readableContentWidth()
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                AsyncButton("Activar \(biometryName)") { await activate() }
                    .buttonStyle(.islasPrimary)
                AsyncButton("Usar el código del iPhone") { await activate() }
            }
        }
    }

    private func useRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(text).font(.body.weight(.medium))
            Spacer()
        }
        .padding(14)
    }

    private func activate() async {
        errorMessage = nil
        do {
            _ = try await container.devices.registerThisDevice()
            session.completeSetup()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
