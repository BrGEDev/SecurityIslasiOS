//
//  WatchQRView.swift
//  SecurityIslasWatch Watch App
//
//  Pantalla 41 (Reloj: Mi QR): el mismo QR del residente, generado en el reloj
//  y sin internet (RF-15). Cambia cada 30 s; un anillo alrededor muestra el
//  tiempo que le queda. Identifica al residente ante el guardia; no reemplaza
//  el botón de abrir.
//

import SwiftUI

struct WatchQRPage: View {
    let userId: String
    let name: String

    @Environment(WatchContainer.self) private var container
    @State private var seed: QRSeed?
    @State private var failed = false

    var body: some View {
        Group {
            if let seed {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let payload = container.residentQR.payload(userId: userId, seed: seed, date: context.date)
                    let remaining = TOTP.secondsRemaining(date: context.date, period: seed.period)
                    VStack(spacing: 6) {
                        QRCodeView(payload: payload)
                            // Margen blanco (zona de silencio) para que el lector lo encuentre.
                            .padding(10)
                            .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(seed.period))
                                    .stroke(BrandPalette.blue[0], style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .padding(-3)
                                    .animation(.linear(duration: 1), value: remaining)
                            }
                            .accessibilityLabel("Código QR de acceso de \(name)")
                        Text("Cambia en \(remaining) s")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .padding(.horizontal, 10)
                }
            } else if failed {
                WatchMessageView(
                    systemImage: "wifi.slash",
                    title: "Sin QR todavía",
                    message: "Conéctate una vez a internet para descargarlo. Después funciona sin conexión."
                )
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                seed = try await container.residentQR.seed()
            } catch {
                failed = true
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
            let cell = floor(min(size.width, size.height) / CGFloat(matrix.size))
            let side = cell * CGFloat(matrix.size)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            var path = Path()
            for y in 0..<matrix.size {
                for x in 0..<matrix.size where matrix.isDark(x: x, y: y) {
                    path.addRect(CGRect(
                        x: origin.x + CGFloat(x) * cell,
                        y: origin.y + CGFloat(y) * cell,
                        width: cell,
                        height: cell
                    ))
                }
            }
            context.fill(path, with: .color(.black))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
