//
//  WatchHomeView.swift
//  SecurityIslasWatch Watch App
//
//  Pantalla 40 (Reloj: app): visitas en caseta, abrir pluma con las mismas
//  reglas de geocerca y carril (RF-23, RF-68), Mi QR y pánico. Funciona con
//  datos del reloj, sin el iPhone cerca.
//

import Observation
import SwiftUI

@Observable
final class WatchHomeModel {
    private(set) var summary: HomeSummary?
    private(set) var isLoading = false
    var errorMessage: String?
    let gate: GateViewModel

    private let visits: VisitsRepository

    init(visits: VisitsRepository, gateRepository: GateRepository, location: LocationService) {
        self.visits = visits
        gate = GateViewModel(repository: gateRepository, location: location)
    }

    var pending: [Visit] { summary?.pendingVisits ?? [] }

    func load() async {
        isLoading = summary == nil
        defer { isLoading = false }
        do {
            let summary = try await visits.home()
            self.summary = summary
            gate.configuration = summary.gate
            await gate.refreshPosition()
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Vale la primera respuesta de la vivienda (RF-06).
    func decide(_ visit: Visit, _ decision: VisitDecision) async -> Bool {
        defer { NotificationManager.withdraw(visitId: visit.id) }
        do {
            _ = try await visits.decide(visit.id, decision: decision)
            await load()
            return true
        } catch {
            errorMessage = error.userMessage
            await load()
            return false
        }
    }
}

nonisolated enum WatchRoute: Hashable {
    case qr
    case panic
}

struct WatchHomeView: View {
    let profile: UserProfile

    @Environment(WatchContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var model: WatchHomeModel?
    @State private var confirmUnlink = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(AppInfo.name)
        }
        .task {
            if !container.location.usesSimulation, container.location.authorization == .notDetermined {
                container.location.requestWhenInUse()
            }
            if model == nil {
                model = WatchHomeModel(
                    visits: container.visits,
                    gateRepository: container.gate,
                    location: container.location
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ model: WatchHomeModel) -> some View {
        List {
            if !profile.isRestrictedOwner, !model.pending.isEmpty {
                Section("En caseta") {
                    ForEach(model.pending) { visit in
                        NavigationLink(value: visit) {
                            WatchVisitRow(visit: visit)
                        }
                    }
                }
            }

            Section {
                // El propietario no residente entra con su QR, sin botón de abrir (RF-87).
                if profile.role != .nonResidentOwner {
                    WatchGateButton(model: model.gate)
                }
                NavigationLink(value: WatchRoute.qr) {
                    Label("Mi QR", systemImage: "qrcode")
                }
                NavigationLink(value: WatchRoute.panic) {
                    Label("Pánico", systemImage: "sos.circle.fill")
                        .foregroundStyle(.red)
                }
            } footer: {
                if let residence = profile.residence {
                    Text("\(residence.name) · \(residence.fraccionamientoName)")
                }
            }

            if container.usesMockBackend {
                Section("Simulación") {
                    Button("Llega una visita") {
                        Task { await container.simulateArrival(kind: .visit) }
                    }
                    Button("Llega un servicio") {
                        Task { await container.simulateArrival(kind: .service) }
                    }
                }
            }

            Section {
                Button("Desvincular reloj", role: .destructive) {
                    confirmUnlink = true
                }
            } footer: {
                Text("Para volver a usarlo, vincúlalo desde tu iPhone.")
            }
        }
        .navigationDestination(for: WatchRoute.self) { route in
            switch route {
            case .qr:
                WatchQRView(userId: profile.id, name: profile.fullName)
            case .panic:
                WatchPanicView(model: makePanicModel(model))
            }
        }
        .navigationDestination(for: Visit.self) { visit in
            WatchVisitDetailView(visit: visit) { decision in
                await model.decide(visit, decision)
            }
        }
        .task(id: container.dataVersion) {
            await model.load()
        }
        .refreshable {
            await model.load()
        }
        .alert("¿Desvincular este reloj?", isPresented: $confirmUnlink) {
            Button("Desvincular", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Dejará de recibir avisos y de abrir la pluma.")
        }
        .alert(
            "No se pudo completar",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Si aún no llega la configuración, se asume "dentro" para el texto previo;
    /// el backend decide el destino real con la ubicación (RF-42).
    private static let unknownGate = GateConfiguration(
        lanes: [],
        entranceRadius: 0,
        perimeterCenter: Coordinate(latitude: 0, longitude: 0),
        perimeterRadius: .greatestFiniteMagnitude
    )

    private func makePanicModel(_ model: WatchHomeModel) -> PanicViewModel {
        PanicViewModel(
            entry: .hold,
            repository: container.panic,
            location: container.location,
            gate: model.summary?.gate ?? Self.unknownGate,
            residenceName: profile.residence?.fraccionamientoName ?? "tu fraccionamiento"
        )
    }
}

struct WatchVisitRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KindBadge(kind: visit.kind)
            Text(visit.name)
                .font(.headline)
                .lineLimit(2)
            Text(visit.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
