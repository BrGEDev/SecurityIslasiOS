//
//  NewInvitationView.swift
//  SecurityIslas
//
//  Pantallas 14, 15 y 16. Invitación única de tipo Visita o Servicio (RF-07);
//  con "Varias personas" se vuelve de evento: un solo enlace con cupo (RF-75).
//  No pide Face ID para no meter fricción. Se comparte por WhatsApp, SMS o
//  enlace; la visita no instala nada.
//

import SwiftUI

struct NewInvitationView: View {
    let repository: VisitsRepository
    var onCreated: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    @State private var kind: AccessKind = .visit
    @State private var name = ""
    @State private var day = Date.now
    @State private var startTime = TimeOfDay(hour: 18, minute: 0).date()
    @State private var endTime = TimeOfDay(hour: 23, minute: 59).date()
    @State private var plate = ""
    @State private var isEvent = false
    @State private var capacity = 10
    @State private var errorMessage: String?
    @State private var created: Invitation?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && endTime > startTime
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(AccessKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section(isEvent ? "Nombre del evento" : "Nombre") {
                    TextField(isEvent ? "Cumpleaños de Sofía" : (kind == .visit ? "Luis Rivera" : "Mantenimiento de clima"), text: $name)
                        .textContentType(.name)
                }

                Section("Día") {
                    DatePicker("Día", selection: $day, in: Date.now..., displayedComponents: .date)
                }

                Section("Horario") {
                    DatePicker("Desde", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Hasta", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section("Placa (opcional)") {
                    TextField("ABC-123-D", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle(isOn: $isEvent.animation()) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Varias personas (evento)")
                            Text("Un enlace con cupo").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if isEvent {
                        Stepper("Cupo: \(capacity) personas", value: $capacity, in: 2...200)
                    }
                } footer: {
                    Text(isEvent
                         ? "Cada invitado se registra con su nombre y te avisamos en grupo, no uno por uno."
                         : "Al llegar, el guardia valida el código y te avisamos.")
                }
            }
            .navigationTitle("Nueva invitación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    AsyncButton {
                        await create()
                    } label: {
                        Label("Compartir invitación", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.islasPrimary)
                    .disabled(!canSubmit)
                }
            }
            .sheet(item: $created, onDismiss: {
                onCreated()
                dismiss()
            }) { invitation in
                ActivityShareSheet(items: [InvitationMessage.text(for: invitation, host: session.profile)])
                    .presentationDetents([.medium, .large])
            }
            .errorAlert($errorMessage)
        }
    }

    private func create() async {
        let calendar = Calendar.current
        let start = TimeOfDay(date: startTime).date(on: day, calendar: calendar)
        let end = TimeOfDay(date: endTime).date(on: day, calendar: calendar)
        let request = NewInvitationRequest(
            kind: kind,
            guestName: name.trimmingCharacters(in: .whitespaces),
            startsAt: start,
            endsAt: end,
            plate: plate.isEmpty ? nil : plate.uppercased(),
            isEvent: isEvent,
            capacity: isEvent ? capacity : nil
        )
        do {
            created = try await repository.createInvitation(request)
        } catch {
            errorMessage = error.userMessage
        }
    }
}

enum InvitationMessage {
    /// Mensaje que acompaña al enlace (pantalla 15).
    static func text(for invitation: Invitation, host: UserProfile?) -> String {
        let firstName = invitation.guestName.split(separator: " ").first.map(String.init) ?? invitation.guestName
        let day = Calendar.current.isDateInToday(invitation.startsAt)
            ? "hoy"
            : invitation.startsAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let greeting = invitation.isEvent ? "¡Hola!" : "Hola \(firstName),"
        let place = host?.residence.map { " en \($0.name)" } ?? ""
        return """
        \(greeting) te espero \(day) a partir de las \(invitation.startsAt.shortTime)\(place). \
        Muestra este código en la caseta: \(invitation.shareURL.absoluteString)
        """
    }

    static func text(for recurring: RecurringAccess) -> String {
        "Hola \(recurring.name), este es tu acceso (\(recurring.scheduleSummary)). Muéstralo en la caseta: \(recurring.shareURL.absoluteString)"
    }
}

/// 16: lo que ve la visita en el navegador (vista previa; la página es web).
struct InvitationPreviewView: View {
    let invitation: Invitation
    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text((profile.residence?.fraccionamientoName ?? "").uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Hola, \(invitation.guestName.split(separator: " ").first.map(String.init) ?? invitation.guestName)")
                    .font(.largeTitle.bold())
                Text("\(profile.firstName) te invitó a \(Text(profile.residence?.name ?? "").bold())")
                Text("\(invitation.startsAt.relativeDayAndTime.capitalized) a \(invitation.endsAt.shortTime)")
                    .foregroundStyle(.secondary)

                if let image = QRCodeRenderer.image(for: invitation.shareURL.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(16)
                        .background(.white, in: .rect(cornerRadius: 20))
                        .accessibilityLabel("Código QR de la invitación")
                }
                Text("El código cambia cada 30 s").font(.caption).foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("PIN de respaldo").font(.caption).foregroundStyle(.secondary)
                    Text(invitation.pin.map(String.init).joined(separator: " "))
                        .font(.title.monospacedDigit().bold())
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))

                Text("Muéstralo al guardia en la caseta. El código no abre la pluma por sí solo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding()
        }
        .readableContentWidth()
        .navigationTitle("Vista previa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: InvitationMessage.text(for: invitation, host: profile)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}
