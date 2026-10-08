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
            VStack(spacing: 20) {
                pass
                    .frame(maxWidth: 380)

                VStack(spacing: 10) {
                    infoRow("Muéstralo al guardia para entrar en taxi, a pie o en otro auto.", systemImage: "car.side")
                    infoRow("Funciona sin internet: el código se genera en tu iPhone.", systemImage: "wifi.slash")
                    infoRow("Subimos el brillo mientras esta pantalla está abierta.", systemImage: "sun.max")
                }
                .frame(maxWidth: 380)

                DismissibleSiriTip(MiQRIntent(), key: "qr")
                    .frame(maxWidth: 380)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .readableContentWidth()
        .navigationTitle("Mi QR")
        .task { await loadSeed() }
        .onAppear(perform: raiseBrightness)
        .onDisappear(perform: restoreBrightness)
    }

    /// Pase con la anatomía de Wallet: cabecera de marca, código sobre blanco
    /// (máximo contraste para el lector de la caseta) y vigencia del código.
    private var pass: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((profile.residence?.fraccionamientoName ?? AppInfo.name).uppercased())
                        .font(.caption.weight(.semibold))
                        .opacity(0.8)
                    Text(profile.role == .nonResidentOwner ? "Pase de propietario" : "Pase de residente")
                        .font(.title3.bold())
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.55, blue: 1.0), Color(red: 0.0, green: 0.3, blue: 0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            VStack(spacing: 16) {
                Group {
                    if let seed {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let payload = generator.payload(userId: profile.id, seed: seed, date: context.date)
                            let remaining = TOTP.secondsRemaining(date: context.date, period: seed.period)
                            VStack(spacing: 14) {
                                QRImage(payload: payload)
                                    .id(payload)
                                    .transition(.opacity)
                                HStack(spacing: 6) {
                                    CountdownRing(progress: Double(remaining) / Double(seed.period))
                                    Text("Se renueva en \(remaining) s")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                        .contentTransition(.numericText(countsDown: true))
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: payload)
                        }
                    } else if let errorMessage {
                        ContentUnavailableView("Sin código", systemImage: "qrcode", description: Text(errorMessage))
                        AsyncButton("Reintentar") { await loadSeed() }
                            .buttonStyle(.islasSecondary)
                    } else {
                        ProgressView().frame(height: 260)
                    }
                }
                .padding(.top, 20)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TITULAR").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(profile.fullName).font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("VIVIENDA").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(profile.residence?.name ?? "—").font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
    }

    private func infoRow(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .labelStyle(.alignedIcon)
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
        .frame(width: 220, height: 220)
        .padding(14)
        // Siempre blanco, también en modo oscuro: los lectores lo necesitan.
        .background(.white, in: .rect(cornerRadius: 16, style: .continuous))
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
