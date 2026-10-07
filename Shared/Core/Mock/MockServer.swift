//
//  MockServer.swift
//  SecurityIslas
//
//  Backend de prueba que vive dentro de la app. Recibe URLRequest reales
//  (ya pasados por los interceptores) y responde como lo haría el backend:
//  • Emite tokens con vencimiento corto para ejercitar el refresh del
//    AuthInterceptor (401 → refresh → reintento).
//  • Verifica las firmas P-256 de las acciones sensibles con la llave pública
//    registrada, el timestamp y el nonce (sin firma válida, 403).
//  • Vuelve a validar la geocerca, el tipo de carril y el límite de pulsos.
//
//  Las cuentas y llaves se guardan en UserDefaults para sobrevivir reinicios;
//  lo demás (visitas, paquetes...) se reinicia con cada arranque.
//

import CryptoKit
import Foundation

nonisolated struct MockTransport: HTTPTransport {
    let server: MockServer

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await server.handle(request)
    }
}

nonisolated struct MockRequest: Sendable {
    let method: String
    let path: [String]
    let query: [String: String]
    let headers: [String: String]
    let body: Data?

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        // Quita el prefijo de versión: /v1/visits/1 → ["visits", "1"]
        path = (components?.path ?? "")
            .split(separator: "/")
            .map(String.init)
            .drop { $0 == "v1" }
            .map { $0 }
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value
        }
        self.query = query
        var headers: [String: String] = [:]
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            headers[key.lowercased()] = value
        }
        self.headers = headers
        body = request.httpBody
    }

    var relativePath: String { path.joined(separator: "/") }

    /// `match("POST", "visits/:id/decision")` → `["123"]` si coincide.
    func match(_ method: String, _ template: String) -> [String]? {
        guard self.method == method else { return nil }
        let parts = template.split(separator: "/").map(String.init)
        guard parts.count == path.count else { return nil }
        var captured: [String] = []
        for (part, value) in zip(parts, path) {
            if part.hasPrefix(":") {
                captured.append(value)
            } else if part != value {
                return nil
            }
        }
        return captured
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body, let value = try? JSONCoding.decoder().decode(T.self, from: body) else {
            throw MockFailure(422, "INVALID_BODY", "Faltan datos en la solicitud.")
        }
        return value
    }
}

nonisolated struct MockFailure: Error {
    let status: Int
    let body: ServerErrorBody

    init(_ status: Int, _ code: String, _ message: String) {
        self.status = status
        self.body = ServerErrorBody(code: code, message: message)
    }
}

nonisolated struct MockPersistentState: Codable, Sendable {
    var accounts: [MockAccount]
    /// Dispositivos dados de baja: pierden el acceso de inmediato (RF-65).
    var revokedDeviceIds: Set<String> = []
}

/// Ajustes de simulación que se pueden cambiar desde Cuenta > Simulación.
nonisolated enum MockSettings {
    static let stateKey = "mock.server.state.v1"
    static let accessTokenLifetimeKey = "mock.accessTokenLifetime"

    static var accessTokenLifetime: Int {
        let stored = UserDefaults.standard.integer(forKey: accessTokenLifetimeKey)
        return stored > 0 ? stored : 120
    }
}

