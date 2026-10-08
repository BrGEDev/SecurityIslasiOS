//
//  RegistrationRepository.swift
//  SecurityIslas
//
//  Alta del residente (RF-60 a RF-66) y registro de la llave del dispositivo.
//

import Foundation

protocol RegistrationRepository {
    func searchFraccionamientos(_ query: String) async throws -> [Fraccionamiento]
    func homes(in fraccionamiento: Fraccionamiento) async throws -> [HomeOption]
    func resolveInvite(_ code: String) async throws -> Fraccionamiento
    func submit(_ request: RegistrationRequest) async throws -> UserProfile
}

final class RemoteRegistrationRepository: RegistrationRepository {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func searchFraccionamientos(_ query: String) async throws -> [Fraccionamiento] {
        try await client.send(API.Registration.fraccionamientos(query: query))
    }

    func homes(in fraccionamiento: Fraccionamiento) async throws -> [HomeOption] {
        try await client.send(API.Registration.homes(fraccionamientoId: fraccionamiento.id))
    }

    func resolveInvite(_ code: String) async throws -> Fraccionamiento {
        try await client.send(API.Registration.resolveInvite(code))
    }

    func submit(_ request: RegistrationRequest) async throws -> UserProfile {
        try await client.send(API.Registration.submit(request))
    }
}

protocol DeviceRepository {
    func devices() async throws -> DeviceList
    /// Quitar un dispositivo es un cambio de cuenta: pide Face ID, salvo en el
    /// registro (pantalla 3b), donde este iPhone aún no tiene llave.
    func remove(_ device: Device, signed: Bool) async throws
    /// Crea la llave del Secure Enclave (atada a Face ID) y registra la pública.
    /// `usingPasscode`: la llave se ata al código del iPhone en lugar de Face ID.
    func registerThisDevice(usingPasscode: Bool) async throws -> Device
    /// Código de un solo uso para vincular el Apple Watch. Agregar un
    /// dispositivo es un cambio de cuenta: pide Face ID (RF-67).
    func createWatchLink() async throws -> WatchLinkTicket
    /// Registra el token de APNs de este dispositivo.
    func registerPushToken(_ request: PushTokenRequest) async throws
}

final class RemoteDeviceRepository: DeviceRepository {
    private let client: any APIClientProtocol
    private let signer: RequestSigner
    private let keys: DeviceKeyManager
    private let biometrics: BiometricAuthenticator
    private let descriptor: DeviceDescriptor
    private let attester: AppAttester

    init(
        client: any APIClientProtocol,
        signer: RequestSigner,
        keys: DeviceKeyManager,
        biometrics: BiometricAuthenticator,
        descriptor: DeviceDescriptor,
        attester: AppAttester
    ) {
        self.client = client
        self.signer = signer
        self.keys = keys
        self.biometrics = biometrics
        self.descriptor = descriptor
        self.attester = attester
    }

    func devices() async throws -> DeviceList {
        try await client.send(API.Devices.list())
    }

    func remove(_ device: Device, signed: Bool) async throws {
        var endpoint = API.Devices.remove(device.id)
        if signed {
            endpoint = try await signer.sign(endpoint, reason: "Quitar \(device.name) de tu cuenta")
        }
        _ = try await client.send(endpoint)
    }

    func createWatchLink() async throws -> WatchLinkTicket {
        let endpoint = try await signer.sign(API.Devices.createWatchLink(), reason: "Vincular tu Apple Watch")
        return try await client.send(endpoint)
    }

    func registerPushToken(_ request: PushTokenRequest) async throws {
        _ = try await client.send(API.Devices.registerPushToken(request))
    }

    func registerThisDevice(usingPasscode: Bool) async throws -> Device {
        // Con Face ID registrado, la llave es `.biometryCurrentSet`: se verifica
        // con biometría para no crearla con un contexto de código.
        // En el simulador la llave es de software: no hay nada que atar a Face ID.
        let biometric = !usingPasscode && DeviceKeyManager.usesSecureEnclave
            && DeviceKeyManager.biometryDomainState() != nil
        let context = try await biometrics.authenticate(reason: "Crear la llave de este iPhone", biometryOnly: biometric)
        let publicKey = try keys.createKey(context: context, usingPasscode: !biometric)
        let attestation = await attester.attest(publicKey: publicKey)
        let request = DeviceKeyRequest(
            name: descriptor.name,
            model: descriptor.model,
            publicKey: publicKey.base64EncodedString(),
            attestation: attestation?.attestation,
            attestationKeyId: attestation?.keyId,
            attestationChallenge: attestation?.challenge,
            hardwareBacked: keys.isHardwareBacked
        )
        do {
            return try await client.send(API.Devices.registerKey(request))
        } catch {
            keys.deleteKey()
            throw error
        }
    }
}
