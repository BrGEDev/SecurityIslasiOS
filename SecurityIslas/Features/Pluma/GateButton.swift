//
//  GateButton.swift
//  SecurityIslas
//
//  Tarjeta principal de Inicio para la pluma (pantallas 9 y 10). Tiene la
//  presencia de un pase de Wallet: es lo primero que el residente busca al
//  llegar, así que domina la pantalla y cambia de color y texto según el
//  estado (carril exclusivo, compartido, lejos, abriendo, abierta, error).
//

import SwiftUI

struct GateHeroCard: View {
    let model: GateViewModel

    @ScaledMetric(relativeTo: .title) private var buttonSide: CGFloat = 72

    var body: some View {
        let look = Appearance(state: model.state)

        Button {
            Task { await model.trigger() }
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Label(look.eyebrow, systemImage: "road.lanes")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let badge = look.badge {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(look.badgeDot)
                                .frame(width: 7, height: 7)
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(look.foreground.opacity(0.14), in: Capsule())
                    }
                }
                .opacity(0.92)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(look.title)
                            .font(.title.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.opacity)
                        Text(look.subtitle)
                            .font(.subheadline)
                            .opacity(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    actionCircle(look)
                }

                if let footer = look.footer {
                    Label(footer.text, systemImage: footer.symbol)
                        .font(.footnote.weight(.medium))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(look.foreground)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(look.background)
                    .overlay(alignment: .topTrailing) {
                        // Brillo sutil en la esquina, como los pases de Wallet.
                        Circle()
                            .fill(.white.opacity(look.isNeutral ? 0 : 0.12))
                            .frame(width: 220, height: 220)
                            .blur(radius: 40)
                            .offset(x: 60, y: -90)
                    }
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
            }
            .shadow(color: look.shadow, radius: 18, y: 10)
            .contentShape(.rect(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!look.isActionable)
        .animation(.smooth(duration: 0.35), value: model.state)
        .sensoryFeedback(trigger: model.state) { _, new in
            switch new {
            case .opened, .passRequested: .success
            case .failed: .error
            default: nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(look.isActionable ? "Pide Face ID." : "")
    }

    private func actionCircle(_ look: Appearance) -> some View {
        ZStack {
            Circle()
                .fill(look.isNeutral ? Color(.tertiarySystemFill) : .white)
            if look.showsProgress {
                ProgressView()
                    .tint(look.accent)
                    .controlSize(.large)
            } else {
                Image(systemName: look.symbol)
                    .font(.system(size: buttonSide * 0.38, weight: .semibold))
                    .foregroundStyle(look.isNeutral ? Color.secondary : look.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: look.title)
            }
        }
        .frame(width: buttonSide, height: buttonSide)
        .shadow(color: .black.opacity(look.isNeutral ? 0 : 0.15), radius: 8, y: 4)
    }

    static func format(_ meters: Int) -> String {
        meters >= 1_000 ? String(format: "%.1f km", Double(meters) / 1_000) : "\(meters) m"
    }
}

// MARK: - Apariencia por estado

private struct Appearance {
    var eyebrow: String
    var title: String
    var subtitle: String
    var symbol: String
    var footer: (text: String, symbol: String)?
    var badge: String?
    var badgeDot: Color = .green
    var colors: [Color]
    var accent: Color
    var isNeutral = false
    var isActionable = false
    var showsProgress = false

    var foreground: Color { isNeutral ? .primary : .white }

    var background: AnyShapeStyle {
        isNeutral
            ? AnyShapeStyle(Color(.secondarySystemGroupedBackground))
            : AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var shadow: Color { isNeutral ? .black.opacity(0.04) : accent.opacity(0.35) }

    static let blue = [Color(red: 0.16, green: 0.55, blue: 1.0), Color(red: 0.0, green: 0.33, blue: 0.86)]
    static let indigo = [Color(red: 0.45, green: 0.38, blue: 0.98), Color(red: 0.27, green: 0.2, blue: 0.78)]
    static let green = [Color(red: 0.2, green: 0.78, blue: 0.45), Color(red: 0.05, green: 0.6, blue: 0.35)]
    static let orange = [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.92, green: 0.42, blue: 0.1)]

    init(state: GateButtonState) {
        switch state {
        case .locating:
            self.init(eyebrow: "Pluma", title: "Buscando tu ubicación", subtitle: "Para saber qué carril te toca.",
                      symbol: "location", colors: [], accent: .accentColor, isNeutral: true, showsProgress: true)
        case .locationOff:
            self.init(eyebrow: "Pluma", title: "Activa tu ubicación", subtitle: "La usamos para abrir la pluma cerca de la entrada.",
                      symbol: "location.slash", colors: [], accent: .accentColor, isNeutral: true)
        case .ready(let lane, let distance) where lane.type == .residentsOnly:
            self.init(eyebrow: lane.name, title: "Abrir pluma", subtitle: "Carril de residentes",
                      symbol: "lock.open.fill", footer: ("Abre directo, sin esperar al guardia", "bolt.fill"),
                      badge: GateHeroCard.format(distance), colors: Self.blue, accent: Self.blue[1], isActionable: true)
        case .ready(let lane, let distance):
            self.init(eyebrow: lane.name, title: "Solicitar paso", subtitle: "Carril compartido",
                      symbol: "bell.fill", footer: ("El guardia confirma y abre", "person.badge.shield.checkmark"),
                      badge: GateHeroCard.format(distance), colors: Self.indigo, accent: Self.indigo[1], isActionable: true)
        case .far(let distance):
            self.init(eyebrow: "Pluma", title: "Lejos de la entrada", subtitle: "Las visitas se autorizan desde cualquier lugar.",
                      symbol: "location", badge: GateHeroCard.format(distance), badgeDot: .secondary,
                      colors: [], accent: .accentColor, isNeutral: true)
        case .working(let lane):
            let residents = lane.type == .residentsOnly
            self.init(eyebrow: lane.name, title: residents ? "Abriendo la pluma…" : "Enviando solicitud…",
                      subtitle: residents ? "Esperando confirmación del controlador." : "Avisando al guardia en caseta.",
                      symbol: "ellipsis", colors: residents ? Self.blue : Self.indigo,
                      accent: residents ? Self.blue[1] : Self.indigo[1], showsProgress: true)
        case .opened(let result):
            self.init(eyebrow: result.laneName, title: "Pluma abierta", subtitle: "\(result.at.shortTime) · queda en la bitácora",
                      symbol: "checkmark", colors: Self.green, accent: Self.green[1])
        case .passRequested(let result):
            self.init(eyebrow: result.laneName, title: "Solicitud enviada", subtitle: "El guardia confirma y abre.",
                      symbol: "bell.badge.fill", colors: Self.indigo, accent: Self.indigo[1])
        case .failed(let message):
            self.init(eyebrow: "Pluma", title: "No se pudo abrir", subtitle: message,
                      symbol: "exclamationmark.triangle.fill", colors: Self.orange, accent: Self.orange[1])
        }
    }

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbol: String,
        footer: (text: String, symbol: String)? = nil,
        badge: String? = nil,
        badgeDot: Color = .green,
        colors: [Color],
        accent: Color,
        isNeutral: Bool = false,
        isActionable: Bool = false,
        showsProgress: Bool = false
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.footer = footer
        self.badge = badge
        self.badgeDot = badgeDot
        self.colors = colors
        self.accent = accent
        self.isNeutral = isNeutral
        self.isActionable = isActionable
        self.showsProgress = showsProgress
    }
}

/// Tarjeta que se hunde levemente al tocarla, como en Wallet.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}
