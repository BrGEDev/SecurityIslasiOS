//
//  wait.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct WaitScreen: View {
    
    @Binding var path: NavigationPath
    
    var body: some View {
        List {
            Section {} header: {
                VStack(spacing: 20) {
                    Image(systemName: "clock")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundStyle(Color.orange)
                        .padding(30)
                        .background(Circle().fill(Color.yellow.opacity(0.2)))
                    
                    Text("Solicitud enviada")
                        .font(.title.bold())
                    
                    Text("La administración de Bosques Sanctórum revisará tu alta. Te avisaremos con una notificación")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
            }
            .headerProminence(.increased)
            
            Section {
                HStack {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                    
                    VStack(alignment: .leading) {
                        Text("Teléfono verificado")
                            .bold()
                    }
                }
                
                HStack {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                    
                    VStack(alignment: .leading) {
                        Text("Priv. Santa Laura - 12C")
                            .bold()
                        
                        Text("Bosques Sanctorum")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading) {
                        Text("Aprobación de administración")
                            .bold()
                        
                        Text("Pendiente de revisión")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            } footer: {
                Label("Mientras estás en espera de aprobación, aún no puedes abrir la pluma ni autorizar entrada de visitas.", systemImage: "lock")
            }
        }
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom) {
            Button("Llamar a la administración") {
                
            }
            .buttonStyle(IslasButton(color: Color.accentColor, backgroundColor: Color(.systemGray5)))
            .padding()
        }
    }
}

#Preview {
    WaitScreen(path: .constant(NavigationPath()))
}
