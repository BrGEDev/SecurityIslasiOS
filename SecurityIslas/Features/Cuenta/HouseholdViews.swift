//
//  HouseholdViews.swift
//  SecurityIslas
//
//  Pantallas 33 (Familia), 34 (Dispositivos) y 35 (Contactos de emergencia).
//

import SwiftUI
import UIKit

// MARK: - 33 Familia

/// El titular invita a su familia sin pasar por la administración (RF-64).
/// Invitar y quitar pide Face ID. Cualquier adulto autoriza visitas; solo el
/// titular agrega o quita integrantes.
struct FamilyView: View {
    let profile: UserProfile
    let repository: HouseholdRepository

    @State private var members: [FamilyMember] = []
    @State private var showInvite = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: member.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(.subheadline.weight(.semibold))
                            Text(member.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if profile.role == .holder, !member.isCurrentUser {
                            Button("Quitar", role: .destructive) {
                                Task { await remove(member) }
                            }
                        }
                    }
                }
            }

            if profile.role == .holder {
                Section {
                    Button {
                        showInvite = true
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemName: "person.badge.plus")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invitar integrante").font(.subheadline.weight(.semibold))
                                Text("Le llega un enlace a su celular").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("La administración puede ver y quitar estos accesos.")
                }
            }
        }
        .navigationTitle("Familia")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showInvite) {
            InviteFamilySheet { request in
                let member = try await repository.inviteFamily(request)
                members.append(member)
            }
        }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            members = try await repository.family()
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func remove(_ member: FamilyMember) async {
        do {
            try await repository.removeFamily(member)
            members.removeAll { $0.id == member.id }
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

private struct InviteFamilySheet: View {
    let onSend: (FamilyInviteRequest) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var isAdult = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ana García", text: $name).textContentType(.name)
                }
                Section("Celular") {
                    TextField("222 123 4567", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section {
                    Picker("Es", selection: $isAdult) {
                        Text("Adulto").tag(true)
                        Text("Menor").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(isAdult ? "Un adulto puede autorizar visitas." : "Un menor solo tiene su QR para entrar.")
                }
            }
            .navigationTitle("Invitar integrante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Enviar") { await send() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phone.filter(\.isNumber).count < 10)
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func send() async {
        let request = FamilyInviteRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            phone: "+52" + phone.filter(\.isNumber).suffix(10),
            role: isAdult ? .adult : .minor
        )
        do {
            try await onSend(request)
            dismiss()
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

// MARK: - 34 Dispositivos

/// Hasta 3 dispositivos por cuenta, cada uno con su propia llave (RF-66).
/// Quitar uno pide Face ID y le quita la llave al instante.
struct DevicesView: View {
    let repository: DeviceRepository

    @State private var list: DeviceList?
    @State private var errorMessage: String?
    @State private var confirmRemoval: Device?

    var body: some View {
        List {
            Section {
                ForEach(list?.devices ?? []) { device in
                    HStack(spacing: 12) {
                        IconTile(systemName: device.model.symbol)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.subheadline.weight(.semibold))
                            Text(device.isCurrent
                                 ? "Este iPhone · \(BiometricAuthenticator().biometryName)"
                                 : "Último uso \(device.lastUsedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if !device.isCurrent {
                            Button("Quitar", role: .destructive) { confirmRemoval = device }
                        }
                    }
                }
                if let list, list.devices.count < list.maxDevices {
                    let free = list.maxDevices - list.devices.count
                    Text("\(free) \(free == 1 ? "lugar disponible" : "lugares disponibles")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("Puedes tener hasta 3 dispositivos. Cada uno tiene su propia llave.")
                    .textCase(nil)
            } footer: {
                FootnoteLabel(text: "Si alguien entra con tu número en otro teléfono, te avisamos aquí.", systemImage: "bell")
                    .padding(.top, 6)
            }
        }
        .navigationTitle("Dispositivos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "¿Quitar \(confirmRemoval?.name ?? "este dispositivo")?",
            isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } }),
            titleVisibility: .visible,
            presenting: confirmRemoval
        ) { device in
            Button("Quitar", role: .destructive) { Task { await remove(device) } }
        } message: { _ in
            Text("Dejará de abrir la pluma y de recibir avisos al instante. Te pediremos Face ID.")
        }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            list = try await repository.devices()
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func remove(_ device: Device) async {
        do {
            try await repository.remove(device, signed: true)
            await load()
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

// MARK: - 35 Contactos de emergencia

/// Reciben la alerta y la ubicación (RF-45). Cambiarlos pide Face ID. Aquí se
/// pide el permiso de ubicación "Siempre" que quedó pendiente en la pantalla 7.
struct EmergencyContactsView: View {
    let repository: HouseholdRepository

    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @State private var contacts: [EmergencyContact] = []
    @State private var showAdd = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(contacts) { contact in
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: contact.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.subheadline.weight(.semibold))
                            Text(contact.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Quitar", role: .destructive) { Task { await remove(contact) } }
                    }
                }
            } header: {
                Text("Les avisamos si activas el pánico fuera del fraccionamiento o si el reloj detecta una caída.")
                    .textCase(nil)
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Agregar contacto", systemImage: "plus")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { container.location.authorization == .always },
                    set: { enabled in
                        if enabled {
                            container.location.requestAlways()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ubicación \"Siempre\"")
                        Text("Para enviarla aunque la app esté cerrada").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
            }
        }
        .navigationTitle("Contactos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            AddContactSheet { request in
                let contact = try await repository.addContact(request)
                contacts.append(contact)
            }
        }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            contacts = try await repository.contacts()
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func remove(_ contact: EmergencyContact) async {
        do {
            try await repository.removeContact(contact)
            contacts.removeAll { $0.id == contact.id }
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

private struct AddContactSheet: View {
    let onSave: (NewEmergencyContactRequest) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = ""
    @State private var phone = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name).textContentType(.name)
                TextField("Parentesco (ej. Papá)", text: $relationship)
                TextField("Celular", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            .navigationTitle("Nuevo contacto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Guardar") {
                        do {
                            try await onSave(NewEmergencyContactRequest(
                                name: name.trimmingCharacters(in: .whitespaces),
                                relationship: relationship.trimmingCharacters(in: .whitespaces),
                                phone: phone.filter { $0.isNumber || $0 == "+" }
                            ))
                            dismiss()
                        } catch BiometricError.canceled {
                            return
                        } catch {
                            errorMessage = error.userMessage
                        }
                    }
                    .disabled(name.isEmpty || phone.filter(\.isNumber).count < 10)
                }
            }
            .errorAlert($errorMessage)
        }
    }
}
