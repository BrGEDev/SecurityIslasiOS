//
//  PushRegistrar.swift
//  SecurityIslas
//
//  Push por APNs directo (decisión de Brandon). Guarda el token que entrega
//  iOS / watchOS y lo sube al backend cuando hay sesión activa. Solo vuelve a
//  subirlo si cambió el token o la cuenta.
//
//  Contenido del push (supuesto, ver DECISIONES.md):
//  • Visita en caseta: `aps.category = VISITA_PENDIENTE`, `mutable-content: 1`,
//    `interruption-level: time-sensitive` y en la raíz `type: visit.pending`,
//    `visitId`, `kind` (visit | service), `photoURL` y `residence`.
//  • Aviso informativo: `aps.category = VISITA_INFO`, `type: visit.info`.
//  • Alguien de la casa ya respondió (RF-06): push silencioso
//    (`content-available: 1`) con `type: visit.responded`, `visitId`,
//    `visitName`, `decision` y `respondedBy`. La app avisa quién respondió.
//

import Foundation

/// Lo que trae un push, ya leído del `userInfo`.
nonisolated enum RemotePush: Sendable, Equatable {
    case pendingVisit(visitId: String)
    case visitInfo(visitId: String?)
    case visitResponded(visitId: String, visitName: String?, decision: VisitDecision?, respondedBy: String?)
    case unknown

    init(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String
        let visitId = userInfo["visitId"] as? String
        switch type {
        case "visit.pending":
            self = visitId.map { .pendingVisit(visitId: $0) } ?? .unknown
        case "visit.info":
            self = .visitInfo(visitId: visitId)
        case "visit.responded":
            guard let visitId else { self = .unknown; return }
            self = .visitResponded(
                visitId: visitId,
                visitName: userInfo["visitName"] as? String,
                decision: (userInfo["decision"] as? String).flatMap(VisitDecision.init(rawValue:)),
                respondedBy: userInfo["respondedBy"] as? String
            )
        default:
            self = .unknown
        }
    }
}

final class PushRegistrar {
    private let devices: DeviceRepository
    private let topic: String
    private var alertToken: Data?
    private var activityStartToken: Data?
    private var userId: String?

    private let uploadedKey = "push.uploaded"

    init(devices: DeviceRepository, topic: String = Bundle.main.bundleIdentifier ?? "") {
        self.devices = devices
        self.topic = topic
    }

    /// Debug firma con el entorno de desarrollo de APNs; TestFlight y App Store
    /// con el de producción (`aps-environment` del perfil).
    private var environment: PushTokenRequest.Environment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    func didReceive(alertToken token: Data) {
        alertToken = token
        Task { await sync() }
    }

    func didReceive(activityStartToken token: Data) {
        activityStartToken = token
        Task { await sync() }
    }

    /// Se llama al entrar a Inicio y al cambiar la cuenta.
    func sessionDidChange(userId: String?) {
        self.userId = userId
        if userId == nil {
            UserDefaults.standard.removeObject(forKey: uploadedKey)
        } else {
            Task { await sync() }
        }
    }

    private func sync() async {
        guard let userId else { return }
        let pending: [(PushTokenRequest.Kind, Data)] = [
            alertToken.map { (.alert, $0) },
            activityStartToken.map { (.liveActivityStart, $0) },
        ].compactMap { $0 }

        var uploaded = UserDefaults.standard.dictionary(forKey: uploadedKey) as? [String: String] ?? [:]
        for (kind, token) in pending {
            let hex = token.map { String(format: "%02x", $0) }.joined()
            let marker = "\(userId):\(hex)"
            guard uploaded[kind.rawValue] != marker else { continue }
            let request = PushTokenRequest(kind: kind, token: hex, environment: environment, topic: topic)
            do {
                try await devices.registerPushToken(request)
                uploaded[kind.rawValue] = marker
            } catch {
                // Se reintenta en el siguiente arranque o cambio de sesión.
            }
        }
        UserDefaults.standard.set(uploaded, forKey: uploadedKey)
    }
}
