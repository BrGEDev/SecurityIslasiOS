//
//  PasswordField.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct PasswordField: View {
    
    @Binding var pass: String
    
    @State private var isVisible: Bool = false
    
    var body: some View {
        HStack {
            if isVisible {
                TextField(text: $pass, label: {
                    Text("Contraseña")
                })
                .textFieldStyle(FieldStyle())
            } else {
                SecureField(text: $pass, label: {
                    Text("Contraseña")
                })
                .textFieldStyle(FieldStyle())
            }
            
            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "eye.slash" : "eye")
            }
        }
        
    }
}

struct FieldStyle: TextFieldStyle {
    
    var color: Color = .white
    
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding()
            .background(color)
            .cornerRadius(20)
            .shadow(radius: 0.2)
    }
}

struct SearchField: View {
    
    var leadingIcon: AnyView
    var placeholder: String
    var backgroundColor: Color
    @Binding var text: String
    var trailingIcon: AnyView
    
    init(
        _ placeholder: String,
        text: Binding<String>,
        backgroundColor: Color = .white,
        @ViewBuilder leadingIcon: @escaping () -> some View = { EmptyView() },
        @ViewBuilder trailingIcon: @escaping () -> some View = { EmptyView() }
    ) {
        self.placeholder = placeholder
        self._text = text
        self.backgroundColor = backgroundColor
        self.leadingIcon = AnyView(leadingIcon())
        self.trailingIcon = AnyView(trailingIcon())
    }
    
    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
            TextField(placeholder, text: $text)
            trailingIcon
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(20)
        .shadow(radius: 0.2)
    }
}

#Preview {
    SearchField(
        "Ejemplo",
        text: .constant(""),
        leadingIcon: {
            Image(systemName: "magnifyingglass")
        }
    )
}
