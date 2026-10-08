//
//  VisitActivityController.swift
//  SecurityIslas
//
//  Inicia, actualiza y cierra la Live Activity de cada visita en caseta.
//
//  • Con la app abierta (o al recibir el push de la visita) se inicia una
//    actividad por visita pendiente. Con la app cerrada la inicia el backend
//    con el token "push to start" (iOS 17.2+), que se registra con
//    `PushRegistrar`.
//  • Cada actividad entrega su propio token de push; se manda al backend para
//    que la actualice o la cierre en todos los teléfonos de la casa (RF-06).
//  • Al responder (aquí, desde el aviso, Siri u otro integrante) se cierra con
//    el estado final. Nunca se autoriza sola (RF-04): al agotarse el tiempo
//    queda "sin respuesta".
//

import ActivityKit
import Foundation

final class VisitActivityController {
    private let visits: VisitsRepository
    private let push: PushRegistrar
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    private var startTokenTask: Task<Void, Never>?

    init(visits: VisitsRepository, push: PushRegistrar) {
        self.visits = visits
        self.push = push
    }

    private var environment: PushTokenRequest.Environment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    /// Token "push to start": permite al backend iniciar la actividad aunque la
    /// app esté cerrada.
    func observePushToStartToken() {
        guard startTokenTask == nil else { return }
        if #available(iOS 17.2, *) {
            startTokenTask = Task { [weak self] in
                for await token in Activity<VisitActivityAttributes>.pushToStartTokenUpdates {
                    self?.push.didReceive(activityStartToken: token)
                }
            }
        }
    }

    /// Alinea las actividades con las visitas pendientes de Inicio.
    func sync(pending: [Visit], residence: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let pendingIds = Set(pending.map(\.id))

        // Las que ya no están pendientes y nadie cerró (expiró o respondieron
        // en otro lado sin push) se quitan.
        let stale = Activity<VisitActivityAttributes>.activities.filter {
            !pendingIds.contains($0.attributes.visitId) && $0.content.state.phase == .waiting
        }
        for activity in stale {
            let visitId = activity.attributes.visitId
            Task { await end(visitId: visitId, phase: .noResponse, respondedBy: nil, dismissImmediately: true) }
        }

        let running = Set(Activity<VisitActivityAttributes>.activities.map(\.attributes.visitId))
        for visit in pending where !running.contains(visit.id) {
            start(visit, residence: residence)
        }
    }

    func start(_ visit: Visit, residence: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let respondBy = visit.responseDeadline, respondBy > .now else { return }
        let attributes = VisitActivityAttributes(
            visitId: visit.id,
            arrivedAt: visit.arrivedAt ?? respondBy.addingTimeInterval(-Visit.responseWindow),
            name: visit.name,
            initials: visit.initials,
            kind: visit.kind,
            detail: visit.subtitle,
            residence: residence,
            heldByAdministration: visit.isHeldByAdministration
        )
        let state = VisitActivityAttributes.ContentState(phase: .waiting, respondBy: respondBy, respondedBy: nil)
        // Al vencer el plazo la actividad queda "obsoleta" y muestra que se
        // está escalando; el backend la cierra como "sin respuesta".
        let content = ActivityContent(state: state, staleDate: respondBy, relevanceScore: 100)
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
            observeToken(of: activity)
        } catch {
            // Sin permiso de Live Activities o límite alcanzado: queda el aviso.
        }
    }

    /// Al tocar Autorizar / Rechazar: quita los botones de inmediato.
    func showResponding(visitId: String, decision: VisitDecision) async {
        await update(visitId: visitId) { state in
            state.phase = decision == .authorize ? .authorizing : .rejecting
        }
    }

    /// No se pudo enviar (sin red): vuelven los botones para reintentar.
    func restoreWaiting(visitId: String) async {
        await update(visitId: visitId) { state in
            state.phase = .waiting
        }
    }

    /// Respuesta conocida (aquí, desde el aviso, Siri u otro integrante). Se
    /// espera a que termine: si no, la app puede suspenderse antes de cerrar
    /// la actividad y la isla se queda con los botones.
    func end(
        visitId: String,
        phase: VisitActivityAttributes.ContentState.Phase,
        respondedBy: String?,
        dismissImmediately: Bool = false
    ) async {
        tokenTasks[visitId]?.cancel()
        tokenTasks[visitId] = nil
        let policy: ActivityUIDismissalPolicy = dismissImmediately ? .immediate : .after(.now.addingTimeInterval(4))
        for activity in Activity<VisitActivityAttributes>.activities where activity.attributes.visitId == visitId {
            let state = VisitActivityAttributes.ContentState(
                phase: phase,
                respondBy: activity.content.state.respondBy,
                respondedBy: respondedBy
            )
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy)
        }
    }

    func endAll() {
        Task {
            for activity in Activity<VisitActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        tokenTasks.values.forEach { $0.cancel() }
        tokenTasks = [:]
    }

    private func update(visitId: String, _ change: (inout VisitActivityAttributes.ContentState) -> Void) async {
        for activity in Activity<VisitActivityAttributes>.activities where activity.attributes.visitId == visitId {
            var state = activity.content.state
            guard !state.phase.isFinal else { continue }
            change(&state)
            await activity.update(ActivityContent(state: state, staleDate: state.phase == .waiting ? state.respondBy : nil))
        }
    }

    private func observeToken(of activity: Activity<VisitActivityAttributes>) {
        let visitId = activity.attributes.visitId
        let environment = environment
        tokenTasks[visitId] = Task { [visits] in
            for await token in activity.pushTokenUpdates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                try? await visits.registerActivityToken(ActivityTokenRequest(token: hex, environment: environment), for: visitId)
            }
        }
    }
}
