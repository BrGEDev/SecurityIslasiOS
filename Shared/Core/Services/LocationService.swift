//
//  LocationService.swift
//  SecurityIslas
//
//  Permisos de ubicación (pantallas 7 y 35) y la posición para validar la
//  geocerca de la entrada. Con el backend mock la posición es simulada
//  (Cuenta > Simulación) para poder probar los tres estados del botón.
//

import CoreLocation
import Foundation
import Observation

nonisolated enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case whenInUse
    case always

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorizedAlways: self = .always
        case .authorizedWhenInUse: self = .whenInUse
        default: self = .denied
        }
    }

    var isGranted: Bool { self == .whenInUse || self == .always }
}

/// Posiciones de prueba relativas a las casetas de `MockSeed.gate`.
nonisolated enum SimulatedPosition: String, CaseIterable, Identifiable, Sendable {
    case nearResidentsLane
    case nearSharedLane
    case far

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearResidentsLane: "A 80 m · carril de residentes"
        case .nearSharedLane: "A 80 m · carril compartido"
        case .far: "Lejos (2.3 km)"
        }
    }
}

nonisolated enum LocationError: Error, LocalizedError, Sendable {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "Activa la ubicación para abrir la pluma cerca de la entrada."
        case .unavailable: "No pudimos obtener tu ubicación. Inténtalo de nuevo."
        }
    }
}

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: LocationAuthorization
    private(set) var lastCoordinate: Coordinate?

    private(set) var simulatedPosition: SimulatedPosition

    let usesSimulation: Bool
    private let manager = CLLocationManager()
    private static let simulationKey = "mock.simulatedPosition"
    private static let alwaysRequestedKey = "location.alwaysRequested"

    init(usesSimulation: Bool) {
        self.usesSimulation = usesSimulation
        self.authorization = LocationAuthorization(CLLocationManager().authorizationStatus)
        let stored = UserDefaults.standard.string(forKey: Self.simulationKey)
        self.simulatedPosition = stored.flatMap(SimulatedPosition.init(rawValue:)) ?? .nearResidentsLane
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func setSimulatedPosition(_ position: SimulatedPosition) {
        simulatedPosition = position
        UserDefaults.standard.set(position.rawValue, forKey: Self.simulationKey)
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// iOS solo muestra una vez el aviso para pasar a "Siempre". Si el usuario
    /// elige "Mantener solo al usar", las siguientes llamadas no hacen nada:
    /// a partir de ahí el cambio solo se hace en Ajustes.
    var canPromptForAlways: Bool {
        switch authorization {
        case .notDetermined: true
        case .whenInUse: !UserDefaults.standard.bool(forKey: Self.alwaysRequestedKey)
        case .always, .denied: false
        }
    }

    /// El permiso "Siempre" se pide al configurar el pánico (pantalla 35).
    /// Regresa `false` si iOS ya no mostrará el aviso y hay que ir a Ajustes.
    @discardableResult
    func requestAlways() -> Bool {
        guard canPromptForAlways else { return false }
        UserDefaults.standard.set(true, forKey: Self.alwaysRequestedKey)
        manager.requestAlwaysAuthorization()
        return true
    }

    /// Vuelve a leer el permiso (por ejemplo, al regresar de Ajustes).
    func refreshAuthorization() {
        authorization = LocationAuthorization(manager.authorizationStatus)
    }

    /// Ubicación de alta precisión para la orden de apertura o el pánico.
    func currentCoordinate() async throws -> Coordinate {
        if usesSimulation {
            let coordinate = simulatedCoordinate(for: simulatedPosition)
            lastCoordinate = coordinate
            return coordinate
        }
        guard authorization.isGranted else { throw LocationError.denied }

        for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
            if let location = update.location, location.horizontalAccuracy <= 50 {
                let coordinate = Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                lastCoordinate = coordinate
                return coordinate
            }
        }
        throw LocationError.unavailable
    }

    private func simulatedCoordinate(for position: SimulatedPosition) -> Coordinate {
        let lanes = MockSeed.gate.lanes
        switch position {
        case .nearResidentsLane:
            return lanes[0].location.offset(northMeters: -80)
        case .nearSharedLane:
            return lanes[1].location.offset(northMeters: 80)
        case .far:
            return lanes[0].location.offset(northMeters: -2_300)
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = LocationAuthorization(manager.authorizationStatus)
        Task { @MainActor [weak self] in
            self?.authorization = status
        }
    }
}
