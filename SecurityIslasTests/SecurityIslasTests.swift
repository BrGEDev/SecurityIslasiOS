//
//  SecurityIslasTests.swift
//  SecurityIslasTests
//
//  Pruebas con Swift Testing de la capa que no se ve: interceptor de token,
//  firma, Mi QR (TOTP), geocerca/carril, roles, push y el backend de prueba.
//

import CryptoKit
import Foundation
import LocalAuthentication
import Testing
@testable import SecurityIslas

// MARK: - Dobles de prueba

actor MemoryTokenStore: TokenStore {
    private var stored: AuthTokens?

    init(_ tokens: AuthTokens?) {
        stored = tokens
    }

    func tokens() -> AuthTokens? { stored }
    func save(_ tokens: AuthTokens) { stored = tokens }
    func clear() { stored = nil }
}

/// Cuenta cuántas veces se renovó el token y regresa uno nuevo.
actor RefreshCounter {
    private(set) var count = 0
    var fails = false

    func setFails(_ value: Bool) { fails = value }

    func refresh(_ refreshToken: String) async throws -> AuthTokens {
        count += 1
        try await Task.sleep(for: .milliseconds(50))
        if fails { throw APIError.unauthorized(nil) }
        return AuthTokens(accessToken: "access-\(count)", refreshToken: "refresh-\(count)", expiresAt: .now.addingTimeInterval(3_600))
    }
}

/// Responde con los códigos de estado en orden y guarda lo que recibió.
actor ScriptedTransport: HTTPTransport {
    private var statuses: [Int]
    private(set) var received: [URLRequest] = []

    init(_ statuses: [Int]) {
        self.statuses = statuses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        received.append(request)
        let status = statuses.isEmpty ? 200 : statuses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data("{}".utf8), response)
    }
}

private func expiredTokens() -> AuthTokens {
    AuthTokens(accessToken: "old", refreshToken: "refresh-0", expiresAt: .now.addingTimeInterval(-10))
}

private func validTokens() -> AuthTokens {
    AuthTokens(accessToken: "current", refreshToken: "refresh-0", expiresAt: .now.addingTimeInterval(3_600))
}

// MARK: - AuthInterceptor

@Suite("AuthInterceptor")
struct AuthInterceptorTests {
    @Test("Renueva antes de enviar si el token está por vencer")
    func proactiveRefresh() async throws {
        let store = MemoryTokenStore(expiredTokens())
        let counter = RefreshCounter()
        let interceptor = AuthInterceptor(tokenStore: store, events: SessionEventBus()) { try await counter.refresh($0) }

        let request = try await interceptor.adapt(URLRequest(url: URL(string: "https://x.test/me")!), context: RequestContext(requiresAuth: true))

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(await counter.count == 1)
        #expect(await store.tokens()?.accessToken == "access-1")
    }

