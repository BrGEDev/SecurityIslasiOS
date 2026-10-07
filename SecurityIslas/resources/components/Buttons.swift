//
//  Buttons.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct IslasButton: ButtonStyle {
    
    var color: Color = .white
    var backgroundColor: Color = .accentColor
    
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26,*) {
            configuration
                .label
                .padding()
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive().tint(backgroundColor), in: .rect(cornerRadius: 20))
                .foregroundStyle(color)
        } else {
            configuration
                .label
                .padding()
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .cornerRadius(20)
                .foregroundStyle(color)
        }
    }
}
