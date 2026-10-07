//
//  TextNavigation.swift
//  SecurityIslas
//
//  Created by Brandon Guerra  on 06/10/26.
//

import SwiftUI

struct TextNavigation: View {
    
    var text: String
    var textButton: String
    
    var onTap: () -> Void = {}
    
    private let actionURL = URL(string: "action://tap")!
    
    var body: some View {
        Text(makeText())
            .environment(\.openURL, OpenURLAction { url in
                if url == actionURL {
                    onTap()
                    return .handled
                }
                return .systemAction
            })
    }
    
    private func makeText() -> AttributedString {
        var attributed = AttributedString("\(text) ")
        
        var button = AttributedString(textButton)
        button.foregroundColor = Color.accentColor
        button.link = actionURL
        
        attributed.append(button)
        
        return attributed
    }
}
