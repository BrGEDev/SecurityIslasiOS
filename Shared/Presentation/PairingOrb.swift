//
//  PairingOrb.swift
//  SecurityIslas (iPhone y Apple Watch)
//
//  Animación del vínculo con el Apple Watch, inspirada en la configuración del
//  reloj en el iPhone: un anillo de color que gira con partículas en órbita
//  alrededor del reloj; al terminar se vuelve una palomita verde. Respeta
//  "Reducir movimiento".
//

import SwiftUI

struct PairingOrb: View {
    nonisolated enum Phase: Equatable {
        /// Esperando (instrucciones, instalar la app).
        case idle
        /// Intercambiando el código y creando la llave.
        case linking
        case done
    }

    var phase: Phase = .idle
    var size: CGFloat = 220
    var symbol = "applewatch"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [.blue, .purple, .pink, .orange, .teal]
    private let particleCount = 16

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || phase == .done)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                glow
                if phase != .done {
                    ring(time: time)
                    ForEach(0..<particleCount, id: \.self) { index in
                        particle(index: index, time: time)
                    }
                }
                center
            }
            .frame(width: size, height: size)
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var glow: some View {
        Circle()
            .fill(RadialGradient(
                colors: [(phase == .done ? Color.green : Color.blue).opacity(0.35), .clear],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            ))
    }

    private func ring(time: TimeInterval) -> some View {
        let speed: Double = phase == .linking ? 140 : 45
        return Circle()
            .strokeBorder(
                AngularGradient(
                    colors: Self.colors + [Self.colors[0]],
                    center: .center,
                    angle: .degrees((time * speed).truncatingRemainder(dividingBy: 360))
                ),
                lineWidth: size * 0.035
            )
            .padding(size * 0.08)
            .opacity(phase == .linking ? 1 : 0.75)
    }

    private func particle(index: Int, time: TimeInterval) -> some View {
        let fraction = Double(index) / Double(particleCount)
        let direction: Double = index.isMultiple(of: 2) ? 1 : -0.7
        let speed = phase == .linking ? 1.6 : 0.5
        let angle = fraction * 2 * .pi + time * speed * direction
        let wobble = sin(time * 1.4 + Double(index)) * 0.05
        let radius = Double(size) * (0.32 + wobble)
        let dot = size * (index.isMultiple(of: 3) ? 0.04 : 0.025)
        return Circle()
            .fill(Self.colors[index % Self.colors.count])
            .frame(width: dot, height: dot)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            .opacity(0.45 + 0.55 * abs(sin(time * 1.8 + Double(index))))
    }

    private var center: some View {
        ZStack {
            Circle()
                .fill(phase == .done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Material.regular))
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: .black.opacity(0.15), radius: size * 0.04, y: size * 0.02)
            Image(systemName: phase == .done ? "checkmark" : symbol)
                .font(.system(size: size * 0.18, weight: .semibold))
                .foregroundStyle(phase == .done ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace))
        }
        .scaleEffect(phase == .done ? 1.08 : 1)
    }

    private var accessibilityText: String {
        switch phase {
        case .idle: "Apple Watch"
        case .linking: "Vinculando Apple Watch"
        case .done: "Apple Watch vinculado"
        }
    }
}
