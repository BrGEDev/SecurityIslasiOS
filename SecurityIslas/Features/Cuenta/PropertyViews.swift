//
//  PropertyViews.swift
//  SecurityIslas
//
//  Pantallas 36 (Huésped temporal) y 37 (Permiso de obra).
//

import SwiftUI

// MARK: - 36 Huéspedes

/// Renta vacacional: lo da de alta el titular o el propietario con fechas de
/// entrada y salida (RF-92). No convierte la vivienda en comercio.
struct GuestsView: View {
    let repository: HouseholdRepository

    @State private var guests: [TemporaryGuest] = []
    @State private var showNew = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if guests.isEmpty {
                    Text("Sin huéspedes registrados.").foregroundStyle(.secondary)
                }
                ForEach(guests) { guest in
                    NavigationLink(value: guest) {
                        HStack(spacing: 12) {
                            InitialsAvatar(initials: Initials.from(guest.name))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guest.name).font(.subheadline.weight(.semibold))
                                Text("\(guest.arrival.relativeDayAndTime) → \(guest.departure.relativeDayAndTime)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            GuestStageChip(stage: guest.stage())
                        }
                    }
                }
            } footer: {
                Text("Cada huésped recibe su propio QR para la estancia; te avisamos cada vez que entra y el acceso vence solo.")
            }
        }
        .readableContentWidth()
        .navigationTitle("Huéspedes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuevo huésped")
            }
        }
        .navigationDestination(for: TemporaryGuest.self) { guest in
            GuestDetailView(guest: guest)
        }
        .task { await load() }
        .sheet(isPresented: $showNew) {
            NewGuestView { request in
                let guest = try await repository.createGuest(request)
                guests.append(guest)
            }
        }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            guests = try await repository.guests()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

private struct GuestStageChip: View {
    let stage: TemporaryGuest.Stage

    var body: some View {
        switch stage {
        case .upcoming: StatusChip(text: "Por llegar", tint: .blue)
        case .staying: StatusChip(text: "Hospedado", tint: .green)
        case .finished: StatusChip(text: "Venció", tint: .gray)
        }
    }
}

/// Su propio QR durante la estancia (RF-92). La página del enlace muestra el
/// QR dinámico y el PIN; aquí se ve el mismo enlace para reenviarlo y cada
/// entrada registrada (también llega un aviso por cada una).
struct GuestDetailView: View {
    let guest: TemporaryGuest

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    InitialsAvatar(initials: Initials.from(guest.name), size: 64)
                    Text(guest.name).font(.title3.weight(.semibold))
                    GuestStageChip(stage: guest.stage())
                    if guest.stage() != .finished, let url = guest.shareURL,
                       let image = QRCodeRenderer.image(for: url.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(12)
                            .background(.white, in: .rect(cornerRadius: 18, style: .continuous))
                            .accessibilityLabel("Código QR del huésped")
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Llegada", value: guest.arrival.relativeDayAndTime.sentenceCased)
                LabeledContent("Salida", value: guest.departure.relativeDayAndTime.sentenceCased)
                LabeledContent("Celular", value: guest.phone)
                if let pin = guest.pin {
                    LabeledContent("PIN de respaldo", value: pin)
                }
            } footer: {
                Text("El acceso vence solo al terminar la estancia. No convierte tu vivienda en comercio.")
            }

