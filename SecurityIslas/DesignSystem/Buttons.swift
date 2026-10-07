//
//  Buttons.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

/// Botón de marca de la pantalla de acceso (diseño original de Islas).
struct IslasButton: ButtonStyle {
    var color: Color = .white
    var backgroundColor: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = isEnabled ? backgroundColor : Color(.systemGray4)
        if #available(iOS 26, *) {
            configuration
                .label
                .font(.body.weight(.semibold))
                .padding()
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive().tint(tint), in: .rect(cornerRadius: 20))
                .foregroundStyle(color)
        } else {
            configuration
                .label
                .font(.body.weight(.semibold))
                .padding()
                .frame(maxWidth: .infinity)
                .background(tint, in: .rect(cornerRadius: 20))
                .foregroundStyle(color)
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Estilo de acción de ancho completo con la anatomía de iOS: cápsula, 50 pt
/// de alto que crecen con Dynamic Type, Liquid Glass en iOS 26 y estado
/// deshabilitado con los grises del sistema.
struct ActionButtonStyle: ButtonStyle {
    enum Kind {
        /// Acción principal de la pantalla (relleno de color).
        case prominent
        /// Acción secundaria (fondo teñido, texto de color).
        case tinted
        /// Acción destructiva prominente (ej. "Llamar al 911").
        case destructive
    }

    var kind: Kind = .prominent

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .contentShape(Capsule())

        Group {
            if #available(iOS 26, *) {
                label.glassEffect(glass, in: Capsule())
            } else {
                label
                    .background(background, in: Capsule())
                    .opacity(configuration.isPressed ? 0.8 : 1)
            }
        }
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }

    private var tint: Color {
        kind == .destructive ? .red : .accentColor
    }

    private var foreground: Color {
        guard isEnabled else { return Color(.tertiaryLabel) }
        return kind == .tinted ? tint : .white
    }

    private var background: Color {
        guard isEnabled else { return Color(.tertiarySystemFill) }
        return kind == .tinted ? tint.opacity(0.15) : tint
    }

    @available(iOS 26, *)
    private var glass: Glass {
        guard isEnabled else { return .regular }
        return kind == .tinted ? .regular.interactive() : .regular.tint(tint).interactive()
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    static var islasPrimary: ActionButtonStyle { ActionButtonStyle(kind: .prominent) }
    static var islasSecondary: ActionButtonStyle { ActionButtonStyle(kind: .tinted) }
    static var islasDestructive: ActionButtonStyle { ActionButtonStyle(kind: .destructive) }
}

/// Botón que ejecuta una acción asíncrona y muestra un indicador mientras corre.
struct AsyncButton<Label: View>: View {
    var role: ButtonRole?
    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    @State private var isRunning = false

    init(role: ButtonRole? = nil, action: @escaping () async -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.role = role
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role) {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            ZStack {
                label().opacity(isRunning ? 0 : 1)
                if isRunning {
                    ProgressView()
                }
            }
        }
        .disabled(isRunning)
    }
}

extension AsyncButton where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () async -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

/// Acciones fijas al pie de la pantalla. En iOS 26 los botones flotan sobre
/// el contenido (Liquid Glass); antes, van sobre el material de barra del sistema.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            if #available(iOS 26, *) {
                Color.clear
            } else {
                Rectangle()
                    .fill(.bar)
                    .ignoresSafeArea()
            }
        }
    }
}
