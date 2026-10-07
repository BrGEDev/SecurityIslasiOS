//
//  WatchPairingView.swift
//  SecurityIslas
//
//  Vincular el Apple Watch (sección G) con pasos como la configuración del
//  reloj en el iPhone: presentación → (instalar la app) → Face ID → el reloj
//  crea su llave mientras ambos muestran el mismo código → listo.
//

import SwiftUI

struct WatchPairingView: View {
    nonisolated enum Step: Equatable {
        case intro
        case install
        case linking(verification: String)
        case done(watchName: String)
    }

    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var step: Step = .intro
    @State private var isWorking = false
    @State private var isSlow = false
    @State private var errorMessage: String?
    @State private var slowTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        PairingOrb(phase: orbPhase, size: 230)
                            .padding(.top, 24)
                        content
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)

                BottomActionBar { actions }
            }
            .animation(.smooth(duration: 0.45), value: step)
            .toolbar {
                if !isDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isWorking)
        .errorAlert($errorMessage)
        .sensoryFeedback(.success, trigger: step) { _, new in
            if case .done = new { return true }
            return false
        }
        .onChange(of: container.watch.lastLinked) { _, linked in
            guard let linked, case .linking = step else { return }
            slowTask?.cancel()
            step = .done(watchName: linked.name)
        }
        .onChange(of: container.watch.canLink) { _, canLink in
            // Al terminar de instalarse la app en el reloj, avanza solo.
            if canLink, step == .install { step = .intro }
        }
        .onDisappear { slowTask?.cancel() }
    }

    // MARK: - Contenido por paso

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            header(
                title: "Vincula tu Apple Watch",
                subtitle: "Tu reloj tendrá su propia llave y funcionará aunque el iPhone no esté cerca."
            )
            VStack(alignment: .leading, spacing: 18) {
                feature("bell.badge.fill", .orange, "Responde visitas", "Autoriza o rechaza desde el aviso en tu muñeca.")
                feature("door.garage.open", .blue, "Abre la pluma", "Cerca de la entrada, con el reloj puesto y desbloqueado.")
                feature("qrcode", .purple, "Muestra tu QR", "Se genera en el reloj, también sin internet.")
                feature("sos.circle.fill", .red, "Pide ayuda", "Mantén presionado para enviar una alerta.")
            }
            .padding(.top, 4)

        case .install:
            header(
                title: "Instala \(AppInfo.name) en tu reloj",
                subtitle: "Abre la app Watch de tu iPhone y, en Apps disponibles, toca Instalar junto a \(AppInfo.name)."
            )
            VStack(alignment: .leading, spacing: 14) {
                numbered(1, "Abre la app Watch.")
                numbered(2, "Ve a Mi reloj › Apps disponibles.")
                numbered(3, "Toca Instalar junto a \(AppInfo.name).")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
            Label("Continuaremos solos en cuanto termine de instalarse.", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .linking(let verification):
            header(
                title: container.watch.isReachable ? "Vinculando…" : "Abre \(AppInfo.name) en tu reloj",
                subtitle: container.watch.isReachable
                    ? "Tu reloj está creando su llave. Mantenlo cerca."
                    : "Ahí terminará de vincularse. Mantén el reloj cerca del iPhone."
            )
            VStack(spacing: 8) {
                Text("Confirma que tu reloj muestre")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VerificationDigits(code: verification)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
            if isSlow {
                Label("¿No aparece? Abre la app en el reloj o vuelve a enviar el código.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

        case .done(let watchName):
            header(
                title: "Tu Apple Watch está listo",
                subtitle: "\(watchName) ya tiene su llave. Lo verás en Dispositivos y puedes quitarlo cuando quieras."
            )
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch step {
        case .intro:
            AsyncButton {
                await start()
            } label: {
                Text("Continuar")
            }
            .buttonStyle(.islasPrimary)
        case .install:
            Button("Abrir app Watch") {
                if let url = URL(string: "itms-watchs://") { openURL(url) }
            }
            .buttonStyle(.islasPrimary)
            Button("Ya la instalé") { step = .intro }
                .buttonStyle(.islasSecondary)
        case .linking:
            AsyncButton {
                await start()
            } label: {
                Text("Volver a enviar")
            }
            .buttonStyle(.islasSecondary)
            .opacity(isSlow ? 1 : 0)
            .disabled(!isSlow)
        case .done:
            Button("Listo") { dismiss() }
                .buttonStyle(.islasPrimary)
        }
    }

    // MARK: - Lógica

    private var orbPhase: PairingOrb.Phase {
        switch step {
        case .intro, .install: .idle
        case .linking: .linking
        case .done: .done
        }
    }

    private var isDone: Bool {
        if case .done = step { return true }
        return false
    }

    /// Face ID (agregar un dispositivo es un cambio de cuenta, RF-67), código de
    /// un solo uso y envío al reloj por WatchConnectivity.
    private func start() async {
        guard container.watch.canLink else {
            step = .install
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let ticket = try await container.devices.createWatchLink()
            var account: Data?
            if let server = container.mockServer, let userId = session.profile?.id {
                account = await server.exportAccount(userId: userId)
            }
            try container.watch.send(.link(code: ticket.code, mockAccount: account))
            isSlow = false
            step = .linking(verification: WatchVerificationCode.from(linkCode: ticket.code))
            watchForSlowLink()
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func watchForSlowLink() {
        slowTask?.cancel()
        slowTask = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            withAnimation { isSlow = true }
        }
    }

    // MARK: - Piezas

    private func header(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

/// "4 8 2 1" en casillas, como los códigos de emparejamiento del sistema.
struct VerificationDigits: View {
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(code.enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .frame(width: 46, height: 58)
                    .background(Color(.systemBackground), in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Código \(code.map(String.init).joined(separator: " "))")
    }
}
