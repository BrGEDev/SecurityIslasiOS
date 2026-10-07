//
//  WatchEnvelope.swift
//  SecurityIslas (iPhone y Apple Watch)
//
//  Mensajes entre el iPhone y el reloj por WatchConnectivity. El brief limita
//  WatchConnectivity a la sesión inicial: el iPhone solo le pasa al reloj un
//  código de un solo uso; el reloj crea su llave y su propia sesión contra el
//  backend, y a partir de ahí funciona sin el iPhone cerca.
//
//  Los casos marcados "mock" solo existen mientras el backend sea el de prueba
//  (cada app tiene su propio MockServer y hay que pasarle los datos).
//

import Foundation

/// Datos del reloj ya vinculado (solo mock: el backend real ya los tiene).
nonisolated struct LinkedWatch: Codable, Sendable {
    let userId: String
    let deviceId: String
    let name: String
    let publicKey: String
}

nonisolated enum WatchEnvelope: Codable, Sendable {
    /// iPhone → reloj: código para vincular. `mockAccount` solo con el mock.
    case link(code: String, mockAccount: Data?)
    /// Reloj → iPhone: ya quedó vinculado.
    case linked(LinkedWatch)
    /// iPhone → reloj: se quitó el reloj en Dispositivos o se cerró la sesión.
    case unlinked
    /// iPhone → reloj (mock): llegó una visita simulada.
    case simulatedVisit(Visit, residence: String)

    private static let key = "envelope"

    func message() throws -> [String: Any] {
        [Self.key: try JSONCoding.encoder().encode(self)]
    }

    init?(message: [String: Any]) {
        guard let data = message[Self.key] as? Data,
              let envelope = try? JSONCoding.decoder().decode(WatchEnvelope.self, from: data) else {
            return nil
        }
        self = envelope
    }
}

nonisolated enum WatchBridgeError: Error, LocalizedError, Sendable {
    case unavailable
    case appNotInstalled

    var errorDescription: String? {
        switch self {
        case .unavailable: "No encontramos tu Apple Watch. Revisa que esté cerca y con Bluetooth."
        case .appNotInstalled: "Instala \(AppInfo.name) en tu Apple Watch desde la app Watch del iPhone."
        }
    }
}
