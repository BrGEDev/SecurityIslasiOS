//
//  IslasSecurityApp.swift
//  SecurityIslas
//

import SwiftUI
import UIKit

@main
struct IslasSecurityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, .app)
                .environment(appDelegate.container)
                .environment(appDelegate.container.session)
                .onOpenURL { url in
                    appDelegate.container.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        appDelegate.container.handle(url: url)
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let container = AppContainer()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // El delegado de notificaciones debe quedar antes de terminar el arranque
        // para recibir las acciones Autorizar / Rechazar con la app cerrada.
        container.notifications.configure()
        return true
    }
}
