import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore
    @State private var showingExport = false
    @State private var showingImport = false
    @State private var exportQueryOverride: IndividualQuery?
    @State private var isSidebarCollapsed = false
    @State private var selectedSightingID: String?
    @State private var focusedMapTurtleID: String?

    var body: some View {
        Group {
            if store.isRestoring {
                ProgressView("Restoring sign-in…")
            } else if !store.isAuthenticated {
                AccountLoginView(store: store)
            } else {
                workspace.id(store.sessionGeneration)
                    .environment(\.turtlePhotoLoader, { await store.loadPhoto(for: $0) })
            }
        }
        .frame(minWidth: AdaLayout.minimumWindowSize.width, minHeight: AdaLayout.minimumWindowSize.height)
        .environment(\.locale, store.localization.locale)
        .task { await store.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.organizationKeySettings.clipboard.clearIfOwned()
        }
        .onChange(of: store.sessionGeneration) { _, _ in
            showingExport = false
            showingImport = false
            exportQueryOverride = nil
            selectedSightingID = nil
            focusedMapTurtleID = nil
        }
        #if DEBUG
        .sheet(isPresented: $store.isAuthSheetPresented) { BackendSettingsSheet(store: store) }
        #endif
    }

    private var debugSettingsAction: (() -> Void)? {
        #if DEBUG
        return { store.isAuthSheetPresented = true }
        #else
        return nil
        #endif
    }

    private var signOutAction: (() -> Void)? {
        guard store.isAuthenticated else { return nil }
        return { store.signOut() }
    }

    private func setSidebarCollapsed(_ collapsed: Bool) {
        guard isSidebarCollapsed != collapsed else { return }
        withAnimation(AdaSidebarStyle.animation) {
            isSidebarCollapsed = collapsed
        }
    }

    private func toggleSidebar() {
        setSidebarCollapsed(!isSidebarCollapsed)
    }

    private var workspace: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    selection: $store.activeSection,
                    selectedCondition: $store.selectedCondition,
                    favoriteCount: store.favoriteTurtles.count,
                    selectedSpecies: store.selectedSpecies,
                    onSelectSpecies: { species in
                        store.selectedSpecies = species
                        store.activeSection = .individuals
                    },
                    onOpenProductSettings: store.isAuthenticated ? { store.openSettings() } : nil,
                    onOpenAuthSettings: debugSettingsAction,
                    accountName: store.accountName,
                    accountEmail: store.authEmail,
                    accountOrganization: store.accountOrganization,
                    accountRole: store.isDemoBypassActive ? "Demo" : (store.isLiveOwner ? "Owner" : (store.isLiveRanger ? "Ranger" : store.accountRoleLabel)),
                    isDemoWorkspace: store.isDemoBypassActive,
                    onSignOut: signOutAction,
                    isCollapsed: isSidebarCollapsed,
                    notSurePendingCount: store.notSureAttentionCount,
                    isNavigationLocked: store.organizationKeySettings.isChanging,
                    localization: store.localization,
                    onToggleSidebar: toggleSidebar,
                    onExpandSidebar: { setSidebarCollapsed(false) }
                )

                VStack(spacing: 0) {
                    WorkspaceHeader(store: store, title: pageTitle,
                        onImport: { showingImport = true },
                        onExport: { exportQueryOverride = nil; showingExport = true },
                        isSidebarCollapsed: isSidebarCollapsed,
                        onToggleSidebar: toggleSidebar)

                    ZStack {
                        AdaColors.canvas
                        if let turtle = store.selectedTurtle {
                            let displayedTurtle = store.selectedDetail?.turtle ?? turtle
                            let isFavorite = store.favoriteTurtles.contains { $0.id == displayedTurtle.id }
                            ProfileWorkspaceView(
                                turtle: displayedTurtle,
                                detail: store.selectedDetail,
                                isLoading: store.isDetailLoading,
                                error: store.detailError,
                                selectedSightingID: $selectedSightingID,
                                onBack: { selectedSightingID = nil; store.dismissDetail() },
                                onMap: { openMap(turtleID: displayedTurtle.id) },
                                onExport: {
                                    exportQueryOverride = IndividualQuery(search: displayedTurtle.profileCode ?? displayedTurtle.displayName)
                                    showingExport = true
                                },
                                originTitle: store.detailOrigin.title,
                                isFavorite: isFavorite,
                                onToggleFavorite: { store.toggleFavorite(displayedTurtle) },
                                onRetry: { Task { await store.loadDetail(for: turtle) } }
                            )
                        } else { pageView }

                        if store.isImporting {
                            ProgressView(store.importProgressText ?? "Importing…")
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.regularMaterial, in: Capsule())
                        } else if store.isExporting {
                            ProgressView("Preparing export…")
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.regularMaterial, in: Capsule())
                        } else if store.activeSection != .settings && (store.isLoading || (store.isIndividualsLoading && store.activeSection == .individuals)) {
                            ProgressView("Loading records…")
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RightPaneAutoMinimizeObserver(
                        isSidebarCollapsed: isSidebarCollapsed,
                        isBlocked: showingExport || showingImport,
                        onMinimize: { setSidebarCollapsed(true) }
                    )
                )
                .background(AdaColors.canvas)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 40, bottomTrailingRadius: 0, topTrailingRadius: 0))
            }

            if showingImport {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.16))
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !store.isImporting { showingImport = false }
                    }

                ImportSheetView(store: store, onDismiss: {
                    showingImport = false
                })
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if showingExport {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.16))
                    .ignoresSafeArea()
                    .onTapGesture { showingExport = false; exportQueryOverride = nil }

                ExportSheet(
                    query: exportQueryOverride ?? store.currentIndividualQuery,
                    resultCount: exportQueryOverride == nil ? max(store.totalIndividuals, store.turtles.count) : 1,
                    onCancel: { showingExport = false; exportQueryOverride = nil }
                ) { request in
                    showingExport = false
                    exportQueryOverride = nil
                    store.export(request)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if store.isReviewPracticePresented {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                store.isReviewPracticePresented = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(AdaColors.card, in: Capsule())
                            .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Text("Practice Review")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)

                        Text("Sample")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(AdaColors.navy.opacity(0.08), in: Capsule())

                        Spacer(minLength: 0)

                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                store.isReviewPracticePresented = false
                            }
                        } label: {
                            Text("Done")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 34)
                                .background(AdaColors.navy, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(.leading, 84) // clears macOS window traffic lights cleanly in full-window mode
                    .padding(.trailing, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .background(AdaColors.canvas)

                    ScientistReviewWorkspaceView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AdaColors.canvas)
                .ignoresSafeArea(.container, edges: .top)
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .background(AdaColors.navy)
        .onChange(of: store.activeSection) { _, nextSection in
            selectedSightingID = nil
            store.dismissDetail()
            if nextSection != .map {
                focusedMapTurtleID = nil
            }
        }
        .frame(minWidth: AdaLayout.minimumWindowSize.width, minHeight: AdaLayout.minimumWindowSize.height)
        .animation(.easeOut(duration: 0.16), value: showingExport)
        .animation(.easeOut(duration: 0.16), value: showingImport)
        .animation(.easeOut(duration: 0.16), value: store.isReviewPracticePresented)
        .animation(.easeOut(duration: 0.18), value: store.selectedTurtle?.id)
        .onExitCommand {
            if store.isReviewPracticePresented {
                store.isReviewPracticePresented = false
            } else if showingImport {
                if !store.isImporting { showingImport = false }
            } else if showingExport {
                showingExport = false
                exportQueryOverride = nil
            } else if selectedSightingID != nil {
                selectedSightingID = nil
            } else if store.selectedTurtle != nil {
                store.dismissDetail()
            } else if store.activeSection == .settings && store.settingsDetail != nil {
                store.requestSettingsBack()
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if let error = store.lastError {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(AdaColors.red)
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button("Retry") { Task { await store.reloadAll() } }
                        Button("Dismiss") { store.clearError() }
                    }
                    .padding(12)
                    .background(AdaColors.card)
                }
                if let status = store.statusMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AdaColors.green)
                        Text(status).font(.callout).foregroundStyle(AdaColors.ink)
                        Spacer()
                        Button("Dismiss") { store.clearStatusMessage() }
                    }
                    .padding(12)
                    .background(AdaColors.card)
                }
            }
        }
    }

    private var pageTitle: String {
        if store.selectedTurtle != nil {
            return selectedSightingID == nil ? "Turtle Profile" : "Sighting Details"
        }
        let rawTitle: String
        switch store.activeSection {
        case .individuals, .favorites, .scientistReview:
            rawTitle = AppSection.individuals.title
        default:
            rawTitle = store.activeSection.title
        }
        return store.localization.localized(rawTitle)
    }

    private func openMap(turtleID: String?) {
        store.dismissDetail()
        selectedSightingID = nil
        focusedMapTurtleID = turtleID
        store.activeSection = .map
        if turtleID != nil { store.selectedMapPeriod = .allTime; store.mapSpecies = nil; store.mapCondition = nil }
        Task { await store.reloadMap() }
    }

    @ViewBuilder
    private var pageView: some View {
        switch store.activeSection {
        case .dashboard:
            DashboardView(
                store: store,
                snapshot: store.dashboard,
                turtles: store.analyticsTurtles.isEmpty ? store.turtles : store.analyticsTurtles,
                recentSightings: store.sightings,
                chartMode: $store.chartMode, chartSpecies: $store.chartSpecies,
                onExport: { exportQueryOverride = nil; showingExport = true }, onSelect: store.select,
                onBrowseTurtles: { store.activeSection = .individuals },
                onShowSightings: {
                    store.selectedMapPeriod = .twelveMonths
                    store.mapSpecies = store.chartSpecies
                    store.mapCondition = nil
                    store.activeSection = .sightings
                }, onOpenMap: { openMap(turtleID: nil) })
        case .map:
            MapPageView(turtles: store.allKnownTurtles,
                sightings: store.sightings, selectedPeriod: $store.selectedMapPeriod,
                selectedSpecies: $store.mapSpecies, selectedCondition: $store.mapCondition,
                onReload: { Task { await store.reloadMap() } }, onSelect: store.select,
                focusTurtleID: focusedMapTurtleID,
                onFocusConsumed: { focusedMapTurtleID = nil },
                onOpenSighting: openSighting)
        case .individuals:
            VStack(spacing: 0) {
                catalogTabs
                IndividualsView(
                    turtles: store.turtles,
                    total: store.totalIndividuals,
                    searchText: $store.searchText,
                    selectedCondition: $store.selectedCondition,
                    favoriteIDs: Set(store.favoriteTurtles.map(\.id)),
                    onToggleFavorite: store.toggleFavorite,
                    onSelect: store.select,
                    selectedSpecies: $store.selectedSpecies,
                    pageSize: $store.individualsPageSize,
                    offset: store.individualsOffset,
                    isLoading: store.isIndividualsLoading,
                    onPage: { page in Task { await store.loadIndividualsPage(page) } },
                    sort: $store.sort
                )
            }
        case .sightings:
            SightingsListView(sightings: store.sightings, onSelect: openSighting)
        case .scientistReview:
            VStack(spacing: 0) {
                catalogTabs
                NotSureWorkspaceView(store: store, onOpenPractice: {
                    store.isReviewPracticePresented = true
                })
            }
        case .identification:
            I3SWorkspaceView(store: store)
        case .favorites:
            VStack(spacing: 0) {
                catalogTabs
                FavoritesView(
                    turtles: store.favoriteTurtles,
                    searchText: $store.searchText,
                    selectedCondition: $store.selectedCondition,
                    favoriteIDs: Set(store.favoriteTurtles.map(\.id)),
                    onToggleFavorite: store.toggleFavorite,
                    onSelect: store.select,
                    onBrowseIndividuals: {
                        store.searchText = ""
                        store.selectedSpecies = nil
                        store.selectedCondition = nil
                        store.activeSection = .individuals
                    },
                    selectedSpecies: $store.selectedSpecies
                )
            }
        case .settings:
            SettingsView(store: store, model: store.organizationKeySettings)
        }
    }
    private func openSighting(_ sighting: Sighting) {
        selectedSightingID = sighting.id
        store.select(store.turtle(forID: sighting.turtleID) ?? sighting.turtleReference)
    }

    private var catalogTabs: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                catalogTab(
                    "Individuals",
                    icon: "tortoise",
                    count: store.totalIndividuals,
                    selected: store.activeSection == .individuals
                ) {
                    store.activeSection = .individuals
                }
                catalogTab(
                    "Watchlist",
                    icon: "bookmark",
                    count: store.favoriteTurtles.count,
                    selected: store.activeSection == .favorites
                ) {
                    store.activeSection = .favorites
                }
                catalogTab(
                    "Not Sure",
                    icon: "questionmark.circle",
                    count: store.notSureAttentionCount,
                    selected: store.activeSection == .scientistReview
                ) {
                    store.openNotSureReview()
                }
            }
            .padding(3)
            .background(AdaColors.card, in: Capsule())
            .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .padding(.bottom, 10)
    }

    private func catalogTab(_ title: String, icon: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: selected && icon == "bookmark" ? "bookmark.fill" : icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                Text(count.formatted())
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(selected ? .white.opacity(0.92) : AdaColors.secondaryInk)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(selected ? .white.opacity(0.18) : AdaColors.surfaceMuted, in: Capsule())
            }
            .foregroundStyle(selected ? .white : AdaColors.secondaryInk)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(selected ? AdaColors.navy : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

}

