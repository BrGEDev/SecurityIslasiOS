//
//  WelcomeView.swift
//  SecurityIslas
//
//  Pantalla 1 (Bienvenida). Debe quedar tal cual la maqueta: un solo botón
//  "Comenzar" y el enlace de invitación. Quien ya tiene cuenta también toca
//  "Comenzar" (RF-61).
//

import SwiftUI

struct WelcomeView: View {
    @Bindable var model: OnboardingModel
    @Environment(SessionStore.self) private var session
    @State private var showInviteSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 14) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(
                            LinearGradient(colors: [.blue, Color(red: 0.05, green: 0.3, blue: 0.85)], startPoint: .top, endPoint: .bottom),
                            in: .rect(cornerRadius: 22)
                        )
                        .shadow(color: .blue.opacity(0.35), radius: 16, y: 8)
                        .accessibilityHidden(true)

                    Text(AppInfo.name)
                        .font(.system(size: 40, weight: .bold))

                    Text("La entrada de tu fraccionamiento,\nen tu teléfono.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    feature("bell", "Te avisamos cuando llega tu visita")
                    feature("road.lanes", "Abre la pluma desde tu iPhone o Siri")
                    feature("exclamationmark.triangle", "Botón de pánico conectado a caseta")
                }

                if let notice = session.notice {
                    FootnoteLabel(text: notice, systemImage: "info.circle")
                }

                if let code = model.inviteCode {
                    Label("Invitación lista · código \(code)", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                Button("Comenzar") {
                    session.notice = nil
                    model.path.append(.phone)
                }
                .buttonStyle(.islasPrimary)

                Button {
                    showInviteSheet = true
                } label: {
                    Label("Tengo un enlace de invitación", systemImage: "link")
                        .font(.body.weight(.medium))
                }

                LegalLinks()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showInviteSheet) {
            InviteCodeSheet { code in
                await model.applyInviteCode(code)
                model.path.append(.phone)
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

/// Captura el enlace o código de invitación de la administración.
struct InviteCodeSheet: View {
    var onSubmit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("acceso.app/i/7KX2 o 7KX2", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Pega el enlace que te mandó tu administración o escribe el código.")
                }
            }
            .navigationTitle("Código de invitación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Continuar") {
                        await onSubmit(Self.extractCode(from: text))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).count < 4)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Acepta el enlace completo o solo el código.
    static func extractCode(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.split(separator: "/").last, trimmed.contains("/") {
            return String(last)
        }
        return trimmed
    }
}
