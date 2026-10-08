//
//  VisitLiveActivity.swift
//  IslasWidgets
//
//  Pantallas 11 y 12. Pantalla bloqueada: quién está en caseta, tipo Visita o
//  Servicio, cuenta regresiva y Rechazar / Autorizar (Autorizar pide
//  desbloquear, Rechazar funciona bloqueado, RF-02). Dynamic Island compacta:
//  iniciales a la izquierda y tiempo a la derecha.
//
//  Al vencer el plazo dice que se está escalando y, al cerrarse, "sin
//  respuesta": nunca se autoriza sola (RF-04). Si otro integrante responde se
//  ve quién (RF-06).
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct VisitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VisitActivityAttributes.self) { context in
            VisitLockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color(white: 0.1))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    InitialsBadge(attributes: context.attributes, size: 40)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // `Text(timerInterval:)` ocupa todo el ancho que le den: con un
                    // ancho fijo y una sola línea no se parte en "0:1 / 4".
                    CountdownText(state: context.state, isStale: context.isStale)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 64, alignment: .trailing)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.name).font(.headline).lineLimit(1)
                        Text("\(context.attributes.kind.title) · \(context.attributes.residence)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DecisionRow(context: context)
                }
            } compactLeading: {
                Text(context.attributes.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.attributes.kind.tint)
            } compactTrailing: {
                CountdownText(state: context.state, isStale: context.isStale)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 40, alignment: .trailing)
            } minimal: {
                Text(context.attributes.initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}

private struct VisitLockScreenView: View {
    let context: ActivityViewContext<VisitActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(AppInfo.name, systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if context.state.phase == .waiting {
                    HStack(spacing: 4) {
                        if !context.isStale { Text("Responde en") }
                        CountdownText(state: context.state, isStale: context.isStale)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .lineLimit(1)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                InitialsBadge(attributes: context.attributes, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.name) en caseta")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(context.attributes.kind.title) · \(context.attributes.detail)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }

            if context.state.phase == .waiting, !context.isStale {
                ProgressView(timerInterval: Date.now...context.state.respondBy, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.orange)
            }

            DecisionRow(context: context)
        }
    }
}

/// Botones o, si ya se respondió, el resultado.
private struct DecisionRow: View {
    let context: ActivityViewContext<VisitActivityAttributes>

    var body: some View {
        switch context.state.phase {
        case .waiting:
            if context.isStale {
                Text("Te escribimos por WhatsApp y te llamamos. Si nadie responde, no entra.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 10) {
                Button(intent: VisitDecisionIntent(visitId: context.attributes.visitId, option: .reject)) {
                    Text("Rechazar").frame(maxWidth: .infinity)
                }
                .tint(.red)
                if !context.attributes.heldByAdministration {
                    Button(intent: AuthorizeVisitFromLockScreenIntent(visitId: context.attributes.visitId)) {
                        Text("Autorizar").frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        case .authorized:
            result("Autorizó \(context.state.respondedBy ?? "tu casa")", symbol: "checkmark.circle.fill", tint: .green)
        case .rejected:
            result("Rechazó \(context.state.respondedBy ?? "tu casa")", symbol: "xmark.circle.fill", tint: .red)
        case .noResponse:
            result("Sin respuesta · no entró", symbol: "clock.badge.xmark.fill", tint: .orange)
        }
    }

    private func result(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }
}

private struct CountdownText: View {
    let state: VisitActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.phase != .waiting {
            Text(state.phase == .noResponse ? "Sin resp." : "Listo")
        } else if isStale || state.respondBy <= .now {
            Text("Escalando")
        } else {
            Text(timerInterval: Date.now...state.respondBy, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct InitialsBadge: View {
    let attributes: VisitActivityAttributes
    let size: CGFloat

    var body: some View {
        Text(attributes.initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(attributes.kind.tint.opacity(0.5), in: Circle())
    }
}

#Preview("Pantalla bloqueada", as: .content, using: VisitActivityAttributes(
    visitId: "vis-juan", name: "Juan Pérez", initials: "JP", kind: .visit,
    detail: "Sin invitación · placa TXR-12-34", residence: "Retorno Encino 24", heldByAdministration: false
)) {
    VisitLiveActivity()
} contentStates: {
    VisitActivityAttributes.ContentState(phase: .waiting, respondBy: .now.addingTimeInterval(48), respondedBy: nil)
    VisitActivityAttributes.ContentState(phase: .authorized, respondBy: .now, respondedBy: "Ana")
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: VisitActivityAttributes(
    visitId: "vis-juan", name: "Juan Pérez", initials: "JP", kind: .visit,
    detail: "Sin invitación · placa TXR-12-34", residence: "Retorno Encino 24", heldByAdministration: false
)) {
    VisitLiveActivity()
} contentStates: {
    VisitActivityAttributes.ContentState(phase: .waiting, respondBy: .now.addingTimeInterval(14), respondedBy: nil)
}
