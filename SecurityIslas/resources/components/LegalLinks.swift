//
//  LegalLinks.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct LegalLinks: View {
    var body: some View {
        Text(makeText())
            .font(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }
    
    private func makeText() -> AttributedString {
        var attributed = AttributedString("Al continuar aceptas el ")
        if let url1 = URL(string: "https://islasgower.com.mx") {
            var aviso = AttributedString("Aviso de privacidad")
            aviso.link = url1
            aviso.foregroundColor = .blue
            attributed.append(aviso)
        }
        attributed.append(AttributedString(" y los "))
        if let url2 = URL(string: "https://islasgower.com.mx") {
            var terminos = AttributedString("Términos y condiciones.")
            terminos.link = url2
            terminos.foregroundColor = .blue
            attributed.append(terminos)
        }
        return attributed
    }
}


