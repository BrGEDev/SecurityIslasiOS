//
//  NotificationManager.swift
//  SecurityIslas
//
//  Categorías de aviso (sección 5, "Autorizar visita"):
//  • VISITA_PENDIENTE: "Autorizar" pide desbloquear (.authenticationRequired);
//    "Rechazar" funciona con el teléfono bloqueado (RF-02).
//  • VISITA_INFO: invitaciones y recurrentes, informativo y sin botones (RF-14).
//
//  El push real llega por APNs (`PushRegistrar`); la foto la adjunta la
//  Notification Service Extension. Con el backend mock, Cuenta > Simulación
//  programa un aviso local con la misma categoría y el mismo `userInfo`.
//

import Foundation
import Observation
import UserNotifications

nonisolated enum NotificationCategory {
    static let pendingVisit = "VISITA_PENDIENTE"
    static let visitInfo = "VISITA_INFO"
    static let authorizeAction = "AUTORIZAR"
    static let rejectAction = "RECHAZAR"
}

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Lo conecta AppContainer con VisitsRepository.
    @ObservationIgnored var decisionHandler: ((String, VisitDecision) async -> Void)?
    /// Se llama cuando el usuario toca el aviso (sin elegir botón).
    @ObservationIgnored var openHandler: ((String) -> Void)?
    /// Llegó un aviso con la app en primer plano (para recargar los datos).
    @ObservationIgnored var presentHandler: ((RemotePush) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let authorize = UNNotificationAction(
            identifier: NotificationCategory.authorizeAction,
            title: "Autorizar",
            options: [.authenticationRequired]
        )
        let reject = UNNotificationAction(
            identifier: NotificationCategory.rejectAction,
            title: "Rechazar",
            options: [.destructive]
        )
        let pending = UNNotificationCategory(
            identifier: NotificationCategory.pendingVisit,
            actions: [reject, authorize],
            intentIdentifiers: [],
            options: []
        )
        let info = UNNotificationCategory(
            identifier: NotificationCategory.visitInfo,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([pending, info])
        refreshStatus()
    }

    func refreshStatus() {
        center.getNotificationSettings { @Sendable [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.authorization = status
            }
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable granted, _ in
                continuation.resume(returning: granted)
            }
        }
        refreshStatus()
        return granted
    }

    /// Aviso local que imita el push VISITA_PENDIENTE (solo con backend mock).
    func scheduleSimulatedArrival(_ visit: Visit, residence: String, after seconds: TimeInterval = 5) {
        let content = UNMutableNotificationContent()
        content.title = "\(visit.kind.title) en caseta · \(residence)"
        content.body = "\(visit.name) quiere entrar. Mantén presionado para responder."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.pendingVisit
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["type": "visit.pending", "visitId": visit.id, "kind": visit.kind.rawValue]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: visit.id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    /// Quita el aviso de una visita ya respondida (en la app o desde otro
    /// dispositivo) para que no se pueda volver a contestar desde ahí.
    nonisolated static func withdraw(visitId: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [visitId])
        center.removeDeliveredNotifications(withIdentifiers: [visitId])
    }

    /// Aviso informativo inmediato, por ejemplo cuando una respuesta dada
    /// desde la notificación no se pudo aplicar.
    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = NotificationCategory.visitInfo
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Se usan las variantes con completion handler y no las `async`: iOS llama
    // al delegado fuera del hilo principal y el puente de la variante `async`
    // invoca el handler desde un hilo de fondo, lo que hace que UIKit truene
    // ("Call must be made on main thread") al responder desde el aviso.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let push = RemotePush(userInfo: notification.request.content.userInfo)
        Task { @MainActor [weak self] in
            self?.presentHandler?(push)
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let visitId = response.notification.request.content.userInfo["visitId"] as? String
        nonisolated(unsafe) let completion = completionHandler
        Task { @MainActor [weak self] in
            if let self, let visitId {
                await self.handle(action: action, visitId: visitId)
            }
            completion()
        }
    }

    private func handle(action: String, visitId: String) async {
        switch action {
        case NotificationCategory.authorizeAction:
            await decisionHandler?(visitId, .authorize)
        case NotificationCategory.rejectAction:
            await decisionHandler?(visitId, .reject)
        default:
            openHandler?(visitId)
        }
    }
}
