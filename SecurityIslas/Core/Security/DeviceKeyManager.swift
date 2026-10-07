//
//  DeviceKeyManager.swift
//  SecurityIslas
//
//  Llave P-256 del dispositivo (RF-67, RNF-05). En un iPhone real vive en el
//  Secure Enclave, protegida con SecAccessControl (biometría o código): la
//  biometría no es un booleano local, es lo que habilita la firma.
//
//  En el simulador no hay Secure Enclave: se usa una llave de software solo
//  para poder desarrollar (ver DECISIONES.md).
//

import CryptoKit
import Foundation
import LocalAuthentication
import Security

nonisolated enum DeviceKeyError: Error, LocalizedError, Sendable {
    case missingKey
    case accessControl

    var errorDescription: String? {
        switch self {
        case .missingKey: "Este iPhone todavía no tiene su llave. Vuelve a activar Face ID."
        case .accessControl: "No se pudo proteger la llave del dispositivo."
        }
    }
}

nonisolated final class DeviceKeyManager: Sendable {
    private let keychain: KeychainStore
    private let keyTag = "device.signing.key"
    private let kindTag = "device.signing.kind"

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    var hasKey: Bool {
        keychain.data(for: keyTag) != nil
    }

    var isHardwareBacked: Bool {
        keychain.data(for: kindTag).map { String(decoding: $0, as: UTF8.self) } == "se"
    }

    /// Crea (o reemplaza) la llave del dispositivo y regresa la pública en X9.63.
    func createKey(context: LAContext) throws -> Data {
        deleteKey()

        if SecureEnclave.isAvailable {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.privateKeyUsage, .userPresence],
                &error
            ) else {
                throw DeviceKeyError.accessControl
            }
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                accessControl: access,
                authenticationContext: context
            )
            try keychain.set(key.dataRepresentation, for: keyTag)
            try keychain.set(Data("se".utf8), for: kindTag)
            return key.publicKey.x963Representation
        }

        let key = P256.Signing.PrivateKey()
        try keychain.set(key.rawRepresentation, for: keyTag)
        try keychain.set(Data("sw".utf8), for: kindTag)
        return key.publicKey.x963Representation
    }

    func publicKey() throws -> Data {
        guard let stored = keychain.data(for: keyTag) else { throw DeviceKeyError.missingKey }
        if isHardwareBacked {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored).publicKey.x963Representation
        }
        return try P256.Signing.PrivateKey(rawRepresentation: stored).publicKey.x963Representation
    }

    /// Firma con la llave del dispositivo. `context` debe venir ya autenticado
    /// por `BiometricAuthenticator`; así el Secure Enclave no vuelve a preguntar.
    func sign(_ message: Data, context: LAContext) throws -> Data {
        guard let stored = keychain.data(for: keyTag) else { throw DeviceKeyError.missingKey }
        if isHardwareBacked {
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: stored,
                authenticationContext: context
            )
            return try key.signature(for: message).derRepresentation
        }
        let key = try P256.Signing.PrivateKey(rawRepresentation: stored)
        return try key.signature(for: message).derRepresentation
    }

    func deleteKey() {
        keychain.delete(keyTag)
        keychain.delete(kindTag)
    }
}
