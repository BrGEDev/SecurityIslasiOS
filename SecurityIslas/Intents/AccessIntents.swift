//
//  AccessIntents.swift
//  SecurityIslas
//
//  Siri, Atajos y botón de Acción (RF-30 a RF-34, pantallas 28 y 29). Los
//  intents llaman a los mismos repositorios que la app (vía `AppContainer`) y
//  siguen las mismas reglas:
//  • Solo con el iPhone desbloqueado (RF-32): `.requiresAuthentication`.
//  • Autorizar: si hay varias visitas pendientes, pregunta cuál (RF-33).
//  • Abrir pluma: geocerca de la entrada y tipo de carril (RF-31, RF-23); en
//    carril compartido manda la solicitud de paso. Pide Face ID igual que en la
//    app, por eso abre la app.
//  • Pánico: abre la cuenta regresiva cancelable (RF-41); al terminar se envía.
//
//  Los nombres de los tipos y los `id` de las entidades son un contrato con los
//  atajos guardados: no renombrarlos.
//

import AppIntents
import Foundation

// MARK: - Errores

nonisolated enum AccessIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    case notAllowed
    case heldByAdministration
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Abre Islas Security y entra con tu número para usar este atajo."
        case .notAllowed: "Tu acceso no permite hacer esto."
        case .heldByAdministration: "Esta persona coincide con la lista restringida: la administración decide si entra."
        case .failed(let message): "\(message)"
        }
    }
}

// MARK: - Visitas como entidad

nonisolated struct VisitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Visita"
    static let defaultQuery = VisitEntityQuery()

    /// Mismo `id` que la visita del backend.
    let id: String
    let name: String
    let kindTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kindTitle)")
    }

    init(_ visit: Visit) {
        id = visit.id
        name = visit.name
        kindTitle = visit.kind.title
    }
}

/// Las visitas que esperan en caseta.
nonisolated struct VisitEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [VisitEntity] {
        try await Self.pending().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [VisitEntity] {
        try await Self.pending()
    }

    @MainActor
    static func pending() async throws -> [VisitEntity] {
        let container = AppContainer.shared
        guard let profile = await container.session.activeProfile(), profile.canAuthorizeVisits else { return [] }
        return try await container.visits.home().pendingVisits.map(VisitEntity.init)
    }
}

// MARK: - Autorizar visita (RF-30, RF-33)

struct AutorizarVisitaIntent: AppIntent {
    static let title: LocalizedStringResource = "Autorizar visita"
    static let description = IntentDescription("Autoriza a la visita o al servicio que espera en caseta.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Visita")
    var visita: VisitEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Autorizar a \(\.$visita)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppContainer.shared
        guard let profile = await container.session.activeProfile() else { throw AccessIntentError.signedOut }
        guard profile.canAuthorizeVisits else { throw AccessIntentError.notAllowed }

        // Primero se resuelve cuál; lo irreversible (autorizar) va al final.
        let target: VisitEntity
        if let visita {
            target = visita
        } else {
            let pending = try await VisitEntityQuery.pending()
            switch pending.count {
            case 0:
                return .result(dialog: "No hay visitas en caseta.")
            case 1:
                target = pending[0]
            default:
                target = try await $visita.requestDisambiguation(
                    among: pending,
                    dialog: "Hay \(pending.count) visitas en caseta. ¿Cuál autorizo?"
                )
            }
        }

        let summary = try await container.visits.home()
        guard let visit = summary.pendingVisits.first(where: { $0.id == target.id }) else {
            return .result(dialog: "\(target.name) ya no está esperando en caseta.")
        }
        guard !visit.isHeldByAdministration else { throw AccessIntentError.heldByAdministration }

        do {
            _ = try await container.visits.decide(visit.id, decision: .authorize)
        } catch {
            throw AccessIntentError.failed(error.userMessage ?? "No se pudo autorizar.")
        }
        NotificationManager.withdraw(visitId: visit.id)
        container.dataDidChange()
        return .result(dialog: "Listo, avisamos a caseta que \(visit.name) puede pasar.")
    }
}

