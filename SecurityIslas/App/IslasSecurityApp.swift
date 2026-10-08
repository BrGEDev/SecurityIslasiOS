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
    let container = AppContainer.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // El delegado de notificaciones debe quedar antes de terminar el arranque
        // para recibir las acciones Autorizar / Rechazar con la app cerrada.
        container.notifications.configure()
        // APNs directo. Registrar en cada arranque no muestra ningún permiso:
        // solo entrega el token (que puede cambiar). El permiso de avisos se
        // pide en la pantalla 7.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        container.push.didReceive(alertToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // En el simulador sin APNs o sin red: se reintenta en el próximo arranque.
    }

    /// Push silencioso (`content-available`), por ejemplo "otro integrante ya
    /// respondió" (RF-06).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let push = RemotePush(userInfo: userInfo)
        let changed = container.handleRemote(push)
        completionHandler(changed ? .newData : .noData)
    }
}
