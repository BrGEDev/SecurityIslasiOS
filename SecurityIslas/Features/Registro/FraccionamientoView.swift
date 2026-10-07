//
//  FraccionamientoView.swift
//  SecurityIslas
//
//  Pantalla 4. Solo aparecen los fraccionamientos que su administración dio
//  de alta (RF-60). Sin ubicación todavía: no se piden permisos antes de tiempo.
//

import SwiftUI

struct FraccionamientoView: View {
    @Bindable var model: OnboardingModel
    @State private var showInviteSheet = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    OnboardingHeader(title: "¿Dónde vives?", subtitle: "Busca tu fraccionamiento o condominio.")
                    SearchField(
                        "Bosques Sanctorum, Paseos del Ángel…",
                        text: $model.searchText,
                        backgroundColor: Color(.tertiarySystemFill),
                        leadingIcon: { Image(systemName: "magnifyingglass") },
                        trailingIcon: {
                            if !model.searchText.isEmpty {
                                Button {
                                    model.searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Borrar búsqueda")
                            }
                        }
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if model.fraccionamientos.isEmpty {
                    Text(model.searchText.isEmpty ? "Cargando…" : "Sin resultados para “\(model.searchText)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.fraccionamientos) { fraccionamiento in
                    Button {
                        model.selectedFraccionamiento = fraccionamiento
                    } label: {
                        HStack(spacing: 14) {
                            IconTile(systemName: "building.2")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fraccionamiento.name).font(.body.weight(.semibold))
                                Text(fraccionamiento.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedFraccionamiento == fraccionamiento {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(model.selectedFraccionamiento == fraccionamiento ? Color.accentColor.opacity(0.08) : nil)
                    .accessibilityAddTraits(model.selectedFraccionamiento == fraccionamiento ? .isSelected : [])
                }
            }

            Section {
                Button {
                    showInviteSheet = true
                } label: {
                    Label("Tengo un código de invitación", systemImage: "link")
                }
            } footer: {
                Text("¿No aparece? Solo se muestran los fraccionamientos que su administración ya dio de alta.")
            }

            if let error = model.errorMessage {
                Section { InlineError(message: error) }
            }
        }
        .onboardingStep(3)
        .task(id: model.searchText) {
            await model.search()
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                AsyncButton("Continuar") {
                    await model.continueWithFraccionamiento()
                }
                .buttonStyle(.islasPrimary)
                .disabled(model.selectedFraccionamiento == nil)
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteCodeSheet { code in
                await model.applyInviteCode(code)
            }
        }
    }
}
