//
//  PickerStyles.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct PickerIslas: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(Color.white)
            .cornerRadius(20)
    }
}

extension View {
    func pickerIslas() -> some View {
        self.modifier(PickerIslas())
    }
}
