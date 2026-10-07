//
//  WatchGateButton.swift
//  SecurityIslasWatch Watch App
//
//  Abrir pluma desde el reloj (RF-23, RF-68): mismas reglas que el iPhone.
//  Carril exclusivo → "Abrir pluma"; compartido → "Solicitar paso"; fuera de
//  la geocerca no se puede. No pide Face ID: basta con el reloj puesto y
//  desbloqueado, y la orden va firmada con la llave del reloj.
//

import SwiftUI
import WatchKit

struct WatchGateButton: View {
    let model: GateViewModel

    var body: some View {
        Button {
            Task { await model.trigger() }
        } label: {
            HStack(spacing: 10) {
                icon
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .disabled(!isEnabled)
        .listItemTint(tint)
        .onChange(of: model.state) { _, state in
            switch state {
            case .opened, .passRequested: WKInterfaceDevice.current().play(.success)
            case .failed: WKInterfaceDevice.current().play(.failure)
            default: break
            }
        }
        .task {
            await model.refreshPosition()
        }
    }

    private var isEnabled: Bool {
        if case .ready = model.state { return true }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .working:
            ProgressView()
        case .opened:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .passRequested:
            Image(systemName: "person.badge.clock.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .far, .locationOff:
            Image(systemName: "location.slash").foregroundStyle(.secondary)
        case .locating:
            Image(systemName: "location").foregroundStyle(.secondary)
        case .ready(let lane, _):
            Image(systemName: lane.type == .residentsOnly ? "door.garage.open" : "hand.raised.fill")
                .foregroundStyle(.tint)
        }
    }

    private var title: String {
        switch model.state {
        case .locating: "Buscando tu ubicación"
        case .ready(let lane, _): lane.type == .residentsOnly ? "Abrir pluma" : "Solicitar paso"
        case .far: "Lejos de la entrada"
        case .locationOff: "Activa la ubicación"
        case .working(let lane): lane.type == .residentsOnly ? "Abriendo…" : "Enviando…"
        case .opened: "Pluma abierta"
        case .passRequested: "Solicitud enviada"
        case .failed: "No se pudo abrir"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .locating: "Un momento"
        case .ready(let lane, let distance): "\(distance) m · \(lane.type == .residentsOnly ? "residentes" : "carril compartido")"
        case .far(let distance): distance >= 1000 ? String(format: "A %.1f km", Double(distance) / 1000) : "A \(distance) m"
        case .locationOff: "En la app Ajustes del reloj"
        case .working(let lane): lane.name
        case .opened(let result): result.laneName
        case .passRequested: "El guardia confirma y abre"
        case .failed(let message): message
        }
    }

    private var tint: Color {
        switch model.state {
        case .ready, .working: .accentColor
        case .opened: .green
        case .passRequested: .orange
        default: .gray
        }
    }
}
