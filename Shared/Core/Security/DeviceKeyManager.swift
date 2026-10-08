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
    /// Cambiaron las caras o huellas registradas (`.biometryCurrentSet`).
    case biometryChanged

    #if os(watchOS)
    private static let missingKeyMessage = "Este reloj todavía no tiene su llave. Vuélvelo a vincular desde tu iPhone."
    #else
    private static let missingKeyMessage = "Este iPhone todavía no tiene su llave. Vuelve a activar Face ID."
    #endif

    var errorDescription: String? {
        switch self {
        case .missingKey: Self.missingKeyMessage
        case .accessControl: "No se pudo proteger la llave del dispositivo."
        case .biometryChanged: "Cambiaron las caras o huellas registradas en este iPhone. Por seguridad, vuelve a activar Face ID."
        }
    }
}

nonisolated final class DeviceKeyManager: Sendable {
    private let keychain: KeychainStore
    private let keyTag = "device.signing.key"
    private let kindTag = "device.signing.kind"
    private let modeTag = "device.signing.mode"
    private let domainTag = "device.signing.biometryState"

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    /// En el simulador `SecureEnclave.isAvailable` puede ser `true`, pero la
    /// llave exige un código de desbloqueo que el simulador no tiene y falla
    /// con "Error de autenticación". Ahí siempre se usa la llave de software.
    static var usesSecureEnclave: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        SecureEnclave.isAvailable
        #endif
    }

    /// iPhone: Face ID / Touch ID con `.biometryCurrentSet` (decisión de
    /// Brandon): si cambian las caras o huellas registradas, la llave deja de
    /// servir y hay que volver a activar Face ID (se registra una llave nueva).
    /// Si el iPhone no tiene biometría registrada, la llave queda atada al
    /// código del iPhone (respaldo de RF-67).
    /// Apple Watch: no tiene Face ID; la llave solo se puede usar con el reloj
    /// desbloqueado (`WhenPasscodeSet`), y el reloj se bloquea al quitárselo de
    /// la muñeca. Eso cumple "puesto y desbloqueado" (RF-68).
    private static func accessFlags(biometric: Bool) -> SecAccessControlCreateFlags {
        #if os(watchOS)
        [.privateKeyUsage]
        #else
        biometric ? [.privateKeyUsage, .biometryCurrentSet] : [.privateKeyUsage, .devicePasscode]
        #endif
    }

    var hasKey: Bool {
        keychain.data(for: keyTag) != nil
    }

    var isHardwareBacked: Bool {
        keychain.data(for: kindTag).map { String(decoding: $0, as: UTF8.self) } == "se"
    }

    /// La llave exige biometría (no acepta el código del iPhone). El
    /// autenticador usa entonces la política solo de biometría para que el
    /// contexto le sirva al Secure Enclave.
    var requiresBiometry: Bool {
        keychain.data(for: modeTag).map { String(decoding: $0, as: UTF8.self) } == "bio"
    }

    /// Cambiaron las caras o huellas registradas desde que se creó la llave
    /// (`.biometryCurrentSet`): la llave ya no firma. Se detecta antes de
    /// intentarlo comparando el estado del dominio biométrico.
    var isInvalidatedByBiometryChange: Bool {
        guard hasKey, requiresBiometry, let stored = keychain.data(for: domainTag) else { return false }
        guard let current = Self.biometryDomainState() else {
            // Sin biometría registrada: la llave tampoco sirve.
            return true
        }
        return current != stored
    }

    /// Crea (o reemplaza) la llave del dispositivo y regresa la pública en X9.63.
    /// `usingPasscode` ata la llave al código del iPhone ("Usar el código del
    /// iPhone" en la pantalla 8); si no, a la biometría registrada (si la hay).
    func createKey(context: LAContext, usingPasscode: Bool = false) throws -> Data {
        deleteKey()

        if Self.usesSecureEnclave {
            let domainState = usingPasscode ? nil : Self.biometryDomainState()
            let biometric = domainState != nil
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                Self.accessFlags(biometric: biometric),
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
            #if os(iOS)
            try keychain.set(Data((biometric ? "bio" : "code").utf8), for: modeTag)
            if let domainState {
                try keychain.set(domainState, for: domainTag)
            }
            #endif
            return key.publicKey.x963Representation
        }

        let key = P256.Signing.PrivateKey()
        try keychain.set(key.rawRepresentation, for: keyTag)
        try keychain.set(Data("sw".utf8), for: kindTag)
        return key.publicKey.x963Representation
    }

    /// Huella del conjunto de caras / huellas registradas, o `nil` si el
    /// dispositivo no tiene biometría registrada (o es el reloj).
    static func biometryDomainState() -> Data? {
        #if os(iOS)
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        if #available(iOS 18, *) {
            return context.domainState.biometry.stateHash
        }
        return context.evaluatedPolicyDomainState
        #else
        return nil
        #endif
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
        guard !isInvalidatedByBiometryChange else { throw DeviceKeyError.biometryChanged }
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
        keychain.delete(modeTag)
        keychain.delete(domainTag)
    }
}
