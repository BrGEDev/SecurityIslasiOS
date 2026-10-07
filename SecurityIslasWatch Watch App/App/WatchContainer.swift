//
//  WatchContainer.swift
//  SecurityIslasWatch Watch App
//
//  Dependencias del reloj. Usa la misma capa de red, sesión, firma y mocks que
//  el iPhone (carpeta Shared), pero con su propia sesión y su propia llave:
//  el reloj funciona sin el iPhone cerca (sección G del brief).
//

import Foundation
import LocalAuthentication
import Observation
import WatchKit

@Observable
final class WatchContainer {
    nonisolated enum LinkState: Equatable {
        case idle
        /// `verification`: el mismo código que muestra el iPhone.
        case linking(verification: String)
        /// Pantalla de "listo" antes de entrar a Inicio.
        case succeeded(verification: String)
        case failed(String)
    }

    let session: SessionStore
    let location: LocationService
    let notifications: NotificationManager
    let visits: VisitsRepository
    let gate: GateRepository
    let panic: PanicRepository
    let residentQR: ResidentQRGenerator

    /// Solo existe con el backend mock.
    let mockServer: MockServer?

    private(set) var linkState: LinkState = .idle
    /// Sube cuando cambian datos fuera de la pantalla actual.
    private(set) var dataVersion = 0

    private let auth: AuthRepository
    private let keys: DeviceKeyManager
    private let descriptor: DeviceDescriptor
    private let link: WatchLinkReceiver

    init(useMockBackend: Bool = AppInfo.usesMockBackend) {
        let keychain = KeychainStore.app
        let deviceId = DeviceIdentity.identifier(in: keychain)
        let descriptor = DeviceDescriptor(id: deviceId, name: WKInterfaceDevice.current().name, model: .watch)
        self.descriptor = descriptor

        // Red: el mismo camino que en el iPhone.
        let config: APIConfig
        let transport: any HTTPTransport
        if useMockBackend {
            let server = MockServer()
            mockServer = server
            config = .mock
            transport = MockTransport(server: server)
        } else {
            mockServer = nil
            config = .staging
            transport = URLSessionTransport()
        }

        let events = SessionEventBus()
        let tokenStore = KeychainTokenStore(keychain: keychain)
        let headers = DefaultHeadersInterceptor(deviceId: deviceId, appVersion: AppInfo.version)
        let refreshClient = APIClient(config: config, transport: transport, interceptors: [headers], maxRetries: 0)
        let authInterceptor = AuthInterceptor(tokenStore: tokenStore, events: events) { refreshToken in
            try await refreshClient.send(API.Auth.refresh(refreshToken)).authTokens()
        }
        let client = APIClient(config: config, transport: transport, interceptors: [headers, authInterceptor])

        // Seguridad: llave propia del reloj, usable solo con el reloj desbloqueado.
        let keys = DeviceKeyManager(keychain: keychain)
        self.keys = keys
        let biometrics = BiometricAuthenticator()
        let signer = RequestSigner(keys: keys, biometrics: biometrics)

        let auth = RemoteAuthRepository(client: client, tokenStore: tokenStore, device: descriptor)
        self.auth = auth
        let visits = RemoteVisitsRepository(client: client, signer: signer)
        self.visits = visits
        let gate = RemoteGateRepository(client: client, signer: signer)
        self.gate = gate
        panic = RemotePanicRepository(client: client, signer: signer)
        let residentQR = ResidentQRGenerator(repository: gate, keychain: keychain)
        self.residentQR = residentQR

        location = LocationService(usesSimulation: useMockBackend)
        notifications = NotificationManager()
        link = WatchLinkReceiver()
        session = SessionStore(
            auth: auth,
            tokenStore: tokenStore,
            keys: keys,
            biometrics: biometrics,
            keychain: keychain,
            events: events
        )

        session.onSignOut = { residentQR.clear() }
        notifications.decisionHandler = { [weak self] visitId, decision in
            do {
                _ = try await visits.decide(visitId, decision: decision)
            } catch {
                self?.notifications.notify(title: "No se aplicó tu respuesta", body: error.userMessage ?? "Inténtalo desde la app.")
            }
            self?.dataDidChange()
        }
        link.onEnvelope = { [weak self] envelope in
            await self?.handle(envelope)
        }
    }

    var usesMockBackend: Bool { mockServer != nil }

    /// Al arrancar: categorías de notificación y canal con el iPhone.
    func start() {
        notifications.configure()
        link.activate()
    }

    func dataDidChange() {
        dataVersion += 1
    }

    // MARK: - Vínculo con el iPhone

    private func handle(_ envelope: WatchEnvelope) async {
        switch envelope {
        case .link(let code, let mockAccount):
            await completeLink(code: code, mockAccount: mockAccount)
        case .unlinked:
            await session.signOut()
        case .simulatedVisit(let visit, let residence):
            guard let mockServer, session.profile != nil else { return }
            await mockServer.importVisit(visit)
            notifications.scheduleSimulatedArrival(visit, residence: residence, after: 1)
            dataDidChange()
        case .linked:
            break
        }
    }

    /// Crea la llave del reloj y canjea el código del iPhone por una sesión
    /// propia. A partir de aquí el reloj ya no necesita al iPhone.
    private func completeLink(code: String, mockAccount: Data?) async {
        if case .linking = linkState { return }
        let verification = WatchVerificationCode.from(linkCode: code)
        linkState = .linking(verification: verification)
        if let mockAccount {
            await mockServer?.importAccount(mockAccount)
        }
        do {
            let publicKey = try keys.createKey(context: LAContext())
            let profile = try await auth.completeWatchLink(
                code: code,
                publicKey: publicKey,
                hardwareBacked: keys.isHardwareBacked
            )
            session.didAuthenticate(profile, returningUser: true)
            session.completeSetup()
            linkState = .succeeded(verification: verification)
            WKInterfaceDevice.current().play(.success)
            await notifications.requestAuthorization()
            link.send(.linked(LinkedWatch(
                userId: profile.id,
                deviceId: descriptor.id,
                name: descriptor.name,
                publicKey: publicKey.base64EncodedString()
            )))
        } catch {
            keys.deleteKey()
            linkState = .failed(error.userMessage ?? "No se pudo vincular. Inténtalo de nuevo desde tu iPhone.")
        }
    }

    /// Cierra la pantalla de "listo" y entra a Inicio.
    func finishLinking() {
        linkState = .idle
    }

    // MARK: - Simulación (solo mock)

    func simulateArrival(kind: AccessKind) async {
        guard let mockServer else { return }
        let visit = await mockServer.simulateArrival(kind: kind)
        notifications.scheduleSimulatedArrival(visit, residence: session.profile?.residence?.name ?? "tu vivienda")
        dataDidChange()
    }
}
