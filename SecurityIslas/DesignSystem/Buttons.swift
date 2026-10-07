//
//  Buttons.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

/// Botón principal de ancho completo.
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

extension ButtonStyle where Self == IslasButton {
    static var islasPrimary: IslasButton { IslasButton() }
    static var islasSecondary: IslasButton { IslasButton(color: .accentColor, backgroundColor: Color(.systemGray5)) }
    static var islasDestructive: IslasButton { IslasButton(backgroundColor: .red) }
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

/// Botón inferior fijo, como en las maquetas.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground).opacity(0.95))
    }
}