            Section {
                if let entries = guest.entries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.enteredAt.relativeDayAndTime.sentenceCased).font(.subheadline.weight(.semibold))
                            Text(entry.exitedAt.map { "Entró \(entry.enteredAt.shortTime) · salió \($0.shortTime)" } ?? "Entró \(entry.enteredAt.shortTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Aún no ha entrado.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Entradas")
            } footer: {
                Text("Te avisamos cada vez que entra.")
            }

            if guest.stage() != .finished, let url = guest.shareURL {
                Section {
                    ShareLink(item: url, message: Text("Hola, este es tu acceso de huésped. Muéstralo en la caseta.")) {
                        Label("Reenviar acceso", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .readableContentWidth()
        .navigationTitle("Huésped")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewGuestView: View {
    let onSend: (NewGuestRequest) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var arrival = Calendar.current.date(byAdding: .day, value: 2, to: TimeOfDay(hour: 15, minute: 0).date()) ?? .now
    @State private var departure = Calendar.current.date(byAdding: .day, value: 4, to: TimeOfDay(hour: 12, minute: 0).date()) ?? .now
    @State private var phone = ""
    @State private var errorMessage: String?

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && departure > arrival
            && phone.filter(\.isNumber).count >= 10
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre del huésped") {
                    TextField("Familia Thompson", text: $name)
                }
                Section("Llegada") {
                    DatePicker("Llegada", selection: $arrival, in: Date.now...)
                        .labelsHidden()
                }
                Section("Salida") {
                    DatePicker("Salida", selection: $departure, in: arrival...)
                        .labelsHidden()
                }
                Section {
                    TextField("+1 512 555 0142", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("Celular")
                } footer: {
                    Label("Recibe su propio QR para la estancia. Te avisamos cada vez que entre y el acceso vence solo.", systemImage: "qrcode")
                }
            }
            .navigationTitle("Nuevo huésped")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    AsyncButton("Enviar acceso") { await send() }
                        .buttonStyle(.islasPrimary)
                        .disabled(!canSend)
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func send() async {
        do {
            try await onSend(NewGuestRequest(
                name: name.trimmingCharacters(in: .whitespaces),
                arrival: arrival,
                departure: departure,
                phone: phone.filter { $0.isNumber || $0 == "+" }
            ))
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

// MARK: - 37 Permiso de obra

/// Lo solicita el propietario y lo aprueba la administración; cada trabajador
/// se registra al entrar (RF-88). Resumen diario al dueño y aviso inmediato
/// fuera de horario o con coincidencia en la lista restringida (RF-89).
struct WorkPermitView: View {
    let repository: HouseholdRepository

    @State private var permit: WorkPermit?
    @State private var isLoaded = false
    @State private var showRequest = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let permit {
                Section {
                    statusBanner(permit)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Responsable", value: permit.responsible)
                    LabeledContent("Licencia de construcción", value: permit.license)
                    LabeledContent("Periodo", value: "\(permit.startsOn.longDay) a \(permit.endsOn.longDay)")
                    LabeledContent("Horario de obra", value: permit.schedule)
                }
                Section {
                    Toggle(isOn: Binding(
                        get: { permit.dailySummary },
                        set: { value in Task { await setDailySummary(value) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resumen diario de entradas")
                            Text("Al final del día, quién entró a tu obra").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                } footer: {
                    Text("Siempre te avisamos al instante si alguien entra fuera del horario de obra o coincide con la lista restringida.")
                }

                if permit.status == .approved {
                    Section {
                        let entries = permit.todayEntries ?? []
                        if entries.isEmpty {
                            Text("Hoy no ha entrado nadie.").foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            WorkEntryRow(entry: entry)
                        }
                    } header: {
                        Text("Entradas de hoy")
                    } footer: {
                        Text("El guardia registra a cada trabajador por nombre al entrar. Fuera de horario aplica el flujo normal de visitas.")
                    }
                }
            } else if isLoaded {
                ContentUnavailableView {
                    Label("Sin permiso de obra", systemImage: "hammer")
                } description: {
                    Text("Solicítalo para que la cuadrilla entre en su horario sin pedirte autorización cada día.")
                } actions: {
                    Button("Solicitar permiso") { showRequest = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        }
        .readableContentWidth()
        .navigationTitle("Permiso de obra")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showRequest) {
            WorkPermitRequestView { request in
                permit = try await repository.requestWorkPermit(request)
            }
        }
        .errorAlert($errorMessage)
    }

    private func statusBanner(_ permit: WorkPermit) -> some View {
        let (icon, tint, title): (String, Color, String) = switch permit.status {
        case .inReview: ("clock", .orange, "En revisión por la administración")
        case .approved: ("checkmark.seal", .green, "Aprobado")
        case .rejected: ("xmark.octagon", .red, "Rechazado por la administración")
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("Enviado el \(permit.submittedAt.formatted(.dateTime.day().month(.abbreviated).locale(.app)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 16))
    }

    private func load() async {
        do {
            permit = try await repository.workPermit()
            isLoaded = true
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func setDailySummary(_ enabled: Bool) async {
        do {
            permit = try await repository.setDailySummary(enabled)
        } catch {
            errorMessage = error.userMessage
        }
    }
}

private struct WorkEntryRow: View {
    let entry: WorkEntry

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(initials: Initials.from(entry.name))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.weight(.semibold))
                Text(entry.exitedAt.map { "Entró \(entry.enteredAt.shortTime) · salió \($0.shortTime)" } ?? "Entró \(entry.enteredAt.shortTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if entry.outsideSchedule {
                    StatusChip(text: "Fuera de horario", tint: .orange)
                }
                if let match = entry.restrictedMatch {
                    StatusChip(text: match == .confirmed ? "Lista restringida" : "Posible coincidencia", tint: .yellow)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkPermitRequestView: View {
    let onSend: (WorkPermitRequest) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var responsible = ""
    @State private var license = ""
    @State private var startsOn = Date.now
    @State private var endsOn = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var schedule = "L a V 8:00 a 18:00 · S 8:00 a 14:00"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Responsable (maestro de obra o DRO)") {
                    TextField("Arq. Mario Luna · DRO", text: $responsible)
                }
                Section("Licencia de construcción") {
                    TextField("LC-2026-0418", text: $license)
                        .textInputAutocapitalization(.characters)
                }
                Section("Periodo") {
                    DatePicker("Inicio", selection: $startsOn, displayedComponents: .date)
                    DatePicker("Fin", selection: $endsOn, in: startsOn..., displayedComponents: .date)
                }
                Section {
                    TextField("Horario", text: $schedule)
                } header: {
                    Text("Horario de obra")
                } footer: {
                    Text("Debe respetar el horario del reglamento. Fuera de él aplica el flujo normal de visitas.")
                }
            }
            .navigationTitle("Solicitar permiso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Enviar") {
                        do {
                            try await onSend(WorkPermitRequest(
                                responsible: responsible,
                                license: license,
                                startsOn: startsOn,
                                endsOn: endsOn,
                                schedule: schedule
                            ))
                            dismiss()
                        } catch {
                            errorMessage = error.userMessage
                        }
                    }
                    .disabled(responsible.isEmpty || license.isEmpty)
                }
            }
            .errorAlert($errorMessage)
        }
    }
}
