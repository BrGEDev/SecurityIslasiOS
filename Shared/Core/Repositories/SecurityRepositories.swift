//
//  SecurityRepositories.swift
//  SecurityIslas
//
//  Pluma, Mi QR, pánico y datos de la vivienda (familia, contactos, huéspedes,
//  permiso de obra).
//

import Foundation

// MARK: - Pluma

protocol GateRepository {
    /// Orden firmada {carril, timestamp, nonce}. El backend vuelve a validar la
    /// geocerca y responde si abrió o si mandó la solicitud de paso.
    func open(lane: Lane, from location: Coordinate) async throws -> GateResult
    func qrSeed() async throws -> QRSeed
}

final class RemoteGateRepository: GateRepository {
    private let client: any APIClientProtocol
    private let signer: RequestSigner

    init(client: any APIClientProtocol, signer: RequestSigner) {
        self.client = client
        self.signer = signer
    }

    func open(lane: Lane, from location: Coordinate) async throws -> GateResult {
        let command = GateCommand(laneId: lane.id, timestamp: .now, nonce: UUID().uuidString, location: location)
        let reason = lane.type == .residentsOnly ? "Abrir la pluma" : "Solicitar paso en caseta"
        let endpoint = try await signer.sign(API.Gate.open(command), reason: reason)
        return try await client.send(endpoint)
    }

    func qrSeed() async throws -> QRSeed {
        try await client.send(API.Gate.qrSeed())
    }
}

// MARK: - Pánico

protocol PanicRepository {
    func trigger(at location: Coordinate) async throws -> PanicAlert
    func status(of alert: PanicAlert) async throws -> PanicAlert
    func updateLocation(_ location: Coordinate, for alert: PanicAlert) async throws
    /// Cerrar la alerta pide Face ID (pantalla 26).
    func close(_ alert: PanicAlert) async throws -> PanicAlert
}

final class RemotePanicRepository: PanicRepository {
    private let client: any APIClientProtocol
    private let signer: RequestSigner

    init(client: any APIClientProtocol, signer: RequestSigner) {
        self.client = client
        self.signer = signer
    }

    func trigger(at location: Coordinate) async throws -> PanicAlert {
        try await client.send(API.Panic.create(PanicRequest(location: location)))
    }

    func status(of alert: PanicAlert) async throws -> PanicAlert {
        try await client.send(API.Panic.status(alert.id))
    }

    func updateLocation(_ location: Coordinate, for alert: PanicAlert) async throws {
        _ = try await client.send(API.Panic.updateLocation(alert.id, PanicRequest(location: location)))
    }

    func close(_ alert: PanicAlert) async throws -> PanicAlert {
        let endpoint = try await signer.sign(API.Panic.close(alert.id), reason: "Cerrar la alerta")
        return try await client.send(endpoint)
    }
}

// MARK: - Vivienda

protocol HouseholdRepository {
    func family() async throws -> [FamilyMember]
    func inviteFamily(_ request: FamilyInviteRequest) async throws -> FamilyMember
    func removeFamily(_ member: FamilyMember) async throws

    func contacts() async throws -> [EmergencyContact]
    func addContact(_ request: NewEmergencyContactRequest) async throws -> EmergencyContact
    func removeContact(_ contact: EmergencyContact) async throws

    func guests() async throws -> [TemporaryGuest]
    func createGuest(_ request: NewGuestRequest) async throws -> TemporaryGuest

    func workPermit() async throws -> WorkPermit?
    func requestWorkPermit(_ request: WorkPermitRequest) async throws -> WorkPermit
    func setDailySummary(_ enabled: Bool) async throws -> WorkPermit

    /// Fin de contrato del arrendatario (RF-84). Es un cambio de cuenta: firma.
    func confirmTenancy(_ decision: TenancyDecision) async throws -> UserProfile
}

final class RemoteHouseholdRepository: HouseholdRepository {
    private let client: any APIClientProtocol
    private let signer: RequestSigner

    init(client: any APIClientProtocol, signer: RequestSigner) {
        self.client = client
        self.signer = signer
    }

    func family() async throws -> [FamilyMember] {
        try await client.send(API.Household.family())
    }

    func inviteFamily(_ request: FamilyInviteRequest) async throws -> FamilyMember {
        let endpoint = try await signer.sign(API.Household.inviteFamily(request), reason: "Invitar a \(request.name)")
        return try await client.send(endpoint)
    }

    func removeFamily(_ member: FamilyMember) async throws {
        let endpoint = try await signer.sign(API.Household.removeFamily(member.id), reason: "Quitar a \(member.name)")
        _ = try await client.send(endpoint)
    }

    func contacts() async throws -> [EmergencyContact] {
        try await client.send(API.Household.contacts())
    }

    func addContact(_ request: NewEmergencyContactRequest) async throws -> EmergencyContact {
        let endpoint = try await signer.sign(API.Household.addContact(request), reason: "Agregar un contacto de emergencia")
        return try await client.send(endpoint)
    }

    func removeContact(_ contact: EmergencyContact) async throws {
        let endpoint = try await signer.sign(API.Household.removeContact(contact.id), reason: "Quitar a \(contact.name)")
        _ = try await client.send(endpoint)
    }

    func guests() async throws -> [TemporaryGuest] {
        try await client.send(API.Household.guests())
    }

    func createGuest(_ request: NewGuestRequest) async throws -> TemporaryGuest {
        try await client.send(API.Household.createGuest(request))
    }

    func workPermit() async throws -> WorkPermit? {
        try await client.send(API.Household.workPermit()).permit
    }

    func requestWorkPermit(_ request: WorkPermitRequest) async throws -> WorkPermit {
        try await client.send(API.Household.requestWorkPermit(request))
    }

    func setDailySummary(_ enabled: Bool) async throws -> WorkPermit {
        try await client.send(API.Household.updateWorkPermit(WorkPermitSettings(dailySummary: enabled)))
    }

    func confirmTenancy(_ decision: TenancyDecision) async throws -> UserProfile {
        let reason = decision == .stay ? "Confirmar que sigues en la vivienda" : "Dar de baja tu acceso"
        let endpoint = try await signer.sign(API.Household.confirmTenancy(TenancyConfirmationRequest(decision: decision)), reason: reason)
        return try await client.send(endpoint)
    }
}
