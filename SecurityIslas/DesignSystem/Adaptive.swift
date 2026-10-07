//
//  Adaptive.swift
//  SecurityIslas
//
//  Layout adaptable para cualquier tamaño de ventana, incluido el iPhone Duo:
//  • Nunca se usan medidas de pantalla (`UIScreen`), idiom ni orientación;
//    todo se mide contra el contenedor.
//  • La pantalla interior del Duo es regular × regular: el contenido se limita
//    a un ancho legible y se centra, en lugar de estirarse de orilla a orilla.
//  • Las zonas seguras pueden ser asimétricas; se suma margen extra sin
//    reemplazar el que da el sistema.
//

import SwiftUI

/// Limita el contenido a un ancho cómodo de leer en ventanas anchas.
/// En un iPhone normal no cambia nada (el margen extra es 0).
struct ReadableContentWidth: ViewModifier {
    var maxWidth: CGFloat

    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.horizontal, max(0, (containerWidth - maxWidth) / 2))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                containerWidth = width
            }
    }
}

extension View {
    func readableContentWidth(_ maxWidth: CGFloat = 640) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}

/// Dos columnas cuando hay espacio (pantalla interior del iPhone Duo, iPad o
/// ventana ancha) y una sola en compacto. Las columnas dejan libre el centro
/// para que ningún control quede sobre el pliegue.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var spacing: CGFloat = 16
    /// Espacio central en dos columnas (≥ al ancho del pliegue).
    var centerGap: CGFloat = 40
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: centerGap) {
                VStack(alignment: .leading, spacing: spacing, content: leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: spacing, content: trailing)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                leading()
                trailing()
            }
        }
    }
}
