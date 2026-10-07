//
//  AppInfo.swift
//  SecurityIslas
//

import Foundation

nonisolated enum AppInfo {
    /// Nombre provisional del producto (brief, sección 9). Va también en las
    /// frases de Siri: cámbialo solo aquí.
    static let name = "Acceso"

    /// Dominio de los enlaces de invitación (de ejemplo).
    static let inviteHost = "acceso.app"

    static let adminPhone = "+522221000000"

    /// Grupo de Keychain compartido con widgets y extensiones. `nil` hasta que
    /// se active Keychain Sharing en los targets (ver DECISIONES.md).
    static let keychainAccessGroup: String? = nil

    /// Va en el encabezado `X-Client`.
    #if os(watchOS)
    static let platform = "watchos"
    #else
    static let platform = "ios"
    #endif

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// `mock` mientras no exista el backend. Para apuntar al real, lanza la app
    /// con el argumento `-useLiveAPI YES`.
    static var usesMockBackend: Bool {
        !UserDefaults.standard.bool(forKey: "useLiveAPI")
    }
}