struct ExportSheet: View {
    let query: IndividualQuery
    let resultCount: Int
    let onCancel: () -> Void
    let onExport: (ExportRequest) -> Void
    @State private var scope: ExportScope = .currentView
    @State private var range: ExportRange = .sevenDays
    @State private var fields: Set<ExportField> = [.profile]
    @State private var format: ExportFormat = .csv

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export data")
                        .font(.system(size: 16, weight: .semibold))
                    Text(scope == .currentView ? "Filtered from \(resultCount) catalogued individuals" : "All catalogued individuals")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
            }
            .frame(height: 48, alignment: .top)

            ExportSectionLabel("Scope")
                .padding(.top, 5)
                .padding(.bottom, 7)
            HStack(spacing: 0) {
                ForEach(ExportScope.allCases) { option in
                    ExportOptionButton(title: option.title, isSelected: scope == option, style: .segment) { scope = option }
                }
            }
            .padding(2)
            .frame(width: 218, height: 29)
            .background(Color.black.opacity(0.055))
            .clipShape(Capsule())

            ExportSectionLabel("Data range")
                .padding(.top, 16)
                .padding(.bottom, 7)
            HStack(spacing: 7) {
                ForEach(ExportRange.allCases) { option in
                    ExportOptionButton(title: option.title.capitalized, isSelected: range == option) { range = option }
                }
            }

            ExportSectionLabel("Fields")
                .padding(.top, 22)
                .padding(.bottom, 7)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(ExportField.allCases) { field in
                    ExportFieldButton(title: field.title, isSelected: fields.contains(field)) {
                        if fields.contains(field), fields.count > 1 { fields.remove(field) }
                        else { fields.insert(field) }
                    }
                }
            }

            ExportSectionLabel("Format")
                .padding(.top, 22)
                .padding(.bottom, 7)
            HStack(spacing: 8) {
                ForEach(ExportFormat.allCases) { option in
                    ExportOptionButton(title: option == .pdf ? "PDF report" : option.title, isSelected: format == option) { format = option }
                }
            }

            Spacer(minLength: 20)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(ModalSecondaryButtonStyle())
                Button("Export") {
                    onExport(ExportRequest(scope: scope, range: range, fields: fields, format: format, query: query))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ModalPrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 414, height: 493)
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
    }
}

