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
        #if os(iOS)
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
        #else
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            self = .canceled
        default:
            self = .failed
        }
        #endif
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

    #if os(iOS)
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
    #endif

    /// Regresa un contexto autenticado. Si hubo una autenticación hace menos de
    /// `reuseWindow` segundos, la reutiliza.
    ///
    /// En el Apple Watch no hay Face ID (RF-68): basta con que el reloj esté
    /// puesto y desbloqueado. Eso lo garantiza la llave, que solo se puede usar
    /// con el reloj desbloqueado (`DeviceKeyManager`), así que aquí no se pide nada.
    ///
    /// `biometryOnly`: la llave es `.biometryCurrentSet` y no acepta el código,
    /// así que se evalúa solo la biometría (sin botón "Ingresar código").
    func authenticate(reason: String, biometryOnly: Bool = false) async throws -> LAContext {
        #if os(watchOS)
        return LAContext()
        #else
        if let cachedContext, let authenticatedAt,
           Date.now.timeIntervalSince(authenticatedAt) < reuseWindow {
            return cachedContext
        }

        #if targetEnvironment(simulator)
        // Pruebas de UI en el simulador: no hay quien mire a Face ID.
        if UserDefaults.standard.bool(forKey: "uiTesting") {
            return LAContext()
        }
        #endif

        let policy: LAPolicy = biometryOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.touchIDAuthenticationAllowableReuseDuration = reuseWindow
        if biometryOnly {
            context.localizedFallbackTitle = ""
        }

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            #if targetEnvironment(simulator)
            // El simulador no tiene código y Face ID viene sin registrar
            // (Features › Face ID › Enrolled). Para poder desarrollar se deja
            // pasar sin biometría; en un iPhone real esto nunca ocurre.
            cachedContext = context
            authenticatedAt = .now
            return context
            #else
            throw BiometricError(error)
            #endif
        }

        try await evaluate(context, policy: policy, reason: reason)
        cachedContext = context
        authenticatedAt = .now
        return context
        #endif
    }

    func invalidate() {
        cachedContext?.invalidate()
        cachedContext = nil
        authenticatedAt = nil
    }

    #if os(iOS)
    private func evaluate(_ context: LAContext, policy: LAPolicy, reason: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(policy, localizedReason: reason) { @Sendable success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BiometricError(error))
                }
            }
        }
    }
    #endif
}
