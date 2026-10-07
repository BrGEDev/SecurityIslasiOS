//
//  GateViewModel.swift
//  SecurityIslas
//
//  Botón principal según dónde estás (pantalla 10, decisión I-01):
//  • Dentro de la geocerca, carril exclusivo  → "Abrir pluma" (abre directo).
//  • Dentro de la geocerca, carril compartido → "Solicitar paso" (confirma el guardia).
//  • Fuera de la geocerca → "Lejos de la entrada" (autorizar visitas sigue funcionando).
//  La app muestra "Pluma abierta" solo cuando el backend confirma el pulso.
//

import Foundation
import Observation

nonisolated enum GateButtonState: Equatable {
    case locating
    case ready(Lane, distance: Int)
    case far(distance: Int)
    case locationOff
    case working(Lane)
    case opened(GateResult)
    case passRequested(GateResult)
    case failed(String)

    static func == (lhs: GateButtonState, rhs: GateButtonState) -> Bool {
        switch (lhs, rhs) {
        case (.locating, .locating), (.locationOff, .locationOff): true
        case let (.ready(a, d1), .ready(b, d2)): a == b && d1 == d2
        case let (.far(a), .far(b)): a == b
        case let (.working(a), .working(b)): a == b
        case let (.opened(a), .opened(b)), let (.passRequested(a), .passRequested(b)): a.at == b.at
        case let (.failed(a), .failed(b)): a == b
        default: false
        }
    }
}

@Observable
final class GateViewModel {
    private(set) var state: GateButtonState = .locating
    var configuration: GateConfiguration?

    private let repository: GateRepository
    private let location: LocationService
    private var lastCoordinate: Coordinate?
    private var resetTask: Task<Void, Never>?

    init(repository: GateRepository, location: LocationService) {
        self.repository = repository
        self.location = location
    }

    var isBusy: Bool {
        if case .working = state { return true }
        return false
    }

    func refreshPosition() async {
        guard let configuration, !isBusy else { return }
        if !location.usesSimulation, !location.authorization.isGranted {
            state = .locationOff
            return
        }
        do {
            let coordinate = try await location.currentCoordinate()
            lastCoordinate = coordinate
            state = Self.evaluate(coordinate, in: configuration)
        } catch {
            state = .locationOff
        }
    }

    /// Valida la geocerca en el teléfono; el backend la vuelve a validar.
    static func evaluate(_ coordinate: Coordinate, in configuration: GateConfiguration) -> GateButtonState {
        let nearest = configuration.lanes
            .map { (lane: $0, distance: coordinate.distance(to: $0.location)) }
            .min { $0.distance < $1.distance }
        guard let nearest else { return .far(distance: 0) }
        let meters = Int(nearest.distance.rounded())
        return nearest.distance <= configuration.entranceRadius
            ? .ready(nearest.lane, distance: meters)
            : .far(distance: meters)
    }

    func trigger() async {
        guard case .ready(let lane, _) = state, let coordinate = lastCoordinate else { return }
        resetTask?.cancel()
        state = .working(lane)
        do {
            let result = try await repository.open(lane: lane, from: coordinate)
            state = result.outcome == .opened ? .opened(result) : .passRequested(result)
        } catch BiometricError.canceled {
            state = .ready(lane, distance: Int(coordinate.distance(to: lane.location)))
            return
        } catch let error as APIError where error.serverCode == "OUTSIDE_GEOFENCE" {
            state = .failed(error.errorDescription ?? "Acércate a la entrada.")
        } catch let error as APIError where error.serverCode == "CONTROLLER_OFFLINE" {
            state = .failed("No se pudo abrir, pide apoyo en caseta.")
        } catch {
            state = .failed(error.userMessage ?? "No se pudo abrir, pide apoyo en caseta.")
        }
        scheduleReset()
    }

    private func scheduleReset() {
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await self?.refreshPosition()
        }
    }
}
