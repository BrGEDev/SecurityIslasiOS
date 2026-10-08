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
    /// Una sola instancia por proceso: la usan la app y los App Intents, que
    /// pueden ejecutarse sin que aparezca ninguna vista.
    static let shared = AppContainer()

    let session: SessionStore
    let location: LocationService
    let notifications: NotificationManager
    let biometrics: BiometricAuthenticator
    /// Vínculo con el Apple Watch (solo la sesión inicial).
    let watch: PhoneWatchBridge

    let auth: AuthRepository
    let registration: RegistrationRepository
    let devices: DeviceRepository
    let visits: VisitsRepository
    let gate: GateRepository
    let panic: PanicRepository
    let household: HouseholdRepository
    let residentQR: ResidentQRGenerator
    /// Token de APNs de este iPhone.
    let push: PushRegistrar
    /// Caché sin red (SwiftData) de visitas, recurrentes, invitaciones e historial.
    let offlineCache: OfflineCache
    /// Live Activity de las visitas en caseta (pantallas 11 y 12).
    let liveActivities: VisitActivityController

    /// Solo existe con el backend mock (menú Cuenta > Simulación).
    let mockServer: MockServer?
    let deviceDescriptor: DeviceDescriptor

    /// Sube cada vez que cambian datos fuera de la pantalla actual (ej. se
    /// respondió una visita desde la notificación) para que las vistas recarguen.
    private(set) var dataVersion = 0

    /// Código de invitación recibido por enlace (Universal Link).
    var pendingInviteCode: String?

    /// Visita que hay que mostrar porque se tocó su aviso.
    var visitToOpen: String?

    /// Pedidos de Siri, widgets y controles para la interfaz.
    var panicRequest: PanicEntry?
    var tabRequest: MainTab?
    /// Abrir pluma desde un widget, control o complicación (pide Face ID).
    var gateRequest = false

    init(useMockBackend: Bool = AppInfo.usesMockBackend) {
        let keychain = KeychainStore.app
        // Pruebas de UI (`-uiTesting YES`): empiezan sin sesión y con el
        // backend de prueba recién sembrado.
        if useMockBackend, UserDefaults.standard.bool(forKey: "uiTesting") {
            UserDefaults.standard.removeObject(forKey: MockSettings.stateKey)
            for key in ["session.tokens", "session.profile", "resident.qr.seed"] {
                keychain.delete(key)
            }
            DeviceKeyManager(keychain: keychain).deleteKey()
            UserDefaults.standard.set(SimulatedPosition.nearResidentsLane.rawValue, forKey: "mock.simulatedPosition")
        }
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
            descriptor: descriptor,
            attester: AppAttester(client: client, keychain: keychain)
        )
        let offlineCache = OfflineCache()
        self.offlineCache = offlineCache
        let visits = CachedVisitsRepository(
            remote: RemoteVisitsRepository(client: client, signer: signer),
            cache: offlineCache
        )
        self.visits = visits
        let gate = RemoteGateRepository(client: client, signer: signer)
        self.gate = gate
        panic = RemotePanicRepository(client: client, signer: signer)
        household = RemoteHouseholdRepository(client: client, signer: signer)
        let residentQR = ResidentQRGenerator(repository: gate, keychain: keychain)
        self.residentQR = residentQR
        let push = PushRegistrar(devices: devices)
        self.push = push
        let liveActivities = VisitActivityController(visits: visits, push: push)
        self.liveActivities = liveActivities

        // Servicios
        location = LocationService(usesSimulation: useMockBackend)
        notifications = NotificationManager()
        let watch = PhoneWatchBridge()
        self.watch = watch
        session = SessionStore(
            auth: auth,
            tokenStore: tokenStore,
            keys: keys,
            biometrics: biometrics,
            keychain: keychain,
            events: events
        )

        session.onSignOut = {
            residentQR.clear()
            push.sessionDidChange(userId: nil)
            offlineCache.clear()
            liveActivities.endAll()
            WidgetSnapshotStore.clear()
            // El reloj usa su propia sesión, pero al cerrar la del iPhone
            // también se desvincula para no dejarlo abierto sin querer.
            watch.sendIfPossible(.unlinked)
        }
        let mockServer = self.mockServer
        watch.onLinked = { [weak self] linked in
            await mockServer?.importLinkedWatch(linked)
            self?.dataDidChange()
        }
        watch.activate()
        // Botones del aviso, de la Live Activity y del widget: mismo camino.
        notifications.decisionHandler = { [weak self] visitId, decision in
            await self?.respondOutsideApp(visitId, decision)
        }
        VisitDecisionHandler.decide = { [weak self] visitId, decision in
            await self?.respondOutsideApp(visitId, decision)
        }
        // Respuestas dentro de la app (Inicio, Visitas, Siri): cierran la
        // actividad y el aviso de esa visita.
        visits.onDecision = { [weak self] visit, decision in
            NotificationManager.withdraw(visitId: visit.id)
            Task {
                await self?.liveActivities.end(
                    visitId: visit.id,
                    phase: decision == .authorize ? .authorized : .rejected,
                    respondedBy: nil
                )
            }
        }
        liveActivities.observePushToStartToken()
        // Controles del Centro de control (OpenAppTargetIntent).
        AppLinkHandler.open = { [weak self] link in
            self?.handle(url: link.url)
        }
        notifications.openHandler = { [weak self] visitId in
            self?.visitToOpen = visitId
        }
        notifications.presentHandler = { [weak self] push in
            self?.handleRemote(push)
        }
    }

    var usesMockBackend: Bool { mockServer != nil }

    /// Visitas con una respuesta en camino: un segundo toque (o el mismo botón
    /// en el aviso y en la isla) no vuelve a enviarla.
    @ObservationIgnored private var respondingVisitIds: Set<String> = []

    /// Autorizar / Rechazar desde la Live Activity, el widget o el aviso.
    /// 1. Quita los botones de la actividad al instante ("Autorizando…").
    /// 2. Envía la respuesta una sola vez.
    /// 3. Muestra el resultado y cierra la actividad a los pocos segundos.
    /// Si otro integrante ya respondió (409), la actividad dice quién, sin
    /// mandar avisos extra. Si falla la red, vuelven los botones y se avisa.
    /// Todo se espera antes de regresar: el sistema puede suspender la app en
    /// cuanto termina el intent.
    func respondOutsideApp(_ visitId: String, _ decision: VisitDecision) async {
        guard respondingVisitIds.insert(visitId).inserted else { return }
        defer { respondingVisitIds.remove(visitId) }

        await liveActivities.showResponding(visitId: visitId, decision: decision)
        do {
            _ = try await visits.decide(visitId, decision: decision)
            NotificationManager.withdraw(visitId: visitId)
            await liveActivities.end(visitId: visitId, phase: decision == .authorize ? .authorized : .rejected, respondedBy: nil)
        } catch let error as APIError where error.serverCode == "ALREADY_RESPONDED" {
            NotificationManager.withdraw(visitId: visitId)
            let visit = try? await visits.today().first { $0.id == visitId }
            let phase: VisitActivityAttributes.ContentState.Phase = switch visit?.status {
            case .rejected: .rejected
            case .noResponse, .expired, .canceled: .noResponse
            default: .authorized
            }
            await liveActivities.end(visitId: visitId, phase: phase, respondedBy: visit?.respondedBy ?? "Otro integrante")
        } catch {
            await liveActivities.restoreWaiting(visitId: visitId)
            notifications.notify(title: "No se envió tu respuesta", body: error.userMessage ?? "Inténtalo de nuevo.")
        }
        dataDidChange()
    }

    func dataDidChange() {
        dataVersion += 1
    }

    /// Push recibido con la app abierta o en segundo plano (incluye los
    /// silenciosos). Regresa si hubo datos nuevos.
    @discardableResult
    func handleRemote(_ push: RemotePush) -> Bool {
        switch push {
        case .pendingVisit, .visitInfo:
            dataDidChange()
            return true
        case .visitResponded(let visitId, let visitName, let decision, let respondedBy):
            // Otro integrante respondió primero (RF-06): el aviso ya no sirve
            // y se avisa quién respondió.
            NotificationManager.withdraw(visitId: visitId)
            let phase: VisitActivityAttributes.ContentState.Phase =
                decision == .authorize ? .authorized : decision == .reject ? .rejected : .noResponse
            Task { await liveActivities.end(visitId: visitId, phase: phase, respondedBy: respondedBy) }
            if let respondedBy, let decision {
                let verb = decision == .authorize ? "autorizó" : "rechazó"
                notifications.notify(
                    title: "\(respondedBy) ya respondió",
                    body: "\(respondedBy) \(verb) \(visitName.map { "a \($0)" } ?? "la visita")."
                )
            }
            dataDidChange()
            return true
        case .unknown:
            return false
        }
    }

    /// Lo que se acaba de cargar en Inicio: alimenta los widgets y las Live
    /// Activities de las visitas en caseta.
    func publishHome(_ summary: HomeSummary, profile: UserProfile, gate: GateButtonState) {
        let snapshotGate: WidgetSnapshot.GateState
        var distance: Int?
        switch gate {
        case .ready(let lane, let meters):
            snapshotGate = lane.type == .residentsOnly ? .open : .requestPass
            distance = meters
        case .far(let meters):
            snapshotGate = .far
            distance = meters
        default:
            snapshotGate = .unavailable
        }
        let pending = profile.canAuthorizeVisits ? summary.pendingVisits : []
        WidgetSnapshotStore.save(WidgetSnapshot(
            fraccionamiento: profile.residence?.fraccionamientoName ?? AppInfo.name,
            pending: pending.map {
                WidgetSnapshot.PendingVisit(
                    id: $0.id, name: $0.name, initials: $0.initials, kind: $0.kind,
                    arrivedAt: $0.arrivedAt, respondBy: $0.responseDeadline,
                    heldByAdministration: $0.isHeldByAdministration
                )
            },
            gate: profile.canUseGate ? snapshotGate : .unavailable,
            distance: distance,
            canAuthorizeVisits: profile.canAuthorizeVisits,
            canUseGate: profile.canUseGate,
            updatedAt: .now
        ))
        liveActivities.sync(pending: pending, residence: profile.residence?.name ?? "tu vivienda")
    }

    /// `https://acceso.app/i/7KX2` → "7KX2"
    /// `islassecurity://gate|panic|qr|visits` (widgets, controles y complicaciones)
    func handle(url: URL) {
        if let link = AppLink(url: url) {
            switch link {
            case .gate: gateRequest = true
            case .panic: panicRequest = .countdown
            case .qr: tabRequest = .qr
            case .visits: tabRequest = .visits
            }
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count == 2, parts[0] == "i" || parts[0] == "invite" {
            pendingInviteCode = parts[1]
        }
    }
}
