//
//  PanicFlowView.swift
//  SecurityIslas
//
//  Pantallas 24 a 27.
//

import MapKit
import SwiftUI

struct PanicFlowView: View {
    @State private var model: PanicViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: PanicViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.stage {
            case .hold:
                PanicHoldScreen(description: model.recipientsDescription) {
                    model.startCountdown()
                } onClose: {
                    model.cancel()
                }
            case .countdown(let remaining):
                PanicCountdownScreen(remaining: remaining, insidePerimeter: model.insidePerimeter) {
                    model.cancel()
                }
            case .sending:
                PanicCountdownScreen(remaining: nil, insidePerimeter: model.insidePerimeter, onCancel: nil)
            case .active:
                if let alert = model.alert {
                    PanicActiveScreen(model: model, alert: alert)
                }
            case .failed(let message):
                PanicFailedScreen(message: message) {
                    await model.retry()
                } onClose: {
                    model.cancel()
                }
            }
        }
        .task { await model.prepare() }
        .onChange(of: model.didFinish) { _, finished in
            if finished { dismiss() }
        }
        .errorAlert($model.errorMessage)
    }
}

private let panicGradient = LinearGradient(
    colors: [Color(red: 0.75, green: 0.1, blue: 0.1), Color(red: 0.5, green: 0.04, blue: 0.04)],
    startPoint: .top,
    endPoint: .bottom
)

/// 24: mantener presionado; el anillo muestra el avance (desde widget o control).
private struct PanicHoldScreen: View {
    let description: String
    let onComplete: () -> Void
    let onClose: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            panicGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("Cerrar", action: onClose)
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(Color.red)
                        .padding(18)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 180, height: 180)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: PanicHoldBar.holdDuration) {
                    onComplete()
                } onPressingChanged: { pressing in
                    withAnimation(pressing ? .linear(duration: PanicHoldBar.holdDuration) : .easeOut(duration: 0.2)) {
                        progress = pressing ? 1 : 0
                    }
                }
                .accessibilityLabel("Botón de pánico")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onComplete() }

                VStack(spacing: 6) {
                    Text("Mantén presionado").font(.title.bold())
                    Text("Suelta para cancelar").font(.subheadline)
                }
                .foregroundStyle(.white)

                Label(description, systemImage: "shield")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
                Spacer()
            }
            .padding()
        }
    }
}

/// 25: unos segundos para cancelar y evitar falsas alarmas; vibra cada segundo.
private struct PanicCountdownScreen: View {
    let remaining: Int?
    let insidePerimeter: Bool
    let onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            panicGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle().stroke(.white, lineWidth: 5)
                    if let remaining {
                        Text("\(remaining)")
                            .font(.system(size: 88, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        ProgressView().tint(.white).controlSize(.large)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 160, height: 160)

                VStack(spacing: 6) {
                    Text("Enviando alerta").font(.title.bold())
                    Text(insidePerimeter ? "a los guardias en turno con tu ubicación" : "a tus contactos de emergencia con tu ubicación")
                        .font(.subheadline)
                }
                .foregroundStyle(.white)
                Spacer()
                if let onCancel {
                    Button(action: onCancel) {
                        Text("Cancelar")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: remaining)
        .animation(.snappy, value: remaining)
    }
}

/// 26 (dentro) y 27 (fuera del fraccionamiento).
private struct PanicActiveScreen: View {
    let model: PanicViewModel
    let alert: PanicAlert
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Circle().fill(Color.red).frame(width: 12, height: 12)
                Text("Alerta activa").font(.title2.bold())
                Spacer()
                Text(alert.scope == .guards ? alert.createdAt.shortTime : "Fuera de \(model.residenceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if alert.scope == .guards {
                if let coordinate = model.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        latitudinalMeters: 400,
                        longitudinalMeters: 400
                    ))) {
                        Annotation("Tú", coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)) {
                            Circle().fill(.red).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                    }
                    .frame(height: 160)
                    .clipShape(.rect(cornerRadius: 16))
                    .allowsHitTesting(false)
                }
                statusList(guardRows)
            } else {
                Button {
                    openURL(.emergency)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "phone.fill").font(.title)
                        Text("Llamar al 911").font(.title2.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Color.red, in: .rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                statusList(contactRows)
            }

            Spacer()

            VStack(spacing: 12) {
                if alert.scope == .guards {
                    Button {
                        openURL(.emergency)
                    } label: {
                        Label("Llamar al 911", systemImage: "phone.fill")
                    }
                    .buttonStyle(.islasDestructive)
                }
                AsyncButton("Estoy bien, cerrar alerta") {
                    await model.close()
                }
                .buttonStyle(.islasSecondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private struct Row: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
    }

    private var guardRows: [Row] {
        var rows: [Row] = []
        if let guardName = alert.guardName {
            let confirmed = alert.guardConfirmedAt.map { $0.formatted(.relative(presentation: .named)) } ?? ""
            rows.append(Row(id: "guard", icon: "checkmark", tint: .green, title: "\(guardName) atiende", subtitle: "Confirmó \(confirmed) · va en camino"))
        } else {
            rows.append(Row(id: "guard", icon: "clock", tint: .orange, title: "Avisando a los guardias en turno", subtitle: alert.status == .received ? "Alerta recibida en caseta" : "Enviando…"))
        }
        rows.append(Row(id: "location", icon: "location", tint: .blue, title: "Compartiendo tu ubicación", subtitle: "En vivo, hasta que cierres la alerta"))
        if !alert.contacts.isEmpty {
            rows.append(Row(id: "contacts", icon: "person.2", tint: .blue, title: "Avisamos a tus contactos", subtitle: alert.contacts.map(\.name).joined(separator: ", ")))
        }
        return rows
    }

    private var contactRows: [Row] {
        var rows = alert.contacts.map { contact in
            contact.state == .seen
                ? Row(id: contact.id, icon: "checkmark", tint: .green, title: contact.name, subtitle: "Vio la alerta · \(contact.at?.shortTime ?? "")")
                : Row(id: contact.id, icon: "clock", tint: .orange, title: contact.name, subtitle: "Enviada por \(contact.channel)")
        }
        rows.append(Row(id: "location", icon: "location", tint: .blue, title: "Compartiendo tu ubicación", subtitle: "Con tus contactos de emergencia"))
        return rows
    }

    private func statusList(_ rows: [Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    IconTile(systemName: row.icon, tint: row.tint, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .accessibilityElement(children: .combine)
                if index < rows.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .cardBackground()
        .animation(.default, value: rows.map(\.title))
    }
}

private struct PanicFailedScreen: View {
    let message: String
    let onRetry: () async -> Void
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            panicGradient.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 56))
                Text("No se pudo enviar la alerta").font(.title2.bold())
                Text(message).multilineTextAlignment(.center)
                Spacer()
                Button {
                    openURL(.emergency)
                } label: {
                    Label("Llamar al 911", systemImage: "phone.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                AsyncButton("Reintentar", action: onRetry)
                    .buttonStyle(.islasSecondary)
                Button("Cerrar", action: onClose)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }
}
