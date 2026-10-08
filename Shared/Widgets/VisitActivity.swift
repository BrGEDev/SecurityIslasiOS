//
//  VisitActivity.swift
//  SecurityIslas (app y widgets de iPhone)
//
//  Live Activity de la visita en caseta (pantallas 11 y 12): cuenta regresiva
//  hasta el escalamiento, Autorizar / Rechazar en la pantalla bloqueada y en la
//  Dynamic Island. Nunca se autoriza sola (RF-04): al agotarse el tiempo dice
//  "sin respuesta" y se cierra en todos los teléfonos de la casa cuando alguien
//  responde (RF-06).
//
//  Los botones usan `VisitDecisionIntent`, que es `LiveActivityIntent`: el
//  sistema lo ejecuta en el proceso de la app (no en el widget), así llama al
//  mismo repositorio que la app.
//

#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

nonisolated struct VisitActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Sendable {
            case waiting
            case authorized
            case rejected
            /// Pasó el tiempo y nadie respondió: no entra (RF-04).
            case noResponse
        }

        var phase: Phase
        /// Fin de la cuenta regresiva antes de escalar a WhatsApp y llamada.
        var respondBy: Date
        /// Quién de la casa respondió (RF-06).
        var respondedBy: String?
    }

    let visitId: String
    let name: String
    let initials: String
    let kind: AccessKind
    let detail: String
    let residence: String
    /// Lista restringida (RF-86): Autorizar no aplica.
    let heldByAdministration: Bool
}

/// Lo conecta la app al arrancar. En el proceso del widget queda en `nil`,
/// pero `LiveActivityIntent` siempre corre en el de la app.
@MainActor
enum VisitDecisionHandler {
    static var decide: ((String, VisitDecision) async throws -> Void)?
}

nonisolated enum VisitDecisionOption: String, AppEnum {
    case authorize
    case reject

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Respuesta"
    static let caseDisplayRepresentations: [VisitDecisionOption: DisplayRepresentation] = [
        .authorize: "Autorizar",
        .reject: "Rechazar",
    ]

    var decision: VisitDecision {
        switch self {
        case .authorize: .authorize
        case .reject: .reject
        }
    }
}

/// Autorizar / Rechazar desde la Live Activity, el widget o el aviso. Autorizar
/// desde la pantalla bloqueada pide desbloquear (RF-02): se marca con
/// `.requiresAuthentication` solo esa acción.
struct VisitDecisionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Responder a la visita"
    static let isDiscoverable = false

    @Parameter(title: "Visita")
    var visitId: String

    @Parameter(title: "Respuesta")
    var option: VisitDecisionOption

    init() {}

    init(visitId: String, option: VisitDecisionOption) {
        self.visitId = visitId
        self.option = option
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await VisitDecisionHandler.decide?(visitId, option.decision)
        return .result()
    }
}

/// Autorizar exige el iPhone desbloqueado; Rechazar funciona bloqueado (RF-02).
struct AuthorizeVisitFromLockScreenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Autorizar visita en caseta"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Visita")
    var visitId: String

    init() {}

    init(visitId: String) {
        self.visitId = visitId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await VisitDecisionHandler.decide?(visitId, .authorize)
        return .result()
    }
}
#endif
