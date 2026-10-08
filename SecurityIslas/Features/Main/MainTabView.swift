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
        tabs
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
            .task(id: profile.id) {
                container.push.sessionDidChange(userId: profile.id)
            }
            .onChange(of: container.panicRequest, initial: true) { _, entry in
                // Siri, widget, control o botón de Acción: cuenta regresiva
                // cancelable (RF-41), sin tener que mantener presionado.
                guard let entry else { return }
                container.panicRequest = nil
                router.panic = entry
            }
            .onChange(of: container.gateRequest, initial: true) { _, requested in
                // Inicio atiende el pedido con el mismo botón (y Face ID).
                if requested { router.selectedTab = .home }
            }
            .onChange(of: container.tabRequest, initial: true) { _, tab in
                guard let tab else { return }
                container.tabRequest = nil
                router.selectedTab = tab
            }
            .onChange(of: container.visitToOpen, initial: true) { _, visitId in
                // Se tocó el aviso de una visita: abre Visitas › Hoy.
                guard visitId != nil else { return }
                container.visitToOpen = nil
                if profile.canAuthorizeVisits {
                    router.open(.today)
                } else {
                    router.selectedTab = .home
                }
            }
    }

    /// iOS 18+: API de `Tab` con estilo adaptable. En la pantalla interior del
    /// iPhone Duo (o en iPad) las pestañas pasan a una barra lateral.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $router.selectedTab) {
                Tab("Inicio", systemImage: "house", value: MainTab.home) { homeTab }
                if profile.canAuthorizeVisits {
                    Tab("Visitas", systemImage: "person.2", value: MainTab.visits) { visitsTab }
                }
                Tab("Mi QR", systemImage: "qrcode", value: MainTab.qr) { qrTab }
                Tab("Cuenta", systemImage: "person.crop.circle", value: MainTab.account) { accountTab }
            }
            .tabViewStyle(.sidebarAdaptable)
            .panicTabAccessory {
                router.panic = .countdown
            } onAccessibilityActivate: {
                router.panic = .hold
            }
        } else {
            TabView(selection: $router.selectedTab) {
                homeTab
                    .tabItem { Label("Inicio", systemImage: "house") }
                    .tag(MainTab.home)
                if profile.canAuthorizeVisits {
                    visitsTab
                        .tabItem { Label("Visitas", systemImage: "person.2") }
                        .tag(MainTab.visits)
                }
                qrTab
                    .tabItem { Label("Mi QR", systemImage: "qrcode") }
                    .tag(MainTab.qr)
                accountTab
                    .tabItem { Label("Cuenta", systemImage: "person.crop.circle") }
                    .tag(MainTab.account)
            }
        }
    }

    private var homeTab: some View {
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
    }

    private var visitsTab: some View {
        NavigationStack {
            VisitsView(profile: profile, container: container)
        }
    }

    private var qrTab: some View {
        NavigationStack {
            MyQRView(profile: profile, generator: container.residentQR)
        }
    }

    private var accountTab: some View {
        NavigationStack(path: $router.accountPath) {
            AccountView(profile: profile)
                .navigationDestination(for: AccountRoute.self) { route in
                    accountDestination(route)
                }
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
