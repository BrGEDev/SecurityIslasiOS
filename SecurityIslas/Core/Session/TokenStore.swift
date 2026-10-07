//
//  TokenStore.swift
//  SecurityIslas
//

import Foundation

nonisolated struct AuthTokens: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    func isExpired(leeway: TimeInterval = 0, now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-leeway) <= now
    }
}

nonisolated protocol TokenStore: Sendable {
    func tokens() async -> AuthTokens?
    func save(_ tokens: AuthTokens) async throws
    func clear() async
}

/// Guarda los tokens en el Keychain y los mantiene en memoria para no leer
/// el Keychain en cada petición.
actor KeychainTokenStore: TokenStore {
    private let keychain: KeychainStore
    private let key = "session.tokens"
    private var cached: AuthTokens?
    private var didLoad = false

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func tokens() -> AuthTokens? {
        if !didLoad {
            cached = keychain.value(AuthTokens.self, for: key)
            didLoad = true
        }
        return cached
    }

    func save(_ tokens: AuthTokens) throws {
        try keychain.setValue(tokens, for: key)
        cached = tokens
        didLoad = true
    }

    func clear() {
        keychain.delete(key)
        cached = nil
        didLoad = true
    }
}

/// Eventos de sesión que nacen en la capa de red (fuera del MainActor).
nonisolated enum SessionEvent: Sendable {
    case expired
}

nonisolated final class SessionEventBus: Sendable {
    let events: AsyncStream<SessionEvent>
    private let continuation: AsyncStream<SessionEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        self.events = stream
        self.continuation = continuation
    }

    func send(_ event: SessionEvent) {
        continuation.yield(event)
    }
}

/// Identificador estable del dispositivo (sobrevive reinstalaciones porque
/// vive en el Keychain). Se manda en `X-Device-Id`.
nonisolated enum DeviceIdentity {
    static func identifier(in keychain: KeychainStore) -> String {
        let key = "device.id"
        if let data = keychain.data(for: key), let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        try? keychain.set(Data(id.utf8), for: key)
        return id
    }
}
