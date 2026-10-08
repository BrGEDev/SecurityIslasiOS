//
//  AccessControls.swift
//  IslasWidgets
//
//  Controles del Centro de control y de las esquinas de la pantalla bloqueada
//  (iOS 18, RF-41, pantalla 31): Abrir pluma, Pánico y Mi QR. Abren la app con
//  `OpenAppTargetIntent` (un `OpenIntent` de la app y la extensión; un
//  `OpenURLIntent` con el esquema propio no abría nada): abrir pide Face ID y
//  el pánico inicia la cuenta regresiva cancelable (RF-41).
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct GateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.security.islasgower.control.gate") {
            ControlWidgetButton(action: OpenAppTargetIntent(.gate)) {
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
            ControlWidgetButton(action: OpenAppTargetIntent(.panic)) {
                Label("Pánico", systemImage: "exclamationmark.triangle.fill")
            }
            .tint(.red)
        }
        .displayName("Pánico")
        .description("Inicia la cuenta regresiva del pánico. Puedes cancelarla antes de que se envíe.")
    }
}

@available(iOS 18.0, *)
struct MyQRControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.security.islasgower.control.qr") {
            ControlWidgetButton(action: OpenAppTargetIntent(.qr)) {
                Label("Mi QR", systemImage: "qrcode")
            }
        }
        .displayName("Mi QR")
        .description("Muestra tu QR de acceso.")
    }
}
