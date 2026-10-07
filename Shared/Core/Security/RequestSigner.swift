//
//  RequestSigner.swift
//  SecurityIslas
//
//  Acciones sensibles (RF-67): abrir la pluma, recurrentes, autorizaciones
//  automáticas y cambios de cuenta. iOS pide Face ID, se firma con la llave
//  del dispositivo y el backend verifica con la llave pública registrada.
//
//  Mensaje firmado (supuesto, ver DECISIONES.md):
//      METHOD \n path \n timestamp \n nonce \n sha256(body)
//

import CryptoKit
import Foundation

nonisolated enum SignaturePayload {
    static func canonical(method: String, path: String, timestamp: String, nonce: String, body: Data?) -> Data {
        let bodyHash = SHA256.hash(data: body ?? Data())
            .map { String(format: "%02x", $0) }
            .joined()
        let lines = [method, path, timestamp, nonce, bodyHash]
        return Data(lines.joined(separator: "\n").utf8)
    }
}

nonisolated enum SignatureHeader {
    static let signature = "X-Signature"
    static let timestamp = "X-Signature-Timestamp"
    static let nonce = "X-Signature-Nonce"
}

final class RequestSigner {
    private let keys: DeviceKeyManager
    private let biometrics: BiometricAuthenticator

    init(keys: DeviceKeyManager, biometrics: BiometricAuthenticator) {
        self.keys = keys
        self.biometrics = biometrics
    }

    /// Pide Face ID (o reutiliza una autenticación reciente) y firma el endpoint.
    func sign<Response>(_ endpoint: Endpoint<Response>, reason: String) async throws -> Endpoint<Response> {
        let context = try await biometrics.authenticate(reason: reason)
        let timestamp = String(Int(Date.now.timeIntervalSince1970))
        let nonce = UUID().uuidString
        let message = SignaturePayload.canonical(
            method: endpoint.method.rawValue,
            path: endpoint.path,
            timestamp: timestamp,
            nonce: nonce,
            body: endpoint.body
        )
        let signature = try keys.sign(message, context: context)

        var signed = endpoint
        signed.headers[SignatureHeader.timestamp] = timestamp
        signed.headers[SignatureHeader.nonce] = nonce
        signed.headers[SignatureHeader.signature] = signature.base64EncodedString()
        return signed
    }
}
