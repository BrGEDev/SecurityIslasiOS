//
//  VisitLiveActivity.swift
//  IslasWidgets
//
//  Pantallas 11 y 12. Pantalla bloqueada: quién está en caseta, tipo Visita o
//  Servicio, anillo con la cuenta regresiva y Rechazar / Autorizar (Autorizar
//  pide desbloquear, Rechazar funciona bloqueado, RF-02). Dynamic Island
//  compacta: iniciales a la izquierda y tiempo a la derecha.
//
//  Al tocar un botón, los botones se cambian por "Autorizando…" y después por
//  el resultado; la actividad se cierra sola a los pocos segundos. Al vencer
//  el plazo dice que se está escalando y, al cerrarse, "sin respuesta": nunca
//  se autoriza sola (RF-04). Si otro integrante responde se ve quién (RF-06).
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct VisitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VisitActivityAttributes.self) { context in
            // Colores semánticos: en la pantalla bloqueada sigue el modo claro u
            // oscuro; en la Dynamic Island el sistema siempre la dibuja oscura.
            VisitLockScreenView(context: context)
                .padding(16)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VisitAvatar(attributes: context.attributes, size: 44)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VisitTitle(attributes: context.attributes, subtitle: "\(context.attributes.kind.title) · \(context.attributes.residence)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownRing(context: context, size: 44)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VisitActionArea(context: context)
                        .padding(.top, 6)
                }
            } compactLeading: {
                VisitAvatar(attributes: context.attributes, size: 24)
            } compactTrailing: {
                CompactStatus(context: context)
            } minimal: {
                CountdownRing(context: context, size: 24, showsTime: false)
            }
            .keylineTint(.orange)
            .widgetURL(AppLink.visits.url)
        }
    }
}

// MARK: - Pantalla bloqueada

private struct VisitLockScreenView: View {
    let context: ActivityViewContext<VisitActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                Text(AppInfo.name)
                Spacer()
                KindChip(kind: context.attributes.kind)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VisitAvatar(attributes: context.attributes, size: 48)
                VisitTitle(
                    attributes: context.attributes,
                    subtitle: context.attributes.detail,
                    title: "\(context.attributes.name) en caseta"
                )
                Spacer(minLength: 8)
                CountdownRing(context: context, size: 48)
            }

            VisitActionArea(context: context)
        }
    }
}

// MARK: - Piezas

private struct VisitAvatar: View {
    let attributes: VisitActivityAttributes
    let size: CGFloat

