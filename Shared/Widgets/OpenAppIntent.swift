//
//  OpenAppIntent.swift
//  SecurityIslas (app y widgets de iPhone)
//
//  Controles del Centro de control, pantalla bloqueada y botón de Acción
//  (iOS 18): para que un control abra la app tiene que usar un `OpenIntent`
//  que pertenezca a la app y a la extensión de widgets. Por eso vive en
//  `Shared`. El sistema lo ejecuta en el proceso de la app, que atiende el
//  enlace con las mismas reglas que los widgets (`AppLink`).
//

#if os(iOS)
import AppIntents
import Foundation

nonisolated enum AppLinkTarget: String, AppEnum {
    case gate
    case panic
    case qr

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pantalla"
    static let caseDisplayRepresentations: [AppLinkTarget: DisplayRepresentation] = [
        .gate: "Abrir pluma",
        .panic: "Pánico",
        .qr: "Mi QR",
    ]

    var link: AppLink {
        switch self {
        case .gate: .gate
        case .panic: .panic
        case .qr: .qr
        }
    }
}

/// Lo conecta la app al arrancar; en el proceso del widget queda en `nil`.
@MainActor
enum AppLinkHandler {
    static var open: ((AppLink) -> Void)?
}

struct OpenAppTargetIntent: OpenIntent {
    static let title: LocalizedStringResource = "Abrir en Islas Security"
    static let isDiscoverable = false

    @Parameter(title: "Pantalla")
    var target: AppLinkTarget

    init() {}

    init(_ target: AppLinkTarget) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLinkHandler.open?(target.link)
        return .result()
    }
}
#endif
