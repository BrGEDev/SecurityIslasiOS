//
//  HeaderCompat.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 05/10/26.
//

import SwiftUI

struct HeaderCompat: ViewModifier {
    var title: String
    var subtitle: String = ""
    
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

extension View {
    func headerCompat(title: String, subtitle: String = "") -> some View {
        return self.modifier(HeaderCompat(title: title, subtitle: subtitle))
    }
}