actor MockServer {
    private let latency: Duration
    private var persistent: MockPersistentState
    private var visits: [Visit]
    private var invitations: [Invitation]
    private var recurring: [RecurringAccess]
    private var packages: [Package]
    private var history: [HistoryEvent]
    private var family: [MockFamilyMember]
    private var contacts: [EmergencyContact]
    private var guests: [TemporaryGuest] = []
    private var workPermit: WorkPermit?
    private var packagePolicy: PackagePolicy = .leaveAtBooth
    private var panicAlerts: [String: PanicAlert] = [:]
    private var usedNonces: Set<String> = []
    private var lastPulse: [String: Date] = [:]
    private var revokedRefreshTokens: Set<String> = []

    init(latency: Duration = .milliseconds(450)) {
        let now = Date.now
        self.latency = latency
        if let data = UserDefaults.standard.data(forKey: MockSettings.stateKey),
           let saved = try? JSONCoding.decoder().decode(MockPersistentState.self, from: data) {
            persistent = saved
        } else {
            persistent = MockPersistentState(accounts: MockSeed.accounts(now: now))
        }
        visits = MockSeed.visits(now: now)
        invitations = MockSeed.invitations(now: now)
        recurring = MockSeed.recurring(now: now)
        packages = MockSeed.packages(now: now)
        history = MockSeed.history(now: now)
        family = MockSeed.family()
        contacts = MockSeed.contacts()
        workPermit = MockSeed.workPermit(now: now)
    }

    // MARK: - Entrada

    func handle(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: latency)
        guard let url = urlRequest.url else { throw URLError(.badURL) }

        let request = MockRequest(urlRequest)
        let result: (status: Int, data: Data)
        do {
            result = try route(request)
        } catch let failure as MockFailure {
            result = (failure.status, (try? JSONCoding.encoder().encode(failure.body)) ?? Data())
        }
        let status = result.status
        let data = result.data

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    /// Simula que llega una visita a caseta (menú de simulación).
    func simulateArrival(kind: AccessKind) -> Visit {
        let names: [(String, String?)] = kind == .visit
            ? [("Sofía Herrera", "PUE-88-21"), ("Miguel Ángel Ruiz", nil), ("Daniela Torres", "TXZ-45-10")]
            : [("Rappi", nil), ("Agua Bonafont", nil), ("Paquetería Estafeta", nil)]
        let pick = names.randomElement() ?? ("Visita", nil)
        let visit = Visit(
            id: "vis-\(UUID().uuidString.prefix(8))",
            kind: kind,
            name: pick.0,
            company: kind == .service ? pick.0 : nil,
            plate: pick.1,
            origin: .walkIn,
            status: .waiting,
            arrivedAt: .now
        )
        visits.insert(visit, at: 0)
        return visit
    }

    func resetAll() {
        UserDefaults.standard.removeObject(forKey: MockSettings.stateKey)
        persistent = MockPersistentState(accounts: MockSeed.accounts(now: .now))
    }

    // MARK: - Rutas

    private func route(_ r: MockRequest) throws -> (Int, Data) {
        // Autenticación
        if r.match("POST", "auth/otp") != nil { return try requestOTP(r) }
        if r.match("POST", "auth/otp/verify") != nil { return try verifyOTP(r) }
        if r.match("POST", "auth/refresh") != nil { return try refresh(r) }
        if r.match("POST", "auth/watch-link") != nil { return try completeWatchLink(r) }
        if r.match("POST", "auth/logout") != nil {
            _ = try authenticatedAccount(r)
            return try ok(EmptyResponse())
        }
        if r.match("GET", "me") != nil { return try ok(currentProfile(authenticatedIndex(r))) }

        // Registro
        if r.match("GET", "fraccionamientos") != nil {
            _ = try authenticatedAccount(r)
            let query = (r.query["q"] ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let results = MockSeed.fraccionamientos.filter {
                query.isEmpty || $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
            }
            return try ok(results)
        }
        if let params = r.match("GET", "fraccionamientos/:id/homes") {
            _ = try authenticatedAccount(r)
            return try ok(MockSeed.homes(for: params[0]))
        }
        if r.match("POST", "invites/resolve") != nil { return try resolveInvite(r) }
        if r.match("POST", "registrations") != nil { return try submitRegistration(r) }

        // Dispositivos
        if r.match("GET", "devices") != nil { return try listDevices(r) }
        if let params = r.match("DELETE", "devices/:id") { return try removeDevice(r, id: params[0]) }
        if r.match("POST", "devices/key") != nil { return try registerKey(r) }
        if r.match("POST", "devices/watch-link") != nil { return try createWatchLink(r) }

        // A partir de aquí: residente aprobado.
        if r.match("GET", "home") != nil { return try home(r) }
        if r.match("GET", "visits") != nil {
            try requireResident(r, restrictOwner: true)
            return try ok(visits)
        }
        if let params = r.match("POST", "visits/:id/decision") { return try decide(r, id: params[0]) }
        if let params = r.match("POST", "visits/:id/sleepover") { return try sleepover(r, id: params[0]) }
        if r.match("GET", "invitations") != nil {
            try requireResident(r, restrictOwner: true)
            return try ok(invitations)
        }
        if r.match("POST", "invitations") != nil { return try createInvitation(r) }
        if r.match("GET", "recurring") != nil {
            try requireResident(r, restrictOwner: true)
            return try ok(recurring)
        }
        if let params = r.match("GET", "recurring/:id") {
            try requireResident(r, restrictOwner: true)
            guard let item = recurring.first(where: { $0.id == params[0] }) else { throw notFound() }
            return try ok(item)
        }
        if r.match("POST", "recurring") != nil { return try createRecurring(r) }
        if let params = r.match("DELETE", "recurring/:id") { return try revokeRecurring(r, id: params[0]) }
        if r.match("GET", "packages") != nil {
            try requireResident(r, restrictOwner: true)
            return try ok(packages)
        }
        if r.match("GET", "package-policy") != nil {
            try requireResident(r, restrictOwner: true)
            return try ok(PackagePolicySetting(policy: packagePolicy))
        }
        if r.match("PUT", "package-policy") != nil {
            try requireResident(r, restrictOwner: true)
            try verifySignature(r)
            packagePolicy = try r.decode(PackagePolicySetting.self).policy
            return try ok(PackagePolicySetting(policy: packagePolicy))
        }
        if r.match("GET", "history") != nil {
            try requireResident(r, restrictOwner: true)
            let filtered = r.query["category"].flatMap(HistoryCategory.init(rawValue:))
                .map { category in history.filter { $0.category == category } } ?? history
            return try ok(filtered.sorted { $0.date > $1.date })
        }

        // Pluma y QR
        if r.match("POST", "gate/open") != nil { return try openGate(r) }
        if r.match("GET", "qr-seed") != nil { return try qrSeed(r) }

        // Pánico
        if r.match("POST", "panic") != nil { return try createPanic(r) }
        if let params = r.match("GET", "panic/:id") { return try panicStatus(r, id: params[0]) }
        if let params = r.match("POST", "panic/:id/location") {
            try requireResident(r, restrictOwner: false)
            guard panicAlerts[params[0]] != nil else { throw notFound() }
            return try ok(EmptyResponse())
        }
        if let params = r.match("POST", "panic/:id/close") { return try closePanic(r, id: params[0]) }

        // Vivienda
        if r.match("GET", "family") != nil { return try listFamily(r) }
        if r.match("POST", "family") != nil { return try inviteFamily(r) }
        if let params = r.match("DELETE", "family/:id") { return try removeFamily(r, id: params[0]) }
        if r.match("GET", "emergency-contacts") != nil {
            try requireResident(r, restrictOwner: false)
            return try ok(contacts)
        }
        if r.match("POST", "emergency-contacts") != nil { return try addContact(r) }
        if let params = r.match("DELETE", "emergency-contacts/:id") {
            try requireResident(r, restrictOwner: false)
            try verifySignature(r)
            contacts.removeAll { $0.id == params[0] }
            return try ok(EmptyResponse())
        }
        if r.match("GET", "guests") != nil {
            try requireHolder(r)
            return try ok(guests)
        }
        if r.match("POST", "guests") != nil { return try createGuest(r) }
        if r.match("GET", "work-permit") != nil {
            try requireHolder(r)
            return try ok(WorkPermitEnvelope(permit: workPermit))
        }
        if r.match("POST", "work-permit") != nil { return try requestWorkPermit(r) }
        if r.match("PATCH", "work-permit") != nil {
            try requireHolder(r)
            guard var permit = workPermit else { throw notFound() }
            permit.dailySummary = try r.decode(WorkPermitSettings.self).dailySummary
            workPermit = permit
            return try ok(permit)
        }

        throw MockFailure(404, "NOT_FOUND", "Ruta no encontrada: \(r.method) \(r.relativePath)")
    }

    // MARK: - Auth

    private func requestOTP(_ r: MockRequest) throws -> (Int, Data) {
        let body = try r.decode(OTPRequest.self)
        guard body.phone.filter(\.isNumber).count >= 11 else {
            throw MockFailure(422, "INVALID_PHONE", "Revisa tu número de celular.")
        }
        return try ok(OTPChallenge(expiresIn: 300, resendIn: 42))
    }

    private func verifyOTP(_ r: MockRequest) throws -> (Int, Data) {
        let body = try r.decode(VerifyOTPRequest.self)
        guard body.code == "123456" else {
            throw MockFailure(422, "INVALID_OTP", "El código no es correcto. Revísalo e inténtalo de nuevo.")
        }

        let index: Int
        if let existing = persistent.accounts.firstIndex(where: { $0.phones.contains(body.phone) }) {
            index = existing
        } else {
            let profile = UserProfile(
                id: "usr-\(UUID().uuidString.prefix(8).lowercased())",
                firstName: "",
                lastName: "",
                phone: body.phone,
                role: .holder,
                tenure: nil,
                residence: nil,
                approvalStatus: .unregistered,
                rejectionReason: nil
            )
            persistent.accounts.append(MockAccount(phones: [body.phone], profile: profile, state: .newResident, devices: []))
            index = persistent.accounts.count - 1
            save()
        }

        persistent.revokedDeviceIds.remove(body.device.id)
        save()

        let account = persistent.accounts[index]
        let otherDevices = account.devices
            .filter { $0.id != body.device.id }
            .map { Device(id: $0.id, name: $0.name, model: $0.model, lastUsedAt: $0.lastUsedAt, isCurrent: false) }

        // Si este iPhone ya estaba registrado (app reinstalada), la llave anterior deja de servir.
        if account.devices.contains(where: { $0.id == body.device.id }) {
            persistent.accounts[index].devices.removeAll { $0.id == body.device.id }
            save()
        }

        let result = VerificationResult(
            accountState: account.state,
            profile: currentProfile(index),
            devices: otherDevices,
            maxDevices: 3,
            preload: MockSeed.preload(for: account)
        )
        return try ok(VerifyOTPResponse(tokens: issueTokens(for: account.profile.id), result: result))
    }

    private func refresh(_ r: MockRequest) throws -> (Int, Data) {
        let body = try r.decode(RefreshRequest.self)
        let parts = body.refreshToken.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "mock-refresh",
              !revokedRefreshTokens.contains(body.refreshToken),
              persistent.accounts.contains(where: { $0.profile.id == parts[1] }) else {
            throw MockFailure(401, "INVALID_REFRESH_TOKEN", "Tu sesión expiró.")
        }
        try ensureDeviceNotRevoked(r)
        // Rotación: el refresh token anterior deja de servir.
        revokedRefreshTokens.insert(body.refreshToken)
        return try ok(issueTokens(for: parts[1]))
    }

    private func issueTokens(for userId: String) -> TokenResponse {
        let lifetime = MockSettings.accessTokenLifetime
        let expiry = Int(Date.now.timeIntervalSince1970) + lifetime
        return TokenResponse(
            accessToken: "mock-access.\(userId).\(expiry)",
            refreshToken: "mock-refresh.\(userId).\(UUID().uuidString.prefix(8))",
            expiresIn: lifetime
        )
    }

    // MARK: - Registro

    private func resolveInvite(_ r: MockRequest) throws -> (Int, Data) {
        _ = try authenticatedAccount(r)
        let code = try r.decode(InviteResolveRequest.self).code
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count >= 4, code != "0000" else {
            throw MockFailure(404, "INVITE_NOT_FOUND", "Ese código de invitación no existe o ya venció.")
        }
        return try ok(MockSeed.bosques)
    }

    private func submitRegistration(_ r: MockRequest) throws -> (Int, Data) {
        let index = try authenticatedIndex(r)
        let body = try r.decode(RegistrationRequest.self)
        guard let fraccionamiento = MockSeed.fraccionamientos.first(where: { $0.id == body.fraccionamientoId }),
              let home = MockSeed.homes(for: fraccionamiento.id).first(where: { $0.id == body.homeId }) else {
            throw MockFailure(422, "INVALID_HOME", "Elige una vivienda del catálogo.")
        }
        guard !body.firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !body.lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MockFailure(422, "INVALID_NAME", "Escribe tu nombre y apellidos.")
        }

        var account = persistent.accounts[index]
        account.profile.firstName = body.firstName
        account.profile.lastName = body.lastName
        account.profile.tenure = body.tenure
        account.profile.residence = Residence(
            id: home.id,
            name: home.name,
            fraccionamientoId: fraccionamiento.id,
            fraccionamientoName: fraccionamiento.name,
            isRented: false
        )
        // Precargado por la administración: aprobado al instante (RF-63).
        account.profile.approvalStatus = account.state == .preloaded ? .approved : .pending
        account.registrationSubmittedAt = .now
        persistent.accounts[index] = account
        save()
        return try ok(currentProfile(index))
    }

    /// Simula la aprobación de la administración ~12 s después de la solicitud.
    private func currentProfile(_ index: Int) -> UserProfile {
        var account = persistent.accounts[index]
        if account.profile.approvalStatus == .pending,
           let submitted = account.registrationSubmittedAt,
           Date.now.timeIntervalSince(submitted) > 12 {
            account.profile.approvalStatus = .approved
            account.state = .existing
            persistent.accounts[index] = account
            save()
        }
        return account.profile
    }

    // MARK: - Dispositivos

    private func listDevices(_ r: MockRequest) throws -> (Int, Data) {
        let account = try authenticatedAccount(r)
        let deviceId = r.headers["x-device-id"]
        let devices = account.devices.map {
            Device(id: $0.id, name: $0.name, model: $0.model, lastUsedAt: $0.lastUsedAt, isCurrent: $0.id == deviceId)
        }
        return try ok(DeviceList(devices: devices, maxDevices: 3))
    }

    private func removeDevice(_ r: MockRequest, id: String) throws -> (Int, Data) {
        let index = try authenticatedIndex(r)
        let deviceId = r.headers["x-device-id"]
        let callerIsRegistered = persistent.accounts[index].devices.contains { $0.id == deviceId && $0.publicKey != nil }
        // Ya con llave, quitar un dispositivo es un cambio de cuenta firmado (RF-67).
        if callerIsRegistered {
            try verifySignature(r)
        }
        guard persistent.accounts[index].devices.contains(where: { $0.id == id }) else { throw notFound() }
        persistent.accounts[index].devices.removeAll { $0.id == id }
        persistent.revokedDeviceIds.insert(id)
        save()
        return try ok(EmptyResponse())
    }

    private func registerKey(_ r: MockRequest) throws -> (Int, Data) {
        let index = try authenticatedIndex(r)
        guard currentProfile(index).approvalStatus == .approved else {
            throw MockFailure(403, "PENDING_APPROVAL", "Tu alta sigue en revisión.")
        }
        guard let deviceId = r.headers["x-device-id"] else {
            throw MockFailure(422, "MISSING_DEVICE", "Falta el identificador del dispositivo.")
        }
        let body = try r.decode(DeviceKeyRequest.self)
        guard let keyData = Data(base64Encoded: body.publicKey),
              (try? P256.Signing.PublicKey(x963Representation: keyData)) != nil else {
            throw MockFailure(422, "INVALID_KEY", "La llave del dispositivo no es válida.")
        }

        var devices = persistent.accounts[index].devices.filter { $0.id != deviceId }
        guard devices.filter(\.model.countsTowardLimit).count < 3 else {
            throw MockFailure(409, "DEVICE_LIMIT", "Ya tienes 3 dispositivos. Quita uno para continuar.")
        }
        devices.append(MockDevice(id: deviceId, name: body.name, model: body.model, lastUsedAt: .now, publicKey: body.publicKey))
        persistent.accounts[index].devices = devices
        save()
        return try ok(Device(id: deviceId, name: body.name, model: body.model, lastUsedAt: .now, isCurrent: true))
    }

    // MARK: - Apple Watch

    /// Código de un solo uso: `mock-link.<userId>.<vence>` (5 min).
    private func createWatchLink(_ r: MockRequest) throws -> (Int, Data) {
        let account = try requireResident(r, restrictOwner: false)
        try verifySignature(r)
        // Los relojes no cuentan en el límite de 3 dispositivos (RF-66).
        let expiresAt = Date.now.addingTimeInterval(300)
        let code = "mock-link.\(account.profile.id).\(Int(expiresAt.timeIntervalSince1970))"
        return try ok(WatchLinkTicket(code: code, expiresAt: expiresAt), status: 201)
    }

    private func completeWatchLink(_ r: MockRequest) throws -> (Int, Data) {
        let body = try r.decode(WatchLinkRequest.self)
        let parts = body.code.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "mock-link",
              let expiry = TimeInterval(parts[2]), Date.now.timeIntervalSince1970 < expiry,
              let index = persistent.accounts.firstIndex(where: { $0.profile.id == parts[1] }) else {
            throw MockFailure(410, "LINK_EXPIRED", "El código venció. Vuelve a vincular desde tu iPhone.")
        }
        guard let keyData = Data(base64Encoded: body.publicKey),
              (try? P256.Signing.PublicKey(x963Representation: keyData)) != nil else {
            throw MockFailure(422, "INVALID_KEY", "La llave del reloj no es válida.")
        }
        // Se pueden tener varios relojes y no ocupan lugar en el límite (RF-66).
        var devices = persistent.accounts[index].devices.filter { $0.id != body.device.id }
        devices.append(MockDevice(
            id: body.device.id,
            name: body.device.name,
            model: .watch,
            lastUsedAt: .now,
            publicKey: body.publicKey
        ))
        persistent.accounts[index].devices = devices
        persistent.revokedDeviceIds.remove(body.device.id)
        save()
        let response = WatchLinkResponse(tokens: issueTokens(for: parts[1]), profile: currentProfile(index))
        return try ok(response)
    }

    // MARK: - Puente entre el iPhone y el reloj (solo mock)
    //
    // Con el backend real ambos dispositivos ven el mismo servidor. Con el mock
    // cada app tiene el suyo, así que el iPhone le pasa al reloj la cuenta y las
    // visitas simuladas por WatchConnectivity.

    func exportAccount(userId: String) -> Data? {
        guard let account = persistent.accounts.first(where: { $0.profile.id == userId }) else { return nil }
        return try? JSONCoding.encoder().encode(account)
    }

    func importAccount(_ data: Data) {
        guard let account = try? JSONCoding.decoder().decode(MockAccount.self, from: data) else { return }
        if let index = persistent.accounts.firstIndex(where: { $0.profile.id == account.profile.id }) {
            persistent.accounts[index] = account
        } else {
            persistent.accounts.append(account)
        }
        save()
    }

    /// El reloj ya se vinculó: el iPhone lo muestra en Dispositivos.
    func importLinkedWatch(_ watch: LinkedWatch) {
        guard let index = persistent.accounts.firstIndex(where: { $0.profile.id == watch.userId }) else { return }
        var devices = persistent.accounts[index].devices.filter { $0.id != watch.deviceId }
        devices.append(MockDevice(id: watch.deviceId, name: watch.name, model: .watch, lastUsedAt: .now, publicKey: watch.publicKey))
        persistent.accounts[index].devices = devices
        save()
    }

    func importVisit(_ visit: Visit) {
        visits.removeAll { $0.id == visit.id }
        visits.insert(visit, at: 0)
    }

    // MARK: - Visitas

    private func home(_ r: MockRequest) throws -> (Int, Data) {
        let account = try requireResident(r, restrictOwner: false)
        if account.profile.isRestrictedOwner {
            return try ok(HomeSummary(pendingVisits: [], today: [], gate: MockSeed.gate, packagesAtBooth: 0))
        }
        let calendar = Calendar.current
        let pending = visits.filter { $0.status == .waiting }
        let today = visits.filter { visit in
            guard visit.status != .waiting else { return false }
            let reference = visit.enteredAt ?? visit.arrivedAt ?? visit.scheduledAt
            return reference.map { calendar.isDateInToday($0) } ?? false
        }
        let atBooth = packages.filter { $0.status == .atBooth }.count
        return try ok(HomeSummary(pendingVisits: pending, today: today, gate: MockSeed.gate, packagesAtBooth: atBooth))
    }

    private func decide(_ r: MockRequest, id: String) throws -> (Int, Data) {
        let account = try requireResident(r, restrictOwner: true)
        guard account.profile.role != .minor else {
            throw MockFailure(403, "NOT_ALLOWED", "Solo los adultos de la vivienda autorizan visitas.")
        }
        let decision = try r.decode(VisitDecisionRequest.self).decision
        guard let index = visits.firstIndex(where: { $0.id == id }) else { throw notFound() }
        guard visits[index].status == .waiting else {
            let who = visits[index].respondedBy ?? "Otro integrante"
            throw MockFailure(409, "ALREADY_RESPONDED", "\(who) ya respondió a esta visita.")
        }
        visits[index].status = decision == .authorize ? .authorized : .rejected
        visits[index].respondedBy = account.profile.firstName
        if decision == .authorize {
            visits[index].enteredAt = .now
        }
        let visit = visits[index]
        history.append(HistoryEvent(
            id: "his-\(UUID().uuidString.prefix(6))",
            category: visit.kind == .visit ? .visit : .service,
            title: visit.name,
            detail: "\(visit.kind.title) · \(decision == .authorize ? "autorizó" : "rechazó") \(account.profile.firstName)",
            date: .now,
            isWarning: decision == .reject
        ))
        return try ok(visit)
    }

    private func sleepover(_ r: MockRequest, id: String) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: true)
        guard let index = visits.firstIndex(where: { $0.id == id }) else { throw notFound() }
        visits[index].status = .sleepover
        return try ok(visits[index])
    }

    private func createInvitation(_ r: MockRequest) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: true)
        let body = try r.decode(NewInvitationRequest.self)
        guard !body.guestName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MockFailure(422, "INVALID_NAME", "Escribe el nombre de tu visita.")
        }
        let code = String(UUID().uuidString.prefix(4))
        let invitation = Invitation(
            id: "inv-\(code.lowercased())",
            kind: body.kind,
            guestName: body.guestName,
            startsAt: body.startsAt,
            endsAt: body.endsAt,
            plate: body.plate,
            isEvent: body.isEvent,
            capacity: body.capacity,
            shareURL: URL(string: "https://\(AppInfo.inviteHost)/i/\(code)")!,
            pin: String(format: "%04d", Int.random(in: 0...9999)),
            status: .scheduled
        )
        invitations.insert(invitation, at: 0)
        if Calendar.current.isDateInToday(body.startsAt) {
            visits.append(Visit(
                id: "vis-\(invitation.id)",
                kind: body.kind,
                name: body.guestName,
                plate: body.plate,
                origin: body.isEvent ? .event : .invitation,
                status: .scheduled,
                scheduledAt: body.startsAt
            ))
        }
        return try ok(invitation, status: 201)
    }

    private func createRecurring(_ r: MockRequest) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: true)
        try verifySignature(r)
        let body = try r.decode(NewRecurringRequest.self)
        guard !body.weekdays.isEmpty else {
            throw MockFailure(422, "INVALID_DAYS", "Elige al menos un día.")
        }
        let code = String(UUID().uuidString.prefix(5))
        let item = RecurringAccess(
            id: "rec-\(code.lowercased())",
            kind: body.kind,
            name: body.name,
            detail: nil,
            weekdays: body.weekdays,
            startTime: body.startTime,
            endTime: body.endTime,
            expiresOn: body.expiresOn,
            codeType: body.codeType,
            pinUsesPerDay: body.pinUsesPerDay,
            shareURL: URL(string: "https://\(AppInfo.inviteHost)/r/\(code)")!,
            recentEntries: []
        )
        recurring.append(item)
        return try ok(item, status: 201)
    }

    private func revokeRecurring(_ r: MockRequest, id: String) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: true)
        try verifySignature(r)
        guard recurring.contains(where: { $0.id == id }) else { throw notFound() }
        recurring.removeAll { $0.id == id }
        return try ok(EmptyResponse())
    }

    // MARK: - Pluma

    private func openGate(_ r: MockRequest) throws -> (Int, Data) {
        let account = try requireResident(r, restrictOwner: false)
        guard account.profile.role != .nonResidentOwner else {
            throw MockFailure(403, "NOT_ALLOWED", "Con tu acceso de propietario entras con tu QR en caseta.")
        }
        try verifySignature(r)
        let command = try r.decode(GateCommand.self)
        guard let lane = MockSeed.gate.lanes.first(where: { $0.id == command.laneId }) else { throw notFound() }

        guard command.location.distance(to: lane.location) <= MockSeed.gate.entranceRadius else {
            throw MockFailure(403, "OUTSIDE_GEOFENCE", "Acércate a la entrada para abrir la pluma.")
        }

        // Tiempo mínimo entre pulsos al mismo carril (RF-80).
        if let last = lastPulse[lane.id], Date.now.timeIntervalSince(last) < 5 {
            throw MockFailure(429, "TOO_SOON", "La pluma acaba de recibir una orden. Espera unos segundos.")
        }
        lastPulse[lane.id] = .now

        let outcome: GateOutcome = lane.type == .residentsOnly ? .opened : .passRequested
        history.append(HistoryEvent(
            id: "his-\(UUID().uuidString.prefix(6))",
            category: .gate,
            title: outcome == .opened ? "Pluma abierta" : "Solicitud de paso",
            detail: "\(account.profile.firstName) · \(lane.name.lowercased())",
            date: .now
        ))
        return try ok(GateResult(outcome: outcome, laneName: lane.name, at: .now))
    }

    private func qrSeed(_ r: MockRequest) throws -> (Int, Data) {
        let index = try authenticatedIndex(r)
        guard currentProfile(index).approvalStatus == .approved else {
            throw MockFailure(403, "PENDING_APPROVAL", "Tu alta sigue en revisión.")
        }
        let secret: String
        if let existing = persistent.accounts[index].qrSecret {
            secret = existing
        } else {
            secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
            persistent.accounts[index].qrSecret = secret
            save()
        }
        return try ok(QRSeed(secret: secret, period: 30, digits: 8))
    }

    // MARK: - Pánico

    private func createPanic(_ r: MockRequest) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: false)
        let body = try r.decode(PanicRequest.self)
        let inside = body.location.distance(to: MockSeed.gate.perimeterCenter) <= MockSeed.gate.perimeterRadius
        let alert = PanicAlert(
            id: "pan-\(UUID().uuidString.prefix(6).lowercased())",
            scope: inside ? .guards : .contacts,
            status: .sent,
            createdAt: .now,
            guardName: nil,
            guardConfirmedAt: nil,
            contacts: contacts.map { ContactAlert(id: $0.id, name: $0.name, state: .sent, channel: $0.hasApp ? "notificación" : "notificación y SMS", at: nil) }
        )
        panicAlerts[alert.id] = alert
        history.append(HistoryEvent(
            id: "his-\(alert.id)",
            category: .alert,
            title: "Alerta de pánico",
            detail: inside ? "Enviada a los guardias en turno" : "Enviada a tus contactos de emergencia",
            date: .now,
            isWarning: true
        ))
        return try ok(alert, status: 201)
    }

    /// El estado avanza con el tiempo: recibida → guardia en camino / contacto la vio.
    private func panicStatus(_ r: MockRequest, id: String) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: false)
        guard var alert = panicAlerts[id] else { throw notFound() }
        guard alert.status != .closed else { return try ok(alert) }

        let elapsed = Date.now.timeIntervalSince(alert.createdAt)
        if elapsed > 2, alert.status == .sent {
            alert.status = .received
        }
        if elapsed > 6, alert.scope == .guards, alert.guardName == nil {
            alert.status = .guardOnTheWay
            alert.guardName = "Guardia Ramírez"
            alert.guardConfirmedAt = .now
        }
        if elapsed > 5, let first = alert.contacts.first, first.state == .sent {
            alert.contacts[0] = ContactAlert(id: first.id, name: first.name, state: .seen, channel: first.channel, at: .now)
        }
        panicAlerts[id] = alert
        return try ok(alert)
    }

    private func closePanic(_ r: MockRequest, id: String) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: false)
        try verifySignature(r)
        guard var alert = panicAlerts[id] else { throw notFound() }
        alert.status = .closed
        panicAlerts[id] = alert
        return try ok(alert)
    }

    // MARK: - Vivienda

    private func listFamily(_ r: MockRequest) throws -> (Int, Data) {
        let account = try requireResident(r, restrictOwner: false)
        let members = family.map {
            FamilyMember(id: $0.id, name: $0.name, role: $0.role, isCurrentUser: $0.userId == account.profile.id)
        }
        return try ok(members)
    }

    private func inviteFamily(_ r: MockRequest) throws -> (Int, Data) {
        try requireHolder(r)
        try verifySignature(r)
        let body = try r.decode(FamilyInviteRequest.self)
        let member = MockFamilyMember(id: "fam-\(UUID().uuidString.prefix(6))", userId: "usr-invited", name: body.name, role: body.role)
        family.append(member)
        return try ok(FamilyMember(id: member.id, name: member.name, role: member.role, isCurrentUser: false), status: 201)
    }

    private func removeFamily(_ r: MockRequest, id: String) throws -> (Int, Data) {
        let account = try requireHolder(r)
        try verifySignature(r)
        guard let member = family.first(where: { $0.id == id }) else { throw notFound() }
        guard member.userId != account.profile.id else {
            throw MockFailure(422, "CANNOT_REMOVE_SELF", "No puedes quitarte a ti mismo.")
        }
        family.removeAll { $0.id == id }
        return try ok(EmptyResponse())
    }

    private func addContact(_ r: MockRequest) throws -> (Int, Data) {
        try requireResident(r, restrictOwner: false)
        try verifySignature(r)
        let body = try r.decode(NewEmergencyContactRequest.self)
        let contact = EmergencyContact(
            id: "con-\(UUID().uuidString.prefix(6))",
            name: body.name,
            relationship: body.relationship,
            phone: body.phone,
            hasApp: false
        )
        contacts.append(contact)
        return try ok(contact, status: 201)
    }

    private func createGuest(_ r: MockRequest) throws -> (Int, Data) {
        try requireHolder(r)
        let body = try r.decode(NewGuestRequest.self)
        guard body.departure > body.arrival else {
            throw MockFailure(422, "INVALID_DATES", "La salida debe ser después de la llegada.")
        }
        let guest = TemporaryGuest(
            id: "gst-\(UUID().uuidString.prefix(6))",
            name: body.name,
            arrival: body.arrival,
            departure: body.departure,
            phone: body.phone
        )
        guests.append(guest)
        return try ok(guest, status: 201)
    }

    private func requestWorkPermit(_ r: MockRequest) throws -> (Int, Data) {
        let account = try requireHolder(r)
        guard account.profile.tenure == .owner || account.profile.role == .nonResidentOwner else {
            throw MockFailure(403, "OWNER_ONLY", "El permiso de obra lo solicita el propietario.")
        }
        let body = try r.decode(WorkPermitRequest.self)
        let permit = WorkPermit(
            id: "wp-\(UUID().uuidString.prefix(6))",
            status: .inReview,
            responsible: body.responsible,
            license: body.license,
            startsOn: body.startsOn,
            endsOn: body.endsOn,
            schedule: body.schedule,
            dailySummary: true,
            submittedAt: .now
        )
        workPermit = permit
        return try ok(permit, status: 201)
    }

    // MARK: - Autorización

    private func authenticatedIndex(_ r: MockRequest) throws -> Int {
        guard let header = r.headers["authorization"], header.hasPrefix("Bearer ") else {
            throw MockFailure(401, "MISSING_TOKEN", "Inicia sesión para continuar.")
        }
        let parts = header.dropFirst("Bearer ".count).split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "mock-access", let expiry = TimeInterval(parts[2]) else {
            throw MockFailure(401, "INVALID_TOKEN", "Token inválido.")
        }
        guard Date.now.timeIntervalSince1970 < expiry else {
            throw MockFailure(401, "TOKEN_EXPIRED", "El token expiró.")
        }
        guard let index = persistent.accounts.firstIndex(where: { $0.profile.id == parts[1] }) else {
            throw MockFailure(401, "INVALID_TOKEN", "La cuenta ya no existe.")
        }
        try ensureDeviceNotRevoked(r)
        return index
    }

    /// Al dar de baja un dispositivo pierde el acceso de inmediato (RF-65).
    private func ensureDeviceNotRevoked(_ r: MockRequest) throws {
        if let deviceId = r.headers["x-device-id"], persistent.revokedDeviceIds.contains(deviceId) {
            throw MockFailure(401, "DEVICE_REVOKED", "Este dispositivo ya no tiene acceso a la cuenta.")
        }
    }

    private func authenticatedAccount(_ r: MockRequest) throws -> MockAccount {
        let index = try authenticatedIndex(r)
        return persistent.accounts[index]
    }

    /// Residente aprobado. `restrictOwner`: el propietario no residente con la
    /// casa rentada no ve visitas ni bitácora (RF-87).
    @discardableResult
    private func requireResident(_ r: MockRequest, restrictOwner: Bool) throws -> MockAccount {
        let index = try authenticatedIndex(r)
        let profile = currentProfile(index)
        guard profile.approvalStatus == .approved else {
            throw MockFailure(403, "PENDING_APPROVAL", "Tu alta sigue en revisión: aún no puedes abrir la pluma ni autorizar visitas.")
        }
        if restrictOwner, profile.isRestrictedOwner {
            throw MockFailure(403, "RENTED_HOME", "Mientras la vivienda esté rentada, el arrendatario autoriza las visitas y ve la bitácora.")
        }
        return persistent.accounts[index]
    }

    @discardableResult
    private func requireHolder(_ r: MockRequest) throws -> MockAccount {
        let account = try requireResident(r, restrictOwner: false)
        guard account.profile.canManageHousehold else {
            throw MockFailure(403, "HOLDER_ONLY", "Solo el titular puede hacer este cambio.")
        }
        return account
    }

    /// Verifica la firma ECDSA P-256 con la llave pública del dispositivo.
    private func verifySignature(_ r: MockRequest) throws {
        guard let signatureB64 = r.headers["x-signature"],
              let timestamp = r.headers["x-signature-timestamp"],
              let nonce = r.headers["x-signature-nonce"],
              let deviceId = r.headers["x-device-id"] else {
            throw MockFailure(403, "SIGNATURE_REQUIRED", "Esta acción necesita Face ID.")
        }
        let account = try authenticatedAccount(r)
        guard let keyB64 = account.devices.first(where: { $0.id == deviceId })?.publicKey,
              let keyData = Data(base64Encoded: keyB64),
              let publicKey = try? P256.Signing.PublicKey(x963Representation: keyData) else {
            throw MockFailure(403, "UNKNOWN_DEVICE", "Este dispositivo no tiene una llave registrada.")
        }
        guard let seconds = TimeInterval(timestamp), abs(Date.now.timeIntervalSince1970 - seconds) < 120 else {
            throw MockFailure(403, "SIGNATURE_EXPIRED", "La orden expiró. Inténtalo de nuevo.")
        }
        guard !usedNonces.contains(nonce) else {
            throw MockFailure(403, "REPLAYED_REQUEST", "Esta orden ya se usó.")
        }
        let message = SignaturePayload.canonical(
            method: r.method,
            path: r.relativePath,
            timestamp: timestamp,
            nonce: nonce,
            body: r.body
        )
        guard let signatureData = Data(base64Encoded: signatureB64),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              publicKey.isValidSignature(signature, for: message) else {
            throw MockFailure(403, "INVALID_SIGNATURE", "No pudimos verificar la firma de este dispositivo.")
        }
        usedNonces.insert(nonce)
    }

    // MARK: - Utilidades

    private func ok<T: Encodable>(_ value: T, status: Int = 200) throws -> (Int, Data) {
        (status, try JSONCoding.encoder().encode(value))
    }

    private func notFound() -> MockFailure {
        MockFailure(404, "NOT_FOUND", "No encontramos lo que buscas.")
    }

    private func save() {
        if let data = try? JSONCoding.encoder().encode(persistent) {
            UserDefaults.standard.set(data, forKey: MockSettings.stateKey)
        }
    }
}
