//
//  WatchVisitDetailView.swift
//  SecurityIslasWatch Watch App
//
//  Pantalla 39 dentro de la app: quién está en caseta, si es Visita o
//  Servicio, y Autorizar / Rechazar. Basta con el reloj puesto y desbloqueado
//  (RF-02, RF-68). La notificación trae los mismos botones (RF-03).
//

import SwiftUI
import WatchKit

struct WatchVisitDetailView: View {
    let visit: Visit
    let onDecide: (VisitDecision) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var working: VisitDecision?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                KindBadge(kind: visit.kind)
                Text(visit.name)
                    .font(.title3.weight(.semibold))
                Text(visit.subtitle.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if let company = visit.company, visit.kind == .service, company != visit.name {
                    Label(company, systemImage: "building.2")
                        .font(.footnote)
                }
                if let plate = visit.plate {
                    Label(plate, systemImage: "car.fill")
                        .font(.footnote)
                }
                if let arrivedAt = visit.arrivedAt {
                    Label("Llegó \(arrivedAt.shortTime)", systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if visit.status == .waiting {
                    VStack(spacing: 6) {
                        decisionButton(.authorize, title: "Autorizar", systemImage: "checkmark", tint: .green)
                        decisionButton(.reject, title: "Rechazar", systemImage: "xmark", tint: .red)
                    }
                    .padding(.top, 6)
                } else {
                    StatusChip(text: visit.statusText, tint: visit.statusTint)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(visit.kind.title)
    }

    private func decisionButton(_ decision: VisitDecision, title: String, systemImage: String, tint: Color) -> some View {
        Button {
            working = decision
            Task {
                let succeeded = await onDecide(decision)
                working = nil
                WKInterfaceDevice.current().play(succeeded ? .success : .failure)
                dismiss()
            }
        } label: {
            if working == decision {
                ProgressView()
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .tint(tint)
        .disabled(working != nil)
    }
}
