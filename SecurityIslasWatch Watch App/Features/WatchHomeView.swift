//
//  WatchHomeView.swift
//  SecurityIslasWatch Watch App
//
//  Pantalla 40 (Reloj: app) con el lenguaje de watchOS 10: páginas verticales
//  que se recorren con la Digital Crown, cada una con el color de su estado
//  (los mismos degradados que la tarjeta de la pluma del iPhone):
//    1. En caseta (solo si hay visitas esperando): responder como una llamada.
//    2. Pluma: un botón grande para abrir o solicitar paso (RF-23, RF-68).
//    3. Mi QR, sin internet (RF-15).
//  Arriba: Ajustes a la izquierda y Pánico a la derecha, siempre a la mano.
//

import Observation
import SwiftUI
import WatchKit

@Observable
final class WatchHomeModel {
    private(set) var summary: HomeSummary?
    private(set) var respondingVisitId: String?
    var errorMessage: String?
    let gate: GateViewModel

    private let visits: VisitsRepository

    init(visits: VisitsRepository, gateRepository: GateRepository, location: LocationService) {
        self.visits = visits
        gate = GateViewModel(repository: gateRepository, location: location)
    }

    var pending: [Visit] { summary?.pendingVisits ?? [] }

    func load() async {
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
    @discardableResult
    func decide(_ visit: Visit, _ decision: VisitDecision) async -> Bool {
        respondingVisitId = visit.id
        defer {
            respondingVisitId = nil
            NotificationManager.withdraw(visitId: visit.id)
        }
        do {
            _ = try await visits.decide(visit.id, decision: decision)
            WKInterfaceDevice.current().play(.success)
            await load()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            errorMessage = error.userMessage
            await load()
            return false
        }
    }
}

nonisolated enum WatchRoute: Hashable {
    case panic
    /// Desde la complicación: directo a la cuenta regresiva (RF-41).
    case panicCountdown
    case settings
    case visits
}

struct WatchHomeView: View {
    nonisolated enum Page: Hashable {
        case visits
        case gate
        case qr
    }

    let profile: UserProfile

