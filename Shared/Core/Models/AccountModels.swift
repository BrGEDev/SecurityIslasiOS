//
//  AccountModels.swift
//  SecurityIslas
//
//  Modelos de cuenta, registro y dispositivos. Los nombres de campo son
//  supuestos hasta tener el contrato OpenAPI (ver DECISIONES.md).
//

import Foundation

// MARK: - Teléfono

nonisolated struct CountryCode: Codable, Sendable, Hashable, Identifiable {
    let iso: String
    let dialCode: String
    var id: String { iso }

    static let mexico = CountryCode(iso: "MX", dialCode: "52")
    static let unitedStates = CountryCode(iso: "US", dialCode: "1")
    static let all: [CountryCode] = [.mexico, .unitedStates]
}

nonisolated struct PhoneNumber: Codable, Sendable, Hashable {
    let country: CountryCode
    /// Solo dígitos, 10 para México.
    let digits: String

    var e164: String { "+\(country.dialCode)\(digits)" }

    var formatted: String {
        "+\(country.dialCode) \(PhoneNumber.group(digits))"
    }

    var isComplete: Bool { digits.count == 10 }

    /// "2221234567" → "222 123 4567"
    static func group(_ digits: String) -> String {
        var result = ""
        for (index, character) in digits.prefix(10).enumerated() {
            if index == 3 || index == 6 { result.append(" ") }
            result.append(character)
        }
        return result
    }
}

// MARK: - Perfil

nonisolated enum ResidentRole: String, Codable, Sendable {
    /// Titular de la vivienda.
    case holder
    case adult
    case minor
    case nonResidentOwner

    var title: String {
        switch self {
        case .holder: "Titular"
        case .adult: "Adulto"
        case .minor: "Menor"
        case .nonResidentOwner: "Propietario no residente"
        }
    }
}

nonisolated enum Tenure: String, Codable, Sendable, CaseIterable, Identifiable {
    case owner
    case tenant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: "Propietario"
        case .tenant: "Arrendatario"
        }
    }
}

nonisolated enum ApprovalStatus: String, Codable, Sendable {
    /// Verificó su número pero aún no solicita alta.
    case unregistered
    case pending
    case approved
    case rejected
}

nonisolated struct Residence: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let fraccionamientoId: String
    let fraccionamientoName: String
    /// La vivienda está rentada (afecta al propietario no residente, RF-87).
    let isRented: Bool
}

nonisolated struct UserProfile: Codable, Sendable, Hashable, Identifiable {
    let id: String
    var firstName: String
    var lastName: String
    var phone: String
    var role: ResidentRole
    var tenure: Tenure?
    var residence: Residence?
    var approvalStatus: ApprovalStatus
    var rejectionReason: String?
    /// Fin del contrato de arrendamiento que fijó la administración (RF-84).
    var contractEndsOn: Date? = nil
    /// Ya confirmó que sigue viviendo ahí; la administración revisa la nueva fecha.
    var tenancyRenewalRequested: Bool? = nil

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    var initials: String { Initials.from(fullName) }

    var canManageHousehold: Bool { role == .holder || role == .nonResidentOwner }

    /// Propietario que no vive en la casa y la tiene rentada: no autoriza
    /// visitas, no ve la bitácora ni usa el botón de apertura (RF-87).
    var isRestrictedOwner: Bool {
        role == .nonResidentOwner && (residence?.isRented ?? false)
    }

    var isMinor: Bool { role == .minor }

    /// Autoriza o rechaza visitas, invita y administra recurrentes y paquetería.
    /// El menor solo abre la pluma (o solicita paso) para su propio paso y usa
    /// su QR (decisión de Brandon, ver DECISIONES.md).
    var canAuthorizeVisits: Bool { !isMinor && !isRestrictedOwner }

    /// Botón de apertura / solicitud de paso (RF-23). El propietario no residente
    /// entra con su QR y no usa el botón (RF-87); el menor sí, solo para su paso.
    var canUseGate: Bool { role != .nonResidentOwner }

    /// Arrendatario titular cuyo contrato termina en 7 días o menos (o ya
    /// terminó): se le pide confirmar si sigue o dar de baja el acceso (RF-84).
    /// Supuesto: aviso con 7 días de anticipación.
    func needsTenancyConfirmation(now: Date = .now) -> Bool {
        guard tenure == .tenant, role == .holder, tenancyRenewalRequested != true,
              let contractEndsOn else { return false }
        return contractEndsOn.timeIntervalSince(now) <= 7 * 86_400
    }
}

nonisolated enum TenancyDecision: String, Codable, Sendable {
    /// Sigue viviendo ahí: la administración actualiza la fecha.
    case stay
    /// Se muda: pierde el acceso en todos sus dispositivos (RF-65).
    case leave
}

nonisolated struct TenancyConfirmationRequest: Codable, Sendable {
    let decision: TenancyDecision
}

nonisolated enum Initials {
    static func from(_ name: String) -> String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter ?? false }
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Registro

nonisolated struct Fraccionamiento: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let booths: Int
    let homes: Int

    var summary: String {
        "\(booths) \(booths == 1 ? "caseta" : "casetas") · \(homes) viviendas"
    }
}

/// Vivienda del catálogo de la administración (no se escribe a mano).
nonisolated struct HomeOption: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
}

nonisolated enum AccountState: String, Codable, Sendable {
    /// Número nuevo: sigue el registro (pantallas 4, 5, 6).
    case newResident
    /// Ya tiene cuenta: pantalla 3a, sin registro ni aprobación.
    case existing
    /// La administración lo precargó: alta aprobada al verificar (RF-63).
    case preloaded
}

nonisolated struct PreloadedRegistration: Codable, Sendable, Hashable {
    let firstName: String
    let lastName: String
    let fraccionamiento: Fraccionamiento
    let home: HomeOption
    let tenure: Tenure
}

nonisolated struct OTPChallenge: Codable, Sendable {
    let expiresIn: Int
    let resendIn: Int
}

nonisolated struct VerificationResult: Codable, Sendable {
    let accountState: AccountState
    let profile: UserProfile
    /// Dispositivos ya registrados en la cuenta (sin contar este).
    let devices: [Device]
    let maxDevices: Int
    let preload: PreloadedRegistration?

    /// Teléfonos y tabletas registrados: los relojes no cuentan en el límite.
    var limitedDevices: [Device] { devices.filter(\.model.countsTowardLimit) }

    var reachedDeviceLimit: Bool { limitedDevices.count >= maxDevices }
}

// MARK: - Dispositivos

nonisolated enum DeviceModel: String, Codable, Sendable {
    case iphone
    case ipad
    case watch
    case android

    /// Hasta 3 teléfonos o tabletas por cuenta (RF-66). Los Apple Watch no
    /// cuentan: se puede tener más de uno sin ocupar lugar.
    var countsTowardLimit: Bool { self != .watch }

    var symbol: String {
        switch self {
        case .iphone, .android: "iphone"
        case .ipad: "ipad"
        case .watch: "applewatch"
        }
    }
}

nonisolated struct Device: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let model: DeviceModel
    let lastUsedAt: Date
    let isCurrent: Bool
}

nonisolated struct DeviceList: Codable, Sendable {
    let devices: [Device]
    let maxDevices: Int

    /// Los relojes no ocupan lugar en el límite.
    var limitedCount: Int { devices.filter(\.model.countsTowardLimit).count }
    var freeSlots: Int { max(0, maxDevices - limitedCount) }
}
