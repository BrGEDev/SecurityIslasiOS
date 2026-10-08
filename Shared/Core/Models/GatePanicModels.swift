//
//  GatePanicModels.swift
//  SecurityIslas
//
//  Pluma (decisión I-01), Mi QR, pánico y datos de la vivienda.
//

import CoreLocation
import Foundation

// MARK: - Ubicación

nonisolated struct Coordinate: Codable, Sendable, Hashable {
    let latitude: Double
    let longitude: Double

    /// Distancia en metros (haversine).
    func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Punto desplazado `meters` hacia el norte.
    func offset(northMeters meters: Double) -> Coordinate {
        Coordinate(latitude: latitude + meters / 111_320, longitude: longitude)
    }
}

// MARK: - Pluma

nonisolated enum LaneType: String, Codable, Sendable {
    /// Carril exclusivo de residentes: el botón abre directo.
    case residentsOnly
    /// Carril compartido: el botón manda una solicitud de paso al guardia.
    case shared
}

nonisolated struct Lane: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let type: LaneType
    let location: Coordinate
}

nonisolated struct GateConfiguration: Codable, Sendable, Hashable {
    let lanes: [Lane]
    /// Geocerca de la entrada (~150 m, RF-23).
    let entranceRadius: Double
    /// Geocerca del fraccionamiento completo: decide a quién va el pánico.
    let perimeterCenter: Coordinate
    let perimeterRadius: Double
}

/// Orden firmada: carril, timestamp y nonce (sección 3, "Pluma").
nonisolated struct GateCommand: Codable, Sendable {
    let laneId: String
    let timestamp: Date
    let nonce: String
    let location: Coordinate
}

nonisolated enum GateOutcome: String, Codable, Sendable {
    /// El backend confirmó que el controlador dio el pulso.
    case opened
    /// Carril compartido: la tablet del guardia recibió la solicitud.
    case passRequested
}

nonisolated struct GateResult: Codable, Sendable {
    let outcome: GateOutcome
    let laneName: String
    let at: Date
}

// MARK: - Mi QR

nonisolated struct QRSeed: Codable, Sendable {
    /// Secreto HMAC en base64. Supuesto: lo entrega el backend una vez por dispositivo.
    let secret: String
    let period: Int
    let digits: Int
}

// MARK: - Inicio

nonisolated struct HomeSummary: Codable, Sendable {
    let pendingVisits: [Visit]
    let today: [Visit]
    let gate: GateConfiguration
    let packagesAtBooth: Int
}

// MARK: - Pánico

nonisolated enum PanicScope: String, Codable, Sendable {
    /// Dentro del fraccionamiento: va a los guardias en turno.
    case guards
    /// Fuera: va a los contactos de emergencia y se ofrece el 911.
    case contacts
}

nonisolated enum PanicStatus: String, Codable, Sendable {
    case sent
    case received
    case guardOnTheWay
    case escalated
    case closed
}

nonisolated enum ContactAlertState: String, Codable, Sendable {
    case sent
    case seen
}

nonisolated struct ContactAlert: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let state: ContactAlertState
    let channel: String
    let at: Date?
}

nonisolated struct PanicAlert: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let scope: PanicScope
    var status: PanicStatus
    let createdAt: Date
    var guardName: String?
    var guardConfirmedAt: Date?
    var contacts: [ContactAlert]
}

nonisolated struct PanicRequest: Codable, Sendable {
    let location: Coordinate
}

// MARK: - Vivienda

nonisolated struct FamilyMember: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: ResidentRole
    let isCurrentUser: Bool

    var initials: String { Initials.from(name) }

    var detail: String {
        switch role {
        case .holder: isCurrentUser ? "Titular · tú" : "Titular"
        case .adult: "Adulto · autoriza visitas"
        case .minor: "Menor · su QR y su paso"
        case .nonResidentOwner: "Propietario"
        }
    }
}

nonisolated struct FamilyInviteRequest: Codable, Sendable {
    let name: String
    let phone: String
    let role: ResidentRole
}

nonisolated struct EmergencyContact: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let relationship: String
    let phone: String
    let hasApp: Bool

    var initials: String { Initials.from(name) }
    var detail: String { "\(relationship) · \(hasApp ? "tiene la app" : "por SMS")" }
}

nonisolated struct NewEmergencyContactRequest: Codable, Sendable {
    let name: String
    let relationship: String
    let phone: String
}

/// Huésped temporal (RF-92): entra con su propio QR durante la estancia, el
/// titular recibe aviso de cada entrada y el acceso vence solo.
nonisolated struct TemporaryGuest: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let arrival: Date
    let departure: Date
    let phone: String
    /// Enlace a la página con su QR dinámico y PIN (como una invitación).
    var shareURL: URL?
    var pin: String?
    var entries: [EntryLog]?

    nonisolated enum Stage: Sendable {
        case upcoming
        case staying
        case finished
    }

    func stage(at date: Date = .now) -> Stage {
        if date < arrival { return .upcoming }
        if date > departure { return .finished }
        return .staying
    }
}

nonisolated struct NewGuestRequest: Codable, Sendable {
    let name: String
    let arrival: Date
    let departure: Date
    let phone: String
}

nonisolated enum WorkPermitStatus: String, Codable, Sendable {
    case inReview
    case approved
    case rejected
}

nonisolated struct WorkPermit: Codable, Sendable, Hashable {
    let id: String
    var status: WorkPermitStatus
    let responsible: String
    let license: String
    let startsOn: Date
    let endsOn: Date
    let schedule: String
    var dailySummary: Bool
    let submittedAt: Date
    /// Entradas de hoy de la cuadrilla (RF-88). El resumen diario y los avisos
    /// inmediatos los manda el backend por push (RF-89).
    var todayEntries: [WorkEntry]?
}

/// Trabajador registrado por el guardia al entrar (RF-88).
nonisolated struct WorkEntry: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let enteredAt: Date
    var exitedAt: Date?
    /// Entró fuera del horario de obra: siguió el flujo normal de visita y se
    /// avisó de inmediato al dueño (RF-89).
    var outsideSchedule: Bool
    /// Coincidencia con la lista restringida (RF-77, RF-89).
    var restrictedMatch: RestrictedMatch?
}

nonisolated struct WorkPermitRequest: Codable, Sendable {
    let responsible: String
    let license: String
    let startsOn: Date
    let endsOn: Date
    let schedule: String
}

nonisolated struct WorkPermitSettings: Codable, Sendable {
    let dailySummary: Bool
}

/// `GET work-permit` puede no tener permiso activo.
nonisolated struct WorkPermitEnvelope: Codable, Sendable {
    let permit: WorkPermit?
}
