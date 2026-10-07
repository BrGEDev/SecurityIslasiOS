//
//  PendingApprovalView.swift
//  SecurityIslas
//
//  Pantalla 6. Sin aprobación la app no abre la pluma ni autoriza visitas
//  (RF-62). Al aprobarse llega una notificación y se continúa en la 7; aquí
//  además se consulta el estado cada pocos segundos.
//

import SwiftUI

struct PendingApprovalView: View {
    let profile: UserProfile
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL

    private var isRejected: Bool { profile.approvalStatus == .rejected }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: isRejected ? "xmark.circle" : "clock")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(isRejected ? Color.red : Color.orange)
                            .frame(width: 96, height: 96)
                            .background((isRejected ? Color.red : Color.orange).opacity(0.15), in: Circle())

                        Text(isRejected ? "Solicitud rechazada" : "Solicitud enviada")
                            .font(.title.bold())

                        Text(isRejected
                             ? (profile.rejectionReason ?? "La administración no pudo aprobar tu alta.")
                             : "La administración de \(profile.residence?.fraccionamientoName ?? "tu fraccionamiento") revisará tu alta. Te avisaremos con una notificación.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    statusRow(icon: "checkmark", tint: .green, title: "Teléfono verificado")
                    statusRow(
                        icon: "checkmark",
                        tint: .green,
                        title: profile.residence?.name ?? "Vivienda",
                        subtitle: profile.residence?.fraccionamientoName
                    )
                    statusRow(
                        icon: isRejected ? "xmark" : "clock",
                        tint: isRejected ? .red : .orange,
                        title: "Aprobación de la administración",
                        subtitle: isRejected ? "Rechazada" : "En revisión"
                    )
                } footer: {
                    FootnoteLabel(text: "Mientras tanto no puedes abrir la pluma ni autorizar visitas.")
                        .padding(.top, 6)
                }
            }
            .readableContentWidth()
            .refreshable { try? await session.refreshProfile() }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    if isRejected {
                        AsyncButton("Corregir mi solicitud") { await session.signOut() }
                            .buttonStyle(.islasPrimary)
                    }
                    Button("Llamar a la administración") {
                        if let url = URL.phone(AppInfo.adminPhone) { openURL(url) }
                    }
                    .buttonStyle(.islasSecondary)
                }
            }
        }
        .task(id: profile.approvalStatus) {
            guard !isRejected else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                try? await session.refreshProfile()
            }
        }
    }

    private func statusRow(icon: String, tint: Color, title: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
