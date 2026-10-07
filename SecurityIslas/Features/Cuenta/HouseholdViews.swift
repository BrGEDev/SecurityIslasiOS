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
    @State private var pendingMemberRemoval: FamilyMember?
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
                            // Sin `role: .destructive`: ese rol quita la fila al
                            // instante y choca con el borrado tras Face ID y red.
                            Button("Quitar") { pendingMemberRemoval = member }
                                .tint(.red)
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
        .readableContentWidth()
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
        .alert(
            "¿Quitar a \(pendingMemberRemoval?.name ?? "")?",
            isPresented: Binding(get: { pendingMemberRemoval != nil }, set: { if !$0 { pendingMemberRemoval = nil } }),
            presenting: pendingMemberRemoval
        ) { member in
            Button("Quitar", role: .destructive) { Task { await remove(member) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Perderá el acceso de inmediato en todos sus dispositivos.")
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

    @Environment(AppContainer.self) private var container
    @State private var list: DeviceList?
    @State private var errorMessage: String?
    @State private var confirmRemoval: Device?
    @State private var showPairing = false

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
                                 : "Último uso \(device.lastUsedAt.formatted(.relative(presentation: .named).locale(.app)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if !device.isCurrent {
                            Button("Quitar") { confirmRemoval = device }
                                .tint(.red)
                        }
                    }
                }
                if let list, list.freeSlots > 0 {
                    let free = list.freeSlots
                    Text("\(free) \(free == 1 ? "lugar disponible" : "lugares disponibles")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("Puedes tener hasta 3 teléfonos o tabletas; tus Apple Watch no cuentan. Cada uno tiene su propia llave.")
                    .textCase(nil)
            } footer: {
                FootnoteLabel(text: "Si alguien entra con tu número en otro teléfono, te avisamos aquí.", systemImage: "bell")
                    .padding(.top, 6)
            }

            watchSection
        }
        .readableContentWidth()
        .navigationTitle("Dispositivos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "¿Quitar \(confirmRemoval?.name ?? "este dispositivo")?",
            isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } }),
            presenting: confirmRemoval
        ) { device in
            Button("Quitar", role: .destructive) { Task { await remove(device) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Dejará de abrir la pluma y de recibir avisos al instante.")
        }
        .errorAlert($errorMessage)
        .sheet(isPresented: $showPairing, onDismiss: { Task { await load() } }) {
            WatchPairingView()
        }
    }

    /// Vincular el Apple Watch (sección G): el reloj registra su propia llave.
    private var watchSection: some View {
        let hasWatch = list?.devices.contains { $0.model == .watch } ?? false
        return Section {
            Button {
                showPairing = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasWatch ? "Volver a vincular Apple Watch" : "Vincular Apple Watch")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Visitas, pluma, QR y pánico en tu muñeca")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
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
            if device.model == .watch {
                container.watch.sendIfPossible(.unlinked)
            }
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
    @State private var pendingContactRemoval: EmergencyContact?
    @State private var settingsPrompt: LocationSettingsPrompt?
    @Environment(\.scenePhase) private var scenePhase
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
                        Button("Quitar") { pendingContactRemoval = contact }
                            .tint(.red)
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
                            // Si iOS ya no mostrará su aviso, se explica y se manda a Ajustes.
                            if !container.location.requestAlways() {
                                settingsPrompt = .enableAlways
                            }
                        } else {
                            // Las apps no pueden quitarse permisos; solo el usuario en Ajustes.
                            settingsPrompt = .disableAlways
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ubicación \"Siempre\"")
                        Text("Para enviarla aunque la app esté cerrada").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
            } footer: {
                Text(locationFooter)
            }
        }
        .readableContentWidth()
        .alert(
            "¿Quitar a \(pendingContactRemoval?.name ?? "")?",
            isPresented: Binding(get: { pendingContactRemoval != nil }, set: { if !$0 { pendingContactRemoval = nil } }),
            presenting: pendingContactRemoval
        ) { contact in
            Button("Quitar", role: .destructive) { Task { await remove(contact) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Ya no recibirá tus alertas de pánico.")
        }
        .alert(
            settingsPrompt?.title ?? "",
            isPresented: Binding(get: { settingsPrompt != nil }, set: { if !$0 { settingsPrompt = nil } }),
            presenting: settingsPrompt
        ) { _ in
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Ahora no", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        // Al volver de Ajustes (o del aviso de iOS) el switch refleja el permiso real.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { container.location.refreshAuthorization() }
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

    private var locationFooter: String {
        switch container.location.authorization {
        case .always:
            "Si activas el pánico, tus contactos y la caseta reciben tu ubicación aunque cierres la app."
        case .whenInUse:
            "Ahora solo se comparte con la app abierta. Si la cierras durante una alerta, dejamos de enviar tu ubicación."
        case .denied:
            "La ubicación está desactivada. El pánico avisará sin tu ubicación."
        case .notDetermined:
            "Activa la ubicación para que el pánico la comparta."
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

/// Avisos para cambiar el permiso de ubicación en Ajustes.
private enum LocationSettingsPrompt: Identifiable {
    case enableAlways
    case disableAlways

    var id: Self { self }

    var title: String {
        switch self {
        case .enableAlways: "Activa \"Siempre\" en Ajustes"
        case .disableAlways: "Cambia el permiso en Ajustes"
        }
    }

    var message: String {
        switch self {
        case .enableAlways:
            "En Ajustes › Ubicación, elige \"Siempre\" para que el pánico comparta tu ubicación aunque la app esté cerrada."
        case .disableAlways:
            "En Ajustes › Ubicación, elige \"Al usar la app\". El pánico solo compartirá tu ubicación con la app abierta."
        }
    }
}
