//
//  AppAttester.swift
//  SecurityIslas
//
//  App Attest (DeviceCheck) al registrar la llave del dispositivo: el backend
//  comprueba que la petición viene de la app legítima en hardware de Apple.
//
//  Flujo (supuesto, ver DECISIONES.md):
//  1. `POST devices/attest-challenge` → reto de un solo uso.
//  2. Se genera una llave de App Attest y se atesta con
//     `clientDataHash = SHA256(reto ‖ llave pública del dispositivo)`, para que
//     la atestación quede ligada a la llave del Secure Enclave que se registra.
//  3. `POST devices/key` lleva `attestation`, `attestationKeyId` y `challenge`.
//
//  En el simulador y en dispositivos sin soporte, `isSupported` es `false` y la
//  llave se registra sin atestación (el backend decide si la acepta).
//  En watchOS no se usa todavía: hay que confirmar con Apple el soporte
//  (sección 9 del brief).
//

import CryptoKit
import Foundation
#if os(iOS)
import DeviceCheck
#endif

nonisolated struct AppAttestation: Sendable {
    /// Objeto de atestación en base64.
    let attestation: String
    let keyId: String
    let challenge: String
}

final class AppAttester {
    private let client: any APIClientProtocol
    private let keychain: KeychainStore
    private let keyIdTag = "appattest.keyId"

    init(client: any APIClientProtocol, keychain: KeychainStore) {
        self.client = client
        self.keychain = keychain
    }

    /// Regresa `nil` si el dispositivo no soporta App Attest o si Apple no
    /// responde: el registro no se bloquea por eso.
    func attest(publicKey: Data) async -> AppAttestation? {
        #if os(iOS)
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        do {
            let challenge = try await client.send(API.Devices.attestChallenge())
            guard let challengeData = Data(base64Encoded: challenge.challenge) else { return nil }
            let keyId = try await service.generateKey()
            let clientDataHash = Data(SHA256.hash(data: challengeData + publicKey))
            let object = try await service.attestKey(keyId, clientDataHash: clientDataHash)
            try? keychain.set(Data(keyId.utf8), for: keyIdTag)
            return AppAttestation(
                attestation: object.base64EncodedString(),
                keyId: keyId,
                challenge: challenge.challenge
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
