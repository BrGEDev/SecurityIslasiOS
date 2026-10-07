//
//  PassCode.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct VerificationCodeInputView: View {
    @Binding var code: String
    private let codeLength = 6
    
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // 1. TextField invisible que captura la entrada real y el teclado
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                // Ocultar visualmente pero mantener activo para eventos táctiles/foco
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered.count > codeLength {
                        code = String(filtered.prefix(codeLength))
                    } else if filtered != newValue {
                        code = filtered
                    }
                }

            // 2. Las 6 celdas visuales con tu estilo
            HStack(spacing: 10) {
                ForEach(0..<codeLength, id: \.self) { index in
                    Text(getDigit(at: index))
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(radius: 0.2)
                        // Borde sutil en la casilla activa si tiene el foco
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isFocused && code.count == index ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private func getDigit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let charIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[charIndex])
    }
}
