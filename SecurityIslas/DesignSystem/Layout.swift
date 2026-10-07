//
//  Layout.swift
//  SecurityIslas
//
//  Encabezados, indicador de pasos, avisos de error y utilidades comunes.
//

import SwiftUI
import UIKit

/// Título grande + subtítulo de las pantallas de registro.
struct OnboardingHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Encabezado grande dentro de un List/Form. Va como header de una sección
/// vacía para respetar los márgenes de la lista (no como fila sin insets).
struct ListHeaderSection<Accessory: View>: View {
    let title: String
    var subtitle: String?
    let accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        Section {} header: {
            VStack(alignment: .leading, spacing: 16) {
                OnboardingHeader(title: title, subtitle: subtitle)
                accessory
            }
            .textCase(nil)
            .padding(.top)
        }
        .headerProminence(.increased)
        .listRowInsets(EdgeInsets())
    }
}

extension ToolbarContent {
    /// `sharedBackgroundVisibility(.hidden)` solo existe desde iOS 26 (quita el
    /// fondo de Liquid Glass compartido del item). Antes no hay fondo que quitar.
    @ToolbarContentBuilder
    func sharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// "1 de 4" en la esquina superior derecha.
struct OnboardingStep: ViewModifier {
    let step: Int
    let total: Int

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) { label }
                .sharedBackgroundHidden()
        }
    }

    private var label: some View {
        Text("\(step) de \(total)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityLabel("Paso \(step) de \(total)")
    }
}

/// `navigationSubtitle` existe desde iOS 26; antes no hace nada y la vista
/// muestra el subtítulo en su contenido.
struct NavigationSubtitleCompat: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationSubtitle(text)
        } else {
            content
        }
    }
}

extension View {
    func navigationSubtitleCompat(_ text: String) -> some View {
        modifier(NavigationSubtitleCompat(text: text))
    }

    func onboardingStep(_ step: Int, of total: Int = 4) -> some View {
        modifier(OnboardingStep(step: step, total: total))
    }

    /// Alerta estándar para errores de red o de negocio.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "No se pudo completar",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            actions: { Button("Entendido", role: .cancel) {} },
            message: { Text(message.wrappedValue ?? "") }
        )
    }
}

struct InlineError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }
}

/// Label con el ícono en una columna de ancho fijo: los textos de varias filas
/// quedan alineados aunque los símbolos tengan anchos distintos (`car.side` es
/// ancho, `sun.max` es cuadrado).
struct AlignedIconLabelStyle: LabelStyle {
    var spacing: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            configuration.icon
                .frame(width: iconWidth, alignment: .center)
            configuration.title
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension LabelStyle where Self == AlignedIconLabelStyle {
    static var alignedIcon: AlignedIconLabelStyle { AlignedIconLabelStyle() }
}

/// Nota pequeña con ícono, como "Mientras tanto no puedes abrir la pluma...".
struct FootnoteLabel: View {
    let text: String
    var systemImage = "lock"

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(.alignedIcon)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BackgroundLabel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content
                .padding()
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        }
    }
}

extension View {
    func backgroundLabel() -> some View {
        modifier(BackgroundLabel())
    }

    /// Tarjeta blanca agrupada (fuera de List).
    /// Esquinas continuas (la curva "squircle" de iOS) y el fondo agrupado del sistema.
    func cardBackground(cornerRadius: CGFloat = 20) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Aviso de privacidad y términos (diseño original de la pantalla de acceso).
struct LegalLinks: View {
    var body: some View {
        Text(makeText())
            .font(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }

    private func makeText() -> AttributedString {
        var attributed = AttributedString("Al continuar aceptas el ")
        if let url = URL(string: "https://islasgower.com.mx") {
            var aviso = AttributedString("Aviso de privacidad")
            aviso.link = url
            aviso.foregroundColor = .blue
            attributed.append(aviso)
        }
        attributed.append(AttributedString(" y los "))
        if let url = URL(string: "https://islasgower.com.mx") {
            var terminos = AttributedString("Términos y condiciones.")
            terminos.link = url
            terminos.foregroundColor = .blue
            attributed.append(terminos)
        }
        return attributed
    }
}

/// Texto con un enlace accionable al final ("... Cambiar").
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
        button.foregroundColor = .accentColor
        button.link = actionURL
        attributed.append(button)
        return attributed
    }
}

/// Hoja de compartir de iOS (pantalla 15) presentada al instante.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
