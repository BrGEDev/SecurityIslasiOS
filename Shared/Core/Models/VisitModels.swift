//
//  VisitModels.swift
//  SecurityIslas
//

import Foundation

/// Visita y Servicio se distinguen siempre visualmente (reglas de negocio).
nonisolated enum AccessKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case visit
    case service

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visit: "Visita"
        case .service: "Servicio"
        }
    }
}

/// Etapas de un acceso (RF-70) más los estados que ve el residente.
nonisolated enum VisitStatus: String, Codable, Sendable {
    case waiting          // En caseta, esperando respuesta
    case authorized
    case rejected
    case noResponse
    case entered
    case exited
    case scheduled        // Invitación por llegar
    case sleepover        // Se queda a dormir (RF-74)
    case canceled
    case expired
}

nonisolated enum VisitOrigin: String, Codable, Sendable {
    case walkIn           // Sin invitación
    case invitation
    case recurring
    case event
}

nonisolated struct Visit: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: AccessKind
    let name: String
    var company: String?
    var plate: String?
    let origin: VisitOrigin
    var status: VisitStatus
    var arrivedAt: Date?
    var scheduledAt: Date?
    var enteredAt: Date?
    var exitedAt: Date?
    /// Quién de la vivienda respondió (RF-06).
    var respondedBy: String?
    /// Un servicio puede ir a varias viviendas (RF-71).
    var destinationCount: Int?
    var photoURL: URL?
    /// Hasta cuándo puede responder antes de que el backend escale a WhatsApp
    /// y llamada (RF-04). Si no llega, se usa `arrivedAt + responseWindow`.
    var respondBy: Date?
    /// Coincidencia con la lista restringida (RF-86). En esta app solo se
    /// refleja como aviso o estado.
    var restrictedMatch: RestrictedMatch?

    /// Tiempo antes de escalar (unos 60 s, RF-04). Valor final pendiente: lo
    /// configura la administración y debería llegar del backend en `respondBy`.
    static let responseWindow: TimeInterval = 60

    var initials: String { name == "Sin nombre" ? "?" : Initials.from(name) }

    var responseDeadline: Date? {
        respondBy ?? arrivedAt?.addingTimeInterval(Self.responseWindow)
    }

    /// La administración detuvo el acceso: la autorización del residente no
    /// basta (RF-86). Rechazar sí se puede.
    var isHeldByAdministration: Bool { restrictedMatch == .confirmed }

    /// Servicio que va a varias viviendas: cada una responde por separado (RF-71).
    var goesToSeveralHomes: Bool { (destinationCount ?? 1) > 1 }
}

nonisolated enum RestrictedMatch: String, Codable, Sendable {
    /// Solo coincide el nombre: "posible coincidencia", el guardia revisa la
    /// identificación antes de detener el acceso.
    case possible
    /// Coincide la placa o la identificación: el acceso se detiene y lo decide
    /// la administración aunque traiga código o autorización.
    case confirmed
}

nonisolated enum VisitDecision: String, Codable, Sendable {
    case authorize
    case reject
}

nonisolated struct Invitation: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: AccessKind
    let guestName: String
    let startsAt: Date
    let endsAt: Date
    var plate: String?
    let isEvent: Bool
    var capacity: Int?
    let shareURL: URL
    let pin: String
    var status: VisitStatus
}

nonisolated struct NewInvitationRequest: Codable, Sendable {
    let kind: AccessKind
    let guestName: String
    let startsAt: Date
    let endsAt: Date
    let plate: String?
    let isEvent: Bool
    let capacity: Int?
}

// MARK: - Recurrentes

