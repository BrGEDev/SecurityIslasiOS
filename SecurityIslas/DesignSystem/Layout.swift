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

/// "1 de 4" en la esquina superior derecha.
struct OnboardingStep: ViewModifier {
    let step: Int
    let total: Int

    func body(content: Content) -> some View {
        content.toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { label }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { label }
            }
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

extension View {
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
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }
}

extension View {
    func backgroundLabel() -> some View {
        modifier(BackgroundLabel())
    }

    /// Tarjeta blanca agrupada (fuera de List).
    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
    }
}

struct LegalLinks: View {
    var body: some View {
        Text(makeText())
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func makeText() -> AttributedString {
        var text = AttributedString("Al continuar aceptas el ")
        var privacy = AttributedString("Aviso de privacidad")
        privacy.link = URL(string: "https://islasgower.com.mx")
        privacy.underlineStyle = .single
        text.append(privacy)
        text.append(AttributedString(" y los "))
        var terms = AttributedString("Términos")
        terms.link = URL(string: "https://islasgower.com.mx")
        terms.underlineStyle = .single
        text.append(terms)
        text.append(AttributedString("."))
        return text
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

// MARK: - Formatos

extension Date {
    /// "hoy 20:00", "ayer 23:10", "vie 9 oct · 15:00"
    var relativeDayAndTime: String {
        let time = formatted(.dateTime.hour().minute())
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "hoy \(time)" }
        if calendar.isDateInYesterday(self) { return "ayer \(time)" }
        if calendar.isDateInTomorrow(self) { return "mañana \(time)" }
        return "\(formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(time)"
    }

    var shortTime: String { formatted(.dateTime.hour().minute()) }

    var longDay: String { formatted(.dateTime.day().month(.abbreviated).year()) }
}

extension URL {
    static let emergency = URL(string: "tel://911")!

    static func phone(_ number: String) -> URL? {
        URL(string: "tel://\(number.filter { $0.isNumber || $0 == "+" })")
    }
}
