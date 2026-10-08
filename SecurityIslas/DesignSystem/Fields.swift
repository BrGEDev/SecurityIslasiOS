//
//  Fields.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct FieldStyle: TextFieldStyle {
    var color: Color = Color(.secondarySystemGroupedBackground)

    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding()
            .background(color, in: .rect(cornerRadius: 20))
    }
}

struct SearchField<Leading: View, Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    var backgroundColor: Color
    let leadingIcon: Leading
    let trailingIcon: Trailing

    init(
        _ placeholder: String,
        text: Binding<String>,
        backgroundColor: Color = Color(.secondarySystemGroupedBackground),
        @ViewBuilder leadingIcon: () -> Leading = { EmptyView() },
        @ViewBuilder trailingIcon: () -> Trailing = { EmptyView() }
    ) {
        self.placeholder = placeholder
        self._text = text
        self.backgroundColor = backgroundColor
        self.leadingIcon = leadingIcon()
        self.trailingIcon = trailingIcon()
    }

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
            trailingIcon
        }
        .padding(12)
        .background(backgroundColor, in: .rect(cornerRadius: 14))
    }
}

/// Seis casillas para el código SMS. El campo real está oculto y acepta la
/// sugerencia de iOS arriba del teclado (`.oneTimeCode`).
struct VerificationCodeInputView: View {
    @Binding var code: String
    var codeLength = 6
    var onComplete: (String) -> Void = { _ in }

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.01)
                .accessibilityLabel("Código de verificación")
                .accessibilityIdentifier("codigo-sms")
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(codeLength))
                    if filtered != newValue {
                        code = filtered
                        return
                    }
                    if filtered.count == codeLength {
                        onComplete(filtered)
                    }
                }

            HStack(spacing: 10) {
                ForEach(0..<codeLength, id: \.self) { index in
                    Text(digit(at: index))
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isFocused && code.count == index ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                }
            }
            .accessibilityHidden(true)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
        .onAppear { isFocused = true }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }
}

/// Fila de selección con círculo (pantallas 3b y 20).
struct RadioRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
