//
//  OwnerHomeView.swift
//  SecurityIslas
//
//  Pantalla 38. Vista reducida del propietario no residente con la casa
//  rentada: su QR para entrar al fraccionamiento, sin botón de abrir; no
//  autoriza visitas ni ve la bitácora (RF-87).
//

import SwiftUI

struct OwnerHomeView: View {
    let profile: UserProfile
    @Environment(MainRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if #available(iOS 26, *) {
                    EmptyView()
                } else {
                    Text(residenceLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    router.selectedTab = .qr
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "qrcode")
                            .font(.title2.weight(.semibold))
                            .frame(width: 56, height: 56)
                            .background(.white.opacity(0.18), in: .rect(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mi QR de propietario").font(.title3.bold())
                            Text("Entra a cualquier hora · avisamos al arrendatario")
                                .font(.footnote).opacity(0.9)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(
                        LinearGradient(colors: [.blue, Color(red: 0, green: 0.35, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 20)
                    )
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    row(icon: "hammer", title: "Permiso de obra", subtitle: "Solicitar o ver el permiso") {
                        router.openAccount(.workPermit)
                    }
                    Divider().padding(.leading, 60)
                    row(icon: "bag", title: "Huéspedes temporales", subtitle: "Si la renta es vacacional") {
                        router.openAccount(.guests)
                    }
                }
                .cardBackground()

                FootnoteLabel(text: "Mientras la vivienda esté rentada, el arrendatario autoriza las visitas y ve la bitácora.")
            }
            .padding(.horizontal)
        }
        .readableContentWidth()
        .background { DashboardBackground() }
        .navigationTitle("Hola, \(profile.firstName)")
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitleCompat(residenceLine)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.selectedTab = .account
                } label: {
                    InitialsAvatar(initials: profile.initials, size: 32, tint: .accentColor)
                }
                .accessibilityLabel("Cuenta")
            }
            .sharedBackgroundHidden()
        }
    }

    private var residenceLine: String {
        "\(profile.residence?.name ?? "") · rentada"
    }

    private func row(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconTile(systemName: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
}