    @Test("Renovaciones simultáneas se agrupan en una sola (single-flight)")
    func singleFlight() async throws {
        let store = MemoryTokenStore(expiredTokens())
        let counter = RefreshCounter()
        let interceptor = AuthInterceptor(tokenStore: store, events: SessionEventBus()) { try await counter.refresh($0) }
        let request = URLRequest(url: URL(string: "https://x.test/me")!)

        try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))
                        .value(forHTTPHeaderField: "Authorization")
                }
            }
            for try await header in group {
                #expect(header == "Bearer access-1")
            }
        }
        #expect(await counter.count == 1)
    }

    @Test("Un 401 renueva y el cliente reintenta una sola vez")
    func retryOnceAfter401() async throws {
        let store = MemoryTokenStore(validTokens())
        let counter = RefreshCounter()
        let interceptor = AuthInterceptor(tokenStore: store, events: SessionEventBus()) { try await counter.refresh($0) }
        let transport = ScriptedTransport([401, 200])
        let client = APIClient(config: .mock, transport: transport, interceptors: [interceptor])

        _ = try await client.send(Endpoint<EmptyResponse>(.get, "me"))

        let received = await transport.received
        #expect(received.count == 2)
        #expect(received.last?.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(await counter.count == 1)
    }

    @Test("Dos 401 seguidos no reintentan para siempre")
    func noInfiniteRetry() async throws {
        let store = MemoryTokenStore(validTokens())
        let counter = RefreshCounter()
        let interceptor = AuthInterceptor(tokenStore: store, events: SessionEventBus()) { try await counter.refresh($0) }
        let transport = ScriptedTransport([401, 401, 401])
        let client = APIClient(config: .mock, transport: transport, interceptors: [interceptor])

        await #expect(throws: APIError.self) {
            _ = try await client.send(Endpoint<EmptyResponse>(.get, "me"))
        }
        #expect(await transport.received.count == 2)
    }

    @Test("Si el refresh token ya no sirve, borra la sesión")
    func refreshRejectedClearsSession() async throws {
        let store = MemoryTokenStore(expiredTokens())
        let counter = RefreshCounter()
        await counter.setFails(true)
        let interceptor = AuthInterceptor(tokenStore: store, events: SessionEventBus()) { try await counter.refresh($0) }

        await #expect(throws: APIError.sessionExpired) {
            _ = try await interceptor.adapt(URLRequest(url: URL(string: "https://x.test/me")!), context: RequestContext(requiresAuth: true))
        }
        #expect(await store.tokens() == nil)
    }

    @Test("Las peticiones sin autenticación no llevan token")
    func noAuthHeaderWhenNotRequired() async throws {
        let interceptor = AuthInterceptor(tokenStore: MemoryTokenStore(nil), events: SessionEventBus()) { _ in
            Issue.record("No debe renovar")
            throw APIError.sessionExpired
        }
        let request = try await interceptor.adapt(URLRequest(url: URL(string: "https://x.test/auth/otp")!), context: RequestContext(requiresAuth: false))
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

// MARK: - Firma (RF-67)

@Suite("RequestSigner")
struct RequestSignerTests {
    @Test("El mensaje canónico es MÉTODO, ruta, timestamp, nonce y sha256 del cuerpo")
    func canonicalPayload() {
        let body = Data(#"{"laneId":"lane-1"}"#.utf8)
        let message = String(decoding: SignaturePayload.canonical(method: "POST", path: "gate/open", timestamp: "100", nonce: "abc", body: body), as: UTF8.self)
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        #expect(message == "POST\ngate/open\n100\nabc\n\(hash)")
    }

    /// En el simulador la llave es de software (no hay Secure Enclave) y no
    /// pide Face ID; en un iPhone el mismo camino exige la biometría.
    @Test("La firma se verifica con la llave pública registrada", .enabled(if: !DeviceKeyManager.usesSecureEnclave))
    func signatureVerifies() throws {
        let keychain = KeychainStore(service: "tests.\(UUID().uuidString)", accessGroup: nil)
        let keys = DeviceKeyManager(keychain: keychain)
        defer { keys.deleteKey() }
        let context = LAContext()
        let publicKey = try P256.Signing.PublicKey(x963Representation: keys.createKey(context: context))

        let body = Data(#"{"laneId":"lane-1"}"#.utf8)
        let message = SignaturePayload.canonical(method: "POST", path: "gate/open", timestamp: "100", nonce: "abc", body: body)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: keys.sign(message, context: context))
        #expect(publicKey.isValidSignature(signature, for: message))

        // Otro cuerpo con la misma firma no pasa (no se puede reutilizar).
        let tampered = SignaturePayload.canonical(method: "POST", path: "gate/open", timestamp: "100", nonce: "abc", body: Data("{}".utf8))
        #expect(!publicKey.isValidSignature(signature, for: tampered))
    }
}

// MARK: - Mi QR (TOTP)

@Suite("Mi QR")
struct ResidentQRTests {
    let secret = Data("12345678901234567890".utf8)

    @Test("El código es estable dentro del periodo y tiene 8 dígitos")
    func stableWithinPeriod() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let a = TOTP.code(secret: secret, date: start)
        let b = TOTP.code(secret: secret, date: start.addingTimeInterval(29))
        #expect(a == b)
        #expect(a.count == 8)
        #expect(a.allSatisfy { $0.isNumber })
    }

    @Test("Cambia cada 30 segundos")
    func changesEveryPeriod() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TOTP.code(secret: secret, date: start) != TOTP.code(secret: secret, date: start.addingTimeInterval(30)))
    }

    @Test("Segundos restantes del periodo")
    func secondsRemaining() {
        #expect(TOTP.secondsRemaining(date: Date(timeIntervalSince1970: 1_800_000_010)) == 20)
    }
}

// MARK: - Geocerca y carril (RF-23)

@Suite("Geocerca y carril")
struct GateRulesTests {
    let gate = MockSeed.gate

    @Test("Cerca del carril de residentes: abre directo")
    func residentsLane() {
        let state = GateViewModel.evaluate(gate.lanes[0].location.offset(northMeters: -80), in: gate)
        guard case .ready(let lane, let distance) = state else {
            Issue.record("Esperaba .ready, llegó \(state)")
            return
        }
        #expect(lane.type == .residentsOnly)
        #expect(distance == 80)
    }

    @Test("Cerca del carril compartido: solicitud de paso")
    func sharedLane() {
        let state = GateViewModel.evaluate(gate.lanes[1].location.offset(northMeters: 80), in: gate)
        guard case .ready(let lane, _) = state else {
            Issue.record("Esperaba .ready, llegó \(state)")
            return
        }
        #expect(lane.type == .shared)
    }

    @Test("Fuera de los 150 m el botón se desactiva")
    func outsideGeofence() {
        let state = GateViewModel.evaluate(gate.lanes[0].location.offset(northMeters: -2_300), in: gate)
        guard case .far(let distance) = state else {
            Issue.record("Esperaba .far, llegó \(state)")
            return
        }
        #expect(distance > 150)
    }
}

