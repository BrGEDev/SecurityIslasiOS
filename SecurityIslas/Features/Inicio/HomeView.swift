//
//  HomeView.swift
//  SecurityIslas
//
//  Panel de Inicio (pantallas 9 y 10), ordenado por urgencia:
//  1. Visita en caseta: tarjeta tipo Live Activity con Autorizar / Rechazar (RF-02).
//  2. Pluma: tarjeta principal tipo Wallet según geocerca y carril (RF-23).
//  3. Accesos rápidos: invitar, recurrentes, Mi QR, familia.
//  4. Hoy: indicadores del día y actividad en línea de tiempo.
//  5. Pánico: mantener presionado 3 s, siempre al alcance del pulgar (RF-40).
//
//  En la pantalla interior del iPhone Duo (regular × regular) los bloques 1–3
//  y 4 van en dos columnas sin cruzar el pliegue.
//

import SwiftUI

struct HomeView: View {
    let profile: UserProfile

    @State private var model: HomeViewModel
    @Environment(MainRouter.self) private var router
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase

    init(profile: UserProfile, container: AppContainer) {
        self.profile = profile
        _model = State(initialValue: HomeViewModel(
            visits: container.visits,
            gateRepository: container.gate,
            location: container.location
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if #available(iOS 26, *) {
                    // En iOS 26 la vivienda va como subtítulo de la barra de navegación.
                    EmptyView()
                } else {
                    Label(residenceLine, systemImage: "house.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                AdaptiveColumns(spacing: 24) {
                    if let visit = model.pendingVisit {
                        LiveVisitCard(
                            visit: visit,
                            extraCount: model.extraPendingCount,
                            isResponding: model.respondingVisitId == visit.id
                        ) { decision in
                            await model.decide(visit, decision)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                    }

                    GateHeroCard(model: model.gate)

                    QuickActionsGrid(items: quickActions)
                        .padding(.top, 4)
                } trailing: {
                    todaySection
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 32)
            .animation(.smooth, value: model.pendingVisit?.id)
        }
        .readableContentWidth(1_000)
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
        .refreshable { await model.load() }
        .legacyPanicBar {
            router.panic = .countdown
        } onAccessibilityActivate: {
            router.panic = .hold
        }
        .task(id: container.dataVersion) {
            await model.load()
            router.gateConfiguration = model.summary?.gate
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .errorAlert($model.errorMessage)
    }

    private var residenceLine: String {
        guard let residence = profile.residence else { return "" }
        return "\(residence.name) · \(residence.fraccionamientoName)"
    }

    private var quickActions: [QuickActionItem] {
        [
            QuickActionItem(id: "invite", title: "Invitar", systemImage: "person.crop.circle.badge.plus", tint: .blue) {
                router.showNewInvitation = true
            },
            QuickActionItem(id: "recurring", title: "Recurrentes", systemImage: "arrow.triangle.2.circlepath", tint: .teal) {
                router.open(.recurring)
            },
            QuickActionItem(id: "qr", title: "Mi QR", systemImage: "qrcode", tint: .indigo) {
                router.selectedTab = .qr
            },
            QuickActionItem(id: "family", title: "Familia", systemImage: "person.2.fill", tint: .orange) {
                router.openAccount(.family)
            },
        ]
    }

    @ViewBuilder
    private var todaySection: some View {
        let isLoading = model.summary == nil
        let today = isLoading ? Visit.placeholders : (model.summary?.today ?? [])
        let pending = model.summary?.pendingVisits.count ?? 0
        let packages = model.summary?.packagesAtBooth ?? 0

        DashboardSectionHeader(title: "Hoy", actionTitle: "Historial") {
            router.homePath.append(.history)
        }

        HStack(spacing: 12) {
            SummaryTile(
                value: "\(today.count)",
                title: today.count == 1 ? "Acceso" : "Accesos",
                systemImage: "figure.walk.arrival",
                tint: .blue
            ) {
                router.homePath.append(.history)
            }
            SummaryTile(
                value: "\(pending)",
                title: "En caseta",
                systemImage: "clock.badge.exclamationmark.fill",
                tint: pending > 0 ? .orange : .gray
            ) {
                router.open(.today)
            }
            SummaryTile(
                value: "\(packages)",
                title: packages == 1 ? "Paquete" : "Paquetes",
                systemImage: "shippingbox.fill",
                tint: packages > 0 ? .brown : .gray
            ) {
                router.homePath.append(.packages)
            }
        }
        .redacted(reason: isLoading ? .placeholder : [])

        if !isLoading && today.isEmpty {
            ContentUnavailableView {
                Label("Sin accesos hoy", systemImage: "sun.max")
            } description: {
                Text("Aquí verás quién entra y quién respondió.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .cardBackground(cornerRadius: 22)
        } else {
            ActivityTimeline(visits: today)
                .redacted(reason: isLoading ? .placeholder : [])
        }
    }
}

/// Fondo con un degradado de marca muy sutil en la parte superior que se
/// funde con el fondo agrupado del sistema (claro y oscuro).
struct DashboardBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 360)
        }
        .ignoresSafeArea()
    }
}

private extension Visit {
    /// Filas de ejemplo para el estado de carga (se dibujan con `.redacted`).
    static let placeholders: [Visit] = (0..<3).map { index in
        Visit(id: "placeholder-\(index)", kind: .visit, name: "Nombre de visita", origin: .walkIn, status: .entered, enteredAt: .now)
    }
}
