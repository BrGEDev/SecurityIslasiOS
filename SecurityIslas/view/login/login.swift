//
//  login.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct Login: View {
    @StateObject private var loginVM = loginViewModel.shared

    let ancho = UIScreen.main.bounds.width
    let alto = UIScreen.main.bounds.height
    
    @Binding var path: NavigationPath
    
    var body: some View {
        ScrollView {
            VStack(spacing: 50) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tu número de celular")
                        .font(.title.bold())
                    Text("Te enviaremos un código por SMS para verificarlo.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: ancho, alignment: .leading)
                
                
                VStack(spacing: 15) {
                    HStack(spacing: 10) {
                        Picker("", selection: $loginVM.selectedLada) {
                            ForEach(loginVM.ladaCountry, id: \.self) { lada in
                                Text("+\(lada.lada)")
                                    .tag(lada)
                            }
                        }
                        .pickerIslas()
                        
                        TextField("XXX XXX XXXX", text: $loginVM.phone)
                            .keyboardType(.numberPad)
                            .textFieldStyle(FieldStyle())
                            .onChange(of: loginVM.phone) { _, newValue in
                                renderPhone(newValue)
                            }
                    }
                    
                    if !loginVM.error.isEmpty {
                        Text(loginVM.error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    Text("Con este número te identificaran en caseta")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: ancho, alignment: .leading)
                }
                
                Spacer()
            }
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("1 de \(loginVM.phases)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("1 de \(loginVM.phases)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button("Enviar código") {
                loginVM.login(path: $path)
            }
            .buttonStyle(IslasButton())
            .padding()
        }
    }
    
    private func renderPhone(_ value: String) {
        let digits = value.filter(\.isNumber)
        
        var formatted = ""
        let maxCount = 10
        let limited = String(digits.prefix(maxCount))
        for (i, c) in limited.enumerated() {
            if i == 3 || i == 6 {
                formatted += " "
            }
            formatted.append(c)
        }
        
        if formatted != value {
            loginVM.phone = formatted
        }
    }
}

#Preview {
    Login(path: .constant(NavigationPath()))
}
