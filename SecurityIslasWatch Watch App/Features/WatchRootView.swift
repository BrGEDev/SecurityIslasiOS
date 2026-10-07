//
//  WatchRootView.swift
//  SecurityIslasWatch Watch App
//
//  Raíz según la sesión del reloj: sin vincular → instrucciones; alta en
//  revisión → aviso; activa → Inicio del reloj (pantalla 40).
//

import SwiftUI

struct WatchRootView: View {
    @Environment(WatchContainer.self) private var container
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
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
/// la sesión inicial). El código llega solo; aquí se muestra cómo pedirlo.
struct WatchLinkView: View {
    @Environment(WatchContainer.self) private var container
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch container.linkState {
                case .linking:
                    ProgressView()
                    Text("Vinculando…")
                        .font(.headline)
                    Text("Creando la llave de este reloj.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .idle, .failed:
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Text("Vincula tu reloj")
                        .font(.headline)
                    Text("En tu iPhone abre \(AppInfo.name) › Cuenta › Dispositivos › Vincular Apple Watch.")
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
    }
}
