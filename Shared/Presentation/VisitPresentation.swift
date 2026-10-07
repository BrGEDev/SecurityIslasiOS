//
//  VisitPresentation.swift
//  SecurityIslas (iPhone y Apple Watch)
//
//  Visita y Servicio se distinguen siempre visualmente (sección 3): chips,
//  colores y textos de estado compartidos por las dos apps.
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

// MARK: - Estados de visita

extension Visit {
    var statusText: String {
        switch status {
        case .waiting: "En caseta"
        case .authorized: respondedBy.map { "Autorizó \($0)" } ?? "Autorizada"
        case .rejected: respondedBy.map { "Rechazó \($0)" } ?? "Rechazada"
        case .noResponse: "Sin respuesta"
        case .entered: enteredAt.map { "Entró \($0.formatted(.dateTime.hour().minute().locale(.app)))" } ?? "Entró"
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
