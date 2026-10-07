//
//  WatchSettingsView.swift
//  SecurityIslasWatch Watch App
//
//  Cuenta en el reloj: quién eres, tu vivienda y desvincular. Los cambios de
//  cuenta se hacen en el iPhone (RF-68). Con el mock, también la simulación.
//

import SwiftUI

struct WatchSettingsView: View {
    let profile: UserProfile

    @Environment(WatchContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var confirmUnlink = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    WatchAvatar(initials: profile.initials, colors: BrandPalette.blue, size: 48)
                    Text(profile.fullName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let residence = profile.residence {
                        Text("\(residence.name)\n\(residence.fraccionamientoName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if container.usesMockBackend {
                Section {
                    Button {
                        Task { await container.simulateArrival(kind: .visit) }
                    } label: {
                        Label("Llega una visita", systemImage: AccessKind.visit.symbol)
                    }
                    Button {
                        Task { await container.simulateArrival(kind: .service) }
                    } label: {
                        Label("Llega un servicio", systemImage: AccessKind.service.symbol)
                    }
                } header: {
                    Text("Simulación")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmUnlink = true
                } label: {
                    Label("Desvincular reloj", systemImage: "applewatch.slash")
                }
            } footer: {
                Text("Los cambios de cuenta se hacen en tu iPhone.")
            }
        }
        .navigationTitle("Cuenta")
        .containerBackground(BrandPalette.backdrop(BrandPalette.blue, intensity: 0.35), for: .navigation)
        .alert("¿Desvincular este reloj?", isPresented: $confirmUnlink) {
            Button("Desvincular", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Dejará de recibir avisos y de abrir la pluma.")
        }
    }
}
