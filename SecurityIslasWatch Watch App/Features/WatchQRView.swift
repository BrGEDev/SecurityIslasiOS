//
//  WatchQRView.swift
//  SecurityIslasWatch Watch App
//
//  Pantalla 41 (Reloj: Mi QR): el mismo QR del residente, generado en el reloj
//  y sin internet (RF-15). Cambia cada 30 s. Identifica al residente ante el
//  guardia; no reemplaza el botón de abrir.
//

import SwiftUI

struct WatchQRView: View {
    let userId: String
    let name: String

    @Environment(WatchContainer.self) private var container
    @State private var seed: QRSeed?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let seed {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let payload = container.residentQR.payload(userId: userId, seed: seed, date: context.date)
                    let remaining = TOTP.secondsRemaining(date: context.date, period: seed.period)
                    VStack(spacing: 6) {
                        QRCodeView(payload: payload)
                            .accessibilityLabel("Código QR de acceso de \(name)")
                        Text("CAMBIA EN \(remaining) S")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
            } else if let errorMessage {
                WatchMessageView(systemImage: "wifi.slash", title: "Sin QR todavía", message: errorMessage)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Mi QR")
        .task {
            do {
                seed = try await container.residentQR.seed()
            } catch {
                errorMessage = "Conéctate una vez a internet para descargar tu QR. Después funciona sin conexión."
            }
        }
    }
}

/// Dibuja el QR con `Canvas`; el reloj no tiene CoreImage.
struct QRCodeView: View {
    let payload: String

    var body: some View {
        let matrix = QRCodeMatrix(text: payload)
        Canvas { context, size in
            guard let matrix else { return }
            let quietZone = 2
            let cells = matrix.size + quietZone * 2
            let cell = floor(min(size.width, size.height) / CGFloat(cells))
            let side = cell * CGFloat(cells)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.fill(Path(CGRect(origin: origin, size: CGSize(width: side, height: side))), with: .color(.white))
            var path = Path()
            for y in 0..<matrix.size {
                for x in 0..<matrix.size where matrix.isDark(x: x, y: y) {
                    path.addRect(CGRect(
                        x: origin.x + CGFloat(x + quietZone) * cell,
                        y: origin.y + CGFloat(y + quietZone) * cell,
                        width: cell,
                        height: cell
                    ))
                }
            }
            context.fill(path, with: .color(.black))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
    }
}