private struct ExportSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(AdaColors.ink) }
}

private struct ExportOptionButton: View {
    enum Style { case chip, segment }
    let title: String
    let isSelected: Bool
    var style: Style = .chip
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isSelected && style == .chip ? Color.white : AdaColors.secondaryInk)
                .padding(.horizontal, style == .segment ? 13 : 12)
                .frame(maxWidth: style == .segment ? .infinity : nil)
                .frame(height: 25)
                .background(isSelected ? (style == .chip ? AdaColors.navy : AdaColors.card) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ExportFieldButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? AdaColors.navy : AdaColors.card)
                    .frame(width: 15, height: 15)
                    .overlay { if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                    .overlay { Circle().stroke(AdaColors.line, lineWidth: isSelected ? 0 : 1) }
                Text(title).font(.system(size: 11)).foregroundStyle(AdaColors.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isSelected ? AdaColors.brandBlue.opacity(0.09) : Color.black.opacity(0.035))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ModalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 17).frame(height: 30).background(AdaColors.navy.opacity(configuration.isPressed ? 0.8 : 1)).clipShape(Capsule())
    }
}

private struct ModalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).padding(.horizontal, 15).frame(height: 30).background(Color.black.opacity(configuration.isPressed ? 0.08 : 0.045)).clipShape(Capsule())
    }
}

