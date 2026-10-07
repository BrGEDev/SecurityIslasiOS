//
//  Badges.swift
//  SecurityIslas
//
//  Chips, avatares e íconos de las tarjetas.
//

import SwiftUI

struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

/// Visita y Servicio se distinguen siempre visualmente.
struct KindBadge: View {
    let kind: AccessKind

    var body: some View {
        StatusChip(text: kind.title.uppercased(), tint: kind.tint)
    }
}

extension AccessKind {
    var tint: Color {
        switch self {
        case .visit: .blue
        case .service: .purple
        }
    }

    var symbol: String {
        switch self {
        case .visit: "person.fill"
        case .service: "truck.box.fill"
        }
    }
}

/// Monograma con el estilo de Contactos: degradado suave y letras blancas.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 40
    var tint: Color = Color(.systemGray)

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.4)
        Text(initials)
            .font(.system(size: side * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(
                LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .top, endPoint: .bottom),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

/// Ícono teñido para tarjetas y filas de contenido.
struct IconTile: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.4)
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: side * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Ícono de fila al estilo de Configuración: cuadro con el símbolo en blanco.
///
/// Cada símbolo de SF Symbols tiene proporciones distintas (`iphone` es alto,
/// `person.2.fill` es ancho). Para que todos se vean del mismo tamaño, el glifo
/// se ajusta a una caja fija (60 % del cuadro) en lugar de usar un tamaño de
/// fuente: así el margen alrededor es el mismo en todas las filas.
struct SettingsIcon: View {
    let systemName: String
    /// Por omisión, el color de acento de la app.
    var tint: Color = .accentColor

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: side * 0.6, height: side * 0.6)
            .frame(width: side, height: side)
            .background(tint.gradient, in: .rect(cornerRadius: side * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Estados de visita

extension Visit {
    var statusText: String {
        switch status {
        case .waiting: "En caseta"
        case .authorized: respondedBy.map { "Autorizó \($0)" } ?? "Autorizada"
        case .rejected: respondedBy.map { "Rechazó \($0)" } ?? "Rechazada"
        case .noResponse: "Sin respuesta"
        case .entered: enteredAt.map { "Entró \($0.formatted(.dateTime.hour().minute()))" } ?? "Entró"
        case .exited: respondedBy.map { "Autorizó \($0)" } ?? "Salió"
        case .scheduled: "Por llegar"
        case .sleepover: "Se queda a dormir"
        case .canceled: "Cancelada"
        case .expired: "Vencida"
        }
    }

    var statusTint: Color {
        switch status {
        case .waiting: .orange
        case .authorized, .entered, .exited: .green
        case .rejected, .noResponse: .red
        case .scheduled: .blue
        case .sleepover, .canceled, .expired: .gray
        }
    }

    var subtitle: String {
        var parts: [String] = []
        switch origin {
        case .walkIn: parts.append(kind == .visit ? "Visita · sin invitación" : "Servicio")
        case .invitation: parts.append("Invitación")
        case .recurring: parts.append("\(kind.title) recurrente")
        case .event: parts.append("Evento")
        }
        if let count = destinationCount, count > 1 {
            parts.append("va a \(count) viviendas")
        }
        if status == .scheduled, let scheduledAt {
            parts.append(scheduledAt.relativeDayAndTime)
        } else if let arrivedAt, !Calendar.current.isDateInToday(arrivedAt) {
            parts.append(arrivedAt.relativeDayAndTime)
        }
        return parts.joined(separator: " · ")
    }
}
