//
//  HomeViewModel.swift
//  SecurityIslas
//

import Foundation
import Observation

@Observable
final class HomeViewModel {
    private(set) var summary: HomeSummary?
    private(set) var respondingVisitId: String?
    var errorMessage: String?
    let gate: GateViewModel

    private let visits: VisitsRepository

    init(visits: VisitsRepository, gateRepository: GateRepository, location: LocationService) {
        self.visits = visits
        self.gate = GateViewModel(repository: gateRepository, location: location)
    }

    var pendingVisit: Visit? { summary?.pendingVisits.first }
    var extraPendingCount: Int { max(0, (summary?.pendingVisits.count ?? 0) - 1) }

    func load() async {
        do {
            let summary = try await visits.home()
            self.summary = summary
            gate.configuration = summary.gate
            await gate.refreshPosition()
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Vale la primera respuesta de la vivienda (RF-06): si otro integrante ya
    /// respondió, el backend regresa 409 y se muestra quién.
    func decide(_ visit: Visit, _ decision: VisitDecision) async {
        respondingVisitId = visit.id
        defer { respondingVisitId = nil }
        do {
            _ = try await visits.decide(visit.id, decision: decision)
        } catch {
            errorMessage = error.userMessage
        }
        // Con respuesta o con 409, el aviso de esa visita ya no sirve.
        NotificationManager.withdraw(visitId: visit.id)
        await load()
    }
}
