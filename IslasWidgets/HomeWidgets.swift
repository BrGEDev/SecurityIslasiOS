//
//  HomeWidgets.swift
//  IslasWidgets
//
//  Pantalla 30: widget mediano interactivo (visita en caseta con Rechazar /
//  Autorizar y botón de abrir pluma o solicitar paso) y widget chico de
//  pánico. Pantalla 31: en la pantalla bloqueada, distancia a la entrada y
//  visitas pendientes.
//
//  Los datos salen de `WidgetSnapshot` (lo escribe la app). Abrir pluma y
//  pánico abren la app: abrir pide Face ID igual que en la app y el pánico
//  inicia la cuenta regresiva cancelable (RF-41).
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : WidgetSnapshotStore.load()
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    /// La app recarga los widgets cada vez que cambia algo; como respaldo se
    /// pide otra lectura en 15 minutos.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Mediano: visita en caseta + pluma

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.security.islasgower.home", provider: SnapshotProvider()) { entry in
            HomeWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Caseta")
        .description("Responde a la visita en caseta y abre la pluma.")
        .supportedFamilies([.systemMedium])
    }
}

struct HomeWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(snapshot.fraccionamiento, systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let visit = snapshot.pending.first {
                HStack(spacing: 10) {
                    Text(visit.initials)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(visit.kind.tint.opacity(0.18), in: Circle())
                        .foregroundStyle(visit.kind.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(visit.name) en caseta")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(visit.kind.title)
                            if let arrivedAt = visit.arrivedAt {
                                Text("· hace")
                                Text(arrivedAt, style: .relative)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    if snapshot.pending.count > 1 {
                        Spacer(minLength: 0)
                        Text("+\(snapshot.pending.count - 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 8) {
                    Button(intent: VisitDecisionIntent(visitId: visit.id, option: .reject)) {
                        Text("Rechazar").frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                    if !visit.heldByAdministration {
                        Button(intent: AuthorizeVisitFromLockScreenIntent(visitId: visit.id)) {
                            Text("Autorizar").frame(maxWidth: .infinity)
                        }
                        .tint(.green)
                    }
                    if snapshot.canUseGate {
                        GateLinkButton(snapshot: snapshot, compact: true)
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                Text("Sin visitas en caseta")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if snapshot.canUseGate {
                    GateLinkButton(snapshot: snapshot, compact: false)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Abre la app y dispara el mismo botón de Inicio (geocerca, carril y Face ID).
private struct GateLinkButton: View {
    let snapshot: WidgetSnapshot
    let compact: Bool

    private var title: String {
        switch snapshot.gate {
        case .requestPass: compact ? "Paso" : "Solicitar paso"
        case .far: compact ? "Lejos" : "Lejos de la entrada"
        default: compact ? "Abrir" : "Abrir pluma"
        }
    }

    var body: some View {
        Link(destination: AppLink.gate.url) {
            Label(title, systemImage: snapshot.gate == .requestPass ? "bell.fill" : "road.lanes")
                .frame(maxWidth: compact ? nil : .infinity)
        }
        .tint(snapshot.gate == .requestPass ? .indigo : .blue)
        .disabled(snapshot.gate == .far)
    }
}

// MARK: - Chico: pánico

struct PanicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.security.islasgower.panic", provider: SnapshotProvider()) { _ in
            PanicWidgetView()
                .containerBackground(for: .widget) {
                    BrandPalette.gradient(BrandPalette.red)
                }
                .widgetURL(AppLink.panic.url)
        }
        .configurationDisplayName("Pánico")
        .description("Un toque inicia la cuenta regresiva del pánico; puedes cancelarla.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PanicWidgetView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
            Spacer()
            Text("Pánico")
                .font(.headline)
            Text("Toca para enviar")
                .font(.caption)
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pánico. Inicia una cuenta regresiva que puedes cancelar.")
    }
}

// MARK: - Pantalla bloqueada (pantalla 31)

struct EntranceAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.security.islasgower.lockscreen", provider: SnapshotProvider()) { entry in
            EntranceAccessoryView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Entrada y visitas")
        .description("Distancia a la entrada y visitas en caseta.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct EntranceAccessoryView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var visitsText: String {
        switch snapshot.pending.count {
        case 0: "Sin visitas en caseta"
        case 1: "\(snapshot.pending[0].name) en caseta"
        default: "\(snapshot.pending.count) visitas en caseta"
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "road.lanes")
                    Text(snapshot.distanceText ?? "—")
                        .font(.caption2)
                        .minimumScaleFactor(0.6)
                }
            }
            .widgetURL(AppLink.gate.url)
            .accessibilityLabel("Entrada a \(snapshot.distanceText ?? "distancia desconocida")")
        case .accessoryInline:
            Label(visitsText, systemImage: "checkmark.shield")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label(AppInfo.name, systemImage: "checkmark.shield")
                    .font(.caption.weight(.semibold))
                Text(visitsText)
                    .font(.caption)
                if let distance = snapshot.distanceText {
                    Text("Entrada a \(distance)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(snapshot.pending.isEmpty ? AppLink.gate.url : AppLink.visits.url)
        }
    }
}

#Preview(as: .systemMedium) {
    HomeWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
    SnapshotEntry(date: .now, snapshot: .empty)
}
