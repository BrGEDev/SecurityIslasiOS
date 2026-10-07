//
//  VisitsView.swift
//  SecurityIslas
//
//  Pantallas 13 (Hoy), Invitaciones y 17 (Recurrentes).
//

import Observation
import SwiftUI

@Observable
final class VisitsViewModel {
    private(set) var today: [Visit] = []
    private(set) var invitations: [Invitation] = []
    private(set) var recurring: [RecurringAccess] = []
    private(set) var loaded: Set<VisitsSegment> = []
    var errorMessage: String?
    /// La vivienda está rentada y quien entra es el propietario (RF-87).
    private(set) var isRestricted = false

    let repository: VisitsRepository

    init(repository: VisitsRepository) {
        self.repository = repository
    }

    func load(_ segment: VisitsSegment) async {
        do {
            switch segment {
            case .today: today = try await repository.today()
            case .invitations: invitations = try await repository.invitations()
            case .recurring: recurring = try await repository.recurring()
            }
            loaded.insert(segment)
        } catch let error as APIError where error.serverCode == "RENTED_HOME" {
            isRestricted = true
        } catch {
            errorMessage = error.userMessage
        }
    }

    func decide(_ visit: Visit, _ decision: VisitDecision) async {
        do {
            _ = try await repository.decide(visit.id, decision: decision)
        } catch {
            errorMessage = error.userMessage
        }
        await load(.today)
    }

    /// "Se queda a dormir": para que no se cierre sola en la noche (RF-74).
    func markSleepover(_ visit: Visit) async {
        do {
            _ = try await repository.markSleepover(visit)
        } catch {
            errorMessage = error.userMessage
        }
        await load(.today)
    }
}

struct VisitsView: View {
    let profile: UserProfile

    @State private var model: VisitsViewModel
    @State private var showNewRecurring = false
    @State private var pendingDecision: Visit?
    @Environment(MainRouter.self) private var router
    @Environment(AppContainer.self) private var container

    init(profile: UserProfile, container: AppContainer) {
        self.profile = profile
        _model = State(initialValue: VisitsViewModel(repository: container.visits))
    }

    var body: some View {
        @Bindable var router = router

        List {
            Section {
                Picker("Sección", selection: $router.visitsSegment) {
                    ForEach(VisitsSegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: router.visitsSegment)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if model.isRestricted || profile.isRestrictedOwner {
                ContentUnavailableView(
                    "Vivienda rentada",
                    systemImage: "house.lodge",
                    description: Text("Mientras la vivienda esté rentada, el arrendatario autoriza las visitas y ve la bitácora.")
                )
                .listRowBackground(Color.clear)
            } else {
                switch router.visitsSegment {
                case .today: todaySection
                case .invitations: invitationsSection
                case .recurring: recurringSection
                }
            }
        }
        .readableContentWidth()
        .navigationTitle("Visitas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if router.visitsSegment == .recurring {
                        showNewRecurring = true
                    } else {
                        router.showNewInvitation = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(router.visitsSegment == .recurring ? "Nuevo recurrente" : "Nueva invitación")
                .disabled(profile.isRestrictedOwner)
            }
        }
        .navigationDestination(for: RecurringAccess.self) { item in
            RecurringDetailView(recurring: item, repository: container.visits) {
                Task { await model.load(.recurring) }
            }
        }
        .navigationDestination(for: Invitation.self) { invitation in
            InvitationPreviewView(invitation: invitation, profile: profile)
        }
        .refreshable { await model.load(router.visitsSegment) }
        .task(id: TaskKey(segment: router.visitsSegment, version: container.dataVersion)) {
            await model.load(router.visitsSegment)
        }
        .sheet(isPresented: $showNewRecurring) {
            NewRecurringView(repository: container.visits) {
                Task { await model.load(.recurring) }
            }
        }
        .alert(
            pendingDecision.map { "\($0.name) está en caseta" } ?? "",
            isPresented: Binding(get: { pendingDecision != nil }, set: { if !$0 { pendingDecision = nil } }),
            presenting: pendingDecision
        ) { visit in
            Button("Autorizar") { Task { await model.decide(visit, .authorize) } }
            Button("Rechazar", role: .destructive) { Task { await model.decide(visit, .reject) } }
            Button("Cancelar", role: .cancel) {}
        }
        .errorAlert($model.errorMessage)
    }

    nonisolated private struct TaskKey: Hashable {
        let segment: VisitsSegment
        let version: Int
    }

    @ViewBuilder
    private var todaySection: some View {
        Section {
            if model.today.isEmpty, model.loaded.contains(.today) {
                Text("No hay accesos hoy.").foregroundStyle(.secondary)
            }
            ForEach(model.today) { visit in
                VisitRow(visit: visit)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if visit.status == .waiting { pendingDecision = visit }
                    }
                    .swipeActions(edge: .leading) {
                        if visit.status == .waiting {
                            Button {
                                Task { await model.decide(visit, .authorize) }
                            } label: {
                                Label("Autorizar", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if visit.status == .waiting {
                            Button {
                                Task { await model.decide(visit, .reject) }
                            } label: {
                                Label("Rechazar", systemImage: "xmark")
                            }
                            .tint(.red)
                        } else if visit.status == .entered || visit.status == .authorized {
                            Button {
                                Task { await model.markSleepover(visit) }
                            } label: {
                                Label("Se queda a dormir", systemImage: "moon.zzz.fill")
                            }
                            .tint(.indigo)
                        }
                    }
                    .contextMenu {
                        if visit.status == .waiting {
                            Button {
                                Task { await model.decide(visit, .authorize) }
                            } label: {
                                Label("Autorizar", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                Task { await model.decide(visit, .reject) }
                            } label: {
                                Label("Rechazar", systemImage: "xmark.circle")
                            }
                        } else if visit.status == .entered || visit.status == .authorized {
                            Button {
                                Task { await model.markSleepover(visit) }
                            } label: {
                                Label("Se queda a dormir", systemImage: "moon.zzz")
                            }
                        }
                    }
            }
        } footer: {
            Text("Desliza a la izquierda una visita que sigue adentro para marcar que se queda a dormir.")
        }
    }

    @ViewBuilder
    private var invitationsSection: some View {
        Section {
            if model.invitations.isEmpty, model.loaded.contains(.invitations) {
                Text("No tienes invitaciones activas.").foregroundStyle(.secondary)
            }
            ForEach(model.invitations) { invitation in
                NavigationLink(value: invitation) {
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: Initials.from(invitation.guestName))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invitation.guestName).font(.subheadline.weight(.semibold))
                            Text("\(invitation.isEvent ? "Evento" : invitation.kind.title) · \(invitation.startsAt.relativeDayAndTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusChip(text: "PIN \(invitation.pin)", tint: .blue)
                    }
                }
            }
        } footer: {
            Text("Al llegar, el guardia valida el código y te avisamos.")
        }
    }

    @ViewBuilder
    private var recurringSection: some View {
        Section {
            if model.recurring.isEmpty, model.loaded.contains(.recurring) {
                Text("Aún no tienes accesos recurrentes.").foregroundStyle(.secondary)
            }
            ForEach(model.recurring) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: item.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text("\(item.kind.title) · \(item.scheduleSummary)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Vence \(item.expiresOn.longDay)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } footer: {
            Text("Cada vez que entra alguien de esta lista te avisamos.")
        }
    }
}
