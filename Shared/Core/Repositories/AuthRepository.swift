//
//  AuthRepository.swift
//  SecurityIslas
//
//  Cuenta por número de celular + código SMS (RF-61). Sin usuario ni contraseña.
//

import Foundation

protocol AuthRepository {
    func requestCode(for phone: PhoneNumber) async throws -> OTPChallenge
    /// Verifica el código y guarda los tokens de la sesión.
    func verifyCode(_ code: String, for phone: PhoneNumber) async throws -> VerificationResult
    func me() async throws -> UserProfile
    func logout() async throws
    /// Apple Watch: canjea el código del iPhone, registra la llave del reloj y
    /// guarda su propia sesión.
    func completeWatchLink(code: String, publicKey: Data, hardwareBacked: Bool) async throws -> UserProfile
}

final class RemoteAuthRepository: AuthRepository {
    private let client: any APIClientProtocol
    private let tokenStore: any TokenStore
    private let device: DeviceDescriptor

    init(client: any APIClientProtocol, tokenStore: any TokenStore, device: DeviceDescriptor) {
        self.client = client
        self.tokenStore = tokenStore
        self.device = device
    }

    func requestCode(for phone: PhoneNumber) async throws -> OTPChallenge {
        try await client.send(API.Auth.requestOTP(phone))
    }

    func verifyCode(_ code: String, for phone: PhoneNumber) async throws -> VerificationResult {
        let request = VerifyOTPRequest(phone: phone.e164, code: code, device: device)
        let response = try await client.send(API.Auth.verifyOTP(request))
        try await tokenStore.save(response.tokens.authTokens())
        return response.result
    }

    func me() async throws -> UserProfile {
        try await client.send(API.Auth.me())
    }

    func logout() async throws {
        _ = try await client.send(API.Auth.logout())
    }

    func completeWatchLink(code: String, publicKey: Data, hardwareBacked: Bool) async throws -> UserProfile {
        let request = WatchLinkRequest(
            code: code,
            device: device,
            publicKey: publicKey.base64EncodedString(),
            attestation: nil,
            hardwareBacked: hardwareBacked
        )
        let response = try await client.send(API.Auth.completeWatchLink(request))
        try await tokenStore.save(response.tokens.authTokens())
        return response.profile
    }
}
