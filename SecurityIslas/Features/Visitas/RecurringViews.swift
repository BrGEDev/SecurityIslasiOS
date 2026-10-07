//
//  RecurringViews.swift
//  SecurityIslas
//
//  Pantallas 18 (Nuevo recurrente con Face ID) y 19 (Detalle del recurrente).
//

import SwiftUI
import UIKit

struct NewRecurringView: View {
    let repository: VisitsRepository
    var onCreated: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var kind: AccessKind = .service
    @State private var name = ""
    @State private var weekdays: Set<Weekday> = [.monday, .wednesday, .friday]
    @State private var startTime = TimeOfDay(hour: 8, minute: 0).date()
    @State private var endTime = TimeOfDay(hour: 15, minute: 0).date()
    @State private var expiresOn = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var codeType: AccessCodeType = .dynamicQR
    @State private var errorMessage: String?
    @State private var created: RecurringAccess?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty && endTime > startTime
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

                Section("Nombre") {
                    TextField(kind == .visit ? "Mamá" : "Rosa Martínez", text: $name)
                }

                Section("Días") {
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases) { day in
                            let selected = weekdays.contains(day)
                            Button {
                                if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(day.letter)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(day.name)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Horario") {
                    DatePicker("Desde", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Hasta", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section("Vence") {
                    DatePicker("Vence", selection: $expiresOn, in: Date.now..., displayedComponents: .date)
                }

                Section {
                    Picker("Código", selection: $codeType) {
                        Text("QR dinámico").tag(AccessCodeType.dynamicQR)
                        Text("PIN · 2 usos/día").tag(AccessCodeType.pin)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Código")
                }
            }
            .navigationTitle("Nuevo recurrente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    AsyncButton("Guardar") { await save() }
                        .buttonStyle(.islasPrimary)
                        .disabled(!canSave)
                }
            }
            .sheet(item: $created, onDismiss: {
                onCreated()
                dismiss()
            }) { item in
                ActivityShareSheet(items: [InvitationMessage.text(for: item)])
                    .presentationDetents([.medium, .large])
            }
            .errorAlert($errorMessage)
        }
    }

    private func save() async {
        let request = NewRecurringRequest(
            kind: kind,
            name: name.trimmingCharacters(in: .whitespaces),
            weekdays: weekdays,
            startTime: TimeOfDay(date: startTime),
            endTime: TimeOfDay(date: endTime),
            expiresOn: expiresOn,
            codeType: codeType,
            pinUsesPerDay: codeType == .pin ? 2 : nil
        )
        do {
            created = try await repository.createRecurring(request)
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

struct RecurringDetailView: View {
    let repository: VisitsRepository
    var onChange: () -> Void = {}

    @State private var recurring: RecurringAccess
    @State private var errorMessage: String?
    @State private var confirmRevoke = false
    @Environment(\.dismiss) private var dismiss

    init(recurring: RecurringAccess, repository: VisitsRepository, onChange: @escaping () -> Void = {}) {
        _recurring = State(initialValue: recurring)
        self.repository = repository
        self.onChange = onChange
    }

    var body: some View {
        List {
            // Encabezado como en Contactos: monograma, nombre y acciones rápidas.
            Section {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        InitialsAvatar(initials: recurring.initials, size: 84, tint: recurring.kind == .service ? .purple : Color(.systemGray))
                        Text(recurring.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text([recurring.kind.title, recurring.detail].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        ShareLink(item: InvitationMessage.text(for: recurring)) {
                            ContactActionLabel(title: "Reenviar", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.url = recurring.shareURL
                        } label: {
                            ContactActionLabel(title: "Copiar enlace", systemImage: "link")
                        }
                    }
                    .buttonStyle(PressableCardStyle())
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                LabeledContent("Días y horario") {
                    Text(recurring.allDay
                         ? Weekday.summary(recurring.weekdays).sentenceCased
                         : "\(Weekday.summary(recurring.weekdays)) · \(recurring.startTime.formatted) a \(recurring.endTime.formatted)")
                }
                LabeledContent("Vence", value: recurring.expiresOn.longDay)
                LabeledContent("Código", value: recurring.codeType == .dynamicQR ? "QR dinámico" : "PIN · \(recurring.pinUsesPerDay ?? 1) usos/día")
            }

            Section {
                if recurring.recentEntries.isEmpty {
                    Text("Todavía no hay entradas.").foregroundStyle(.secondary)
                }
                ForEach(recurring.recentEntries) { entry in
                    LabeledContent {
                        Text(entry.exitedAt.map { "\(entry.enteredAt.shortTime) – \($0.shortTime)" } ?? entry.enteredAt.shortTime)
                            .monospacedDigit()
                    } label: {
                        Text(entry.enteredAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.app)).sentenceCased)
                    }
                }
            } header: {
                Text("Últimas entradas")
            } footer: {
                Text("Cada vez que entra te avisamos.")
            }

            // Acción destructiva al final, como "Bloquear contacto".
            Section {
                Button("Revocar código", role: .destructive) { confirmRevoke = true }
            } footer: {
                Text("Deja de funcionar de inmediato en las casetas con conexión.")
            }
        }
        .readableContentWidth()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let fresh = try? await repository.recurringDetail(id: recurring.id) {
                recurring = fresh
            }
        }
        .confirmationDialog("¿Revocar el código de \(recurring.name)?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revocar", role: .destructive) { Task { await revoke() } }
        } message: {
            Text("Aplica de inmediato en las casetas con conexión.")
        }
        .errorAlert($errorMessage)
    }

    /// Revocar aplica de inmediato en casetas con conexión (RF-12). Pide Face ID.
    private func revoke() async {
        do {
            try await repository.revoke(recurring)
            onChange()
            dismiss()
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

/// Pantalla 20. Cada vivienda elige cómo atender la paquetería (RF-72). Es una
/// autorización automática: cambiarla pide Face ID. En los tres casos se avisa.
struct PackagePolicyView: View {
    let repository: VisitsRepository

    @State private var policy: PackagePolicy?
    @State private var saving: PackagePolicy?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ListHeaderSection(title: "Cuando llegue un paquete", subtitle: "Siempre te avisamos, elijas lo que elijas.")

            Section {
                ForEach(PackagePolicy.allCases) { option in
                    Button {
                        Task { await select(option) }
                    } label: {
                        HStack {
                            RadioRow(title: option.title, subtitle: option.detail, isSelected: policy == option)
                            if saving == option { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(policy == option ? Color.accentColor.opacity(0.08) : nil)
                }
            }
        }
        .readableContentWidth()
        .navigationTitle("Paquetería")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(saving != nil)
        .task {
            do {
                policy = try await repository.packagePolicy()
            } catch {
                errorMessage = error.userMessage
            }
        }
        .errorAlert($errorMessage)
    }

    private func select(_ option: PackagePolicy) async {
        guard option != policy else { return }
        saving = option
        defer { saving = nil }
        do {
            policy = try await repository.updatePackagePolicy(option)
        } catch BiometricError.canceled {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

/// Botón de acción bajo el encabezado, como los de Contactos.
private struct ContactActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }
}
