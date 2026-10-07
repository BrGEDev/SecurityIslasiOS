//
//  SecurityIslasWatchApp.swift
//  SecurityIslasWatch Watch App
//
//  App independiente del Apple Watch (sección G): avisos de visita con
//  Autorizar / Rechazar, abrir la pluma, Mi QR y pánico, con su propia sesión
//  y su propia llave. El iPhone solo interviene para vincularlo.
//

import SwiftUI
import WatchKit

@main
struct SecurityIslasWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(\.locale, .app)
                .environment(appDelegate.container)
                .environment(appDelegate.container.session)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let container = WatchContainer()

    /// El delegado de notificaciones y WatchConnectivity deben quedar listos
    /// antes de terminar el arranque: así llegan las acciones del aviso y el
    /// código de vínculo aunque la app estuviera cerrada.
    func applicationDidFinishLaunching() {
        container.start()
    }
}
