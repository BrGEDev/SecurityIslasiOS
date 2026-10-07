//
//  NotificationManager.swift
//  SecurityIslas
//
//  Categorías de aviso (sección 5, "Autorizar visita"):
//  • VISITA_PENDIENTE: "Autorizar" pide desbloquear (.authenticationRequired);
//    "Rechazar" funciona con el teléfono bloqueado (RF-02).
//  • VISITA_INFO: invitaciones y recurrentes, informativo y sin botones (RF-14).
//
//  La foto de la visita la descargará la Notification Service Extension
//  (target pendiente). Con el backend mock, Cuenta > Simulación programa un
//  aviso local con la misma categoría.
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
        content.userInfo = ["visitId": visit.id, "kind": visit.kind.rawValue]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: visit.id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let visitId = response.notification.request.content.userInfo["visitId"] as? String
        guard let visitId else { return }
        await handle(action: action, visitId: visitId)
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