/// Passively watches clicks inside the right workspace pane so pressing anywhere on
/// the right screen smoothly minimizes an expanded left sidebar without blocking
/// buttons, scrolling, maps, or excluding the header sidebar toggle button.
@MainActor
private struct RightPaneAutoMinimizeObserver: NSViewRepresentable {
    let isSidebarCollapsed: Bool
    let isBlocked: Bool
    let onMinimize: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        context.coordinator.anchorView = view
        sync(context.coordinator)
        context.coordinator.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.anchorView = nsView
        sync(context.coordinator)
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    private func sync(_ coordinator: Coordinator) {
        coordinator.isSidebarCollapsed = isSidebarCollapsed
        coordinator.isBlocked = isBlocked
        coordinator.onMinimize = onMinimize
    }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        weak var anchorView: AnchorView?
        var isSidebarCollapsed = false
        var isBlocked = false
        var onMinimize: () -> Void = {}
        nonisolated(unsafe) private var monitor: Any?
        private var pendingPress: (windowNumber: Int, downOrigin: NSPoint)?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                guard Thread.isMainThread else { return event }
                let isMouseDown = event.type == .leftMouseDown
                let isMouseUp = event.type == .leftMouseUp
                let locationInWindow = event.locationInWindow
                let eventWindowNumber = event.windowNumber
                MainActor.assumeIsolated {
                    self?.handleMouseEvent(
                        isMouseDown: isMouseDown,
                        isMouseUp: isMouseUp,
                        locationInWindow: locationInWindow,
                        eventWindowNumber: eventWindowNumber
                    )
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            pendingPress = nil
        }

