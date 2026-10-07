//
//  house.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct House: View {
    @StateObject var loginVM: loginViewModel = .shared
    
    @Binding var path: NavigationPath
    
    var body: some View {
        Form {
            Section {} header: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tu vivienda")
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                    Text("Bosques Sanctorum")
                        .foregroundStyle(.secondary)
                }
                .textCase(nil) // Evita que SwiftUI fuerce mayúsculas en el header
            }
            .headerProminence(.increased)
            .listRowInsets(EdgeInsets())
            .padding(.top)
            
            Section("Nombre") {
                TextField("John", text: .constant(""))
            }
            
            Section("Apellidos") {
                TextField("Doe", text: .constant(""))
            }
            
            Section("Vivienda") {
                NavigationLink(destination: EmptyView(), label: {
                    Text("Sin configurar")
                })
            }
            
            Section("Soy") {
                Picker("Soy", selection: .constant("Propietario")) {
                    Text("Propietario")
                        .tag("Propietario")
                    Text("Arrendatario")
                        .tag("Arrendatario")
                }
                .pickerStyle(.segmented)
            }
        }
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("4 de \(loginVM.phases)")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("4 de \(loginVM.phases)")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Enviar solicitud") {
                path.append(Router.wait)
            }
            .buttonStyle(IslasButton())
            .padding()
        }
    }
}

#Preview {
    House(path: .constant(NavigationPath()))
}
