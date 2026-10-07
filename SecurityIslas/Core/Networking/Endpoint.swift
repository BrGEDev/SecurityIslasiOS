//
//  Endpoint.swift
//  SecurityIslas
//
//  Describe una llamada al backend y el tipo que regresa. Los endpoints
//  concretos viven en Core/API/API.swift.
//

import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated struct Endpoint<Response: Decodable & Sendable>: Sendable {
    var method: HTTPMethod
    /// Ruta relativa a `APIConfig.baseURL`, sin diagonal inicial (ej. `visits/123/decision`).
    var path: String
    var query: [URLQueryItem]
    /// Cuerpo ya codificado. Se guarda en bytes para que la firma (RequestSigner)
    /// y lo que viaja por la red sean exactamente lo mismo.
    var body: Data?
    var headers: [String: String]
    /// Si es `true`, el `AuthInterceptor` agrega el token y lo renueva cuando expira.
    var requiresAuth: Bool

    init(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = nil
        self.headers = [:]
        self.requiresAuth = requiresAuth
    }

    init<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Body,
        requiresAuth: Bool = true
    ) throws {
        self.init(method, path, requiresAuth: requiresAuth)
        self.body = try JSONCoding.encoder().encode(body)
        self.headers["Content-Type"] = "application/json"
    }
}

/// Respuesta vacía (204 o `{}`).
nonisolated struct EmptyResponse: Codable, Sendable, Equatable {
    init() {}
}

nonisolated enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
