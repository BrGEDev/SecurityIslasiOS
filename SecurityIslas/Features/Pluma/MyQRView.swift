//
//  MyQRView.swift
//  SecurityIslas
//
//  Pantalla 21 (Mi QR): QR propio para entrar en taxi, a pie o en otro auto;
//  el guardia lo escanea y abre sin pedir autorización (RF-15). Cambia cada
//  30 s y se genera en el teléfono, así funciona sin internet. Identifica al
//  residente; no reemplaza el botón de abrir.
//

import SwiftUI
import UIKit

struct MyQRView: View {
    let profile: UserProfile
    let generator: ResidentQRGenerator

    @State private var seed: QRSeed?
    @State private var errorMessage: String?
    @State private var previousBrightness: CGFloat?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let seed {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let payload = generator.payload(userId: profile.id, seed: seed, date: context.date)
                        let remaining = TOTP.secondsRemaining(date: context.date, period: seed.period)
                        VStack(spacing: 14) {
                            QRImage(payload: payload)
                            HStack(spacing: 6) {
                                CountdownRing(progress: Double(remaining) / Double(seed.period))
                                Text("Cambia en \(remaining) s")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView("Sin código", systemImage: "qrcode", description: Text(errorMessage))
                    AsyncButton("Reintentar") { await loadSeed() }
                } else {
                    ProgressView().frame(height: 280)
                }

                VStack(spacing: 4) {
                    Text(profile.fullName).font(.title3.bold())
                    Text([profile.residence?.name, profile.residence?.fraccionamientoName].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if profile.role == .nonResidentOwner {
                        Text("Acceso de propietario · avisamos al arrendatario")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                FootnoteLabel(text: "Subimos el brillo al abrir esta pantalla.", systemImage: "sun.max")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .readableContentWidth()
        .navigationTitle("Mi QR")
        .task { await loadSeed() }
        .onAppear(perform: raiseBrightness)
        .onDisappear(perform: restoreBrightness)
    }

    private func loadSeed() async {
        do {
            errorMessage = nil
            seed = try await generator.seed()
        } catch {
            errorMessage = error.userMessage
        }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    private func raiseBrightness() {
        guard let screen else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        guard let screen, let previousBrightness else { return }
        screen.brightness = previousBrightness
    }
}

private struct QRImage: View {
    let payload: String

    var body: some View {
        Group {
            if let image = QRCodeRenderer.image(for: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit()
            }
        }
        .frame(width: 240, height: 240)
        .padding(20)
        .background(.white, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityLabel("Tu código QR de acceso")
    }
}

private struct CountdownRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .animation(.linear(duration: 1), value: progress)
    }
}
