//
//  VerificationCodeView.swift
//  SecurityIslas
//
//  Pantalla 3. iOS sugiere el código arriba del teclado y al completarlo se
//  verifica solo. Si el número ya tiene cuenta pasa a 3a; si la
//  administración lo precargó, a la 5 para confirmar datos.
//

import SwiftUI

struct VerificationCodeView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Escribe el código")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    TextNavigation(
                        text: "Lo enviamos al \(model.phone.formatted).",
                        textButton: "Cambiar"
                    ) {
                        model.path.removeLast()
                    }
                    .foregroundStyle(.secondary)
                }

                VerificationCodeInputView(code: $model.code) { _ in
                    Task { await model.verifyCode() }
                }
                .disabled(model.isLoading)

                if model.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Verificando…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                InlineError(message: model.errorMessage)

                ResendCodeButton(availableAt: model.resendAvailableAt) {
                    await model.resendCode()
                }
                .frame(maxWidth: .infinity)

                #if DEBUG
                if AppInfo.usesMockBackend {
                    FootnoteLabel(text: "Backend de prueba: el código es 123456.", systemImage: "hammer")
                }
                #endif
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .readableContentWidth()
        .onboardingStep(2)
        .onAppear { model.errorMessage = nil }
    }
}

/// "Reenviar código en 0:42" con cuenta regresiva real.
private struct ResendCodeButton: View {
    let availableAt: Date?
    let action: () async -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((availableAt ?? .distantPast).timeIntervalSince(context.date).rounded(.up)))
            if remaining > 0 {
                Text("Reenviar código en \(Text(String(format: "%d:%02d", remaining / 60, remaining % 60)).bold())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                AsyncButton("Reenviar código", action: action)
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}