    var body: some View {
        Text(attributes.initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(attributes.kind.tint.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct VisitTitle: View {
    let attributes: VisitActivityAttributes
    let subtitle: String
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? attributes.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct KindChip: View {
    let kind: AccessKind

    var body: some View {
        Text(kind.title.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(kind.tint)
            .background(kind.tint.opacity(0.2), in: Capsule())
    }
}

/// Anillo que se vacía hasta el escalamiento, con el tiempo adentro. Después
/// del plazo (o ya respondida) muestra un símbolo en lugar del tiempo.
private struct CountdownRing: View {
    let context: ActivityViewContext<VisitActivityAttributes>
    let size: CGFloat
    var showsTime = true

    private var state: VisitActivityAttributes.ContentState { context.state }

    var body: some View {
        Group {
            if state.phase == .waiting, !context.isStale, context.attributes.arrivedAt < state.respondBy {
                ProgressView(timerInterval: context.attributes.arrivedAt...state.respondBy, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    if showsTime {
                        Text(timerInterval: Date.now...state.respondBy, countsDown: true, showsHours: false)
                            .font(.system(size: size * 0.26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .progressViewStyle(.circular)
                .tint(.orange)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }

    private var symbol: String {
        switch state.phase {
        case .waiting: "phone.arrow.up.right.fill"
        case .authorizing, .rejecting: "ellipsis"
        case .authorized: "checkmark.circle.fill"
        case .rejected: "xmark.circle.fill"
        case .noResponse: "clock.badge.xmark.fill"
        }
    }

    private var tint: Color {
        switch state.phase {
        case .authorized: .green
        case .rejected: .red
        default: .orange
        }
    }
}

/// Lado derecho de la isla compacta: el tiempo o el resultado.
private struct CompactStatus: View {
    let context: ActivityViewContext<VisitActivityAttributes>

    var body: some View {
        let state = context.state
        Group {
            switch state.phase {
            case .waiting where !context.isStale && state.respondBy > .now:
                Text(timerInterval: Date.now...state.respondBy, countsDown: true, showsHours: false)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
            case .waiting:
                Image(systemName: "phone.arrow.up.right.fill").foregroundStyle(.orange)
            case .authorizing, .rejecting:
                Image(systemName: "ellipsis").foregroundStyle(.primary)
            case .authorized:
                Image(systemName: "checkmark").foregroundStyle(.green)
            case .rejected:
                Image(systemName: "xmark").foregroundStyle(.red)
            case .noResponse:
                Image(systemName: "clock.badge.xmark").foregroundStyle(.orange)
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .frame(width: 36, alignment: .trailing)
    }
}

/// Botones mientras espera; después, lo que pasó. Al tocar un botón la app
/// cambia la actividad a "Autorizando…" antes de enviar, así no se puede
/// enviar dos veces.
private struct VisitActionArea: View {
    let context: ActivityViewContext<VisitActivityAttributes>

    private var name: String { context.attributes.name }

    var body: some View {
        switch context.state.phase {
        case .waiting:
            VStack(alignment: .leading, spacing: 8) {
                if context.isStale {
                    Text("Te escribimos por WhatsApp y te llamamos. Si nadie responde, no entra.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if context.attributes.heldByAdministration {
                    Label("Lista restringida: la administración decide.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                HStack(spacing: 10) {
                    Button(intent: VisitDecisionIntent(visitId: context.attributes.visitId, option: .reject)) {
                        Label("Rechazar", systemImage: "xmark")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .tint(.red)
                    if !context.attributes.heldByAdministration {
                        Button(intent: AuthorizeVisitFromLockScreenIntent(visitId: context.attributes.visitId)) {
                            Label("Autorizar", systemImage: "checkmark")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .tint(.green)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        case .authorizing:
            progress("Autorizando a \(name)…")
        case .rejecting:
            progress("Rechazando a \(name)…")
        case .authorized:
            result(
                context.state.respondedBy.map { "\($0) autorizó a \(name)" } ?? "Autorizaste a \(name)",
                symbol: "checkmark.circle.fill",
                tint: .green
            )
        case .rejected:
            result(
                context.state.respondedBy.map { "\($0) rechazó a \(name)" } ?? "Rechazaste a \(name)",
                symbol: "xmark.circle.fill",
                tint: .red
            )
        case .noResponse:
            result("Sin respuesta · \(name) no entró", symbol: "clock.badge.xmark.fill", tint: .orange)
        }
    }

    private func progress(_ text: String) -> some View {
        // Los widgets no animan un `ProgressView` indeterminado: se dibuja como
        // un anillo fijo. Un símbolo comunica mejor que ya se envió.
        HStack(spacing: 8) {
            Image(systemName: "paperplane.fill")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.quaternary, in: Capsule())
    }

    private func result(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

// MARK: - Previews

private let previewAttributes = VisitActivityAttributes(
    visitId: "vis-juan", arrivedAt: .now.addingTimeInterval(-20), name: "Juan Pérez", initials: "JP", kind: .visit,
    detail: "Sin invitación · placa TXR-12-34", residence: "Retorno Encino 24", heldByAdministration: false
)

#Preview("Pantalla bloqueada", as: .content, using: previewAttributes) {
    VisitLiveActivity()
} contentStates: {
    VisitActivityAttributes.ContentState(phase: .waiting, respondBy: .now.addingTimeInterval(40), respondedBy: nil)
    VisitActivityAttributes.ContentState(phase: .authorizing, respondBy: .now.addingTimeInterval(40), respondedBy: nil)
    VisitActivityAttributes.ContentState(phase: .authorized, respondBy: .now, respondedBy: nil)
    VisitActivityAttributes.ContentState(phase: .rejected, respondBy: .now, respondedBy: "Ana")
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: previewAttributes) {
    VisitLiveActivity()
} contentStates: {
    VisitActivityAttributes.ContentState(phase: .waiting, respondBy: .now.addingTimeInterval(40), respondedBy: nil)
    VisitActivityAttributes.ContentState(phase: .authorizing, respondBy: .now.addingTimeInterval(40), respondedBy: nil)
    VisitActivityAttributes.ContentState(phase: .authorized, respondBy: .now, respondedBy: nil)
}
