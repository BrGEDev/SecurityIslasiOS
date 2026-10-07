//
//  WatchGateButton.swift
//  SecurityIslasWatch Watch App
//
//  Página "Pluma" del reloj (RF-23, RF-68). Mismas reglas, textos, símbolos y
//  colores que la tarjeta del iPhone: residentes → "Abrir pluma" (azul);
//  carril compartido → "Solicitar paso" (índigo); abierta → verde. No pide
//  Face ID: basta con el reloj puesto y desbloqueado, y la orden va firmada
//  con la llave del reloj.
//

import SwiftUI
import WatchKit

struct WatchGateStyle {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    let isActionable: Bool
    let showsProgress: Bool

    static let neutral = [Color.gray, Color(white: 0.35)]

    init(state: GateButtonState) {
        switch state {
        case .locating:
            self.init("Buscando tu ubicación", "Para saber qué carril te toca", "location", Self.neutral, progress: true)
        case .locationOff:
            self.init("Activa la ubicación", "En Ajustes del reloj", "location.slash", Self.neutral)
        case .ready(let lane, let distance) where lane.type == .residentsOnly:
            self.init("Abrir pluma", "\(Self.format(distance)) · residentes", "lock.open.fill", BrandPalette.blue, actionable: true)
        case .ready(_, let distance):
            self.init("Solicitar paso", "\(Self.format(distance)) · carril compartido", "bell.fill", BrandPalette.indigo, actionable: true)
        case .far(let distance):
            self.init("Lejos de la entrada", "A \(Self.format(distance))", "location", Self.neutral)
        case .working(let lane):
            let residents = lane.type == .residentsOnly
            self.init(residents ? "Abriendo…" : "Enviando…", lane.name, "ellipsis",
                      residents ? BrandPalette.blue : BrandPalette.indigo, progress: true)
        case .opened(let result):
            self.init("Pluma abierta", "\(result.laneName) · \(result.at.shortTime)", "checkmark", BrandPalette.green)
        case .passRequested:
            self.init("Solicitud enviada", "El guardia confirma y abre", "bell.badge.fill", BrandPalette.indigo)
        case .failed(let message):
            self.init("No se pudo abrir", message, "exclamationmark.triangle.fill", BrandPalette.orange)
        }
    }

    private init(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ colors: [Color],
        actionable: Bool = false,
        progress: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.colors = colors
        self.isActionable = actionable
        self.showsProgress = progress
    }

    static func format(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m"
    }
}

struct WatchGatePage: View {
    let model: GateViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let style = WatchGateStyle(state: model.state)
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                Task { await model.trigger() }
            } label: {
                ZStack {
                    if style.isActionable && !reduceMotion {
                        Circle()
                            .stroke(style.colors[0].opacity(0.5), lineWidth: 3)
                            .scaleEffect(pulse ? 1.18 : 1)
                            .opacity(pulse ? 0 : 1)
                    }
                    Circle()
                        .fill(BrandPalette.gradient(style.colors))
                        .shadow(color: style.colors[1].opacity(0.55), radius: 10, y: 4)
                    if style.showsProgress {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: style.symbol)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 96, height: 96)
            }
            .buttonStyle(.plain)
            .disabled(!style.isActionable)
            .accessibilityLabel(style.title)
            .accessibilityHint(style.subtitle)

            VStack(spacing: 2) {
                Text(style.title)
                    .font(.headline)
                    .contentTransition(.opacity)
                Text(style.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: model.state)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .onChange(of: model.state) { _, state in
            switch state {
            case .opened, .passRequested: WKInterfaceDevice.current().play(.success)
            case .failed: WKInterfaceDevice.current().play(.failure)
            default: break
            }
        }
        .task {
            await model.refreshPosition()
        }
    }
}
