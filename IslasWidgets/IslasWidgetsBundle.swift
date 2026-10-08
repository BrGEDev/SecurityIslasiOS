//
//  IslasWidgetsBundle.swift
//  IslasWidgets
//
//  Widgets (pantallas 30 y 31), Live Activity de la visita (11 y 12) y
//  controles del Centro de control (iOS 18, pantalla 31).
//

import SwiftUI
import WidgetKit

@main
struct IslasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
        PanicWidget()
        EntranceAccessoryWidget()
        VisitLiveActivity()
        if #available(iOS 18.0, *) {
            GateControl()
            PanicControl()
            MyQRControl()
        }
    }
}
