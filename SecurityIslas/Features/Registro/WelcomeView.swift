//
//  WelcomeView.swift
//  SecurityIslas
//
//  Pantalla 1 (Bienvenida). Conserva el diseño de marca de Islas: imagen de
//  fondo, logo y textos originales. Un solo botón principal y el enlace de
//  invitación; quien ya tiene cuenta también entra por aquí (RF-61).
//

import SwiftUI

struct WelcomeView: View {
    @Bindable var model: OnboardingModel
    @Environment(SessionStore.self) private var session
    @State private var showInviteSheet = false

    var body: some View {
        GeometryReader { proxy in
            let ancho = proxy.size.width

            ZStack(alignment: .top) {
                Image(.loginHero)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ancho, height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom, alignment: .top)
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Image(.logo)
                        .resizable()
                        .renderingMode(.template)
                        .colorInvert()
                        .scaledToFit()
                        .frame(width: ancho * 0.5)
                        .accessibilityLabel("Islas")

                    VStack(spacing: 30) {
                        Text(AppInfo.name)
                            .foregroundStyle(.cyan)
                            .font(.title.bold())

                        Text("La entrada a tu fraccionamiento en tu teléfono")
                            .foregroundStyle(.white)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 30)
                    .padding(.horizontal)
                    .frame(width: ancho)

                    Spacer()

                    VStack(spacing: 15) {
                        feature("bell.fill", "Te avisamos cuando llega tu visita y autoriza su entrada")
                        feature("car.rear.road.lane", "Abre la pluma desde tu iPhone, Apple Watch o con Siri")
                        feature("light.beacon.min.fill", "Aviso de emergencia inmediata con caseta y tus contactos")

                        if let notice = session.notice {
                            Label(notice, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.white)
                        }

                        if let code = model.inviteCode {
                            Label("Invitación lista · código \(code)", systemImage: "checkmark.seal.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.green)
                        }

                        Spacer(minLength: 5)

                        Button("Continuar") {
                            session.notice = nil
                            model.path.append(.phone)
                        }
                        .buttonStyle(IslasButton())

                        Button {
                            showInviteSheet = true
                        } label: {
                            Label("Tengo un enlace de invitación", systemImage: "link")
                                .foregroundStyle(.white)
                        }
                        .padding()
                    }
                    .padding()
                    .frame(maxWidth: ancho)

                    Spacer()

                    LegalLinks()
                        .padding()

                    Spacer()
                }
                .padding(.top, 60)
            }
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
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.accentColor)

            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .backgroundLabel()
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
