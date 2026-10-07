//
//  BackgroundLabel.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct BackgroundLabel: ViewModifier {
    func body(content: Content) -> some View {
        
        if #available(iOS 26,*)
        {
            content
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content
                .padding()
                .backgroundStyle(.ultraThinMaterial)
                .cornerRadius(20)
        }
        
    }
}

extension View {
    func backgroundLabel() -> some View {
        self.modifier(BackgroundLabel())
    }
}
