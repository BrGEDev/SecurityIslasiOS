//
//  Haptics.swift
//  SecurityIslas
//
//  Respuesta háptica para gestos de "mantener presionado". En lugar de una
//  sola vibración al empezar, el iPhone da golpes que se aceleran y ganan
//  fuerza conforme avanza el progreso (como "mantener para SOS"), y termina
//  con una confirmación clara. Si se suelta antes, se detiene al instante.
//

import SwiftUI
import UIKit

final class HoldHapticRamp {
    private var task: Task<Void, Never>?
    private let impact = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

    /// Inicia la rampa. Intensidad de 0.35 → 1.0 y pausas de 0.30 s → 0.08 s.
    func start(duration: TimeInterval) {
        stop()
        impact.prepare()
        notification.prepare()
        let impact = self.impact
        task = Task {
            let start = Date.now
            while !Task.isCancelled {
                let progress = min(1, Date.now.timeIntervalSince(start) / duration)
                impact.impactOccurred(intensity: 0.35 + 0.65 * progress)
                if progress >= 1 { break }
                // Curva cuadrática: al final los golpes casi se juntan.
                let interval = 0.30 - 0.22 * progress * progress
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Se soltó antes de tiempo.
    func cancel() {
        stop()
    }

    /// Se completó el gesto.
    func complete() {
        stop()
        notification.notificationOccurred(.success)
    }

    private func stop() {
        task?.cancel()
        task = nil
    }
}

/// Mantener presionado con progreso animado y rampa háptica.
struct HoldToConfirmGesture: ViewModifier {
    let duration: TimeInterval
    @Binding var progress: CGFloat
    @Binding var isPressing: Bool
    let onComplete: () -> Void

    @State private var haptics = HoldHapticRamp()

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                haptics.complete()
                progress = 0
                isPressing = false
                onComplete()
            } onPressingChanged: { pressing in
                isPressing = pressing
                if pressing {
                    haptics.start(duration: duration)
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    haptics.cancel()
                    withAnimation(.spring(duration: 0.3)) { progress = 0 }
                }
            }
            .onDisappear { haptics.cancel() }
    }
}

extension View {
    func holdToConfirm(
        duration: TimeInterval,
        progress: Binding<CGFloat>,
        isPressing: Binding<Bool>,
        onComplete: @escaping () -> Void
    ) -> some View {
        modifier(HoldToConfirmGesture(duration: duration, progress: progress, isPressing: isPressing, onComplete: onComplete))
    }
}
