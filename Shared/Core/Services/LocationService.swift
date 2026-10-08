//
//  LocationService.swift
//  SecurityIslas
//
//  Permisos de ubicación (pantallas 7 y 35) y la posición para validar la
//  geocerca de la entrada. Con el backend mock la posición es simulada
//  (Cuenta > Simulación) para poder probar los tres estados del botón.
//
//  • Geocercas con `CLMonitor`: la de la entrada (150 m alrededor de cada
//    carril) y el perímetro del fraccionamiento. El sistema avisa al entrar o
//    salir aunque la app esté suspendida (con permiso "Siempre").
//  • Pánico: `CLBackgroundActivitySession` + modo de fondo de ubicación para
//    seguir mandando la ubicación con la app en segundo plano.
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

    /// Último estado conocido de las geocercas (`nil` = sin dato todavía).
    private(set) var isNearEntrance: Bool?
    private(set) var isInsidePerimeter: Bool?

    let usesSimulation: Bool
    private let manager = CLLocationManager()
    private static let simulationKey = "mock.simulatedPosition"
    private static let alwaysRequestedKey = "location.alwaysRequested"
    private static let monitorName = "islas.geocercas"

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var monitoredGate: GateConfiguration?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var nearLanes: Set<String> = []

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

    // MARK: - Seguimiento continuo (pánico)

    /// Ubicación continua mientras dure la alerta. Abre una
    /// `CLBackgroundActivitySession` para que iOS siga entregando posiciones
    /// con la app en segundo plano (modo de fondo "location") y muestre el
    /// indicador azul de ubicación. Se cierra al terminar el `AsyncStream`.
    func trackCoordinates() -> AsyncStream<Coordinate> {
        if usesSimulation {
            let coordinate = simulatedCoordinate(for: simulatedPosition)
            return AsyncStream { continuation in
                let task = Task {
                    while !Task.isCancelled {
                        continuation.yield(coordinate)
                        try? await Task.sleep(for: .seconds(5))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        backgroundSession?.invalidate()
        backgroundSession = CLBackgroundActivitySession()
        return AsyncStream { continuation in
            let task = Task { [weak self] in
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                        guard let location = update.location, location.horizontalAccuracy <= 100 else { continue }
                        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                        self?.lastCoordinate = coordinate
                        continuation.yield(coordinate)
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in self?.endBackgroundTracking() }
            }
        }
    }

    private func endBackgroundTracking() {
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    // MARK: - Geocercas (CLMonitor)

    /// Registra la geocerca de la entrada (una por carril) y el perímetro.
    /// Se llama cada vez que llega la configuración en el resumen de Inicio;
    /// si no cambió, no hace nada.
    func monitorGeofences(_ gate: GateConfiguration) {
        if usesSimulation {
            evaluate(gate, at: simulatedCoordinate(for: simulatedPosition))
            return
        }
        #if os(watchOS)
        // watchOS no tiene CLMonitor: se calcula con la última posición.
        if let lastCoordinate { evaluate(gate, at: lastCoordinate) }
        #else
        guard authorization.isGranted, monitoredGate != gate else { return }
        monitoredGate = gate
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            let monitor = await CLMonitor(Self.monitorName)
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
            for lane in gate.lanes {
                let condition = CLMonitor.CircularGeographicCondition(
                    center: lane.location.clCoordinate,
                    radius: gate.entranceRadius
                )
                await monitor.add(condition, identifier: "entrance.\(lane.id)", assuming: .unsatisfied)
            }
            let perimeter = CLMonitor.CircularGeographicCondition(
                center: gate.perimeterCenter.clCoordinate,
                radius: gate.perimeterRadius
            )
            await monitor.add(perimeter, identifier: "perimeter", assuming: .unsatisfied)

            do {
                for try await event in await monitor.events {
                    self?.apply(identifier: event.identifier, satisfied: event.state == .satisfied)
                }
            } catch {}
        }
        #endif
    }

    private func evaluate(_ gate: GateConfiguration, at coordinate: Coordinate) {
        isNearEntrance = gate.lanes.contains { coordinate.distance(to: $0.location) <= gate.entranceRadius }
        isInsidePerimeter = coordinate.distance(to: gate.perimeterCenter) <= gate.perimeterRadius
    }

    private func apply(identifier: String, satisfied: Bool) {
        if identifier == "perimeter" {
            isInsidePerimeter = satisfied
        } else if identifier.hasPrefix("entrance.") {
            if satisfied { nearLanes.insert(identifier) } else { nearLanes.remove(identifier) }
            isNearEntrance = !nearLanes.isEmpty
        }
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
