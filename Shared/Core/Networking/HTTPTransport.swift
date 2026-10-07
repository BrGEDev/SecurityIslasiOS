//
//  HTTPTransport.swift
//  SecurityIslas
//
//  Capa más baja de la red. El APIClient no sabe si habla con URLSession
//  o con el servidor mock: solo recibe (Data, HTTPURLResponse).
//

import Foundation

nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, http)
    }
}
