//
//  OfflineCache.swift
//  SecurityIslas
//
//  Caché con SwiftData de lo que el residente consulta (visitas de hoy,
//  invitaciones, recurrentes, historial y el resumen de Inicio) para abrir la
//  app sin red. Guarda la respuesta del backend tal cual (JSON) por clave:
//  así no hay que mantener un esquema paralelo mientras el contrato OpenAPI
//  siga cambiando.
//
//  Solo se usa al fallar la red; las acciones (autorizar, abrir, firmar)
//  nunca salen de la caché. Se borra al cerrar sesión (RNF-06).
//

import Foundation
import Observation
import SwiftData

@Model
final class CachedResponse {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String, payload: Data, updatedAt: Date) {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Observable
final class OfflineCache {
    /// Fecha de los datos guardados que se están mostrando porque no hubo red.
    /// `nil` cuando lo que se ve viene del backend.
    private(set) var showingDataFrom: Date?

    @ObservationIgnored private let context: ModelContext?

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try? ModelContainer(for: CachedResponse.self, configurations: configuration)
        context = container.map { ModelContext($0) }
    }

    /// Pide al backend y guarda la respuesta. Si no hay red, regresa lo
    /// último guardado para esa clave (o vuelve a lanzar el error).
    func fetch<T: Codable & Sendable>(_ key: String, _ load: () async throws -> T) async throws -> T {
        do {
            let value = try await load()
            store(value, for: key)
            showingDataFrom = nil
            return value
        } catch let error as APIError where error.isConnectivity {
            guard let (value, date) = cached(T.self, for: key) else { throw error }
            showingDataFrom = date
            return value
        }
    }

    func clear() {
        try? context?.delete(model: CachedResponse.self)
        try? context?.save()
        showingDataFrom = nil
    }

    private func store<T: Encodable>(_ value: T, for key: String) {
        guard let context, let data = try? JSONCoding.encoder().encode(value) else { return }
        let descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = data
            existing.updatedAt = .now
        } else {
            context.insert(CachedResponse(key: key, payload: data, updatedAt: .now))
        }
        try? context.save()
    }

    private func cached<T: Decodable>(_ type: T.Type, for key: String) -> (T, Date)? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        guard let entry = try? context.fetch(descriptor).first,
              let value = try? JSONCoding.decoder().decode(T.self, from: entry.payload) else { return nil }
        return (value, entry.updatedAt)
    }
}

nonisolated extension APIError {
    /// Falla de red (no del backend): se puede mostrar lo guardado.
    var isConnectivity: Bool {
        switch self {
        case .offline, .timeout, .transport: true
        default: false
        }
    }
}
