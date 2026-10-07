//
//  RequestInterceptor.swift
//  SecurityIslas
//

import Foundation

nonisolated struct RequestContext: Sendable {
    let requiresAuth: Bool
}

nonisolated enum RetryDecision: Sendable, Equatable {
    case retry
    case doNotRetry
}

/// Se ejecuta en orden sobre cada petición antes de enviarla (`adapt`) y
/// decide si una respuesta fallida se vuelve a intentar (`retry`).
nonisolated protocol RequestInterceptor: Sendable {
    func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest
    func retry(
        _ request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        attempt: Int
    ) async throws -> RetryDecision
}

nonisolated extension RequestInterceptor {
    func retry(
        _ request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        attempt: Int
    ) async throws -> RetryDecision {
        .doNotRetry
    }
}

/// Encabezados comunes a todas las peticiones.
nonisolated struct DefaultHeadersInterceptor: RequestInterceptor {
    let deviceId: String
    let appVersion: String

    func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("es-MX", forHTTPHeaderField: "Accept-Language")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue("ios/\(appVersion)", forHTTPHeaderField: "X-Client")
        return request
    }
}
