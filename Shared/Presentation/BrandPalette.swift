//
//  BrandPalette.swift
//  SecurityIslas (iPhone y Apple Watch)
//
//  Degradados de la app. El iPhone (tarjeta de la pluma, Mi QR) y el reloj
//  usan los mismos colores para cada estado, así se sienten una sola app.
//

import SwiftUI

nonisolated enum BrandPalette {
    /// Abrir pluma (carril de residentes) y Mi QR.
    static let blue = [Color(red: 0.16, green: 0.55, blue: 1.0), Color(red: 0.0, green: 0.33, blue: 0.86)]
    /// Solicitar paso (carril compartido).
    static let indigo = [Color(red: 0.45, green: 0.38, blue: 0.98), Color(red: 0.27, green: 0.2, blue: 0.78)]
    /// Pluma abierta, autorizar.
    static let green = [Color(red: 0.2, green: 0.78, blue: 0.45), Color(red: 0.05, green: 0.6, blue: 0.35)]
    /// Visita en caseta, solicitud enviada.
    static let orange = [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.92, green: 0.42, blue: 0.1)]
    /// Pánico.
    static let red = [Color(red: 1.0, green: 0.27, blue: 0.23), Color(red: 0.75, green: 0.1, blue: 0.1)]

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Fondo de pantalla del reloj: el color de la marca que se desvanece a
    /// negro, como las apps del sistema en watchOS 10.
    static func backdrop(_ colors: [Color], intensity: Double = 0.55) -> LinearGradient {
        LinearGradient(
            colors: [colors[0].opacity(intensity), colors[colors.count - 1].opacity(intensity * 0.35), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