// MARK: - Abrir pluma / Solicitar paso (RF-31, RF-23)

nonisolated struct AbrirPlumaIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir pluma"
    static let description = IntentDescription("Abre la pluma en el carril de residentes o solicita paso en el carril compartido. Solo funciona cerca de la entrada.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    /// La orden se firma con la llave atada a Face ID: se necesita la app al frente.
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppContainer.shared
        guard let profile = await container.session.activeProfile() else { throw AccessIntentError.signedOut }
        guard profile.canUseGate else { throw AccessIntentError.notAllowed }

        let configuration: GateConfiguration
        let coordinate: Coordinate
        do {
            configuration = try await container.visits.home().gate
            coordinate = try await container.location.currentCoordinate()
        } catch {
            throw AccessIntentError.failed(error.userMessage ?? "No pudimos obtener tu ubicación.")
        }

        switch GateViewModel.evaluate(coordinate, in: configuration) {
        case .ready(let lane, _):
            do {
                let result = try await container.gate.open(lane: lane, from: coordinate)
                container.dataDidChange()
                switch result.outcome {
                case .opened:
                    return .result(dialog: "Pluma abierta · \(result.laneName).")
                case .passRequested:
                    return .result(dialog: "Solicitud de paso enviada. El guardia confirma y abre.")
                }
            } catch BiometricError.canceled {
                return .result(dialog: "No se abrió la pluma.")
            } catch {
                throw AccessIntentError.failed(error.userMessage ?? "No se pudo abrir. Pide apoyo en caseta.")
            }
        case .far(let distance):
            let away = distance >= 1_000
                ? "Estás a \((Double(distance) / 1_000).formatted(.number.precision(.fractionLength(1)).locale(.app))) km."
                : "Estás a \(distance) m."
            return .result(dialog: "Tienes que estar cerca de la entrada para abrir la pluma. \(away)")
        default:
            return .result(dialog: "Activa la ubicación para abrir la pluma cerca de la entrada.")
        }
    }
}

// MARK: - Pánico (RF-41)

nonisolated struct PanicoIntent: AppIntent {
    static let title: LocalizedStringResource = "Pánico"
    static let description = IntentDescription("Inicia la cuenta regresiva del pánico. Si no la cancelas, la alerta se envía con tu ubicación.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = AppContainer.shared
        guard await container.session.activeProfile() != nil else { throw AccessIntentError.signedOut }
        container.panicRequest = .countdown
        return .result()
    }
}

// MARK: - Mi QR

nonisolated struct MiQRIntent: AppIntent {
    static let title: LocalizedStringResource = "Mostrar Mi QR"
    static let description = IntentDescription("Abre tu QR de acceso para mostrarlo en caseta.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = AppContainer.shared
        guard await container.session.activeProfile() != nil else { throw AccessIntentError.signedOut }
        container.tabRequest = .qr
        return .result()
    }
}

// MARK: - Atajos de la app (RF-30, RF-31, RF-34)

nonisolated struct AccessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AutorizarVisitaIntent(),
            phrases: [
                "Autoriza la visita en \(.applicationName)",
                "Deja pasar a mi visita en \(.applicationName)",
            ],
            shortTitle: "Autorizar visita",
            systemImageName: "person.badge.shield.checkmark"
        )
        AppShortcut(
            intent: AbrirPlumaIntent(),
            phrases: [
                "Abre la pluma en \(.applicationName)",
                "Solicita paso en \(.applicationName)",
            ],
            shortTitle: "Abrir pluma",
            systemImageName: "road.lanes"
        )
        AppShortcut(
            intent: PanicoIntent(),
            phrases: [
                "Pánico en \(.applicationName)",
                "Activa el pánico en \(.applicationName)",
            ],
            shortTitle: "Pánico",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: MiQRIntent(),
            phrases: ["Muestra mi QR en \(.applicationName)"],
            shortTitle: "Mi QR",
            systemImageName: "qrcode"
        )
    }
}
