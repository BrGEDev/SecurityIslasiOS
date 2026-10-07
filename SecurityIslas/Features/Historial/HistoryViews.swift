//
//  HistoryViews.swift
//  SecurityIslas
//
//  Pantallas 22 (Historial de la vivienda) y 23 (Paquetes en caseta).
//

import SwiftUI

/// Bitácora solo de su vivienda: visitas, servicios, aperturas y paquetes,
/// con quién respondió. Se abre desde "Ver todo" en Inicio.
struct HistoryView: View {
    let repository: VisitsRepository

    @State private var filter: HistoryCategory?
    @State private var events: [HistoryEvent] = []
    @State private var isLoaded = false
    @State private var errorMessage: String?

    private var filters: [HistoryCategory?] { [nil, .visit, .service, .gate, .package, .alert] }

    private var grouped: [(day: Date, events: [HistoryEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (day, groups[day, default: []].sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { category in
                            let selected = filter == category
                            Button(category?.filterTitle ?? "Todo") {
                                filter = category
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if isLoaded, events.isEmpty {
                ContentUnavailableView("Sin movimientos", systemImage: "clock", description: Text("Aquí verás quién entró y quién respondió."))
                    .listRowBackground(Color.clear)
            }

            ForEach(grouped, id: \.day) { group in
                Section(Self.sectionTitle(for: group.day)) {
                    ForEach(group.events) { event in
                        HStack(spacing: 12) {
                            IconTile(
                                systemName: event.category.symbol,
                                tint: event.isWarning ? .orange : .accentColor,
                                size: 36
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.subheadline.weight(.semibold))
                                Text(event.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.date.shortTime).font(.caption).foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Historial")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: filter) { await load() }
        .errorAlert($errorMessage)
    }

    private func load() async {
        do {
            events = try await repository.history(category: filter)
            isLoaded = true
        } catch {
            errorMessage = error.userMessage
        }
    }

    static func sectionTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

/// El guardia registra los paquetes, se avisa al residente y queda quién
/// recogió y cuándo (RF-73).
struct PackagesView: View {
    let repository: VisitsRepository

    @State private var packages: [Package] = []
    @State private var errorMessage: String?

    private var atBooth: Int { packages.filter { $0.status == .atBooth }.count }

    var body: some View {
        List {
            if atBooth > 0 {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(atBooth) \(atBooth == 1 ? "paquete" : "paquetes") en caseta").font(.headline)
                            Text("Pasa a recogerlos con tu QR").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.orange.opacity(0.1))
                }
            }

            Section {
                ForEach(packages) { package in
                    HStack(spacing: 12) {
                        IconTile(systemName: "shippingbox", tint: package.status == .atBooth ? .orange : .gray, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.carrier).font(.subheadline.weight(.semibold))
                            Text(detail(for: package)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusChip(
                            text: package.status == .atBooth ? "En caseta" : "Entregado",
                            tint: package.status == .atBooth ? .orange : .gray
                        )
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                NavigationLink {
                    PackagePolicyView(repository: repository)
                } label: {
                    Label("Cuando llegue un paquete", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Paquetes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .errorAlert($errorMessage)
    }

    private func detail(for package: Package) -> String {
        if package.status == .delivered, let by = package.pickedUpBy, let at = package.pickedUpAt {
            return "Recogió \(by) · \(at.shortTime)"
        }
        return "Recibido \(package.receivedAt.shortTime) · \(package.receivedBy)"
    }

    private func load() async {
        do {
            packages = try await repository.packages()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
