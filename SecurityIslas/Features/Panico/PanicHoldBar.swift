//
//  PanicHoldBar.swift
//  SecurityIslas
//
//  "Mantén presionado para pánico" (pantalla 9): se activa manteniendo
//  presionado 3 s y abre la cuenta regresiva cancelable (RF-40).
//

import SwiftUI

struct PanicHoldBar: View {
    static let holdDuration: Double = 3

    let onComplete: () -> Void
    /// VoiceOver no puede mantener presionado: abre la pantalla de pánico.
    let onAccessibilityActivate: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isPressing = false

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.red)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color(red: 0.6, green: 0, blue: 0))
                    .frame(width: proxy.size.width * progress)
            }
            Label(isPressing ? "Sigue presionando…" : "Mantén presionado para pánico", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 50)
        .clipShape(Capsule())
        .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 40) {
            progress = 0
            isPressing = false
            onComplete()
        } onPressingChanged: { pressing in
            isPressing = pressing
            if pressing {
                withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: isPressing) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Botón de pánico")
        .accessibilityHint("Mantén presionado tres segundos para enviar una alerta.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAccessibilityActivate() }
    }
}
