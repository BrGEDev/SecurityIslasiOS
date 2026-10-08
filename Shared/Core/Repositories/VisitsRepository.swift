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
    /// Token de push de la Live Activity de la visita (ActivityKit).
    func registerActivityToken(_ token: ActivityTokenRequest, for visitId: String) async throws

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

    func registerActivityToken(_ token: ActivityTokenRequest, for visitId: String) async throws {
        _ = try await client.send(API.Visits.registerActivityToken(visitId, token))
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

/// Mismo repositorio con caché sin red (SwiftData). Las lecturas regresan lo
/// último guardado si no hay conexión; las escrituras van siempre al backend.
final class CachedVisitsRepository: VisitsRepository {
    private let remote: VisitsRepository
    private let cache: OfflineCache
    /// Se llama después de responder una visita desde cualquier lugar (para
    /// cerrar su Live Activity y su aviso).
    var onDecision: ((Visit, VisitDecision) -> Void)?

    init(remote: VisitsRepository, cache: OfflineCache) {
        self.remote = remote
        self.cache = cache
    }

    func home() async throws -> HomeSummary {
        try await cache.fetch("home") { try await remote.home() }
    }

    func today() async throws -> [Visit] {
        try await cache.fetch("visits.today") { try await remote.today() }
    }

    func decide(_ visitId: String, decision: VisitDecision) async throws -> Visit {
        let visit = try await remote.decide(visitId, decision: decision)
        onDecision?(visit, decision)
        return visit
    }

    func markSleepover(_ visit: Visit) async throws -> Visit {
        try await remote.markSleepover(visit)
    }

    func registerActivityToken(_ token: ActivityTokenRequest, for visitId: String) async throws {
        try await remote.registerActivityToken(token, for: visitId)
    }

    func invitations() async throws -> [Invitation] {
        try await cache.fetch("invitations") { try await remote.invitations() }
    }

    func createInvitation(_ request: NewInvitationRequest) async throws -> Invitation {
        try await remote.createInvitation(request)
    }

    func recurring() async throws -> [RecurringAccess] {
        try await cache.fetch("recurring") { try await remote.recurring() }
    }

    func recurringDetail(id: String) async throws -> RecurringAccess {
        try await cache.fetch("recurring.\(id)") { try await remote.recurringDetail(id: id) }
    }

    func createRecurring(_ request: NewRecurringRequest) async throws -> RecurringAccess {
        try await remote.createRecurring(request)
    }

    func revoke(_ recurring: RecurringAccess) async throws {
        try await remote.revoke(recurring)
    }

    func packages() async throws -> [Package] {
        try await cache.fetch("packages") { try await remote.packages() }
    }

    func packagePolicy() async throws -> PackagePolicy {
        try await remote.packagePolicy()
    }

    func updatePackagePolicy(_ policy: PackagePolicy) async throws -> PackagePolicy {
        try await remote.updatePackagePolicy(policy)
    }

    func history(category: HistoryCategory?) async throws -> [HistoryEvent] {
        try await cache.fetch("history.\(category?.rawValue ?? "all")") { try await remote.history(category: category) }
    }
}
