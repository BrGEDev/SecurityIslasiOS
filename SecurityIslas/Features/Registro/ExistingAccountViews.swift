//
//  ExistingAccountViews.swift
//  SecurityIslas
//
//  Pantallas 3a (Ya tienes cuenta) y 3b (Ya tienes 3 dispositivos).
//

import SwiftUI

/// 3a: sin registro ni aprobación. Sigue a permisos (7), Face ID (8) e Inicio.
struct ExistingAccountView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        if let verification = model.verification {
            content(verification)
        } else {
            ProgressView()
        }
    }

    private func content(_ verification: VerificationResult) -> some View {
        let profile = verification.profile
        let deviceNumber = min(verification.devices.count + 1, verification.maxDevices)

        return ScrollView {
            VStack(spacing: 20) {
                InitialsAvatar(initials: profile.initials, size: 88, tint: .accentColor)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Hola de nuevo,\n\(profile.firstName)")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Encontramos tu cuenta con el \(model.phone.formatted).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 0) {
                    if let residence = profile.residence {
                        row(
                            icon: "house",
                            title: residence.name,
                            subtitle: "\(residence.fraccionamientoName) · \(profile.role.title.lowercased())"
                        )
                        Divider().padding(.leading, 60)
                    }
                    row(
                        icon: "iphone",
                        title: "Este iPhone",
                        subtitle: verification.reachedDeviceLimit
                            ? "Ya tienes \(verification.maxDevices) dispositivos"
                            : "Dispositivo \(deviceNumber) de \(verification.maxDevices)"
                    )
                }
                .cardBackground()

                FootnoteLabel(text: "Avisaremos a tus otros dispositivos que entraste en este iPhone.", systemImage: "bell")
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button("Continuar") { model.continueAsExistingUser() }
                    .buttonStyle(.islasPrimary)
                Button("No soy yo") { model.restart() }
            }
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

/// 3b: solo aparece si la cuenta ya tiene 3 dispositivos (RF-66). El que se
/// quita pierde su llave y su sesión al instante y recibe un aviso.
struct DeviceLimitView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        List {
            ListHeaderSection(
                title: "Ya tienes 3 dispositivos",
                subtitle: "Para usar este iPhone, quita uno. Dejará de abrir la pluma y de recibir avisos."
            )

            Section {
                ForEach(model.verification?.devices ?? []) { device in
                    Button {
                        model.deviceToRemove = device
                    } label: {
                        RadioRow(
                            title: device.name,
                            subtitle: "Último uso \(device.lastUsedAt.formatted(.relative(presentation: .named)))",
                            isSelected: model.deviceToRemove == device
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(model.deviceToRemove == device ? Color.accentColor.opacity(0.08) : nil)
                }
            } footer: {
                FootnoteLabel(text: "Recomendamos quitar el que ya no usas.")
                    .padding(.top, 6)
            }

            if let error = model.errorMessage {
                Section { InlineError(message: error) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                AsyncButton("Quitar y continuar") {
                    await model.removeDeviceAndContinue()
                }
                .buttonStyle(.islasPrimary)
                .disabled(model.deviceToRemove == nil)

                Button("Cancelar") { model.path.removeLast() }
            }
        }
    }
}
