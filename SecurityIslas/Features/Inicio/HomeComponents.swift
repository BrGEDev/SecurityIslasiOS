//
//  HomeComponents.swift
//  SecurityIslas
//
//  Piezas del panel de Inicio.
//

import SwiftUI

// MARK: - Encabezado de sección

struct DashboardSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Visita en caseta (estilo Live Activity)

/// Igual que la Live Activity de la pantalla bloqueada: oscura, con cuenta
/// regresiva hacia el escalamiento (~60 s, RF-04) y los dos botones.
struct LiveVisitCard: View {
    let visit: Visit
    var extraCount = 0
    var isResponding = false
    let onDecision: (VisitDecision) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 12) {
                InitialsAvatar(initials: visit.initials, size: 48, tint: visit.kind.tint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(visit.name)
                            .font(.headline)
                            .lineLimit(1)
                        KindBadge(kind: visit.kind)
                            .environment(\.colorScheme, .dark)
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }

            if let notice = visit.restrictedNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if visit.goesToSeveralHomes, let count = visit.destinationCount {
                Label("Va a \(count) viviendas. Tu respuesta solo cuenta para la tuya.", systemImage: "house.and.flag.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }

            HStack(spacing: 10) {
                decisionButton("Rechazar", systemImage: "xmark", foreground: .red, background: .white.opacity(0.12)) {
                    await onDecision(.reject)
                }
                decisionButton("Autorizar", systemImage: "checkmark", foreground: .white, background: .green) {
                    await onDecision(.authorize)
                }
                .accessibilityIdentifier("autorizar-visita")
                .disabled(visit.isHeldByAdministration)
                .opacity(visit.isHeldByAdministration ? 0.4 : 1)
            }
            .disabled(isResponding)

            if extraCount > 0 {
                Label("\(extraCount) más esperando en caseta", systemImage: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(white: 0.17), Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: .rect(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .sensoryFeedback(.warning, trigger: visit.id)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, visit.responseDeadline.map { $0.timeIntervalSince(context.date) } ?? Visit.responseWindow)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(AppInfo.name, systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(remaining > 0
                         ? "Responde en \(Self.clock(remaining))"
                         : "Escalando a WhatsApp y llamada")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText(countsDown: true))
                }
                ProgressView(value: min(remaining, Visit.responseWindow), total: Visit.responseWindow)
                    .tint(.orange)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
                    .accessibilityHidden(true)
                Text(visit.escalationText(at: context.date))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func decisionButton(
        _ title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () async -> Void
    ) -> some View {
        AsyncButton(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(background, in: Capsule())
        }
        .buttonStyle(PressableCardStyle())
    }

    private var detail: String {
        var parts: [String] = []
        if visit.kind == .service, let company = visit.company, company != visit.name {
            parts.append(company)
        }
        parts.append(visit.origin == .walkIn ? "Sin invitación" : visit.subtitle)
        if let plate = visit.plate { parts.append("Placa \(plate)") }
        return parts.joined(separator: " · ")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Resumen del día

struct SummaryTile: View {
    let value: String
    let title: String
    let systemImage: String
    let tint: Color
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .cardBackground(cornerRadius: 22)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Accesos rápidos

struct QuickActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
}

/// Botones redondos con etiqueta, como los del Centro de control o Wallet.
struct QuickActionsGrid: View {
    let items: [QuickActionItem]

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 54

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                Button(action: item.action) {
                    VStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: circle * 0.4, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(item.tint)
                            .frame(width: circle, height: circle)
                            .background {
                                if #available(iOS 26, *) {
                                    Circle().fill(.clear).glassEffect(.regular.interactive(), in: Circle())
                                } else {
                                    Circle().fill(Color(.secondarySystemGroupedBackground))
                                }
                            }
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }
}

// MARK: - Actividad (línea de tiempo)

struct ActivityTimeline: View {
    let visits: [Visit]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                HStack(alignment: .top, spacing: 12) {
                    Text(time(for: visit))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        Image(systemName: visit.kind.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(visit.statusTint.gradient, in: Circle())
                        if index < visits.count - 1 {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.name)
                            .font(.subheadline.weight(.semibold))
                        Text(visit.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        StatusChip(text: visit.statusText, tint: visit.statusTint)
                            .padding(.top, 4)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    Spacer(minLength: 0)
                }
                // La fila toma su alto natural y la línea vertical lo llena.
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .cardBackground(cornerRadius: 22)
    }

    private func time(for visit: Visit) -> String {
        (visit.enteredAt ?? visit.arrivedAt ?? visit.scheduledAt)?.shortTime ?? ""
    }
}

// MARK: - Fila de acceso (Visitas > Hoy)

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(initials: visit.initials, tint: visit.kind == .service ? .purple : Color(.systemGray))
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.name).font(.body.weight(.semibold))
                Text(visit.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusChip(text: visit.statusText, tint: visit.statusTint)
                if let match = visit.restrictedMatch {
                    StatusChip(text: match == .confirmed ? "Lista restringida" : "Posible coincidencia", tint: .yellow)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
