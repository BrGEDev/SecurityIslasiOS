//
//  home.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct Home: View {
    var body: some View {
        TabView {
            Text("Inicio")
                .tag(1)
                .tabItem {
                    Label(
                        "Inicio",
                        systemImage: "house.fill"
                    )
                }
            
            Text("Seguridad")
                .tag(2)
                .tabItem {
                    Label(
                        "Seguridad",
                        systemImage: "shield.pattern.checkered"
                    )
                }
            
            Text("Mis")
        }
    }
}

#Preview {
    Home()
}