// MARK: - Roles

@Suite("Roles")
struct RoleTests {
    private func profile(_ role: ResidentRole, tenure: Tenure? = .owner, rented: Bool = false, contractEndsOn: Date? = nil) -> UserProfile {
        UserProfile(
            id: "u", firstName: "A", lastName: "B", phone: "+520000000000", role: role, tenure: tenure,
            residence: Residence(id: "r", name: "Casa", fraccionamientoId: "f", fraccionamientoName: "F", isRented: rented),
            approvalStatus: .approved, rejectionReason: nil, contractEndsOn: contractEndsOn
        )
    }

    @Test("El menor abre la pluma para su paso pero no autoriza visitas")
    func minor() {
        let minor = profile(.minor)
        #expect(minor.canUseGate)
        #expect(!minor.canAuthorizeVisits)
    }

    @Test("El propietario no residente entra con su QR, sin botón de abrir (RF-87)")
    func nonResidentOwner() {
        #expect(!profile(.nonResidentOwner).canUseGate)
        #expect(!profile(.nonResidentOwner, rented: true).canAuthorizeVisits)
        #expect(profile(.nonResidentOwner, rented: false).canAuthorizeVisits)
    }

    @Test("Arrendatario con el contrato por terminar debe confirmar (RF-84)")
    func tenancy() {
        let soon = profile(.holder, tenure: .tenant, contractEndsOn: .now.addingTimeInterval(3 * 86_400))
        let later = profile(.holder, tenure: .tenant, contractEndsOn: .now.addingTimeInterval(60 * 86_400))
        #expect(soon.needsTenancyConfirmation())
        #expect(!later.needsTenancyConfirmation())
        #expect(!profile(.holder, tenure: .owner, contractEndsOn: .now).needsTenancyConfirmation())
    }
}

// MARK: - Push

@Suite("Push")
struct RemotePushTests {
    @Test("Visita pendiente")
    func pending() {
        #expect(RemotePush(userInfo: ["type": "visit.pending", "visitId": "v1"]) == .pendingVisit(visitId: "v1"))
    }

    @Test("Otro integrante respondió (RF-06)")
    func responded() {
        let push = RemotePush(userInfo: ["type": "visit.responded", "visitId": "v1", "visitName": "Juan", "decision": "authorize", "respondedBy": "Ana"])
        #expect(push == .visitResponded(visitId: "v1", visitName: "Juan", decision: .authorize, respondedBy: "Ana"))
    }

    @Test("Desconocido")
    func unknown() {
        #expect(RemotePush(userInfo: ["type": "otro"]) == .unknown)
    }
}

// MARK: - Visitas (RF-04, RF-86)

@Suite("Visitas")
struct VisitRulesTests {
    @Test("El plazo de respuesta es la llegada más 60 s si el backend no manda otro")
    func deadline() {
        let arrived = Date(timeIntervalSince1970: 1_000)
        let visit = Visit(id: "v", kind: .visit, name: "Juan", origin: .walkIn, status: .waiting, arrivedAt: arrived)
        #expect(visit.responseDeadline == arrived.addingTimeInterval(60))
    }

    @Test("Coincidencia confirmada con la lista restringida: la decide la administración")
    func restricted() {
        var visit = Visit(id: "v", kind: .visit, name: "Juan", origin: .walkIn, status: .waiting)
        visit.restrictedMatch = .confirmed
        #expect(visit.isHeldByAdministration)
        visit.restrictedMatch = .possible
        #expect(!visit.isHeldByAdministration)
    }
}

// MARK: - Backend de prueba

@Suite("MockServer", .serialized)
struct MockServerTests {
    let brandon = PhoneNumber(country: .mexico, digits: "2221234567")
    let device = DeviceDescriptor(id: "test-device", name: "Prueba", model: .iphone)

    private func client(_ server: MockServer) -> APIClient {
        APIClient(config: .mock, transport: MockTransport(server: server), interceptors: [
            DefaultHeadersInterceptor(deviceId: "test-device", appVersion: "1.0"),
        ])
    }

    @Test("Un código SMS incorrecto se rechaza")
    func wrongCode() async throws {
        let server = MockServer(latency: .zero)
        let client = client(server)
        _ = try await client.send(API.Auth.requestOTP(brandon))
        await #expect(throws: APIError.self) {
            _ = try await client.send(API.Auth.verifyOTP(VerifyOTPRequest(phone: brandon.e164, code: "000000", device: device)))
        }
    }

    @Test("Cuenta existente con el código 123456 (pantalla 3a)")
    func existingAccount() async throws {
        let server = MockServer(latency: .zero)
        let client = client(server)
        _ = try await client.send(API.Auth.requestOTP(brandon))
        let response = try await client.send(API.Auth.verifyOTP(VerifyOTPRequest(phone: brandon.e164, code: "123456", device: device)))
        #expect(response.result.accountState == .existing)
        #expect(response.result.profile.firstName == "Brandon")
    }
}
