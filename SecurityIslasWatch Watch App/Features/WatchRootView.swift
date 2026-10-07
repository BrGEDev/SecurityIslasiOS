//
//  WatchRootView.swift
//  SecurityIslasWatch Watch App
//
//  Raíz según la sesión del reloj: sin vincular → instrucciones con la
//  animación del vínculo; alta en revisión → aviso; activa → Inicio (40).
//

import SwiftUI

struct WatchRootView: View {
    @Environment(WatchContainer.self) private var container
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if case .succeeded(let verification) = container.linkState {
                WatchLinkSuccessView(verification: verification)
            } else {
                switch session.state {
                case .launching:
                    ProgressView()
                case .active(let profile):
                    WatchHomeView(profile: profile)
                case .pendingApproval:
                    WatchMessageView(
                        systemImage: "hourglass",
                        title: "Alta en revisión",
                        message: "Cuando la administración apruebe tu alta podrás usar el reloj."
                    )
                case .signedOut, .needsSetup:
                    WatchLinkView()
                }
            }
        }
        .animation(.smooth, value: container.linkState)
        .task { await session.bootstrap() }
    }
}

/// Pantalla de un solo mensaje (alta en revisión, errores).
struct WatchMessageView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Sin sesión: el reloj se vincula desde el iPhone (WatchConnectivity solo para
/// la sesión inicial). Mientras se vincula muestra el mismo código que el iPhone.
struct WatchLinkView: View {
    @Environment(WatchContainer.self) private var container
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    PairingOrb(phase: isLinking ? .linking : .idle, size: 110, symbol: "iphone")

                    switch container.linkState {
                    case .linking(let verification):
                        Text("Vinculando…")
                            .font(.headline)
                        WatchVerificationDigits(code: verification)
                        Text("Debe coincidir con tu iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    default:
                        Text("Vincula tu reloj")
                            .font(.title3.weight(.semibold))
                        Text("En tu iPhone ve a Cuenta › Dispositivos › Vincular Apple Watch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if case .failed(let message) = container.linkState {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else if let notice = session.notice {
                            Label(notice, systemImage: "info.circle")
                                .font(.footnote)
                        }
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(AppInfo.name)
            .containerBackground(BrandPalette.backdrop(BrandPalette.blue), for: .navigation)
        }
    }

    private var isLinking: Bool {
        if case .linking = container.linkState { return true }
        return false
    }
}

/// Vínculo terminado: palomita, el código y un botón para empezar.
struct WatchLinkSuccessView: View {
    let verification: String
    @Environment(WatchContainer.self) private var container

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    PairingOrb(phase: .done, size: 100)
                    Text("Listo")
                        .font(.title2.weight(.bold))
                    Text("Tu reloj ya tiene su llave. Funciona aunque el iPhone no esté cerca.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Empezar") {
                        container.finishLinking()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandPalette.green[1])
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }
            .containerBackground(BrandPalette.backdrop(BrandPalette.green), for: .navigation)
        }
    }
}

struct WatchVerificationDigits: View {
    let code: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(code.enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .frame(width: 30, height: 38)
                    .background(.white.opacity(0.15), in: .rect(cornerRadius: 8, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Código \(code.map(String.init).joined(separator: " "))")
    }
}
