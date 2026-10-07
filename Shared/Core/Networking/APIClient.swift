//
//  APIClient.swift
//  SecurityIslas
//
//  Cliente HTTP único de la app. Arma la petición, pasa por la cadena de
//  interceptores (encabezados, token), la envía por el transporte, decodifica
//  y reintenta una vez cuando un interceptor lo pide (ej. 401 → refresh).
//
//  Cuando exista el contrato OpenAPI, el cliente generado por
//  swift-openapi-generator puede usar el mismo transporte e interceptores.
//

import Foundation
import OSLog

nonisolated struct APIConfig: Sendable {
    let baseURL: URL
    let timeout: TimeInterval

    /// Host ficticio que atiende `MockServer`.
    static let mock = APIConfig(baseURL: URL(string: "https://mock.acceso.local/v1")!, timeout: 20)

    /// Supuesto: dominio por definir con el equipo de backend.
    static let staging = APIConfig(baseURL: URL(string: "https://api-staging.acceso.app/v1")!, timeout: 20)
}

nonisolated protocol APIClientProtocol: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

actor APIClient: APIClientProtocol {
    private let config: APIConfig
    private let transport: any HTTPTransport
    private let interceptors: [any RequestInterceptor]
    private let maxRetries: Int
    private let logger = Logger(subsystem: "app.security.islasgower", category: "network")

    init(
        config: APIConfig,
        transport: any HTTPTransport,
        interceptors: [any RequestInterceptor] = [],
        maxRetries: Int = 1
    ) {
        self.config = config
        self.transport = transport
        self.interceptors = interceptors
        self.maxRetries = maxRetries
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let context = RequestContext(requiresAuth: endpoint.requiresAuth)
        var attempt = 0

        while true {
            try Task.checkCancellation()

            var request = try makeRequest(for: endpoint)
            for interceptor in interceptors {
                request = try await interceptor.adapt(request, context: context)
            }

            let (data, response) = try await perform(request)
            let method = endpoint.method.rawValue
            let path = endpoint.path
            let status = response.statusCode
            logger.debug("\(method, privacy: .public) \(path, privacy: .public) → \(status)")

            if (200..<300).contains(status) {
                return try decode(Response.self, from: data)
            }

            if attempt < maxRetries,
               try await shouldRetry(request, response: response, data: data, attempt: attempt) {
                attempt += 1
                continue
            }

            throw APIError(statusCode: status, data: data)
        }
    }

    // MARK: - Privado

    private func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        let url = config.baseURL.appending(path: endpoint.path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let finalURL = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: finalURL, timeoutInterval: config.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError(urlError: error)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func shouldRetry(
        _ request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        attempt: Int
    ) async throws -> Bool {
        for interceptor in interceptors {
            let decision = try await interceptor.retry(request, response: response, data: data, attempt: attempt)
            if decision == .retry { return true }
        }
        return false
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let empty = EmptyResponse() as? T, data.isEmpty || T.self == EmptyResponse.self {
            return empty
        }
        do {
            return try JSONCoding.decoder().decode(T.self, from: data)
        } catch {
            logger.error("Decodificación fallida: \(String(describing: error), privacy: .public)")
            throw APIError.decoding(String(describing: error))
        }
    }
}
