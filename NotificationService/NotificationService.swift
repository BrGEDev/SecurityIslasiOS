//
//  NotificationService.swift
//  NotificationService
//
//  Push VISITA_PENDIENTE (fase 1): descarga la foto que tomó el guardia y la
//  adjunta al aviso, y deja claro si es Visita o Servicio (siempre se
//  distinguen, sección 3). Campos supuestos del push: `visitId`, `kind`
//  (visit | service), `photoURL` y `residence` (ver DECISIONES.md).
//
//  La URL de la foto debe ser firmada y de corta vida (no lleva el token de la
//  sesión): la extensión no tiene acceso a la sesión de la app.
//

import UniformTypeIdentifiers
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        let userInfo = content.userInfo
        let isService = (userInfo["kind"] as? String) == "service"
        // "Visita en caseta · Retorno Encino 24" / "Servicio en caseta · …"
        if content.subtitle.isEmpty {
            content.subtitle = isService ? "Servicio" : "Visita"
        }
        if content.title.isEmpty {
            let residence = (userInfo["residence"] as? String).map { " · \($0)" } ?? ""
            content.title = (isService ? "Servicio en caseta" : "Visita en caseta") + residence
        }
        content.interruptionLevel = .timeSensitive

        guard let photo = (userInfo["photoURL"] as? String).flatMap(URL.init(string:)), photo.scheme == "https" else {
            contentHandler(content)
            return
        }

        let task = URLSession.shared.downloadTask(with: photo) { [weak self] location, response, _ in
            guard let self else { return }
            if let location,
               let attachment = Self.attachment(from: location, response: response) {
                content.attachments = [attachment]
            }
            self.deliver()
        }
        downloadTask = task
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // Sin foto a tiempo: el aviso sale con el texto, que es lo importante.
        downloadTask?.cancel()
        deliver()
    }

    private func deliver() {
        guard let contentHandler, let bestAttemptContent else { return }
        self.contentHandler = nil
        contentHandler(bestAttemptContent)
    }

    /// Mueve la descarga a un archivo con extensión: los adjuntos necesitan el
    /// tipo para mostrarse.
    private static func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
        let mime = (response as? HTTPURLResponse)?.mimeType ?? "image/jpeg"
        let type = UTType(mimeType: mime) ?? .jpeg
        guard type.conforms(to: .image) else { return nil }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(type.preferredFilenameExtension ?? "jpg")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            return try UNNotificationAttachment(identifier: "visit-photo", url: destination)
        } catch {
            return nil
        }
    }
}