    @Environment(WatchContainer.self) private var container
    @State private var model: WatchHomeModel?
    @State private var page: Page = .gate
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    pages(model)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: WatchRoute.settings) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Cuenta")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: WatchRoute.panic) {
                        Image(systemName: "sos")
                            .fontWeight(.heavy)
                            .foregroundStyle(.white)
                    }
                    .tint(BrandPalette.red[0])
                    .accessibilityLabel("Pánico")
                }
            }
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .panic:
                    WatchPanicView(model: makePanicModel(entry: .hold))
                case .panicCountdown:
                    WatchPanicView(model: makePanicModel(entry: .countdown))
                case .settings:
                    WatchSettingsView(profile: profile)
                case .visits:
                    if let model {
                        WatchVisitListView(model: model)
                    }
                }
            }
            .navigationDestination(for: Visit.self) { visit in
                if let model {
                    WatchVisitDetailView(visit: visit) { decision in
                        await model.decide(visit, decision)
                    }
                }
            }
        }
        .onChange(of: container.linkRequest, initial: true) { _, link in
            // Complicaciones (pantalla 43): abren la página correspondiente.
            guard let link else { return }
            container.linkRequest = nil
            switch link {
            case .panic:
                path = NavigationPath()
                path.append(WatchRoute.panicCountdown)
            case .gate where profile.canUseGate:
                path = NavigationPath()
                page = .gate
            case .qr, .gate:
                path = NavigationPath()
                page = .qr
            case .visits:
                path = NavigationPath()
            }
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

    private func pages(_ model: WatchHomeModel) -> some View {
        // El menor no autoriza visitas: solo su QR y su paso.
        let showsVisits = profile.canAuthorizeVisits && !model.pending.isEmpty
        // El propietario no residente entra con su QR, sin botón de abrir (RF-87).
        let showsGate = profile.canUseGate
        return TabView(selection: $page) {
            if showsVisits {
                WatchPendingPage(model: model)
                    .tag(Page.visits)
                    .containerBackground(BrandPalette.backdrop(BrandPalette.orange), for: .tabView)
            }
            if showsGate {
                WatchGatePage(model: model.gate)
                    .tag(Page.gate)
                    .containerBackground(BrandPalette.backdrop(WatchGateStyle(state: model.gate.state).colors), for: .tabView)
            }
            WatchQRPage(userId: profile.id, name: profile.fullName)
                .tag(Page.qr)
                .containerBackground(BrandPalette.backdrop(BrandPalette.blue, intensity: 0.35), for: .tabView)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(title(for: page))
        .task(id: container.dataVersion) {
            await model.load()
        }
        .onChange(of: model.pending.map(\.id)) { old, new in
            // Llegó una visita: se muestra primero, como un aviso.
            if new.count > old.count, showsVisits {
                withAnimation { page = .visits }
            } else if new.isEmpty, page == .visits {
                withAnimation { page = showsGate ? .gate : .qr }
            }
        }
        .onAppear {
            if !showsGate { page = .qr }
            if showsVisits { page = .visits }
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

    private func title(for page: Page) -> String {
        switch page {
        case .visits: "En caseta"
        case .gate: "Pluma"
        case .qr: "Mi QR"
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

    private func makePanicModel(entry: PanicEntry) -> PanicViewModel {
        PanicViewModel(
            entry: entry,
            repository: container.panic,
            location: container.location,
            gate: model?.summary?.gate ?? Self.unknownGate,
            residenceName: profile.residence?.fraccionamientoName ?? "tu fraccionamiento"
        )
    }
}

// MARK: - En caseta

/// Responder como una llamada entrante: quién es y dos botones redondos.
private struct WatchPendingPage: View {
    let model: WatchHomeModel

    var body: some View {
        if let visit = model.pending.first {
            VStack(spacing: 6) {
                NavigationLink(value: visit) {
                    VStack(spacing: 4) {
                        WatchAvatar(initials: visit.initials, colors: visit.kind == .visit ? BrandPalette.blue : BrandPalette.indigo, size: 44)
                        Text(visit.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        KindBadge(kind: visit.kind)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                WatchDecisionButtons(isBusy: model.respondingVisitId == visit.id) { decision in
                    await model.decide(visit, decision)
                }

                if model.pending.count > 1 {
                    NavigationLink(value: WatchRoute.visits) {
                        Text("y \(model.pending.count - 1) más en caseta")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrandPalette.orange[0])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
        }
    }
}

/// Rechazar (rojo) y Autorizar (verde), del tamaño de los botones de llamada.
struct WatchDecisionButtons: View {
    var isBusy = false
    /// Lista restringida (RF-86): la administración decide, solo se puede rechazar.
    var canAuthorize = true
    let onDecide: (VisitDecision) async -> Void

    @State private var working: VisitDecision?

    var body: some View {
        HStack(spacing: 22) {
            button(.reject, symbol: "xmark", colors: BrandPalette.red, label: "Rechazar")
            button(.authorize, symbol: "checkmark", colors: BrandPalette.green, label: "Autorizar")
                .disabled(!canAuthorize)
                .opacity(canAuthorize ? 1 : 0.4)
        }
        .disabled(isBusy || working != nil)
    }

    private func button(_ decision: VisitDecision, symbol: String, colors: [Color], label: String) -> some View {
        Button {
            working = decision
            Task {
                await onDecide(decision)
                working = nil
            }
        } label: {
            ZStack {
                Circle().fill(BrandPalette.gradient(colors))
                if working == decision {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            .shadow(color: colors[1].opacity(0.5), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct WatchAvatar: View {
    let initials: String
    let colors: [Color]
    var size: CGFloat = 36

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(BrandPalette.gradient(colors), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Todas las visitas esperando (si hay más de una).
struct WatchVisitListView: View {
    let model: WatchHomeModel

    var body: some View {
        List(model.pending) { visit in
            NavigationLink(value: visit) {
                HStack(spacing: 8) {
                    WatchAvatar(initials: visit.initials, colors: visit.kind == .visit ? BrandPalette.blue : BrandPalette.indigo, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(visit.kind.title)
                            .font(.caption2)
                            .foregroundStyle(visit.kind.tint)
                    }
                }
            }
        }
        .navigationTitle("En caseta")
        .containerBackground(BrandPalette.backdrop(BrandPalette.orange, intensity: 0.4), for: .navigation)
    }
}
