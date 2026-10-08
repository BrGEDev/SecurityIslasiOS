//
//  WidgetSnapshot.swift
//  SecurityIslas (app, widgets y reloj)
//
//  Lo que ven los widgets sin hacer red ni tocar la sesión: la app escribe una
//  foto del estado en el App Group cada vez que carga Inicio y pide recargar
//  los widgets. Los botones de los widgets abren la app con un enlace
//  (`AppLink`) o, para Autorizar / Rechazar, corren un intent en el proceso de
//  la app (`VisitDecisionIntent`).
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated enum AppGroup {
    static let identifier = "group.app.security.islasgower"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Enlaces internos `islassecurity://…` que usan widgets, controles y
/// complicaciones.
nonisolated enum AppLink: String, Sendable, CaseIterable {
    /// Abrir pluma o solicitar paso (pide Face ID en la app).
    case gate
    /// Cuenta regresiva cancelable del pánico (RF-41).
    case panic
    case qr
    case visits

    static let scheme = "islassecurity"

    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let link = AppLink(rawValue: host) else { return nil }
        self = link
    }
}

nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    nonisolated struct PendingVisit: Codable, Sendable, Equatable {
        let id: String
        let name: String
        let initials: String
        let kind: AccessKind
        let arrivedAt: Date?
        let respondBy: Date?
        let heldByAdministration: Bool
    }

    nonisolated enum GateState: String, Codable, Sendable {
        /// Dentro de la geocerca en carril exclusivo.
        case open
        /// Dentro de la geocerca en carril compartido.
        case requestPass
        case far
        case unavailable
    }

    var fraccionamiento: String
    var pending: [PendingVisit]
    var gate: GateState
    /// Metros a la entrada más cercana.
    var distance: Int?
    var canAuthorizeVisits: Bool
    var canUseGate: Bool
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        fraccionamiento: AppInfo.name,
        pending: [],
        gate: .unavailable,
        distance: nil,
        canAuthorizeVisits: false,
        canUseGate: false,
        updatedAt: .distantPast
    )

    static let preview = WidgetSnapshot(
        fraccionamiento: "Bosques Sanctorum",
        pending: [
            PendingVisit(id: "vis-juan", name: "Juan Pérez", initials: "JP", kind: .visit,
                         arrivedAt: .now.addingTimeInterval(-20), respondBy: .now.addingTimeInterval(40),
                         heldByAdministration: false),
        ],
        gate: .open,
        distance: 80,
        canAuthorizeVisits: true,
        canUseGate: true,
        updatedAt: .now
    )

    var distanceText: String? {
        guard let distance else { return nil }
        if distance >= 1_000 {
            return "\((Double(distance) / 1_000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "es_MX")))) km"
        }
        return "\(distance) m"
    }
}

nonisolated enum WidgetSnapshotStore {
    private static let key = "widget.snapshot.v1"

    static func load() -> WidgetSnapshot {
        guard let data = AppGroup.defaults.data(forKey: key),
              let snapshot = try? JSONCoding.decoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    /// Solo recarga los widgets si cambió algo.
    static func save(_ snapshot: WidgetSnapshot) {
        var comparable = load()
        comparable.updatedAt = snapshot.updatedAt
        guard comparable != snapshot, let data = try? JSONCoding.encoder().encode(snapshot) else { return }
        AppGroup.defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Al cerrar sesión no deben quedar datos de la casa en la pantalla de inicio.
    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
