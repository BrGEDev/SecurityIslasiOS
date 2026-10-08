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

/// Cómo se abre el flujo de pánico.
nonisolated enum PanicEntry: Hashable, Identifiable {
    /// Desde widget o control: abre la pantalla de mantener presionado (24).
    case hold
    /// Ya se mantuvo presionado el botón de Inicio: cuenta regresiva (25).
    case countdown

    var id: Self { self }
}

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
    private var locationTask: Task<Void, Never>?

    /// Supuesto: estado cada 3 s y ubicación cada 10 s (DECISIONES.md).
    static let statusInterval: Duration = .seconds(3)
    static let locationInterval: TimeInterval = 10

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
        } else if let inside = location.isInsidePerimeter {
            // Sin posición precisa: usa el último estado de la geocerca (CLMonitor).
            insidePerimeter = inside
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
        stopTracking()
        didFinish = true
    }

    private func stopTracking() {
        trackingTask?.cancel()
        locationTask?.cancel()
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
    /// La ubicación sale de `trackCoordinates()`, que mantiene una
    /// `CLBackgroundActivitySession`: sigue enviándose con la app en segundo
    /// plano o con la pantalla bloqueada (requiere el permiso "Siempre" si la
    /// app deja de estar visible por mucho tiempo).
    private func startTracking() {
        stopTracking()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: PanicViewModel.statusInterval)
                guard let self, let alert = self.alert, alert.status != .closed else { return }
                if let updated = try? await self.repository.status(of: alert) {
                    self.alert = updated
                }
            }
        }
        let stream = location.trackCoordinates()
        locationTask = Task { [weak self] in
            var lastSent = Date.distantPast
            for await coordinate in stream {
                guard let self, let alert = self.alert, alert.status != .closed else { return }
                self.coordinate = coordinate
                guard Date.now.timeIntervalSince(lastSent) >= PanicViewModel.locationInterval else { continue }
                lastSent = .now
                try? await self.repository.updateLocation(coordinate, for: alert)
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
            stopTracking()
            didFinish = true
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}
