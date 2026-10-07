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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guest.name).font(.subheadline.weight(.semibold))
                        Text("\(guest.arrival.relativeDayAndTime) → \(guest.departure.relativeDayAndTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            Text("Aviso inmediato fuera de horario").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
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
