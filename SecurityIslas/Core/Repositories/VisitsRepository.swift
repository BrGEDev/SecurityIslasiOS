//
//  VisitsRepository.swift
//  SecurityIslas
//
//  Visitas, invitaciones, recurrentes y paquetería (sección B del brief).
//

import Foundation

protocol VisitsRepository {
    func home() async throws -> HomeSummary
    func today() async throws -> [Visit]
    /// Autorizar o rechazar. No pide Face ID (RF-02, RF-67).
    func decide(_ visitId: String, decision: VisitDecision) async throws -> Visit
    func markSleepover(_ visit: Visit) async throws -> Visit

    func invitations() async throws -> [Invitation]
    /// Invitación única o de evento. No pide Face ID para no meter fricción (RF-07).
    func createInvitation(_ request: NewInvitationRequest) async throws -> Invitation

    func recurring() async throws -> [RecurringAccess]
    func recurringDetail(id: String) async throws -> RecurringAccess
    /// Crear y revocar recurrentes pide Face ID y firma (RF-67).
    func createRecurring(_ request: NewRecurringRequest) async throws -> RecurringAccess
    func revoke(_ recurring: RecurringAccess) async throws

    func packages() async throws -> [Package]
    func packagePolicy() async throws -> PackagePolicy
    /// Autorización automática: pide Face ID (RF-72, RF-67).
    func updatePackagePolicy(_ policy: PackagePolicy) async throws -> PackagePolicy

    func history(category: HistoryCategory?) async throws -> [HistoryEvent]
}

final class RemoteVisitsRepository: VisitsRepository {
    private let client: any APIClientProtocol
    private let signer: RequestSigner

    init(client: any APIClientProtocol, signer: RequestSigner) {
        self.client = client
        self.signer = signer
    }

    func home() async throws -> HomeSummary {
        try await client.send(API.Residence.home())
    }

    func today() async throws -> [Visit] {
        try await client.send(API.Visits.today())
    }

    func decide(_ visitId: String, decision: VisitDecision) async throws -> Visit {
        try await client.send(API.Visits.decide(visitId, decision: decision))
    }

    func markSleepover(_ visit: Visit) async throws -> Visit {
        try await client.send(API.Visits.markSleepover(visit.id))
    }

    func invitations() async throws -> [Invitation] {
        try await client.send(API.Visits.invitations())
    }

    func createInvitation(_ request: NewInvitationRequest) async throws -> Invitation {
        try await client.send(API.Visits.createInvitation(request))
    }

    func recurring() async throws -> [RecurringAccess] {
        try await client.send(API.Visits.recurring())
    }

    func recurringDetail(id: String) async throws -> RecurringAccess {
        try await client.send(API.Visits.recurringDetail(id))
    }

    func createRecurring(_ request: NewRecurringRequest) async throws -> RecurringAccess {
        let endpoint = try await signer.sign(
            API.Visits.createRecurring(request),
            reason: "Guardar el acceso recurrente de \(request.name)"
        )
        return try await client.send(endpoint)
    }

    func revoke(_ recurring: RecurringAccess) async throws {
        let endpoint = try await signer.sign(
            API.Visits.revokeRecurring(recurring.id),
            reason: "Revocar el código de \(recurring.name)"
        )
        _ = try await client.send(endpoint)
    }

    func packages() async throws -> [Package] {
        try await client.send(API.Residence.packages())
    }

    func packagePolicy() async throws -> PackagePolicy {
        try await client.send(API.Residence.packagePolicy()).policy
    }

    func updatePackagePolicy(_ policy: PackagePolicy) async throws -> PackagePolicy {
        let endpoint = try await signer.sign(
            API.Residence.updatePackagePolicy(policy),
            reason: "Cambiar cómo atiendes la paquetería"
        )
        return try await client.send(endpoint).policy
    }

    func history(category: HistoryCategory?) async throws -> [HistoryEvent] {
        try await client.send(API.Residence.history(category: category))
    }
}