nonisolated enum Weekday: Int, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var letter: String {
        switch self {
        case .monday: "L"
        case .tuesday: "M"
        case .wednesday: "M"
        case .thursday: "J"
        case .friday: "V"
        case .saturday: "S"
        case .sunday: "D"
        }
    }

    var name: String {
        switch self {
        case .monday: "lunes"
        case .tuesday: "martes"
        case .wednesday: "miércoles"
        case .thursday: "jueves"
        case .friday: "viernes"
        case .saturday: "sábados"
        case .sunday: "domingos"
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    static func summary(_ days: Set<Weekday>) -> String {
        if days.count == 7 { return "todos los días" }
        if days.count == 1, let day = days.first { return day.name }
        return days.sorted().map(\.letter).joined(separator: " ")
    }
}

/// Hora del día sin fecha ("08:00").
nonisolated struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    let hour: Int
    let minute: Int

    var formatted: String { String(format: "%d:%02d", hour, minute) }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

nonisolated enum AccessCodeType: String, Codable, Sendable, CaseIterable, Identifiable {
    case dynamicQR
    case pin

    var id: String { rawValue }
}

nonisolated struct EntryLog: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let enteredAt: Date
    let exitedAt: Date?
}

nonisolated struct RecurringAccess: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: AccessKind
    let name: String
    var detail: String?
    let weekdays: Set<Weekday>
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let expiresOn: Date
    let codeType: AccessCodeType
    var pinUsesPerDay: Int?
    let shareURL: URL
    var recentEntries: [EntryLog]

    var initials: String { Initials.from(name) }
    var allDay: Bool { startTime == TimeOfDay(hour: 0, minute: 0) && endTime == TimeOfDay(hour: 23, minute: 59) }

    var scheduleSummary: String {
        let days = Weekday.summary(weekdays)
        return allDay ? days : "\(days) \(startTime.formatted) a \(endTime.formatted)"
    }
}

nonisolated struct NewRecurringRequest: Codable, Sendable {
    let kind: AccessKind
    let name: String
    let weekdays: Set<Weekday>
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let expiresOn: Date
    let codeType: AccessCodeType
    let pinUsesPerDay: Int?
}

// MARK: - Paquetería

nonisolated enum PackagePolicy: String, Codable, Sendable, CaseIterable, Identifiable {
    case askAlways
    case leaveAtBooth
    case authorizeAlways

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askAlways: "Preguntarme siempre"
        case .leaveAtBooth: "Dejar en caseta"
        case .authorizeAlways: "Autorizar siempre"
        }
    }

    var detail: String {
        switch self {
        case .askAlways: "Autorizo o rechazo cada vez"
        case .leaveAtBooth: "El guardia lo recibe y me avisa"
        case .authorizeAlways: "El repartidor entra a mi casa"
        }
    }

    var shortTitle: String {
        switch self {
        case .askAlways: "Preguntar"
        case .leaveAtBooth: "En caseta"
        case .authorizeAlways: "Autorizar"
        }
    }
}

nonisolated struct PackagePolicySetting: Codable, Sendable {
    let policy: PackagePolicy
}

nonisolated enum PackageStatus: String, Codable, Sendable {
    case atBooth
    case delivered
}

nonisolated struct Package: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let carrier: String
    let receivedAt: Date
    let receivedBy: String
    var status: PackageStatus
    var pickedUpBy: String?
    var pickedUpAt: Date?
}

// MARK: - Historial

nonisolated enum HistoryCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case visit
    case service
    case gate
    case package
    case alert

    var id: String { rawValue }

    var filterTitle: String {
        switch self {
        case .visit: "Visitas"
        case .service: "Servicios"
        case .gate: "Aperturas"
        case .package: "Paquetes"
        case .alert: "Alertas"
        }
    }

    var symbol: String {
        switch self {
        case .visit: "person"
        case .service: "truck.box"
        case .gate: "road.lanes"
        case .package: "shippingbox"
        case .alert: "exclamationmark.triangle"
        }
    }
}

nonisolated struct HistoryEvent: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let category: HistoryCategory
    let title: String
    let detail: String
    let date: Date
    var isWarning: Bool = false
}
