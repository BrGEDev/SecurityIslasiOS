//
//  IslasWatchWidgetsBundle.swift
//  IslasWatchWidgets
//
//  Pantalla 43: complicaciones y Smart Stack del Apple Watch para abrir la
//  pluma, el pánico y Mi QR (RF-41). Cada una abre la app del reloj en esa
//  página; abrir sigue las mismas reglas de geocerca y carril (RF-23, RF-68) y
//  el pánico inicia la cuenta regresiva cancelable (RF-41).
//
//  Los enlaces son los mismos de `AppLink` (Shared): islassecurity://gate,
//  islassecurity://panic e islassecurity://qr.
//

import SwiftUI
import WidgetKit

@main
struct IslasWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GateComplication()
        PanicComplication()
        QRComplication()
    }
}

nonisolated enum WatchShortcut: String {
    case gate
    case panic
    case qr

    var url: URL { URL(string: "islassecurity://\(rawValue)")! }

    var title: String {
        switch self {
        case .gate: "Abrir pluma"
        case .panic: "Pánico"
        case .qr: "Mi QR"
        }
    }

    var symbol: String {
        switch self {
        case .gate: "road.lanes"
        case .panic: "exclamationmark.triangle.fill"
        case .qr: "qrcode"
        }
    }

    var tint: Color {
        switch self {
        case .gate: .blue
        case .panic: .red
        case .qr: .gray
        }
    }

    var description: String {
        switch self {
        case .gate: "Abre la pluma o solicita paso cerca de la entrada."
        case .panic: "Inicia la cuenta regresiva del pánico; puedes cancelarla."
        case .qr: "Muestra tu QR de acceso, también sin internet."
        }
    }
}

struct ShortcutEntry: TimelineEntry {
    let date: Date
}

struct ShortcutProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortcutEntry { ShortcutEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ShortcutEntry) -> Void) {
        completion(ShortcutEntry(date: .now))
    }

    /// Son accesos directos sin datos: una sola entrada que no caduca.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortcutEntry>) -> Void) {
        completion(Timeline(entries: [ShortcutEntry(date: .now)], policy: .never))
    }
}

struct GateComplication: Widget {
    var body: some WidgetConfiguration { WatchShortcutConfiguration.make(.gate) }
}

struct PanicComplication: Widget {
    var body: some WidgetConfiguration { WatchShortcutConfiguration.make(.panic) }
}

struct QRComplication: Widget {
    var body: some WidgetConfiguration { WatchShortcutConfiguration.make(.qr) }
}

@MainActor
enum WatchShortcutConfiguration {
    static func make(_ shortcut: WatchShortcut) -> some WidgetConfiguration {
        StaticConfiguration(kind: "app.security.islasgower.watch.\(shortcut.rawValue)", provider: ShortcutProvider()) { _ in
            WatchShortcutView(shortcut: shortcut)
                .containerBackground(shortcut.tint.gradient, for: .widget)
                .widgetURL(shortcut.url)
        }
        .configurationDisplayName(shortcut.title)
        .description(shortcut.description)
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct WatchShortcutView: View {
    let shortcut: WatchShortcut
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: shortcut.symbol)
                    .font(.title3)
                    .foregroundStyle(shortcut.tint)
                    .widgetAccentable()
                VStack(alignment: .leading) {
                    Text(shortcut.title).font(.headline)
                    Text("Islas Security").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label(shortcut.title, systemImage: shortcut.symbol)
        case .accessoryCorner:
            Image(systemName: shortcut.symbol)
                .font(.title3)
                .widgetLabel(shortcut.title)
                .widgetAccentable()
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: shortcut.symbol)
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityLabel(shortcut.title)
        }
    }
}
