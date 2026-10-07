//
//  HomeRegistrationView.swift
//  SecurityIslas
//
//  Pantalla 5. La vivienda se elige del catálogo de la administración; no se
//  escribe a mano. Propietario o arrendatario (RF-84). Los integrantes de la
//  familia no pasan por aquí: los invita el titular desde Cuenta (RF-64).
//

import SwiftUI

struct HomeRegistrationView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                OnboardingHeader(
                    title: model.isPreloaded ? "Confirma tus datos" : "Tu vivienda",
                    subtitle: model.selectedFraccionamiento?.name
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Nombre") {
                TextField("Nombre", text: $model.firstName)
                    .textContentType(.givenName)
            }

            Section("Apellidos") {
                TextField("Apellidos", text: $model.lastName)
                    .textContentType(.familyName)
            }

            Section("Vivienda") {
                NavigationLink {
                    HomePickerView(model: model)
                } label: {
                    Text(model.selectedHome?.name ?? "Elige tu vivienda")
                        .foregroundStyle(model.selectedHome == nil ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                }
            }

            Section {
                Picker("Soy", selection: $model.tenure) {
                    ForEach(Tenure.allCases) { tenure in
                        Text(tenure.title).tag(tenure)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Soy")
            } footer: {
                Text(model.isPreloaded
                     ? "Tu administración ya registró estos datos. Al confirmar, tu alta queda aprobada."
                     : "La administración usará estos datos para aprobar tu alta.")
            }

            if let error = model.errorMessage {
                Section { InlineError(message: error) }
            }
        }
        .onboardingStep(4)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                AsyncButton(model.isPreloaded ? "Confirmar" : "Enviar solicitud") {
                    await model.submitRegistration()
                }
                .buttonStyle(.islasPrimary)
                .disabled(!model.canSubmitRegistration)
            }
        }
    }
}

struct HomePickerView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [HomeOption] {
        guard !query.isEmpty else { return model.homes }
        return model.homes.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List(filtered) { home in
            Button {
                model.selectedHome = home
                dismiss()
            } label: {
                HStack {
                    Text(home.name).foregroundStyle(.primary)
                    Spacer()
                    if model.selectedHome == home {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Calle y número")
        .navigationTitle("Vivienda")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
