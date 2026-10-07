//
//  PanicViewModel.swift
//  SecurityIslas
//
//  Pánico (RF-40 a RF-45): mantener 3 s → cuenta regresiva cancelable →
//  alerta con ubicación → seguimiento del estado → acceso al 911.
//  A quién avisa depende de la geocerca del fraccionamiento (RF-42).
//

import Foundation
import Observation

@Observable
final class PanicViewModel {
    nonisolated enum Stage: Equatable {
        case hold
        case countdown(Int)
        case sending
        case active
        case failed(String)
    }

    static let countdownSeconds = 5

    private(set) var stage: Stage
    private(set) var alert: PanicAlert?
    private(set) var coordinate: Coordinate?
    private(set) var insidePerimeter = true
    private(set) var isClosing = false
    var errorMessage: String?
    private(set) var didFinish = false

    let residenceName: String
    private let repository: PanicRepository
    private let location: LocationService
    private let gate: GateConfiguration
    private var countdownTask: Task<Void, Never>?
    private var trackingTask: Task<Void, Never>?

    init(
        entry: PanicEntry,
        repository: PanicRepository,
        location: LocationService,
        gate: GateConfiguration,
        residenceName: String
    ) {
        self.repository = repository
        self.location = location
        self.gate = gate
        self.residenceName = residenceName
        self.stage = entry == .hold ? .hold : .countdown(Self.countdownSeconds)
    }

    /// Texto previo: a quién va la alerta según dónde estás.
    var recipientsDescription: String {
        insidePerimeter
            ? "Estás dentro de \(residenceName): la alerta va a los guardias en turno."
            : "Estás fuera de \(residenceName): la alerta va a tus contactos de emergencia."
    }

    func prepare() async {
        if let coordinate = try? await location.currentCoordinate() {
            self.coordinate = coordinate
            insidePerimeter = coordinate.distance(to: gate.perimeterCenter) <= gate.perimeterRadius
        }
        if case .countdown = stage { startCountdown() }
    }

    func startCountdown() {
        countdownTask?.cancel()
        stage = .countdown(Self.countdownSeconds)
        countdownTask = Task { [weak self] in
            for remaining in stride(from: PanicViewModel.countdownSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if remaining == 0 {
                    await self?.send()
                } else {
                    self?.stage = .countdown(remaining)
                }
            }
        }
    }

    func cancel() {
        countdownTask?.cancel()
        trackingTask?.cancel()
        didFinish = true
    }

    func retry() async {
        await send()
    }

    private func send() async {
        stage = .sending
        do {
            let coordinate: Coordinate
            if let current = self.coordinate {
                coordinate = current
            } else {
                coordinate = try await location.currentCoordinate()
            }
            let alert = try await repository.trigger(at: coordinate)
            self.alert = alert
            insidePerimeter = alert.scope == .guards
            stage = .active
            startTracking()
        } catch {
            stage = .failed(error.userMessage ?? "No se pudo enviar la alerta. Llama al 911.")
        }
    }

    /// Consulta el estado y manda la ubicación mientras la alerta siga abierta.
    /// Supuesto: cada 3 s el estado y cada 10 s la ubicación (DECISIONES.md).
    /// Con la app en segundo plano hará falta CLBackgroundActivitySession.
    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, let alert = self.alert, alert.status != .closed else { return }
                if let updated = try? await self.repository.status(of: alert) {
                    self.alert = updated
                }
                tick += 1
                if tick % 3 == 0, let coordinate = try? await self.location.currentCoordinate() {
                    try? await self.repository.updateLocation(coordinate, for: alert)
                }
            }
        }
    }

    /// "Estoy bien, cerrar alerta" pide Face ID.
    func close() async {
        guard let alert else {
            cancel()
            return
        }
        isClosing = true
        defer { isClosing = false }
        do {
            self.alert = try await repository.close(alert)
            trackingTask?.cancel()
            didFinish = true
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}
