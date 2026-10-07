//
//  PhoneWatchBridge.swift
//  SecurityIslas
//
//  Lado iPhone de WatchConnectivity: le pasa al reloj el código para
//  vincularse (Cuenta › Dispositivos) y recibe la confirmación. Después el
//  reloj trabaja con su propia sesión y su propia llave.
//

import Foundation
import Observation
import WatchConnectivity

@Observable
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    /// El reloj confirmó que ya está vinculado.
    @ObservationIgnored var onLinked: ((LinkedWatch) async -> Void)?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    var canLink: Bool { isPaired && isWatchAppInstalled }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Si el reloj tiene la app abierta llega al instante; si no, queda en cola
    /// y se entrega en cuanto la abra.
    func send(_ envelope: WatchEnvelope) throws {
        guard let session, session.activationState == .activated, session.isPaired else {
            throw WatchBridgeError.unavailable
        }
        guard session.isWatchAppInstalled else { throw WatchBridgeError.appNotInstalled }
        let message = try envelope.message()
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
    }

    /// Mismo envío, pero sin error si no hay reloj (avisos de prueba, baja).
    func sendIfPossible(_ envelope: WatchEnvelope) {
        try? send(envelope)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        updateState(from: session)
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        updateState(from: session)
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Al cambiar de reloj, iOS desactiva la sesión: se vuelve a activar.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(WatchEnvelope(message: message))
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(WatchEnvelope(message: userInfo))
    }

    nonisolated private func updateState(from session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak self] in
            self?.isPaired = paired
            self?.isWatchAppInstalled = installed
        }
    }

    nonisolated private func receive(_ envelope: WatchEnvelope?) {
        guard case .linked(let watch) = envelope else { return }
        Task { @MainActor [weak self] in
            await self?.onLinked?(watch)
        }
    }
}
