//
//  API.swift
//  SecurityIslas
//
//  Catálogo de endpoints. Rutas y campos son SUPUESTOS mientras el backend
//  (NestJS) publica su OpenAPI; están listados en DECISIONES.md para
//  acordarlos. Cambiar una ruta aquí no afecta a ninguna vista.
//

import Foundation

// MARK: - DTOs de petición / respuesta que no son modelos de dominio

nonisolated struct OTPRequest: Codable, Sendable {
    let phone: String
}

nonisolated struct DeviceDescriptor: Codable, Sendable {
    let id: String
    let name: String
    let model: DeviceModel
}

nonisolated struct VerifyOTPRequest: Codable, Sendable {
    let phone: String
    let code: String
    let device: DeviceDescriptor
}

nonisolated struct TokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// Segundos de vida del access token.
    let expiresIn: Int

    func authTokens(now: Date = .now) -> AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

nonisolated struct VerifyOTPResponse: Codable, Sendable {
    let tokens: TokenResponse
    let result: VerificationResult
}

nonisolated struct RefreshRequest: Codable, Sendable {
    let refreshToken: String
}

nonisolated struct InviteResolveRequest: Codable, Sendable {
    let code: String
}

nonisolated struct RegistrationRequest: Codable, Sendable {
    let fraccionamientoId: String
    let homeId: String
    let firstName: String
    let lastName: String
    let tenure: Tenure
    let inviteCode: String?
}

nonisolated struct DeviceKeyRequest: Codable, Sendable {
    let name: String
    let model: DeviceModel
    /// Llave pública P-256 en X9.63, base64.
    let publicKey: String
    /// Atestación de App Attest (pendiente, ver DECISIONES.md).
    let attestation: String?
    let hardwareBacked: Bool
}

nonisolated struct VisitDecisionRequest: Codable, Sendable {
    let decision: VisitDecision
}

// MARK: - Endpoints

enum API {
    enum Auth {
        static func requestOTP(_ phone: PhoneNumber) throws -> Endpoint<OTPChallenge> {
            try Endpoint(.post, "auth/otp", body: OTPRequest(phone: phone.e164), requiresAuth: false)
        }

        static func verifyOTP(_ body: VerifyOTPRequest) throws -> Endpoint<VerifyOTPResponse> {
            try Endpoint(.post, "auth/otp/verify", body: body, requiresAuth: false)
        }

        nonisolated static func refresh(_ refreshToken: String) throws -> Endpoint<TokenResponse> {
            try Endpoint(.post, "auth/refresh", body: RefreshRequest(refreshToken: refreshToken), requiresAuth: false)
        }

        static func logout() -> Endpoint<EmptyResponse> {
            Endpoint(.post, "auth/logout")
        }

        static func me() -> Endpoint<UserProfile> {
            Endpoint(.get, "me")
        }
    }

    enum Registration {
        static func fraccionamientos(query: String) -> Endpoint<[Fraccionamiento]> {
            Endpoint(.get, "fraccionamientos", query: [URLQueryItem(name: "q", value: query)])
        }

        static func homes(fraccionamientoId: String) -> Endpoint<[HomeOption]> {
            Endpoint(.get, "fraccionamientos/\(fraccionamientoId)/homes")
        }

        static func resolveInvite(_ code: String) throws -> Endpoint<Fraccionamiento> {
            try Endpoint(.post, "invites/resolve", body: InviteResolveRequest(code: code))
        }

        static func submit(_ body: RegistrationRequest) throws -> Endpoint<UserProfile> {
            try Endpoint(.post, "registrations", body: body)
        }
    }

    enum Devices {
        static func list() -> Endpoint<DeviceList> {
            Endpoint(.get, "devices")
        }

        static func remove(_ id: String) -> Endpoint<EmptyResponse> {
            Endpoint(.delete, "devices/\(id)")
        }

        static func registerKey(_ body: DeviceKeyRequest) throws -> Endpoint<Device> {
            try Endpoint(.post, "devices/key", body: body)
        }
    }

    enum Residence {
        static func home() -> Endpoint<HomeSummary> {
            Endpoint(.get, "home")
        }

        static func history(category: HistoryCategory?) -> Endpoint<[HistoryEvent]> {
            let query = category.map { [URLQueryItem(name: "category", value: $0.rawValue)] } ?? []
            return Endpoint(.get, "history", query: query)
        }

