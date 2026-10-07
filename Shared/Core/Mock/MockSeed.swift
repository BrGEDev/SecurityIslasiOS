//
//  MockSeed.swift
//  SecurityIslas
//
//  Datos de ejemplo de las maquetas (Brandon, Bosques Sanctorum, Juan Pérez,
//  Gas Express...). Solo los usa MockServer.
//
//  Números de prueba (código SMS: 123456):
//  • 222 123 4567 / 221 848 6093 → Brandon, cuenta existente (pantalla 3a)
//  • 222 999 9999 → cuenta existente con 3 dispositivos (pantalla 3b)
//  • 222 555 0000 → precargado por la administración (RF-63)
//  • 551 234 5678 → Laura, propietaria no residente (pantalla 38)
//  • cualquier otro → residente nuevo (pantallas 4, 5, 6; se aprueba a los ~12 s)
//

import Foundation

nonisolated enum MockSeed {
    static let bosques = Fraccionamiento(id: "frac-bosques-sanctorum", name: "Bosques Sanctorum", booths: 2, homes: 340)

    static let fraccionamientos: [Fraccionamiento] = [
        bosques,
        Fraccionamiento(id: "frac-bosques-pilar", name: "Bosques del Pilar", booths: 1, homes: 120),
        Fraccionamiento(id: "frac-bosques-canada", name: "Bosques de la Cañada", booths: 1, homes: 86),
        Fraccionamiento(id: "frac-paseos-angel", name: "Paseos del Ángel", booths: 1, homes: 150),
    ]

    static func homes(for fraccionamientoId: String) -> [HomeOption] {
        let prefix = fraccionamientoId == bosques.id ? "Retorno Encino" : "Calle Roble"
        let numbered = (18...36).map { HomeOption(id: "\(fraccionamientoId)-\($0)", name: "\(prefix) \($0)") }
        let extra = [
            HomeOption(id: "\(fraccionamientoId)-sl12c", name: "Priv. Santa Laura 12C"),
            HomeOption(id: "\(fraccionamientoId)-sl14a", name: "Priv. Santa Laura 14A"),
        ]
        return numbered + extra
    }

    static let brandonResidence = Residence(
        id: "frac-bosques-sanctorum-24",
        name: "Retorno Encino 24",
        fraccionamientoId: bosques.id,
        fraccionamientoName: bosques.name,
        isRented: false
    )

    // MARK: - Cuentas

    static func accounts(now: Date) -> [MockAccount] {
        [
            MockAccount(
                phones: ["+522221234567", "+522218486093"],
                profile: UserProfile(
                    id: "usr-brandon",
                    firstName: "Brandon",
                    lastName: "García",
                    phone: "+522221234567",
                    role: .holder,
                    tenure: .owner,
                    residence: brandonResidence,
                    approvalStatus: .approved,
                    rejectionReason: nil
                ),
                state: .existing,
                devices: [
                    MockDevice(id: "dev-brandon-watch", name: "Apple Watch", model: .watch, lastUsedAt: now.addingTimeInterval(-3_600)),
                ]
            ),
            MockAccount(
                phones: ["+522229999999"],
                profile: UserProfile(
                    id: "usr-brandon-3",
                    firstName: "Brandon",
                    lastName: "García",
                    phone: "+522229999999",
                    role: .holder,
                    tenure: .owner,
                    residence: brandonResidence,
                    approvalStatus: .approved,
                    rejectionReason: nil
                ),
                state: .existing,
                devices: [
                    MockDevice(id: "dev-iphone12", name: "iPhone 12 de Brandon", model: .iphone, lastUsedAt: now.addingTimeInterval(-90 * 86_400)),
                    MockDevice(id: "dev-ipad", name: "iPad de Brandon", model: .ipad, lastUsedAt: now.addingTimeInterval(-86_400)),
                    MockDevice(id: "dev-iphone15", name: "iPhone 15 de Brandon", model: .iphone, lastUsedAt: now.addingTimeInterval(-7 * 86_400)),
                    // Los relojes no cuentan en el límite: esta cuenta sigue con 3 de 3.
                    MockDevice(id: "dev-watch", name: "Apple Watch", model: .watch, lastUsedAt: now.addingTimeInterval(-1_800)),
                ]
            ),
            MockAccount(
                phones: ["+522225550000"],
                profile: UserProfile(
                    id: "usr-mariana",
                    firstName: "Mariana",
                    lastName: "López",
                    phone: "+522225550000",
                    role: .holder,
                    tenure: .tenant,
                    residence: nil,
                    approvalStatus: .unregistered,
                    rejectionReason: nil
                ),
                state: .preloaded,
                devices: []
            ),
            MockAccount(
                phones: ["+525512345678"],
                profile: UserProfile(
                    id: "usr-laura",
                    firstName: "Laura",
                    lastName: "Méndez",
                    phone: "+525512345678",
                    role: .nonResidentOwner,
                    tenure: .owner,
                    residence: Residence(
                        id: "frac-bosques-sanctorum-31",
                        name: "Retorno Encino 31",
                        fraccionamientoId: bosques.id,
                        fraccionamientoName: bosques.name,
                        isRented: true
                    ),
                    approvalStatus: .approved,
                    rejectionReason: nil
                ),
                state: .existing,
                devices: []
            ),
        ]
    }

    static func preload(for account: MockAccount) -> PreloadedRegistration? {
        guard account.state == .preloaded else { return nil }
        return PreloadedRegistration(
            firstName: account.profile.firstName,
            lastName: account.profile.lastName,
            fraccionamiento: bosques,
            home: HomeOption(id: "frac-bosques-sanctorum-27", name: "Retorno Encino 27"),
            tenure: account.profile.tenure ?? .owner
        )
    }

    // MARK: - Pluma y geocercas

    /// Caseta principal (carril exclusivo de residentes) y caseta Encino
    /// (carril compartido), separadas ~450 m.
    static let gate = GateConfiguration(
        lanes: [
            Lane(
                id: "lane-main-residents",
                name: "Entrada principal",
                type: .residentsOnly,
                location: Coordinate(latitude: 19.0414, longitude: -98.2063)
            ),
            Lane(
                id: "lane-encino-shared",
                name: "Entrada Encino",
                type: .shared,
                location: Coordinate(latitude: 19.0454, longitude: -98.2063)
            ),
        ],
        entranceRadius: 150,
        perimeterCenter: Coordinate(latitude: 19.0434, longitude: -98.2063),
        perimeterRadius: 700
    )

    // MARK: - Vivienda de Brandon

    static func visits(now: Date) -> [Visit] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return [
            Visit(id: "vis-juan", kind: .visit, name: "Juan Pérez", plate: "TXR-12-34", origin: .walkIn, status: .waiting,
                  arrivedAt: now.addingTimeInterval(-20)),
            Visit(id: "vis-gas", kind: .service, name: "Gas Express", company: "Gas Express", origin: .walkIn, status: .exited,
                  arrivedAt: today.addingTimeInterval(10 * 3_600 + 30 * 60),
                  enteredAt: today.addingTimeInterval(10 * 3_600 + 32 * 60),
                  exitedAt: today.addingTimeInterval(10 * 3_600 + 50 * 60),
                  respondedBy: "Ana", destinationCount: 4),
            Visit(id: "vis-mama", kind: .visit, name: "Mamá", origin: .recurring, status: .entered,
                  arrivedAt: today.addingTimeInterval(9 * 3_600 + 15 * 60),
                  enteredAt: today.addingTimeInterval(9 * 3_600 + 15 * 60)),
            Visit(id: "vis-luis", kind: .visit, name: "Luis Rivera", origin: .invitation, status: .scheduled,
                  scheduledAt: today.addingTimeInterval(20 * 3_600)),
            Visit(id: "vis-carlos", kind: .visit, name: "Carlos Soto", origin: .walkIn, status: .sleepover,
                  arrivedAt: yesterday.addingTimeInterval(19 * 3_600),
                  enteredAt: yesterday.addingTimeInterval(19 * 3_600), respondedBy: "Brandon"),
            Visit(id: "vis-unknown", kind: .visit, name: "Sin nombre", origin: .walkIn, status: .noResponse,
                  arrivedAt: yesterday.addingTimeInterval(23 * 3_600 + 10 * 60)),
        ]
    }

    static func invitations(now: Date) -> [Invitation] {
        let today = Calendar.current.startOfDay(for: now)
        return [
            Invitation(
                id: "inv-luis",
                kind: .visit,
                guestName: "Luis Rivera",
                startsAt: today.addingTimeInterval(18 * 3_600),
                endsAt: today.addingTimeInterval(23 * 3_600 + 59 * 60),
                plate: nil,
                isEvent: false,
                capacity: nil,
                shareURL: URL(string: "https://\(AppInfo.inviteHost)/i/7KX2")!,
                pin: "4821",
                status: .scheduled
            ),
        ]
    }

    static func recurring(now: Date) -> [RecurringAccess] {
        let calendar = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? now
        }
        let today = calendar.startOfDay(for: now)
        let rosaEntries = (1...2).map { offset -> EntryLog in
            let day = calendar.date(byAdding: .day, value: -offset * 2, to: today) ?? today
            return EntryLog(
                id: "ent-rosa-\(offset)",
                enteredAt: day.addingTimeInterval(8 * 3_600 + Double(offset * 4) * 60),
                exitedAt: day.addingTimeInterval(14 * 3_600 + 52 * 60 + Double(offset * 5) * 60)
            )
        }
        return [
            RecurringAccess(
                id: "rec-mama", kind: .visit, name: "Mamá", detail: "familia",
                weekdays: Set(Weekday.allCases),
                startTime: TimeOfDay(hour: 0, minute: 0), endTime: TimeOfDay(hour: 23, minute: 59),
                expiresOn: date(2026, 12, 31), codeType: .dynamicQR, pinUsesPerDay: nil,
                shareURL: URL(string: "https://\(AppInfo.inviteHost)/r/MAMA")!, recentEntries: []
            ),
            RecurringAccess(
                id: "rec-rosa", kind: .service, name: "Rosa Martínez", detail: "limpieza",
                weekdays: [.monday, .wednesday, .friday],
                startTime: TimeOfDay(hour: 8, minute: 0), endTime: TimeOfDay(hour: 15, minute: 0),
                expiresOn: date(2027, 3, 31), codeType: .dynamicQR, pinUsesPerDay: nil,
                shareURL: URL(string: "https://\(AppInfo.inviteHost)/r/ROSA")!, recentEntries: rosaEntries
            ),
            RecurringAccess(
                id: "rec-pedro", kind: .service, name: "Jardinero (Pedro)", detail: "jardinería",
                weekdays: [.saturday],
                startTime: TimeOfDay(hour: 9, minute: 0), endTime: TimeOfDay(hour: 13, minute: 0),
                expiresOn: date(2026, 11, 30), codeType: .pin, pinUsesPerDay: 2,
                shareURL: URL(string: "https://\(AppInfo.inviteHost)/r/PEDRO")!, recentEntries: []
            ),
        ]
    }

    static func packages(now: Date) -> [Package] {
        let today = Calendar.current.startOfDay(for: now)
        return [
            Package(id: "pkg-ml", carrier: "Mercado Libre", receivedAt: today.addingTimeInterval(11 * 3_600 + 5 * 60),
                    receivedBy: "guardia Ramírez", status: .atBooth),
            Package(id: "pkg-dhl", carrier: "DHL", receivedAt: today.addingTimeInterval(9 * 3_600 + 50 * 60),
                    receivedBy: "guardia Ramírez", status: .atBooth),
            Package(id: "pkg-amz", carrier: "Amazon", receivedAt: today.addingTimeInterval(8 * 3_600 + 40 * 60),
                    receivedBy: "guardia Ramírez", status: .delivered, pickedUpBy: "Ana",
                    pickedUpAt: today.addingTimeInterval(13 * 3_600 + 10 * 60)),
        ]
    }

    static func history(now: Date) -> [HistoryEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return [
            HistoryEvent(id: "his-1", category: .gate, title: "Pluma abierta",
                         detail: "Brandon · carril de residentes", date: today.addingTimeInterval(10 * 3_600 + 41 * 60)),
            HistoryEvent(id: "his-2", category: .service, title: "Gas Express",
                         detail: "Servicio · autorizó Ana · entró 10:32 · salió 10:50", date: today.addingTimeInterval(10 * 3_600 + 32 * 60)),
            HistoryEvent(id: "his-3", category: .visit, title: "Mamá",
                         detail: "Visita recurrente · entró 9:15", date: today.addingTimeInterval(9 * 3_600 + 15 * 60)),
            HistoryEvent(id: "his-4", category: .package, title: "Paquete Amazon",
                         detail: "Recibido en caseta 8:40 · recogió Ana 13:10", date: today.addingTimeInterval(8 * 3_600 + 40 * 60)),
            HistoryEvent(id: "his-5", category: .visit, title: "Sin respuesta",
                         detail: "Visita · 23:10 · no entró", date: yesterday.addingTimeInterval(23 * 3_600 + 10 * 60), isWarning: true),
            HistoryEvent(id: "his-6", category: .visit, title: "Carlos Soto",
                         detail: "Visita · autorizó Brandon · se queda a dormir", date: yesterday.addingTimeInterval(19 * 3_600)),
        ]
    }

    static func family() -> [MockFamilyMember] {
        [
            MockFamilyMember(id: "fam-brandon", userId: "usr-brandon", name: "Brandon García", role: .holder),
            MockFamilyMember(id: "fam-ana", userId: "usr-ana", name: "Ana García", role: .adult),
            MockFamilyMember(id: "fam-diego", userId: "usr-diego", name: "Diego García", role: .minor),
        ]
    }

    static func contacts() -> [EmergencyContact] {
        [
            EmergencyContact(id: "con-ana", name: "Ana García", relationship: "Esposa", phone: "+522221112233", hasApp: true),
            EmergencyContact(id: "con-roberto", name: "Roberto García", relationship: "Papá", phone: "+522224445566", hasApp: false),
        ]
    }

    static func workPermit(now: Date) -> WorkPermit {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)) ?? now
        let end = calendar.date(from: DateComponents(year: 2027, month: 4, day: 30)) ?? now
        let submitted = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)) ?? now
        return WorkPermit(
            id: "wp-1",
            status: .inReview,
            responsible: "Arq. Mario Luna · DRO",
            license: "LC-2026-0418",
            startsOn: start,
            endsOn: end,
            schedule: "L a V 8:00 a 18:00 · S 8:00 a 14:00",
            dailySummary: true,
            submittedAt: submitted
        )
    }
}

// MARK: - Tipos internos del mock

nonisolated struct MockDevice: Codable, Sendable, Hashable {
    let id: String
    var name: String
    let model: DeviceModel
    var lastUsedAt: Date
    var publicKey: String?
}

nonisolated struct MockAccount: Codable, Sendable {
    var phones: [String]
    var profile: UserProfile
    var state: AccountState
    var devices: [MockDevice]
    var registrationSubmittedAt: Date?
    var qrSecret: String?

    init(phones: [String], profile: UserProfile, state: AccountState, devices: [MockDevice]) {
        self.phones = phones
        self.profile = profile
        self.state = state
        self.devices = devices
        self.registrationSubmittedAt = nil
        self.qrSecret = nil
    }
}

nonisolated struct MockFamilyMember: Codable, Sendable {
    let id: String
    let userId: String
    let name: String
    let role: ResidentRole
}
