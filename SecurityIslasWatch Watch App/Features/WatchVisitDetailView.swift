//
//  WatchVisitDetailView.swift
//  SecurityIslasWatch Watch App
//
//  Pantalla 39 dentro de la app: quién está en caseta, si es Visita o
//  Servicio, y Autorizar / Rechazar como una llamada. Basta con el reloj
//  puesto y desbloqueado (RF-02, RF-68). El aviso trae los mismos botones (RF-03).
//

import SwiftUI

struct WatchVisitDetailView: View {
    let visit: Visit
    let onDecide: (VisitDecision) async -> Bool

    @Environment(\.dismiss) private var dismiss

    private var colors: [Color] { visit.kind == .visit ? BrandPalette.blue : BrandPalette.indigo }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchAvatar(initials: visit.initials, colors: colors, size: 52)
                Text(visit.name)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                KindBadge(kind: visit.kind)
                Text(visit.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 4) {
                    if let company = visit.company, visit.kind == .service, company != visit.name {
                        Label(company, systemImage: "building.2")
                    }
                    if let plate = visit.plate {
                        Label(plate, systemImage: "car.fill")
                    }
                    if let arrivedAt = visit.arrivedAt {
                        Label("Llegó \(arrivedAt.shortTime)", systemImage: "clock")
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

                if visit.status == .waiting {
                    WatchDecisionButtons { decision in
                        if await onDecide(decision) { dismiss() }
                    }
                    .padding(.top, 6)
                } else {
                    StatusChip(text: visit.statusText, tint: visit.statusTint)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(visit.kind.title)
        .containerBackground(BrandPalette.backdrop(colors), for: .navigation)
    }
}
