//
//  GateButton.swift
//  SecurityIslas
//
//  Tarjeta del botón principal de Inicio (pantallas 9 y 10).
//

import SwiftUI

struct GateButton: View {
    let model: GateViewModel

    var body: some View {
        content
            .sensoryFeedback(trigger: model.state) { _, new in
                switch new {
                case .opened, .passRequested: .success
                case .failed: .error
                default: nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .locating:
            statusCard(icon: nil, title: "Buscando tu ubicación…", subtitle: "Para saber qué carril te toca")
        case .ready(let lane, let distance):
            actionCard(lane: lane, distance: distance)
        case .far(let distance):
            farCard(distance: distance)
        case .locationOff:
            statusCard(icon: "location.slash", title: "Activa tu ubicación", subtitle: "La necesitamos para abrir la pluma cerca de la entrada.")
        case .working(let lane):
            statusCard(
                icon: nil,
                title: lane.type == .residentsOnly ? "Abriendo la pluma…" : "Enviando solicitud…",
                subtitle: lane.name
            )
        case .opened(let result):
            statusCard(icon: "checkmark", tint: .green, title: "Pluma abierta", subtitle: "\(result.at.shortTime) · queda en la bitácora")
        case .passRequested(let result):
            statusCard(icon: "bell.badge", tint: .indigo, title: "Solicitud de paso enviada", subtitle: "\(result.laneName) · el guardia confirma y abre")
        case .failed(let message):
            statusCard(icon: "exclamationmark.triangle", tint: .orange, title: "No se pudo abrir", subtitle: message)
        }
    }

    private func actionCard(lane: Lane, distance: Int) -> some View {
        let isShared = lane.type == .shared
        let colors: [Color] = isShared
            ? [Color(red: 0.42, green: 0.36, blue: 0.95), Color(red: 0.25, green: 0.22, blue: 0.75)]
            : [Color(red: 0.13, green: 0.52, blue: 1.0), Color(red: 0.0, green: 0.35, blue: 0.85)]

        return Button {
            Task { await model.trigger() }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: isShared ? "bell.fill" : "road.lanes")
                    .font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.18), in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isShared ? "Solicitar paso" : "Abrir pluma")
                        .font(.title3.bold())
                    Text("\(lane.name) · \(isShared ? "carril compartido" : "carril de residentes")")
                        .font(.footnote)
                        .opacity(0.9)
                    Label(
                        isShared ? "El guardia confirma y abre" : "Estás a \(distance) m de la entrada",
                        systemImage: "circle.fill"
                    )
                    .labelStyle(DotLabelStyle())
                    .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isShared ? "Manda una solicitud al guardia. Pide Face ID." : "Abre la pluma. Pide Face ID.")
    }

    private func farCard(distance: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "location")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(Color(.systemGray5), in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("Lejos de la entrada").font(.title3.bold())
                Text("Estás a \(Self.format(distance))").font(.footnote).foregroundStyle(.secondary)
                Text("Las visitas se autorizan desde cualquier lugar").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func statusCard(icon: String?, tint: Color = .accentColor, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.bold))
                        .foregroundStyle(tint)
                        .symbolEffect(.bounce, value: title)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 88)
        .cardBackground(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    static func format(_ meters: Int) -> String {
        meters >= 1_000 ? String(format: "%.1f km", Double(meters) / 1_000) : "\(meters) m"
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(.green)
            configuration.title
        }
    }
}
