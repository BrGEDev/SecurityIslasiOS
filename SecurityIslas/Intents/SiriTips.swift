//
//  SiriTips.swift
//  SecurityIslas
//
//  Sugerencias de Siri junto a la acción que reemplazan (RF-30, RF-31): la
//  frase sale del `AppShortcutsProvider`, así que siempre coincide con lo que
//  Siri entiende. Al cerrarla ya no vuelve a aparecer.
//

import AppIntents
import SwiftUI

struct DismissibleSiriTip<Intent: AppIntent>: View {
    let intent: Intent
    @AppStorage private var isVisible: Bool

    /// `key` identifica la sugerencia para recordar si ya se cerró.
    init(_ intent: Intent, key: String) {
        self.intent = intent
        _isVisible = AppStorage(wrappedValue: true, "siriTip.\(key)")
    }

    var body: some View {
        if isVisible {
            SiriTipView(intent: intent, isVisible: $isVisible)
        }
    }
}
