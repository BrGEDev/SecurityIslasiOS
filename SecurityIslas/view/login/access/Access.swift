//
//  Access.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct Access: View {    
    let ancho = UIScreen.main.bounds.width
    let alto = UIScreen.main.bounds.height
    
    @Binding var path: NavigationPath
    
    var body: some View {
        ZStack(alignment: .top) {
            Image(.loginHero)
                .resizable()
                .scaledToFill()
                .frame(width: ancho, height: alto, alignment: .top)
                .clipped()
                .ignoresSafeArea()
            
            VStack(spacing: 10) {
                Image(.logo)
                    .resizable()
                    .renderingMode(.template)
                    .colorInvert()
                    .scaledToFit()
                    .frame(width: ancho * 0.5)
                
                VStack(spacing: 30) {
                    Text("Acceso")
                        .foregroundStyle(.cyan)
                        .font(.title.bold())
                    
                    Text("La entrada a tu fraccionamiento en tu teléfono")
                        .foregroundStyle(.white)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: ancho)
                        .fixedSize()
                    
                }
                .padding(.vertical, 30)
                .frame(width: ancho)
                
                Spacer()
                
                VStack(spacing: 15) {
                    HStack(spacing: 15) {
                        Image(systemName: "bell.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color.accentColor)
                        
                        Text("Te avisamos cuando llega tu visita y autoriza su entrada")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .backgroundLabel()
                    
                    HStack(spacing: 15) {
                        Image(systemName: "car.rear.road.lane")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color.accentColor)
                        
                        Text("Abre la pluma desde tu iPhone, Apple Watch o con Siri")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .backgroundLabel()
                    
                    HStack(spacing: 15) {
                        Image(systemName: "light.beacon.min.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color.accentColor)
                        
                        Text("Aviso de emergencia inmediata con caseta y tus contactos")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .backgroundLabel()
                    
                    Spacer(minLength: 5)
                    
                    Button("Continuar") {
                        path.append(Router.login)
                    }
                    .buttonStyle(IslasButton())
                    
                    Button(action: {}) {
                        Label("Tengo un enlace de invitación", systemImage: "link")
                            .foregroundStyle(.white)
                    }.padding()
                }
                .padding()
                .frame(maxWidth: ancho)
                .fixedSize()
                
                Spacer()
                
                LegalLinks()
                    .padding()
                
                Spacer()
            }
            .padding(.top, 100)
        }
    }
}

#Preview {
    Access(path: .constant(NavigationPath()))
}
