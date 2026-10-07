//
//  PanicHoldBar.swift
//  SecurityIslas
//
//  Botón de pánico de Inicio (pantalla 9): se mantiene presionado 3 s y abre
//  la cuenta regresiva cancelable (RF-40). El relleno avanza mientras se
//  presiona y vibra al empezar; al soltar antes de tiempo, regresa.
//

import SwiftUI

struct PanicHoldBar: View {
    static let holdDuration: Double = 3

    let onComplete: () -> Void
    /// VoiceOver no puede mantener presionado: abre la pantalla de pánico.
    let onAccessibilityActivate: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sos")
                .font(.system(size: height * 0.26, weight: .heavy))
                .foregroundStyle(.red)
                .frame(width: height - 12, height: height - 12)
                .background(.white, in: Circle())
                .scaleEffect(isPressing ? 0.92 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(isPressing ? "Sigue presionando…" : "Pánico")
                    .font(.body.weight(.semibold))
                Text(isPressing ? "Suelta para cancelar" : "Mantén presionado 3 segundos")
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .contentTransition(.opacity)

            Spacer(minLength: 0)

            Image(systemName: "hand.tap.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
                .symbolEffect(.pulse, isActive: isPressing)
                .padding(.trailing, 8)
        }
        .padding(6)
        .frame(height: height)
        .background {
            ZStack(alignment: .leading) {
                if #available(iOS 26, *) {
                    Capsule().fill(.clear).glassEffect(.regular.tint(.red), in: Capsule())
                } else {
                    Capsule().fill(Color.red.gradient)
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(.black.opacity(0.22))
                        .frame(width: max(height, proxy.size.width * progress))
                        .opacity(progress > 0 ? 1 : 0)
                }
            }
        }
        .clipShape(Capsule())
        .shadow(color: .red.opacity(0.3), radius: 12, y: 6)
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
                withAnimation(.spring(duration: 0.3)) { progress = 0 }
            }
        }
        .animation(.spring(duration: 0.25), value: isPressing)
        .sensoryFeedback(.impact(weight: .heavy), trigger: isPressing) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Botón de pánico")
        .accessibilityHint("Mantén presionado tres segundos para enviar una alerta.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAccessibilityActivate() }
    }
}

// MARK: - Accesorio inferior (iOS 26)

/// Pánico como accesorio de la barra de pestañas, igual que el mini reproductor
/// de Apple Music: expandido sobre las pestañas y compacto junto a ellas cuando
/// la barra se minimiza al hacer scroll. Se mantiene presionado igual (3 s).
@available(iOS 26, *)
struct PanicAccessoryView: View {
    let onComplete: () -> Void
    let onAccessibilityActivate: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var progress: CGFloat = 0
    @State private var isPressing = false

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sos.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .font(isInline ? .title3 : .title2)
                .scaleEffect(isPressing ? 0.9 : 1)

            if isInline {
                Text(isPressing ? "Sigue…" : "Pánico")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isPressing ? "Sigue presionando…" : "Pánico")
                        .font(.subheadline.weight(.semibold))
                    Text(isPressing ? "Suelta para cancelar" : "Mantén presionado 3 segundos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: isPressing)
            }
        }
        .padding(.horizontal, isInline ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.red.opacity(0.28))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.25), value: isPressing)
        .modifier(PanicHoldGesture(progress: $progress, isPressing: $isPressing, onComplete: onComplete))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Botón de pánico")
        .accessibilityHint("Mantén presionado tres segundos para enviar una alerta.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAccessibilityActivate() }
    }
}

/// Mantener presionado 3 s con relleno de progreso y vibración al empezar.
struct PanicHoldGesture: ViewModifier {
    @Binding var progress: CGFloat
    @Binding var isPressing: Bool
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: PanicHoldBar.holdDuration, maximumDistance: 40) {
                progress = 0
                isPressing = false
                onComplete()
            } onPressingChanged: { pressing in
                isPressing = pressing
                if pressing {
                    withAnimation(.linear(duration: PanicHoldBar.holdDuration)) { progress = 1 }
                } else {
                    withAnimation(.spring(duration: 0.3)) { progress = 0 }
                }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: isPressing) { _, new in new }
    }
}

extension View {
    /// iOS 26: pánico como accesorio de la barra de pestañas, que se compacta al
    /// hacer scroll (como Apple Music). Antes no hace nada: Inicio muestra la
    /// barra `PanicHoldBar` al pie.
    @ViewBuilder
    func panicTabAccessory(onComplete: @escaping () -> Void, onAccessibilityActivate: @escaping () -> Void) -> some View {
        if #available(iOS 26, *) {
            self
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    PanicAccessoryView(onComplete: onComplete, onAccessibilityActivate: onAccessibilityActivate)
                }
        } else {
            self
        }
    }

    /// Barra de pánico al pie de Inicio solo antes de iOS 26 (después vive en
    /// el accesorio de la barra de pestañas).
    @ViewBuilder
    func legacyPanicBar(onComplete: @escaping () -> Void, onAccessibilityActivate: @escaping () -> Void) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            safeAreaInset(edge: .bottom) {
                PanicHoldBar(onComplete: onComplete, onAccessibilityActivate: onAccessibilityActivate)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .readableContentWidth(520)
            }
        }
    }
}
