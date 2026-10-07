//
//  WatchPanicView.swift
//  SecurityIslasWatch Watch App
//
//  Pánico desde el reloj (RF-41): mantener 3 s → cuenta regresiva cancelable
//  → alerta y seguimiento. Usa el mismo PanicViewModel que el iPhone, así que
//  el destino (guardias dentro, contactos fuera) sigue la misma regla (RF-42).
//  La caída (pantalla 42) es fase 5 y no se incluye.
//

import SwiftUI
import WatchKit

struct WatchPanicView: View {
    @State private var model: PanicViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: PanicViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.stage {
            case .hold:
                WatchPanicHoldView(description: model.recipientsDescription) {
                    model.startCountdown()
                }
            case .countdown(let remaining):
                WatchPanicCountdownView(remaining: remaining, insidePerimeter: model.insidePerimeter) {
                    model.cancel()
                }
            case .sending:
                WatchPanicCountdownView(remaining: nil, insidePerimeter: model.insidePerimeter, onCancel: nil)
            case .active:
                if let alert = model.alert {
                    WatchPanicActiveView(model: model, alert: alert)
                }
            case .failed(let message):
                WatchPanicFailedView(message: message) {
                    await model.retry()
                }
            }
        }
        .navigationTitle("Pánico")
        .task { await model.prepare() }
        .onChange(of: model.didFinish) { _, finished in
            if finished { dismiss() }
        }
        .alert(
            "No se pudo completar",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - 24: mantener presionado

/// Mismo tiempo que en el iPhone (RF-40).
private let holdDuration: Double = 3

private struct WatchPanicHoldView: View {
    let description: String
    let onComplete: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    @State private var hapticsTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.red.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(.red.gradient)
                        .padding(10)
                    Image(systemName: "sos")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 100, height: 100)
                .scaleEffect(isPressing ? 0.94 : 1)
                .animation(.spring(duration: 0.3), value: isPressing)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 30) {
                    stopHaptics()
                    WKInterfaceDevice.current().play(.success)
                    progress = 0
                    isPressing = false
                    onComplete()
                } onPressingChanged: { pressing in
                    isPressing = pressing
                    if pressing {
                        startHaptics()
                        withAnimation(.linear(duration: holdDuration)) { progress = 1 }
                    } else {
                        stopHaptics()
                        withAnimation(.spring(duration: 0.3)) { progress = 0 }
                    }
                }
                .accessibilityLabel("Botón de pánico")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onComplete() }

                Text(isPressing ? "Suelta para cancelar" : "Mantén presionado")
                    .font(.headline)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .onDisappear { stopHaptics() }
    }

    /// Toques que se aceleran mientras se mantiene presionado.
    private func startHaptics() {
        stopHaptics()
        hapticsTask = Task {
            let start = Date.now
            while !Task.isCancelled {
                let elapsed = Date.now.timeIntervalSince(start) / holdDuration
                guard elapsed < 1 else { return }
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(0.45 - 0.3 * elapsed))
            }
        }
    }

    private func stopHaptics() {
        hapticsTask?.cancel()
        hapticsTask = nil
    }
}

// MARK: - 25: cuenta regresiva

private struct WatchPanicCountdownView: View {
    let remaining: Int?
    let insidePerimeter: Bool
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.red, lineWidth: 4)
                if let remaining {
                    Text("\(remaining)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    ProgressView()
                }
            }
            .frame(width: 84, height: 84)

            Text(insidePerimeter ? "Avisamos a caseta" : "Avisamos a tus contactos")
                .font(.headline)
                .multilineTextAlignment(.center)

            if let onCancel {
                Button("Cancelar", role: .cancel, action: onCancel)
            }
        }
        .animation(.snappy, value: remaining)
        .onChange(of: remaining) { _, new in
            if new != nil { WKInterfaceDevice.current().play(.notification) }
        }
    }
}

// MARK: - 26 / 27: alerta enviada

private struct WatchPanicActiveView: View {
    let model: PanicViewModel
    let alert: PanicAlert
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Label {
                    Text(statusTitle).font(.headline)
                } icon: {
                    Image(systemName: alert.guardName == nil ? "clock.fill" : "checkmark.circle.fill")
                        .foregroundStyle(alert.guardName == nil ? Color.orange : Color.green)
                }
                Label("Compartiendo tu ubicación", systemImage: "location.fill")
                    .font(.footnote)
                ForEach(alert.contacts, id: \.id) { contact in
                    Label(
                        contact.state == .seen ? "\(contact.name) la vio" : "\(contact.name) · enviada",
                        systemImage: contact.state == .seen ? "checkmark" : "paperplane"
                    )
                    .font(.footnote)
                }
            }

            Section {
                Button {
                    openURL(.emergency)
                } label: {
                    Label("Llamar al 911", systemImage: "phone.fill")
                }
                .listItemTint(.red)

                Button {
                    Task { await model.close() }
                } label: {
                    if model.isClosing {
                        ProgressView()
                    } else {
                        Text("Estoy bien, cerrar alerta")
                    }
                }
                .disabled(model.isClosing)
            }
        }
    }

    private var statusTitle: String {
        if alert.scope == .contacts { return "Alerta a tus contactos" }
        if let guardName = alert.guardName { return "\(guardName) atiende" }
        return alert.status == .received ? "Alerta recibida en caseta" : "Avisando a los guardias"
    }
}

private struct WatchPanicFailedView: View {
    let message: String
    let onRetry: () async -> Void
    @Environment(\.openURL) private var openURL
    @State private var retrying = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("No se pudo enviar la alerta")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    openURL(.emergency)
                } label: {
                    Label("Llamar al 911", systemImage: "phone.fill")
                }
                .tint(.red)
                Button {
                    retrying = true
                    Task {
                        await onRetry()
                        retrying = false
                    }
                } label: {
                    if retrying { ProgressView() } else { Text("Reintentar") }
                }
                .disabled(retrying)
            }
        }
    }
}