        private func isInRightPane(_ locationInWindow: NSPoint, window: NSWindow) -> Bool {
            guard let view = anchorView, view.window === window, !view.isHiddenOrHasHiddenAncestor else {
                return false
            }
            let rightRect = view.convert(view.bounds, to: nil)
            guard rightRect.contains(locationInWindow) else { return false }
            if let marker = SidebarToggleExclusionRegistry.windowMarkers.object(forKey: window),
               marker.window === window {
                let markerRect = marker.convert(marker.bounds, to: nil)
                if markerRect.contains(locationInWindow) {
                    return false
                }
            }
            return true
        }

        private func handleMouseEvent(
            isMouseDown: Bool,
            isMouseUp: Bool,
            locationInWindow: NSPoint,
            eventWindowNumber: Int
        ) {
            guard let view = anchorView,
                  let window = view.window,
                  window.windowNumber == eventWindowNumber,
                  !isSidebarCollapsed,
                  !isBlocked,
                  window.attachedSheet == nil else {
                if isMouseDown {
                    pendingPress = nil
                }
                return
            }

            if isMouseDown {
                guard isInRightPane(locationInWindow, window: window) else {
                    pendingPress = nil
                    return
                }
                let downOrigin = window.frame.origin
                let windowNumber = window.windowNumber
                pendingPress = (windowNumber, downOrigin)

                // Fallback for AppKit controls (Map/Menu/Slider) that consume leftMouseUp inside a tracking loop
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window,
                          let press = self.pendingPress,
                          press.windowNumber == window.windowNumber,
                          (NSEvent.pressedMouseButtons & 1) == 0 else { return }
                    self.pendingPress = nil
                    self.triggerMinimizeIfValid(in: window, downOrigin: press.downOrigin)
                }
            } else if isMouseUp {
                guard let press = pendingPress, press.windowNumber == window.windowNumber else {
                    return
                }
                pendingPress = nil
                guard isInRightPane(locationInWindow, window: window) else {
                    return
                }
                let downOrigin = press.downOrigin
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.triggerMinimizeIfValid(in: window, downOrigin: downOrigin)
                }
            }
        }

        private func triggerMinimizeIfValid(in window: NSWindow, downOrigin: NSPoint) {
            guard !isSidebarCollapsed,
                  !isBlocked,
                  let view = anchorView,
                  view.window === window,
                  window.attachedSheet == nil else { return }

            let dx = abs(window.frame.origin.x - downOrigin.x)
            let dy = abs(window.frame.origin.y - downOrigin.y)
            guard dx <= 2 && dy <= 2 else { return }

            onMinimize()
        }
    }
}

#if DEBUG
#Preview("App · World Super Account") {
    PreviewDemoShell(persona: .worldSuperNetwork, section: .dashboard)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("Export Data Modal") {
    ZStack {
        AdaColors.canvas
        ExportSheet(query: IndividualQuery(), resultCount: 45, onCancel: {}, onExport: { _ in })
    }
    .frame(width: 640, height: 600)
    .preferredColorScheme(.light)
}
#endif
