//
//  PhoneNumberView.swift
//  SecurityIslas
//
//  Pantalla 2. Teclado numérico, 10 dígitos con lada +52 por omisión; el
//  botón se habilita cuando el número está completo.
//

import SwiftUI

struct PhoneNumberView: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                OnboardingHeader(
                    title: "Tu número de celular",
                    subtitle: "Te enviaremos un código por SMS para verificarlo."
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Menu {
                            Picker("Lada", selection: $model.country) {
                                ForEach(CountryCode.all) { country in
                                    Text("\(country.iso) +\(country.dialCode)").tag(country)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(model.country.iso) +\(model.country.dialCode)")
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(.primary)
                            .padding()
                            .cardBackground(cornerRadius: 20)
                        }
                        .accessibilityLabel("Lada \(model.country.dialCode)")

                        TextField("222 123 4567", text: Binding(
                            get: { PhoneNumber.group(model.phoneDigits) },
                            set: { model.updatePhone($0) }
                        ))
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .font(.title3)
                        .focused($focused)
                        .textFieldStyle(FieldStyle())
                    }

                    InlineError(message: model.errorMessage)

                    Text("Con este número te identifican la caseta y tu familia.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onboardingStep(1)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                AsyncButton("Enviar código") {
                    await model.sendCode()
                }
                .buttonStyle(.islasPrimary)
                .disabled(!model.canSendCode)
            }
        }
        .onAppear {
            model.errorMessage = nil
            focused = true
        }
    }
}
