//
//  HomeView.swift
//  SecurityIslas
//
//  Pantalla 9 (Inicio): visita en caseta con Autorizar / Rechazar (RF-02),
//  botón de la pluma según geocerca y carril (RF-23), accesos rápidos,
//  lo de hoy y el pánico (mantener presionado 3 s, RF-40).
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
            VStack(alignment: .leading, spacing: 16) {
                header

                if let visit = model.pendingVisit {
                    PendingVisitCard(
                        visit: visit,
                        extraCount: model.extraPendingCount,
                        isResponding: model.respondingVisitId == visit.id
                    ) { decision in
                        await model.decide(visit, decision)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                GateButton(model: model.gate)

                quickActions

                if let summary = model.summary, summary.packagesAtBooth > 0 {
                    Button {
                        router.homePath.append(.packages)
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemName: "shippingbox.fill", tint: .orange)
                            Text("\(summary.packagesAtBooth) \(summary.packagesAtBooth == 1 ? "paquete" : "paquetes") en caseta")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }

                todaySection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.snappy, value: model.pendingVisit?.id)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom) {
            PanicHoldBar {
                router.panic = .countdown
            } onAccessibilityActivate: {
                router.panic = .hold
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.residence?.fraccionamientoName ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Hola, \(profile.firstName)")
                    .font(.largeTitle.bold())
                Text(profile.residence?.name ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                router.selectedTab = .account
            } label: {
                InitialsAvatar(initials: profile.initials, size: 44, tint: .accentColor)
            }
            .accessibilityLabel("Cuenta")
        }
        .padding(.top, 8)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickAction(icon: "person.badge.plus", title: "Invitar") { router.showNewInvitation = true }
            QuickAction(icon: "arrow.triangle.2.circlepath", title: "Recurrentes") { router.open(.recurring) }
            QuickAction(icon: "qrcode", title: "Mi QR") { router.selectedTab = .qr }
            QuickAction(icon: "person.2", title: "Familia") { router.openAccount(.family) }
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        HStack {
            Text("HOY")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Ver todo") { router.homePath.append(.history) }
                .font(.footnote.weight(.semibold))
        }
        .padding(.top, 4)

        let today = model.summary?.today ?? []
        if today.isEmpty {
            Text(model.summary == nil ? "Cargando…" : "Todavía no hay accesos hoy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardBackground()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(today.enumerated()), id: \.element.id) { index, visit in
                    VisitRow(visit: visit, compact: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if index < today.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .cardBackground()
        }
    }
}

private struct QuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}

/// Tarjeta de la visita que espera en caseta.
struct PendingVisitCard: View {
    let visit: Visit
    var extraCount = 0
    var isResponding = false
    let onDecision: (VisitDecision) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KindBadge(kind: visit.kind)
                Spacer()
                if let arrivedAt = visit.arrivedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("En caseta · hace \(Self.elapsed(from: arrivedAt, to: context.date))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 12) {
                InitialsAvatar(initials: visit.initials)
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.name).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                AsyncButton {
                    await onDecision(.reject)
                } label: {
                    Text("Rechazar")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.12), in: .rect(cornerRadius: 12))
                }
                AsyncButton {
                    await onDecision(.authorize)
                } label: {
                    Text("Autorizar")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green, in: .rect(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
            .disabled(isResponding)

            if extraCount > 0 {
                Text("+\(extraCount) más esperando en caseta")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .cardBackground(cornerRadius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor, lineWidth: 1.5))
        .sensoryFeedback(.warning, trigger: visit.id)
    }

    private var detail: String {
        var parts: [String] = []
        if visit.kind == .service, let company = visit.company, company != visit.name {
            parts.append(company)
        }
        parts.append(visit.origin == .walkIn ? "Sin invitación" : visit.subtitle)
        if let plate = visit.plate { parts.append("placa \(plate)") }
        return parts.joined(separator: " · ")
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }
}

/// Fila de acceso usada en Inicio y en Visitas > Hoy.
struct VisitRow: View {
    let visit: Visit
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            if compact {
                IconTile(systemName: visit.kind.symbol, tint: visit.kind.tint, size: 36)
            } else {
                InitialsAvatar(initials: visit.initials)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.name).font(.subheadline.weight(.semibold))
                Text(compact ? compactDetail : visit.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !compact {
                StatusChip(text: visit.statusText, tint: visit.statusTint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var compactDetail: String {
        var parts = [visit.kind.title]
        if let entered = visit.enteredAt {
            parts.append("entró \(entered.shortTime)")
        } else if visit.status == .scheduled, let scheduled = visit.scheduledAt {
            parts.append("llega \(scheduled.shortTime)")
        } else {
            parts.append(visit.statusText.lowercased())
        }
        return parts.joined(separator: " · ")
    }
}
