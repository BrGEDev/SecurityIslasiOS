//
//  AuthInterceptor.swift
//  SecurityIslas
//
//  Interceptor de token:
//  1. Agrega `Authorization: Bearer <access>` a las peticiones autenticadas.
//  2. Si el access token ya expiró (o está por expirar), lo renueva antes de enviar.
//  3. Si el servidor responde 401, renueva y pide al APIClient reintentar una vez.
//  4. Las renovaciones concurrentes se agrupan en una sola llamada (single-flight).
//  5. Si el refresh token ya no sirve, borra la sesión y avisa por `SessionEventBus`.
//

import Foundation

actor AuthInterceptor: RequestInterceptor {
    typealias Refresher = @Sendable (_ refreshToken: String) async throws -> AuthTokens

    private let tokenStore: any TokenStore
    private let refresher: Refresher
    private let events: SessionEventBus
    private let leeway: TimeInterval
    private var refreshTask: Task<AuthTokens, Error>?

    init(
        tokenStore: any TokenStore,
        events: SessionEventBus,
        leeway: TimeInterval = 30,
        refresher: @escaping Refresher
    ) {
        self.tokenStore = tokenStore
        self.events = events
        self.leeway = leeway
        self.refresher = refresher
    }

    func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        guard context.requiresAuth else { return request }
        guard var tokens = await tokenStore.tokens() else {
            throw APIError.sessionExpired
        }
        if tokens.isExpired(leeway: leeway) {
            tokens = try await refreshTokens(using: tokens)
        }
        var request = request
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func retry(
        _ request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        attempt: Int
    ) async throws -> RetryDecision {
        guard response.statusCode == 401,
              let sentHeader = request.value(forHTTPHeaderField: "Authorization") else {
            return .doNotRetry
        }
        guard let current = await tokenStore.tokens() else {
            throw APIError.sessionExpired
        }
        // Otra petición ya renovó el token mientras esta viajaba: solo reintenta.
        if sentHeader != "Bearer \(current.accessToken)" {
            return .retry
        }
        _ = try await refreshTokens(using: current)
        return .retry
    }

    // MARK: - Privado

    private func refreshTokens(using tokens: AuthTokens) async throws -> AuthTokens {
        if let refreshTask {
            return try await refreshTask.value
        }

        let refresher = self.refresher
        let refreshToken = tokens.refreshToken
        let task = Task { try await refresher(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let newTokens = try await task.value
            try await tokenStore.save(newTokens)
            return newTokens
        } catch let error as APIError where error.isAuthFailure {
            await tokenStore.clear()
            events.send(.expired)
            throw APIError.sessionExpired
        }
    }
}
