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
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 6))
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

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 40
    var tint: Color = Color(.systemGray)

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

struct IconTile: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: size * 0.28))
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
