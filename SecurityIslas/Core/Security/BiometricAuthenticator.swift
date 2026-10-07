//
//  BiometricAuthenticator.swift
//  SecurityIslas
//
//  Face ID / Touch ID con el código del iPhone como respaldo (RF-67).
//  Reutiliza la autenticación unos segundos para no pedir Face ID dos veces
//  seguidas (flujo "Acción sensible", sección 5 del brief).
//

import Foundation
import LocalAuthentication

nonisolated enum BiometricError: Error, LocalizedError, Sendable, Equatable {
    case canceled
    case notAvailable
    case lockout
    case failed

    init(_ error: (any Error)?) {
        guard let code = (error as? LAError)?.code else {
            self = .failed
            return
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            self = .canceled
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
            self = .notAvailable
        case .biometryLockout:
            self = .lockout
        default:
            self = .failed
        }
    }

    var errorDescription: String? {
        switch self {
        case .canceled: nil
        case .notAvailable: "Activa Face ID o un código en tu iPhone para continuar."
        case .lockout: "Face ID está bloqueado. Desbloquea tu iPhone con el código."
        case .failed: "No pudimos verificar que eres tú."
        }
    }
}

final class BiometricAuthenticator {
    private var cachedContext: LAContext?
    private var authenticatedAt: Date?
    private let reuseWindow: TimeInterval

    init(reuseWindow: TimeInterval = 10) {
        self.reuseWindow = reuseWindow
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometryName: String {
        switch biometryType {
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Face ID"
        }
    }

    var biometryIcon: String {
        biometryType == .touchID ? "touchid" : "faceid"
    }

    /// Regresa un contexto autenticado. Si hubo una autenticación hace menos de
    /// `reuseWindow` segundos, la reutiliza.
    func authenticate(reason: String) async throws -> LAContext {
        if let cachedContext, let authenticatedAt,
           Date.now.timeIntervalSince(authenticatedAt) < reuseWindow {
            return cachedContext
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.touchIDAuthenticationAllowableReuseDuration = reuseWindow

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw BiometricError(error)
        }

        try await evaluate(context, reason: reason)
        cachedContext = context
        authenticatedAt = .now
        return context
    }

    func invalidate() {
        cachedContext?.invalidate()
        cachedContext = nil
        authenticatedAt = nil
    }

    private func evaluate(_ context: LAContext, reason: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { @Sendable success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BiometricError(error))
                }
            }
        }
    }
}
