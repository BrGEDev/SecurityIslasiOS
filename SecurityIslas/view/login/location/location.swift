//
//  Untitled.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct Fraccionamientos: Hashable, Identifiable {
    let id: UUID = UUID()
    var nombre: String
    var casetas: Int
    var viviendas: Int
}

struct Location: View {
    
    @StateObject var loginVM: loginViewModel = .shared
    
    @State var search: String = ""
    
    var locations: [Fraccionamientos] = [
        Fraccionamientos(
            nombre: "Bosques Sanctórum",
            casetas: 2,
            viviendas: 350
        ),
        Fraccionamientos(
            nombre: "Bosques del Pilar",
            casetas: 1,
            viviendas: 150
        ),
        Fraccionamientos(
            nombre: "Paseos del Ángel",
            casetas: 1,
            viviendas: 150
        ),
    ]
    
    @State var selectedLocation: Fraccionamientos?
    
    let ancho = UIScreen.main.bounds.width
    
    @Binding var path: NavigationPath
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                VStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("¿Dónde vives?")
                            .font(.title.bold())
                        Text("Busca tu fraccionamiento o condominio.")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: ancho, alignment: .leading)
                    
                    
                    VStack(spacing: 15) {
                        SearchField(
                            "Bosques de Sanctorum, Paseos del Ángel...",
                            text: $search,
                            backgroundColor: .gray.opacity(0.15),
                            leadingIcon: {
                                Image(systemName: "magnifyingglass")
                            },
                            trailingIcon: {
                                if !search.isEmpty {
                                    Button(action: { search = "" }) {
                                        Image(systemName: "xmark")
                                            .resizable()
                                            .frame(width: 8, height: 8)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(7)
                                    .background(Circle().fill(Color(.systemBackground)))
                                    .shadow(radius: 1)
                                    .buttonStyle(.plain)
                                }
                            }
                        )
                    }
                }
                .padding([.top, .leading, .trailing])
                
                List {
                    Section {
                        ForEach(locations) { location in
                            Button(action: {
                                selectedLocation = location
                            }) {
                                HStack(spacing: 15) {
                                    Image(systemName: "building.2.fill")
                                        .padding(10)
                                        .background(Circle().fill(Color.accentColor.opacity(0.1)))
                                        .foregroundStyle(Color.accentColor)
                                    
                                    VStack(alignment: .leading) {
                                        Text(location.nombre)
                                        Text("\(location.casetas) casetas - \(location.viviendas) viviendas")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedLocation == location {
                                        Image(systemName: "checkmark")
                                            .padding(10)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(selectedLocation == location ? Color.accentColor.opacity(0.08) : Color(.systemBackground))
                        }
                    }
                    
                    Section {
                        Button(action: {}) {
                            Label("Tengo un código de invitación", systemImage: "link")
                        }
                    } footer: {
                        Text("¿No aparece? Contacta con tu administración para verificar el estado del registro de tu fraccionamiento o condominio.")
                    }
                }
                
                Spacer()
            }
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("3 de \(loginVM.phases)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("3 de \(loginVM.phases)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button("Continuar") {
                path.append(Router.house)
            }
            .buttonStyle(IslasButton())
            .padding()
        }
    }
}

#Preview {
    Location(path: .constant(NavigationPath()))
}
