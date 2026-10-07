//
//  AccountView.swift
//  SecurityIslas
//
//  Pantalla 32. Todo cambio en familia, contactos de emergencia, dispositivos
//  o teléfono pide Face ID (RF-67). Huéspedes y permiso de obra solo aparecen
//  para el titular o el propietario.
//

import SwiftUI

struct AccountView: View {
    let profile: UserProfile

    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var summary = AccountSummary()
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    InitialsAvatar(initials: profile.initials, size: 56, tint: .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.fullName).font(.headline)
                        Text([profile.role.title, profile.residence?.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if !profile.isRestrictedOwner {
                    row(.family, icon: "person.2", title: "Familia", value: summary.family)
                }
                row(.contacts, icon: "heart", title: "Contactos de emergencia", value: summary.contacts)
                row(.devices, icon: "iphone", title: "Dispositivos", value: summary.devices)
                if profile.canManageHousehold {
                    row(.guests, icon: "bag", title: "Huéspedes", value: summary.guests)
                    row(.workPermit, icon: "hammer", title: "Permiso de obra", value: summary.workPermit)
                }
                if !profile.isRestrictedOwner {
                    row(.packagePolicy, icon: "shippingbox", title: "Paquetería", value: summary.packagePolicy)
                    row(.packages, icon: "tray.full", title: "Paquetes en caseta", value: nil)
                }
            }

            if container.usesMockBackend {
                Section {
                    row(.simulation, icon: "hammer.circle", title: "Simulación (backend de prueba)", value: nil)
                } footer: {
                    Text("Solo aparece mientras la app usa datos de ejemplo.")
                }
            }

            Section {
                Button("Cerrar sesión", role: .destructive) { confirmSignOut = true }
            }
        }
        .navigationTitle("Cuenta")
        .task(id: container.dataVersion) { await loadSummary() }
        .confirmationDialog("¿Cerrar sesión en este iPhone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                Task { await session.signOut() }
            }
        } message: {
            Text("Este iPhone dejará de abrir la pluma y de recibir avisos hasta que vuelvas a verificar tu número.")
        }
    }

    private func row(_ route: AccountRoute, icon: String, title: String, value: String?) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                IconTile(systemName: icon, size: 30)
                Text(title)
                Spacer()
                if let value {
                    Text(value).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadSummary() async {
        if let family = try? await container.household.family() {
            summary.family = "\(family.count)"
        }
        if let contacts = try? await container.household.contacts() {
            summary.contacts = "\(contacts.count)"
        }
        if let list = try? await container.devices.devices() {
            summary.devices = "\(list.devices.count) de \(list.maxDevices)"
        }
        if profile.canManageHousehold {
            if let guests = try? await container.household.guests() {
                summary.guests = guests.isEmpty ? "Ninguno" : "\(guests.count)"
            }
            do {
                let permit = try await container.household.workPermit()
                switch permit?.status {
                case .none: summary.workPermit = "No"
                case .approved: summary.workPermit = "Activo"
                case .inReview: summary.workPermit = "En revisión"
                case .rejected: summary.workPermit = "Rechazado"
                }
            } catch {
                summary.workPermit = nil
            }
        }
        if !profile.isRestrictedOwner, let policy = try? await container.visits.packagePolicy() {
            summary.packagePolicy = policy.shortTitle
        }
    }
}

private struct AccountSummary {
    var family: String?
    var contacts: String?
    var devices: String?
    var guests: String?
    var workPermit: String?
    var packagePolicy: String?
}
