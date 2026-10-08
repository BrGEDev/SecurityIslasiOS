//
//  AccessControls.swift
//  IslasWidgets
//
//  Controles del Centro de control y de las esquinas de la pantalla bloqueada
//  (iOS 18, RF-41, pantalla 31): Abrir pluma, Pánico y Mi QR. Abren la app con
//  el mismo enlace que los widgets: abrir pide Face ID y el pánico abre la
//  pantalla de mantener presionado, nunca envía directo.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct GateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.security.islasgower.control.gate") {
            ControlWidgetButton(action: OpenURLIntent(AppLink.gate.url)) {
                Label("Abrir pluma", systemImage: "road.lanes")
            }
        }
        .displayName("Abrir pluma")
        .description("Abre la pluma o solicita paso cerca de la entrada.")
    }
}

@available(iOS 18.0, *)
struct PanicControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.security.islasgower.control.panic") {
            ControlWidgetButton(action: OpenURLIntent(AppLink.panic.url)) {
                Label("Pánico", systemImage: "exclamationmark.triangle.fill")
            }
            .tint(.red)
        }
        .displayName("Pánico")
        .description("Abre la pantalla de pánico con cuenta regresiva para cancelar.")
    }
}

@available(iOS 18.0, *)
struct MyQRControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.security.islasgower.control.qr") {
            ControlWidgetButton(action: OpenURLIntent(AppLink.qr.url)) {
                Label("Mi QR", systemImage: "qrcode")
            }
        }
        .displayName("Mi QR")
        .description("Muestra tu QR de acceso.")
    }
}