        static func packages() -> Endpoint<[Package]> {
            Endpoint(.get, "packages")
        }

        static func packagePolicy() -> Endpoint<PackagePolicySetting> {
            Endpoint(.get, "package-policy")
        }

        static func updatePackagePolicy(_ policy: PackagePolicy) throws -> Endpoint<PackagePolicySetting> {
            try Endpoint(.put, "package-policy", body: PackagePolicySetting(policy: policy))
        }
    }

    enum Visits {
        static func today() -> Endpoint<[Visit]> {
            Endpoint(.get, "visits", query: [URLQueryItem(name: "scope", value: "today")])
        }

        static func decide(_ id: String, decision: VisitDecision) throws -> Endpoint<Visit> {
            try Endpoint(.post, "visits/\(id)/decision", body: VisitDecisionRequest(decision: decision))
        }

        static func markSleepover(_ id: String) -> Endpoint<Visit> {
            Endpoint(.post, "visits/\(id)/sleepover")
        }

        static func invitations() -> Endpoint<[Invitation]> {
            Endpoint(.get, "invitations")
        }

        static func createInvitation(_ body: NewInvitationRequest) throws -> Endpoint<Invitation> {
            try Endpoint(.post, "invitations", body: body)
        }

        static func recurring() -> Endpoint<[RecurringAccess]> {
            Endpoint(.get, "recurring")
        }

        static func recurringDetail(_ id: String) -> Endpoint<RecurringAccess> {
            Endpoint(.get, "recurring/\(id)")
        }

        static func createRecurring(_ body: NewRecurringRequest) throws -> Endpoint<RecurringAccess> {
            try Endpoint(.post, "recurring", body: body)
        }

        static func revokeRecurring(_ id: String) -> Endpoint<EmptyResponse> {
            Endpoint(.delete, "recurring/\(id)")
        }
    }

    enum Gate {
        static func open(_ command: GateCommand) throws -> Endpoint<GateResult> {
            try Endpoint(.post, "gate/open", body: command)
        }

        static func qrSeed() -> Endpoint<QRSeed> {
            Endpoint(.get, "qr-seed")
        }
    }

    enum Panic {
        static func create(_ body: PanicRequest) throws -> Endpoint<PanicAlert> {
            try Endpoint(.post, "panic", body: body)
        }

        static func status(_ id: String) -> Endpoint<PanicAlert> {
            Endpoint(.get, "panic/\(id)")
        }

        static func updateLocation(_ id: String, _ body: PanicRequest) throws -> Endpoint<EmptyResponse> {
            try Endpoint(.post, "panic/\(id)/location", body: body)
        }

        static func close(_ id: String) -> Endpoint<PanicAlert> {
            Endpoint(.post, "panic/\(id)/close")
        }
    }

    enum Household {
        static func family() -> Endpoint<[FamilyMember]> {
            Endpoint(.get, "family")
        }

        static func inviteFamily(_ body: FamilyInviteRequest) throws -> Endpoint<FamilyMember> {
            try Endpoint(.post, "family", body: body)
        }

        static func removeFamily(_ id: String) -> Endpoint<EmptyResponse> {
            Endpoint(.delete, "family/\(id)")
        }

        static func contacts() -> Endpoint<[EmergencyContact]> {
            Endpoint(.get, "emergency-contacts")
        }

        static func addContact(_ body: NewEmergencyContactRequest) throws -> Endpoint<EmergencyContact> {
            try Endpoint(.post, "emergency-contacts", body: body)
        }

        static func removeContact(_ id: String) -> Endpoint<EmptyResponse> {
            Endpoint(.delete, "emergency-contacts/\(id)")
        }

        static func guests() -> Endpoint<[TemporaryGuest]> {
            Endpoint(.get, "guests")
        }

        static func createGuest(_ body: NewGuestRequest) throws -> Endpoint<TemporaryGuest> {
            try Endpoint(.post, "guests", body: body)
        }

        static func workPermit() -> Endpoint<WorkPermitEnvelope> {
            Endpoint(.get, "work-permit")
        }

        static func requestWorkPermit(_ body: WorkPermitRequest) throws -> Endpoint<WorkPermit> {
            try Endpoint(.post, "work-permit", body: body)
        }

        static func updateWorkPermit(_ body: WorkPermitSettings) throws -> Endpoint<WorkPermit> {
            try Endpoint(.patch, "work-permit", body: body)
        }
    }
}
