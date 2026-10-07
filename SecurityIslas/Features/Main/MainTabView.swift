//
//  MainTabView.swift
//  SecurityIslas
//
//  Tabs Inicio · Visitas · Mi QR · Cuenta y el flujo de pánico, que puede
//  abrirse desde cualquier pestaña.
//

import Observation
import SwiftUI

nonisolated enum MainTab: Hashable {
    case home
    case visits
    case qr
    case account
}

nonisolated enum VisitsSegment: String, CaseIterable, Identifiable {
    case today
    case invitations
    case recurring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Hoy"
        case .invitations: "Invitaciones"
        case .recurring: "Recurrentes"
        }
    }
}

nonisolated enum HomeRoute: Hashable {
    case history
    case packages
}

nonisolated enum AccountRoute: Hashable {
    case family
    case contacts
    case devices
    case guests
    case workPermit
    case packagePolicy
    case packages
    case simulation
}

nonisolated enum PanicEntry: Hashable, Identifiable {
    /// Desde widget o control: abre la pantalla de mantener presionado (24).
    case hold
    /// Ya se mantuvo presionado el botón de Inicio: cuenta regresiva (25).
    case countdown

    var id: Self { self }
}

/// Navegación compartida entre pestañas (ej. "Mi QR" desde Inicio).
@Observable
final class MainRouter {
    var selectedTab: MainTab = .home
    var visitsSegment: VisitsSegment = .today
    var homePath: [HomeRoute] = []
    var accountPath: [AccountRoute] = []
    var panic: PanicEntry?
    var showNewInvitation = false
    /// Geocercas que llegan con el resumen de Inicio; el pánico las usa para
    /// decir antes a quién va la alerta.
    var gateConfiguration: GateConfiguration?

    func open(_ segment: VisitsSegment) {
        visitsSegment = segment
        selectedTab = .visits
    }

    func openAccount(_ route: AccountRoute) {
        accountPath = [route]
        selectedTab = .account
    }
}

struct MainTabView: View {
    let profile: UserProfile

    @Environment(AppContainer.self) private var container
    @State private var router = MainRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.homePath) {
                Group {
                    if profile.isRestrictedOwner {
                        OwnerHomeView(profile: profile)
                    } else {
                        HomeView(profile: profile, container: container)
                    }
                }
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .history: HistoryView(repository: container.visits)
                    case .packages: PackagesView(repository: container.visits)
                    }
                }
            }
            .tabItem { Label("Inicio", systemImage: "house") }
            .tag(MainTab.home)

            NavigationStack {
                VisitsView(profile: profile, container: container)
            }
            .tabItem { Label("Visitas", systemImage: "person.2") }
            .tag(MainTab.visits)

            NavigationStack {
                MyQRView(profile: profile, generator: container.residentQR)
            }
            .tabItem { Label("Mi QR", systemImage: "qrcode") }
            .tag(MainTab.qr)

            NavigationStack(path: $router.accountPath) {
                AccountView(profile: profile)
                    .navigationDestination(for: AccountRoute.self) { route in
                        accountDestination(route)
                    }
            }
            .tabItem { Label("Cuenta", systemImage: "person.crop.circle") }
            .tag(MainTab.account)
        }
        .environment(router)
        .fullScreenCover(item: $router.panic) { entry in
            PanicFlowView(model: PanicViewModel(
                entry: entry,
                repository: container.panic,
                location: container.location,
                gate: router.gateConfiguration ?? MockSeed.gate,
                residenceName: profile.residence?.fraccionamientoName ?? "tu fraccionamiento"
            ))
        }
        .sheet(isPresented: $router.showNewInvitation) {
            NewInvitationView(repository: container.visits) {
                container.dataDidChange()
            }
        }
        .onChange(of: container.pendingInviteCode) { _, code in
            // Un enlace de invitación con sesión activa no aplica: ya tiene vivienda.
            if code != nil { container.pendingInviteCode = nil }
        }
    }

    @ViewBuilder
    private func accountDestination(_ route: AccountRoute) -> some View {
        switch route {
        case .family: FamilyView(profile: profile, repository: container.household)
        case .contacts: EmergencyContactsView(repository: container.household)
        case .devices: DevicesView(repository: container.devices)
        case .guests: GuestsView(repository: container.household)
        case .workPermit: WorkPermitView(repository: container.household)
        case .packagePolicy: PackagePolicyView(repository: container.visits)
        case .packages: PackagesView(repository: container.visits)
        case .simulation: SimulationView()
        }
    }
}
