//
//  loginViewModel.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import Foundation
import Combine
import SwiftUI

struct Ladas: Hashable {
    var country: String
    var lada: Int
}

@MainActor
class loginViewModel: ObservableObject {
    static var shared = loginViewModel()
    
    @Published var ladaCountry: [Ladas] = [Ladas(country: "México", lada: 51), Ladas(country: "Estados Unidos", lada: 1)]
    @Published var selectedLada: Ladas?
    
    @Published var phone: String = ""
    
    @Published var verificationCode: String = ""
    
    @Published var error: String = ""
    
    @Published var isLoading: Bool = false
    @Published var phases: Int = 4
    
    init() {
        self.selectedLada = ladaCountry.first
    }
    
    
    func login(path: Binding<NavigationPath>) {
        error = ""
        
        let newPhone = phone.filter(\.isNumber)
        
        guard !newPhone.isEmpty && newPhone.count == 10 else {
            error = "Número de teléfono inválido"
            return
        }
        
        isLoading = false
        
        if newPhone == "2218486093" && selectedLada == ladaCountry.first {
            phases = 2
        } else {
            phases = 4
        }
        
        path.wrappedValue.append(Router.verifyCode)
    }
    
    func verifyCode(path: Binding<NavigationPath>) {
        error = ""
        
        guard !verificationCode.isEmpty && verificationCode.count == 6 else {
            error = "Debe indicar el código de verificación"
            return
        }
        
        if verificationCode == "123456" {
            path.wrappedValue.append(phases == 4 ? Router.location : Router.wait)
            return
        } else {
            error = "Código incorrecto"
            return
        }
    }
}
