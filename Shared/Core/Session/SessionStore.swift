//
//  SessionStore.swift
//  SecurityIslas
//
//  Máquina de estados de la sesión. Decide qué raíz se muestra:
//
//  launching ─► signedOut ─(registro)─► pendingApproval ─► needsSetup ─► active
//                    ▲                                         ▲
//                    └──── sesión expirada / cerrar sesión ────┘
//
//  Reglas (sección 3): al volver a abrir la app no se pide login; un
//  residente pendiente no abre ni autoriza nada; quien ya tiene cuenta entra
//  sin aprobación (permisos → Face ID → Inicio).
//

import Foundation
import Observation

nonisolated enum SessionState: Equatable {
    case launching
    case signedOut
    case pendingApproval(UserProfile)
    /// Alta aprobada: faltan permisos y la llave del dispositivo (pantallas 7 y 8).
    case needsSetup(UserProfile, returningUser: Bool)
    case active(UserProfile)
}

@Observable
final class SessionStore {
    private(set) var state: SessionState = .launching
    /// Mensaje para la pantalla de bienvenida (ej. "Tu sesión expiró").
    var notice: String?

    private let auth: AuthRepository
    private let tokenStore: any TokenStore
    private let keys: DeviceKeyManager
    private let biometrics: BiometricAuthenticator
    private let keychain: KeychainStore
    private let events: SessionEventBus
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored var onSignOut: (() -> Void)?

    private let profileKey = "session.profile"
    private let setupKeyPrefix = "session.setupCompleted."

    init(
        auth: AuthRepository,
        tokenStore: any TokenStore,
        keys: DeviceKeyManager,
        biometrics: BiometricAuthenticator,
        keychain: KeychainStore,
        events: SessionEventBus
    ) {
        self.auth = auth
        self.tokenStore = tokenStore
        self.keys = keys
        self.biometrics = biometrics
        self.keychain = keychain
        self.events = events
    }

    var profile: UserProfile? {
        switch state {
        case .launching, .signedOut: nil
        case .pendingApproval(let profile), .needsSetup(let profile, _), .active(let profile): profile
        }
    }

    // MARK: - Arranque

    func bootstrap() async {
        listenToSessionEvents()

        guard await tokenStore.tokens() != nil else {
            state = .signedOut
            return
        }

        // Entra directo con el perfil guardado y lo actualiza en segundo plano.
        if let cached = keychain.value(UserProfile.self, for: profileKey) {
            route(cached, returningUser: true)
        }

        do {
            let profile = try await auth.me()
            route(profile, returningUser: true)
        } catch let error as APIError where error.isAuthFailure {
            await signOutLocally(notice: APIError.sessionExpired.errorDescription)
        } catch {
            // Sin red: se queda con el perfil guardado (si lo hay).
            if profile == nil { state = .signedOut }
        }
    }

    // MARK: - Transiciones

    /// Después de verificar el SMS (cuenta existente) o de enviar el alta.
    func didAuthenticate(_ profile: UserProfile, returningUser: Bool) {
        route(profile, returningUser: returningUser)
    }

    /// Consulta el estado del alta (pantalla 6).
    func refreshProfile() async throws {
        let profile = try await auth.me()
        let returning: Bool
        if case .needsSetup(_, let flag) = state { returning = flag } else { returning = false }
        route(profile, returningUser: returning)
    }

    /// Permisos y Face ID listos: entra a Inicio.
    func completeSetup() {
        guard let profile else { return }
        UserDefaults.standard.set(true, forKey: setupKeyPrefix + profile.id)
        state = .active(profile)
    }

    func update(_ profile: UserProfile) {
        route(profile, returningUser: true)
    }

    func signOut() async {
        try? await auth.logout()
        await signOutLocally(notice: nil)
    }

    // MARK: - Privado

    private func route(_ profile: UserProfile, returningUser: Bool) {
        try? keychain.setValue(profile, for: profileKey)

        switch profile.approvalStatus {
        case .unregistered:
            // Aún no envía su alta: el flujo de registro sigue en primer plano.
            state = .signedOut
        case .pending, .rejected:
            state = .pendingApproval(profile)
        case .approved:
            let setupDone = UserDefaults.standard.bool(forKey: setupKeyPrefix + profile.id)
            if setupDone && keys.hasKey {
                state = .active(profile)
            } else {
                state = .needsSetup(profile, returningUser: returningUser)
            }
        }
    }

    private func signOutLocally(notice: String?) async {
        if let profile {
            UserDefaults.standard.removeObject(forKey: setupKeyPrefix + profile.id)
        }
        await tokenStore.clear()
        keys.deleteKey()
        biometrics.invalidate()
        keychain.delete(profileKey)
        onSignOut?()
        self.notice = notice
        state = .signedOut
    }

    private func listenToSessionEvents() {
        guard eventsTask == nil else { return }
        let stream = events.events
        eventsTask = Task { [weak self] in
            for await event in stream {
                switch event {
                case .expired:
                    await self?.signOutLocally(notice: APIError.sessionExpired.errorDescription)
                }
            }
        }
    }
}
