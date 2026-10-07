//
//  WatchLinkReceiver.swift
//  SecurityIslasWatch Watch App
//
//  Lado reloj de WatchConnectivity. Solo se usa para la sesión inicial (el
//  código de vínculo) y, con el backend mock, para recibir visitas simuladas.
//

import Foundation
import WatchConnectivity

final class WatchLinkReceiver: NSObject, WCSessionDelegate {
    var onEnvelope: ((WatchEnvelope) async -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ envelope: WatchEnvelope) {
        let session = WCSession.default
        guard session.activationState == .activated, let message = try? envelope.message() else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(WatchEnvelope(message: message))
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(WatchEnvelope(message: userInfo))
    }

    nonisolated private func receive(_ envelope: WatchEnvelope?) {
        guard let envelope else { return }
        Task { @MainActor [weak self] in
            await self?.onEnvelope?(envelope)
        }
    }
}
