//
//  AppContainer.swift
//  SecurityIslas
//
//  Arma el grafo de dependencias una sola vez. Las vistas reciben lo que
//  necesitan desde aquí; ninguna crea clientes de red por su cuenta.
//
//  Para conectar el backend real basta con cambiar el transporte y la
//  configuración (`AppInfo.usesMockBackend`); repositorios, interceptores y
//  vistas no cambian.
//

import Foundation
import Observation
import UIKit

@Observable
final class AppContainer {
    let session: SessionStore
    let location: LocationService
    let notifications: NotificationManager
    let biometrics: BiometricAuthenticator

    let auth: AuthRepository
    let registration: RegistrationRepository
    let devices: DeviceRepository
    let visits: VisitsRepository
    let gate: GateRepository
    let panic: PanicRepository
    let household: HouseholdRepository
    let residentQR: ResidentQRGenerator

    /// Solo existe con el backend mock (menú Cuenta > Simulación).
    let mockServer: MockServer?
    let deviceDescriptor: DeviceDescriptor

    /// Sube cada vez que cambian datos fuera de la pantalla actual (ej. se
    /// respondió una visita desde la notificación) para que las vistas recarguen.
    private(set) var dataVersion = 0

    /// Código de invitación recibido por enlace (Universal Link).
    var pendingInviteCode: String?

    init(useMockBackend: Bool = AppInfo.usesMockBackend) {
        let keychain = KeychainStore.app
        let deviceId = DeviceIdentity.identifier(in: keychain)
        let descriptor = DeviceDescriptor(
            id: deviceId,
            name: UIDevice.current.name,
            model: UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
        )
        deviceDescriptor = descriptor

        // Red
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

        // Cliente sin token, solo para renovar (evita recursión en el interceptor).
        let refreshClient = APIClient(config: config, transport: transport, interceptors: [headers], maxRetries: 0)
        let authInterceptor = AuthInterceptor(tokenStore: tokenStore, events: events) { refreshToken in
            try await refreshClient.send(API.Auth.refresh(refreshToken)).authTokens()
        }
        let client = APIClient(config: config, transport: transport, interceptors: [headers, authInterceptor])

        // Seguridad
        let keys = DeviceKeyManager(keychain: keychain)
        let biometrics = BiometricAuthenticator()
        let signer = RequestSigner(keys: keys, biometrics: biometrics)
        self.biometrics = biometrics

        // Repositorios
        let auth = RemoteAuthRepository(client: client, tokenStore: tokenStore, device: descriptor)
        self.auth = auth
        registration = RemoteRegistrationRepository(client: client)
        devices = RemoteDeviceRepository(
            client: client,
            signer: signer,
            keys: keys,
            biometrics: biometrics,
            descriptor: descriptor
        )
        let visits = RemoteVisitsRepository(client: client, signer: signer)
        self.visits = visits
        let gate = RemoteGateRepository(client: client, signer: signer)
        self.gate = gate
        panic = RemotePanicRepository(client: client, signer: signer)
        household = RemoteHouseholdRepository(client: client, signer: signer)
        let residentQR = ResidentQRGenerator(repository: gate, keychain: keychain)
        self.residentQR = residentQR

        // Servicios
        location = LocationService(usesSimulation: useMockBackend)
        notifications = NotificationManager()
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
                // Ej. ya se respondió en la app o lo hizo otro integrante (409):
                // se avisa en lugar de fallar en silencio.
                self?.notifications.notify(title: "No se aplicó tu respuesta", body: error.userMessage ?? "Ocurrió un error inesperado")
            }
            self?.dataDidChange()
        }
    }

    var usesMockBackend: Bool { mockServer != nil }

    func dataDidChange() {
        dataVersion += 1
    }

    /// `https://acceso.app/i/7KX2` → "7KX2"
    func handle(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count == 2, parts[0] == "i" || parts[0] == "invite" {
            pendingInviteCode = parts[1]
        }
    }
}
