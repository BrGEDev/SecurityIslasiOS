//
//  APIError.swift
//  SecurityIslas
//

import Foundation

/// Cuerpo de error que regresa el backend: `{ "code": "OUTSIDE_GEOFENCE", "message": "..." }`.
/// Supuesto: el contrato aún no existe (ver DECISIONES.md).
nonisolated struct ServerErrorBody: Codable, Sendable, Equatable {
    let code: String
    let message: String
}

nonisolated enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case offline
    case timeout
    case cancelled
    case transport(String)
    case unauthorized(ServerErrorBody?)
    /// El refresh token ya no es válido: hay que volver a verificar el número.
    case sessionExpired
    case forbidden(ServerErrorBody?)
    case notFound(ServerErrorBody?)
    case conflict(ServerErrorBody?)
    case tooManyRequests(ServerErrorBody?)
    case server(status: Int, body: ServerErrorBody?)
    case decoding(String)

    init(statusCode: Int, data: Data) {
        let body = try? JSONCoding.decoder().decode(ServerErrorBody.self, from: data)
        switch statusCode {
        case 401: self = .unauthorized(body)
        case 403: self = .forbidden(body)
        case 404: self = .notFound(body)
        case 409: self = .conflict(body)
        case 429: self = .tooManyRequests(body)
        default: self = .server(status: statusCode, body: body)
        }
    }

    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        case .timedOut:
            self = .timeout
        case .cancelled:
            self = .cancelled
        default:
            self = .transport(urlError.localizedDescription)
        }
    }

    /// Código de negocio que manda el backend, si lo hay.
    var serverCode: String? {
        switch self {
        case .unauthorized(let body), .forbidden(let body), .notFound(let body),
             .conflict(let body), .tooManyRequests(let body):
            return body?.code
        case .server(_, let body):
            return body?.code
        default:
            return nil
        }
    }

    /// El servidor rechazó las credenciales (no es un problema de red).
    var isAuthFailure: Bool {
        switch self {
        case .unauthorized, .sessionExpired: return true
        case .forbidden(let body): return body?.code == "INVALID_REFRESH_TOKEN"
        default: return false
        }
    }

    var isCancellation: Bool { self == .cancelled }
}

nonisolated extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .offline:
            return "Sin conexión. Revisa tu internet e inténtalo de nuevo."
        case .timeout:
            return "El servidor tardó demasiado en responder."
        case .sessionExpired:
            return "Tu sesión expiró. Vuelve a verificar tu número."
        case .cancelled:
            return nil
        case .unauthorized(let body), .forbidden(let body), .notFound(let body),
             .conflict(let body), .tooManyRequests(let body):
            return body?.message ?? "No se pudo completar la solicitud."
        case .server(_, let body):
            return body?.message ?? "Algo salió mal. Inténtalo más tarde."
        case .invalidURL, .invalidResponse, .decoding:
            return "Recibimos una respuesta inesperada del servidor."
        case .transport(let message):
            return message
        }
    }
}

extension Error {
    /// Mensaje listo para mostrar al usuario. `nil` si el error es una cancelación.
    var userMessage: String? {
        if self is CancellationError { return nil }
        if let apiError = self as? APIError {
            return apiError.errorDescription
        }
        return (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
