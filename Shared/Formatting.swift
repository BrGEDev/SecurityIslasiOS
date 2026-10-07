//
//  Formatting.swift
//  SecurityIslas (iPhone y Apple Watch)
//
//  Formatos de fecha, texto y enlaces comunes a las dos apps.
//

import Foundation

extension Locale {
    /// La app está en español de México aunque el iPhone esté en otro idioma
    /// (fechas como "31 dic 2026", no "31 Dec 2026").
    static let app = Locale(identifier: "es_MX")
}

extension String {
    /// Solo la primera letra en mayúscula: "todos los días" → "Todos los días".
    /// (`capitalized` pondría "Todos Los Días".)
    var sentenceCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension Date {
    /// "hoy 20:00", "ayer 23:10", "vie 9 oct · 15:00"
    var relativeDayAndTime: String {
        let time = formatted(.dateTime.hour().minute().locale(.app))
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "hoy \(time)" }
        if calendar.isDateInYesterday(self) { return "ayer \(time)" }
        if calendar.isDateInTomorrow(self) { return "mañana \(time)" }
        return "\(formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))) · \(time)"
    }

    var shortTime: String { formatted(.dateTime.hour().minute().locale(.app)) }

    var longDay: String { formatted(.dateTime.day().month(.abbreviated).year().locale(.app)) }
}

extension URL {
    static let emergency = URL(string: "tel://911")!

    static func phone(_ number: String) -> URL? {
        URL(string: "tel://\(number.filter { $0.isNumber || $0 == "+" })")
    }
}
