//
//  verifyCode.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct VerifyCode: View {
    @StateObject private var loginVM = loginViewModel.shared

    let ancho = UIScreen.main.bounds.width
    let alto = UIScreen.main.bounds.height
    
    @Binding var path: NavigationPath
    
    var body: some View {
        ScrollView {
            VStack(spacing: 50) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Escribe el código")
                        .font(.title.bold())
                    HStack {
                        TextNavigation(
                            text: "Enviamos un código de verificación al número +\(loginVM.selectedLada?.lada ?? 0) \(loginVM.phone).",
                            textButton: "Cambiar",
                        ) {
                            path.removeLast()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: ancho, alignment: .leading)
                
                
                VStack(spacing: 15) {
                    HStack(spacing: 10) {
                        VerificationCodeInputView(code: $loginVM.verificationCode)
                    }
                    .padding(.bottom, 10)
                    
                    
                    if !loginVM.error.isEmpty {
                        Text(loginVM.error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    
                    Text("Reenviar código en \(Text("0:42").bold())")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("2 de \(loginVM.phases)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("2 de \(loginVM.phases)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button("Verificar número") {
                loginVM.verifyCode(path: $path)
            }
            .buttonStyle(IslasButton())
            .padding()
        }
    }
}

#Preview {
    VerifyCode(path: .constant(NavigationPath()))
}
