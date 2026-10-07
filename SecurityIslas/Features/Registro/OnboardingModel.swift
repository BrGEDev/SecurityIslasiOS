//
//  OnboardingModel.swift
//  SecurityIslas
//
//  Estado y navegación del registro (sección A, pantallas 1 a 6):
//  • Nuevo:       1 → 2 → 3 → 4 → 5 → 6
//  • Existente:   1 → 2 → 3 → 3a (→ 3b si hay 3 dispositivos) → 7 → 8 → Inicio
//  • Precargado:  1 → 2 → 3 → 5 (confirmar datos) → 7
//  • Invitación:  1 → 2 → 3 → 5
//

import Foundation
import Observation

nonisolated enum OnboardingRoute: Hashable {
    case phone
    case code
    case existingAccount
    case deviceLimit
    case fraccionamiento
    case home
}

@Observable
final class OnboardingModel {
    var path: [OnboardingRoute] = []

    // Pantalla 2
    var country: CountryCode = .mexico
    var phoneDigits = ""

    // Pantalla 3
    var code = ""
    private(set) var resendAvailableAt: Date?

    // Resultado de la verificación
    private(set) var verification: VerificationResult?

    // Pantalla 3b
    var deviceToRemove: Device?

    // Pantalla 4
    var searchText = ""
    private(set) var fraccionamientos: [Fraccionamiento] = []
    var selectedFraccionamiento: Fraccionamiento?
    var inviteCode: String?

    // Pantalla 5
    var firstName = ""
    var lastName = ""
    private(set) var homes: [HomeOption] = []
    var selectedHome: HomeOption?
    var tenure: Tenure = .owner

    var isLoading = false
    var errorMessage: String?

    private let auth: AuthRepository
    private let registration: RegistrationRepository
    private let devices: DeviceRepository
    private let session: SessionStore

    init(auth: AuthRepository, registration: RegistrationRepository, devices: DeviceRepository, session: SessionStore) {
        self.auth = auth
        self.registration = registration
        self.devices = devices
        self.session = session
    }

    var phone: PhoneNumber { PhoneNumber(country: country, digits: phoneDigits) }

    var canSendCode: Bool { phone.isComplete && !isLoading }

    var isPreloaded: Bool { verification?.accountState == .preloaded }

    var canSubmitRegistration: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedHome != nil
            && selectedFraccionamiento != nil
            && !isLoading
    }

    // MARK: - Pantalla 2: celular

    func updatePhone(_ input: String) {
        let digits = String(input.filter(\.isNumber).prefix(10))
        if digits != phoneDigits { phoneDigits = digits }
    }

    func sendCode() async {
        guard phone.isComplete else {
            errorMessage = "Escribe los 10 dígitos de tu celular."
            return
        }
        await perform {
            let challenge = try await auth.requestCode(for: phone)
            resendAvailableAt = .now.addingTimeInterval(TimeInterval(challenge.resendIn))
            code = ""
            if path.last != .code { path.append(.code) }
        }
    }

    // MARK: - Pantalla 3: código

    func resendCode() async {
        await perform {
            let challenge = try await auth.requestCode(for: phone)
            resendAvailableAt = .now.addingTimeInterval(TimeInterval(challenge.resendIn))
        }
    }

    func verifyCode() async {
        guard code.count == 6, !isLoading else { return }
        await perform {
            let result = try await auth.verifyCode(code, for: phone)
            verification = result
            switch result.accountState {
            case .existing:
                path.append(.existingAccount)
            case .preloaded:
                if let preload = result.preload {
                    firstName = preload.firstName
                    lastName = preload.lastName
                    selectedFraccionamiento = preload.fraccionamiento
                    selectedHome = preload.home
                    tenure = preload.tenure
                    homes = try await registration.homes(in: preload.fraccionamiento)
                }
                path.append(.home)
            case .newResident:
                if let inviteCode {
                    let fraccionamiento = try await registration.resolveInvite(inviteCode)
                    try await select(fraccionamiento)
                    path.append(.home)
                } else {
                    path.append(.fraccionamiento)
                }
            }
        }
        if errorMessage != nil { code = "" }
    }

    // MARK: - Pantallas 3a y 3b

    func continueAsExistingUser() {
        guard let verification else { return }
        if verification.reachedDeviceLimit {
            deviceToRemove = verification.devices.min { $0.lastUsedAt < $1.lastUsedAt }
            path.append(.deviceLimit)
        } else {
            session.didAuthenticate(verification.profile, returningUser: true)
        }
    }

    func removeDeviceAndContinue() async {
        guard let verification, let deviceToRemove else { return }
        await perform {
            // Este iPhone aún no tiene llave: la baja va con el token recién emitido.
            try await devices.remove(deviceToRemove, signed: false)
            session.didAuthenticate(verification.profile, returningUser: true)
        }
    }

    /// "No soy yo": regresa al número.
    func restart() {
        verification = nil
        code = ""
        path = [.phone]
    }

    // MARK: - Pantalla 4: fraccionamiento

    func search() async {
        do {
            try await Task.sleep(for: .milliseconds(250))
            fraccionamientos = try await registration.searchFraccionamientos(searchText)
            if let selected = selectedFraccionamiento, !fraccionamientos.contains(selected) {
                selectedFraccionamiento = nil
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }

    func continueWithFraccionamiento() async {
        guard let selectedFraccionamiento else { return }
        await perform {
            try await select(selectedFraccionamiento)
            path.append(.home)
        }
    }

    func applyInviteCode(_ code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Antes de verificar el número solo se guarda; se resuelve al validar el SMS.
        guard verification != nil else {
            inviteCode = trimmed
            return
        }
        await perform {
            let fraccionamiento = try await registration.resolveInvite(trimmed)
            inviteCode = trimmed
            try await select(fraccionamiento)
            path.append(.home)
        }
    }

    // MARK: - Pantalla 5: vivienda

    func submitRegistration() async {
        guard let selectedFraccionamiento, let selectedHome else { return }
        await perform {
            let request = RegistrationRequest(
                fraccionamientoId: selectedFraccionamiento.id,
                homeId: selectedHome.id,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                tenure: tenure,
                inviteCode: inviteCode
            )
            let profile = try await registration.submit(request)
            session.didAuthenticate(profile, returningUser: false)
        }
    }

    // MARK: - Privado

    private func select(_ fraccionamiento: Fraccionamiento) async throws {
        if selectedFraccionamiento != fraccionamiento || homes.isEmpty {
            homes = try await registration.homes(in: fraccionamiento)
            selectedHome = nil
        }
        selectedFraccionamiento = fraccionamiento
    }

    private func perform(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
