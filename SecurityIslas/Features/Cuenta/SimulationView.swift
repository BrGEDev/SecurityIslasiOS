//
//  SimulationView.swift
//  SecurityIslas
//
//  Solo con el backend mock. Permite probar lo que en producción provoca el
//  mundo real: dónde estás, que llegue una visita a caseta (push) y que el
//  token expire para ver el refresh del interceptor.
//

import SwiftUI

struct SimulationView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var tokenLifetime = MockSettings.accessTokenLifetime
    @State private var lastAction: String?

    var body: some View {
        Form {
            Section {
                Picker("Posición", selection: Binding(
                    get: { container.location.simulatedPosition },
                    set: { container.location.setSimulatedPosition($0) }
                )) {
                    ForEach(SimulatedPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Tu ubicación")
            } footer: {
                Text("Cambia el botón de Inicio entre Abrir pluma, Solicitar paso y Lejos de la entrada. Lejos también manda el pánico a tus contactos.")
            }

            Section {
                AsyncButton("Llega una visita a caseta") { await simulate(.visit) }
                AsyncButton("Llega un servicio a caseta") { await simulate(.service) }
            } header: {
                Text("Avisos")
            } footer: {
                Text("Aparece en Inicio y, a los 5 s, como notificación con Autorizar / Rechazar. Bloquea el iPhone para probar que Rechazar funciona bloqueado y Autorizar pide desbloquear.")
            }

            Section {
                Picker("Vida del access token", selection: $tokenLifetime) {
                    Text("20 segundos").tag(20)
                    Text("2 minutos").tag(120)
                    Text("1 hora").tag(3_600)
                }
                .onChange(of: tokenLifetime) { _, value in
                    UserDefaults.standard.set(value, forKey: MockSettings.accessTokenLifetimeKey)
                }
            } header: {
                Text("Sesión")
            } footer: {
                Text("Aplica al siguiente token emitido. Al expirar, el AuthInterceptor lo renueva solo (401 → refresh → reintento).")
            }

            Section {
                Button("Borrar datos del backend de prueba", role: .destructive) {
                    Task {
                        await container.mockServer?.resetAll()
                        await session.signOut()
                    }
                }
            } footer: {
                Text("Reinicia cuentas, dispositivos y llaves registradas, y cierra la sesión.")
            }

            if let lastAction {
                Section { Text(lastAction).foregroundStyle(.secondary) }
            }
        }
        .readableContentWidth()
        .navigationTitle("Simulación")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func simulate(_ kind: AccessKind) async {
        guard let server = container.mockServer else { return }
        let visit = await server.simulateArrival(kind: kind)
        container.notifications.scheduleSimulatedArrival(
            visit,
            residence: session.profile?.residence?.name ?? "tu vivienda"
        )
        container.dataDidChange()
        lastAction = "\(visit.name) está en caseta."
    }
}
