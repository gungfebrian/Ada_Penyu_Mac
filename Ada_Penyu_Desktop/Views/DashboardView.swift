import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var store: AppStore
    let snapshot: DashboardSnapshot
    let turtles: [Turtle]
    let recentSightings: [Sighting]
    @Binding var chartMode: ChartMode
    @Binding var chartSpecies: TurtleSpecies?
    let onExport: () -> Void
    let onSelect: (Turtle) -> Void
    var onBrowseTurtles: () -> Void = {}
    var onShowSightings: () -> Void = {}
    var onOpenMap: () -> Void = {}

    init(
        store: AppStore? = nil,
        snapshot: DashboardSnapshot,
        turtles: [Turtle],
        recentSightings: [Sighting],
        chartMode: Binding<ChartMode>,
        chartSpecies: Binding<TurtleSpecies?>,
        onExport: @escaping () -> Void,
        onSelect: @escaping (Turtle) -> Void,
        onBrowseTurtles: @escaping () -> Void = {},
        onShowSightings: @escaping () -> Void = {},
        onOpenMap: @escaping () -> Void = {}
    ) {
        self.store = store ?? AppStore()
        self.snapshot = snapshot
        self.turtles = turtles
        self.recentSightings = recentSightings
        self._chartMode = chartMode
        self._chartSpecies = chartSpecies
        self.onExport = onExport
        self.onSelect = onSelect
        self.onBrowseTurtles = onBrowseTurtles
        self.onShowSightings = onShowSightings
        self.onOpenMap = onOpenMap
    }

    private var analytics: DashboardAnalytics {
        DashboardAnalytics.compute(snapshot: snapshot, turtles: turtles, sightings: recentSightings)
    }

    private var widgets: [DashboardWidgetItem] {
        store.dashboardLayout.widgets
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.isEditingDashboardWidgets {
                        iOSEditModeBar(store: store)
                    }

                    if widgets.isEmpty {
                        EmptySunkenDashboardGrid(
                            width: proxy.size.width,
                            onAddWidget: { store.isWidgetPickerPresented = true },
                            onRestoreDefault: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    store.applyDashboardPreset(store.currentAccountDefaultPreset)
                                }
                            }
                        )
                    } else {
                        DashboardWidgetGrid(
                            store: store,
                            containerWidth: proxy.size.width,
                            widgets: widgets,
                            analytics: analytics,
                            snapshot: snapshot,
                            turtles: turtles,
                            recentSightings: recentSightings,
                            onSelect: onSelect,
                            onBrowseTurtles: onBrowseTurtles,
                            onShowSightings: onShowSightings,
                            onOpenMap: onOpenMap
                        )
                    }

                    Label("Organization records · summary covers the last 12 months", systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(.horizontal, AdaLayout.pagePadding)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $store.isWidgetPickerPresented) {
            AppleStyleWidgetGallerySheet(
                store: store,
                snapshot: snapshot,
                analytics: analytics,
                sightings: recentSightings.isEmpty ? DemoFixtures.sightings : recentSightings
            )
        }
    }
}

// MARK: - Subtle iOS-Style Edit Mode Pill Bar

private struct iOSEditModeBar: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DashboardRolePreset.allCases) { preset in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        store.applyDashboardPreset(preset)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 11))
                        Text(preset.title)
                            .font(.system(size: 12, weight: store.dashboardLayout.activePreset == preset ? .semibold : .regular))
                    }
                    .foregroundStyle(store.dashboardLayout.activePreset == preset ? .white : AdaColors.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        store.dashboardLayout.activePreset == preset ? AdaColors.navy : AdaColors.card,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Drag widgets to reorder")
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.secondaryInk)
        }
    }
}

// MARK: - Sunken / Recessed iOS Empty Slot Well ("Mencekung ke Bawah")

/// Recessed well with a realistic inner shadow at the top/left and bottom rim highlight
/// so empty widget slots physically look sunken into the canvas ("mencekung ke bawah").
private struct SunkenWidgetSlotWell: View {
    var height: CGFloat = 245
    var label: String = "Add Widget"
    var subtitle: String = "Drop a widget into this slot"
    let action: () -> Void

    @State private var isHovered = false

    private static let sunkenFill = Color(red: 233 / 255, green: 236 / 255, blue: 240 / 255)
    private static let sunkenHoverFill = Color(red: 227 / 255, green: 231 / 255, blue: 236 / 255)

    var body: some View {
        Button(action: action) {
            ZStack {
                // Base recessed surface
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                    .fill(isHovered ? Self.sunkenHoverFill : Self.sunkenFill)

                // Top-down inner shadow gradient ("mencekung ke bawah" depth)
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.075),
                                Color.black.opacity(0.015),
                                Color.clear,
                                Color.white.opacity(0.35),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Recessed inner rim: dark top/left bevel + white bottom/right catchlight
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.13),
                                Color.black.opacity(0.05),
                                Color.white.opacity(0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )

                // Inner dashed slot guide
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius - 6, style: .continuous)
                    .strokeBorder(
                        AdaColors.navy.opacity(isHovered ? 0.22 : 0.10),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
                    .padding(6)

                // Center tactile + button
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isHovered ? 0.95 : 0.78))
                            .frame(width: 42, height: 42)
                            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AdaColors.navy)
                    }
                    .scaleEffect(isHovered ? 1.06 : 1.0)

                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaColors.ink.opacity(0.75))

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(AdaColors.secondaryInk.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct EmptySunkenDashboardGrid: View {
    let width: CGFloat
    let onAddWidget: () -> Void
    let onRestoreDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SunkenWidgetSlotWell(
                height: 170,
                label: "Empty Banner Slot",
                subtitle: "Click to add Observed Summary or wide widget · or restore default layout below",
                action: onAddWidget
            )

            if width >= 1000 {
                HStack(spacing: 24) {
                    SunkenWidgetSlotWell(height: 245, label: "Add Widget", subtitle: "Left slot · Click to open Widget Gallery", action: onAddWidget)
                    SunkenWidgetSlotWell(height: 245, label: "Add Widget", subtitle: "Right slot · Click to open Widget Gallery", action: onAddWidget)
                }
                HStack(spacing: 24) {
                    SunkenWidgetSlotWell(height: 245, label: "Add Widget", subtitle: "Bottom-left slot", action: onAddWidget)
                    SunkenWidgetSlotWell(height: 245, label: "Add Widget", subtitle: "Bottom-right slot", action: onAddWidget)
                }
            } else {
                VStack(spacing: 24) {
                    SunkenWidgetSlotWell(height: 245, action: onAddWidget)
                    SunkenWidgetSlotWell(height: 245, action: onAddWidget)
                }
            }

            HStack {
                Spacer()
                Button("Restore Default Dashboard", action: onRestoreDefault)
                    .buttonStyle(AdaPillButtonStyle())
                Spacer()
            }
        }
    }
}

// MARK: - Responsive 2-Column / Full-Width Widget Grid

private enum DashboardWidgetRow: Identifiable {
    case full(DashboardWidgetItem)
    case pair(DashboardWidgetItem, DashboardWidgetItem)
    case singleHalf(DashboardWidgetItem)

    var id: String {
        switch self {
        case .full(let item): "full-\(item.id.uuidString)"
        case .pair(let lhs, let rhs): "pair-\(lhs.id.uuidString)-\(rhs.id.uuidString)"
        case .singleHalf(let item): "half-\(item.id.uuidString)"
        }
    }
}

private struct DashboardWidgetGrid: View {
    @ObservedObject var store: AppStore
    let containerWidth: CGFloat
    let widgets: [DashboardWidgetItem]
    let analytics: DashboardAnalytics
    let snapshot: DashboardSnapshot
    let turtles: [Turtle]
    let recentSightings: [Sighting]
    let onSelect: (Turtle) -> Void
    let onBrowseTurtles: () -> Void
    let onShowSightings: () -> Void
    let onOpenMap: () -> Void

    @State private var draggedWidgetID: UUID?

    private var rows: [DashboardWidgetRow] {
        var result: [DashboardWidgetRow] = []
        var pendingHalf: DashboardWidgetItem?

        for item in widgets {
            switch item.span {
            case .full:
                if let half = pendingHalf {
                    result.append(.singleHalf(half))
                    pendingHalf = nil
                }
                result.append(.full(item))
            case .half:
                if let half = pendingHalf {
                    result.append(.pair(half, item))
                    pendingHalf = nil
                } else {
                    pendingHalf = item
                }
            }
        }
        if let half = pendingHalf {
            result.append(.singleHalf(half))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                switch row {
                case .full(let item):
                    widgetView(for: item)
                case .pair(let leftItem, let rightItem):
                    if containerWidth >= 1000 {
                        HStack(alignment: .top, spacing: 24) {
                            widgetView(for: leftItem)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            widgetView(for: rightItem)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(spacing: 24) {
                            widgetView(for: leftItem)
                            widgetView(for: rightItem)
                        }
                    }
                case .singleHalf(let item):
                    // When a half-width widget has an empty neighbor slot, show a sunken well right next to it!
                    if containerWidth >= 1000 {
                        HStack(alignment: .top, spacing: 24) {
                            widgetView(for: item)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            SunkenWidgetSlotWell(
                                height: 245,
                                label: "Empty Widget Slot",
                                subtitle: "Click to add a widget next to \(item.kind.title)"
                            ) {
                                store.isWidgetPickerPresented = true
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        widgetView(for: item)
                    }
                }
            }

            if store.isEditingDashboardWidgets {
                if containerWidth >= 1000 {
                    HStack(spacing: 24) {
                        SunkenWidgetSlotWell(
                            height: 185,
                            label: "Add Widget",
                            subtitle: "Click to browse visual widgets"
                        ) {
                            store.isWidgetPickerPresented = true
                        }
                        SunkenWidgetSlotWell(
                            height: 185,
                            label: "Add Widget",
                            subtitle: "Click to browse visual widgets"
                        ) {
                            store.isWidgetPickerPresented = true
                        }
                    }
                } else {
                    SunkenWidgetSlotWell(height: 185) {
                        store.isWidgetPickerPresented = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func widgetView(for item: DashboardWidgetItem) -> some View {
        let index = widgets.firstIndex(where: { $0.id == item.id }) ?? 0
        iOSWidgetContainer(
            item: item,
            isEditing: store.isEditingDashboardWidgets,
            canMoveEarlier: index > 0,
            canMoveLater: index < widgets.count - 1,
            onMoveEarlier: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.moveDashboardWidget(id: item.id, direction: -1)
                }
            },
            onMoveLater: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.moveDashboardWidget(id: item.id, direction: 1)
                }
            },
            onToggleSpan: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.toggleDashboardWidgetSpan(id: item.id)
                }
            },
            onRemove: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.removeDashboardWidget(id: item.id)
                }
            }
        ) {
            switch item.kind {
            case .kpiOverview:
                FigCraftSummaryWidget(
                    snapshot: snapshot,
                    compact: containerWidth < 1050,
                    onBrowseTurtles: onBrowseTurtles,
                    onShowSightings: onShowSightings
                )
            case .notSureQueue:
                FigCraftNotSureQueueWidget(
                    onOpenScenario: { scenario, mode in
                        store.openNotSureReview(scenario: scenario, layoutMode: mode)
                    },
                    onOpenIdentification: {
                        store.activeSection = .identification
                    }
                )
            case .sightingsTrend:
                FigCraftTrendWidget(snapshot: snapshot)
            case .geographicMap:
                FigCraftGeographicWidget(sightings: recentSightings, onOpenMap: onOpenMap)
            case .recentSightings:
                FigCraftRecentResightingsWidget(
                    sightings: recentSightings,
                    turtles: turtles,
                    onShowSightings: onShowSightings,
                    onSelect: onSelect
                )
            case .speciesBreakdown:
                FigCraftSpeciesWidget(snapshot: snapshot)
            case .injuryTriage:
                FigCraftTriageWidget(
                    item: item,
                    analytics: analytics,
                    onUpdateMode: { mode in
                        store.updateDashboardWidgetOptions(
                            id: item.id,
                            conditionFilter: item.conditionFilter,
                            metricMode: mode
                        )
                    },
                    onSelectTurtle: onSelect,
                    onOpenIndividualsTriage: {
                        store.selectedCondition = .injured
                        store.activeSection = .individuals
                    }
                )
            case .recaptureAnalysis:
                FigCraftRecaptureWidget(analytics: analytics, onSelectTurtle: onSelect)
            case .habitatHotspots:
                FigCraftHotspotsWidget(analytics: analytics, onOpenMap: onOpenMap)
            case .photoIDReadiness:
                FigCraftPhotoIDWidget(
                    analytics: analytics,
                    onSelectTurtle: onSelect,
                    onOpenScientistReview: { store.openNotSureReview() },
                    onOpenIdentification: { store.activeSection = .identification }
                )
            case .conditionBreakdown:
                FigCraftConditionWidget(
                    analytics: analytics,
                    onSelectCondition: { condition in
                        store.selectedCondition = condition
                        store.activeSection = .individuals
                    }
                )
            case .favoritesWatch:
                FigCraftFavoritesWidget(
                    favorites: store.favoriteTurtles,
                    onSelect: onSelect,
                    onBrowseIndividuals: onBrowseTurtles
                )
            }
        }
        .opacity(draggedWidgetID == item.id ? 0.65 : 1.0)
        .onDrag {
            draggedWidgetID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: DashboardWidgetDropDelegate(
                targetItem: item,
                store: store,
                draggedWidgetID: $draggedWidgetID
            )
        )
    }
}

private struct DashboardWidgetDropDelegate: DropDelegate {
    let targetItem: DashboardWidgetItem
    let store: AppStore
    @Binding var draggedWidgetID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedWidgetID, draggedID != targetItem.id else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            store.moveDashboardWidget(fromID: draggedID, toID: targetItem.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedWidgetID = nil
        if let provider = info.itemProviders(for: [.text]).first {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let raw = object as? String, raw.hasPrefix("kind:") else { return }
                let kindRaw = String(raw.dropFirst(5))
                guard let kind = DashboardWidgetKind(rawValue: kindRaw) else { return }
                Task { @MainActor in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.addDashboardWidget(kind)
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Apple iOS Widget Edit Chrome (Zero Clutter in Normal Mode!)

private struct iOSWidgetContainer<Content: View>: View {
    let item: DashboardWidgetItem
    let isEditing: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onToggleSpan: () -> Void
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .scaleEffect(isEditing ? 0.988 : 1.0)
                .shadow(
                    color: Color.black.opacity(isEditing ? 0.08 : 0.0),
                    radius: isEditing ? 14 : 0,
                    y: isEditing ? 6 : 0
                )
                .contextMenu {
                    Button(action: onToggleSpan) {
                        Label(
                            item.span == .full ? "Resize to Half Width (1×1)" : "Expand to Full Width (2×1)",
                            systemImage: item.span.toggled.icon
                        )
                    }
                    if canMoveEarlier {
                        Button(action: onMoveEarlier) {
                            Label("Move Earlier", systemImage: "arrow.up.left")
                        }
                    }
                    if canMoveLater {
                        Button(action: onMoveLater) {
                            Label("Move Later", systemImage: "arrow.down.right")
                        }
                    }
                    Divider()
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove Widget", systemImage: "minus.circle")
                    }
                }

            if isEditing {
                // Apple iOS top-left circular minus badge
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(AdaColors.red)
                            .frame(width: 26, height: 26)
                            .overlay {
                                Circle().stroke(Color.white, lineWidth: 2)
                            }
                            .shadow(color: Color.black.opacity(0.18), radius: 5, y: 2)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 11, height: 2.5)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: -7, y: -7)
                .help("Remove widget")
                .accessibilityLabel("Remove \(item.kind.title)")

                // Apple iOS top-right floating size & order pill
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Button(action: onMoveEarlier) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdaColors.ink)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveEarlier)
                        .opacity(canMoveEarlier ? 1 : 0.3)

                        Divider().frame(height: 12)

                        Button(action: onToggleSpan) {
                            HStack(spacing: 4) {
                                Image(systemName: item.span == .full ? "rectangle.fill" : "rectangle.lefthalf.filled")
                                    .font(.system(size: 10))
                                Text(item.span == .full ? "2×1" : "1×1")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(AdaColors.ink)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Switch between 1×1 half width and 2×1 full width")

                        Divider().frame(height: 12)

                        Button(action: onMoveLater) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdaColors.ink)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveLater)
                        .opacity(canMoveLater ? 1 : 0.3)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
                    .offset(x: -10, y: -9)
                }
            }
        }
    }
}

// MARK: - Exact FigCraft Design Language Widgets

private struct FigCraftSummaryWidget: View {
    let snapshot: DashboardSnapshot
    let compact: Bool
    let onBrowseTurtles: () -> Void
    let onShowSightings: () -> Void

    var body: some View {
        let metrics = snapshot.metrics
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Observed turtles").font(.system(size: 17))
                        Text(metrics.observed.formatted()).font(.system(size: 38, weight: .medium)).monospacedDigit()
                        Text("Unique individuals in the summary").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        Button("View all turtles  →", action: onBrowseTurtles).buttonStyle(SummaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !compact { subsets(metrics) }
                }
                if compact { subsets(metrics) }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: compact ? 255 : 170, alignment: .leading)
            .background(AdaColors.navy, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius))

            VStack(alignment: .leading, spacing: 10) {
                Label("Recorded sightings", systemImage: "binoculars").font(.system(size: 16))
                Text(metrics.sightings.formatted()).font(.system(size: 38, weight: .medium)).monospacedDigit()
                Text("All records in the summary").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                Button("View sightings  →", action: onShowSightings).buttonStyle(SummaryButtonStyle())
            }
            .padding(22)
            .frame(width: compact ? 220 : 255, height: compact ? 255 : 170, alignment: .leading)
            .background(AdaColors.navy, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius))
        }
        .foregroundStyle(.white)
    }

    private func subsets(_ metrics: DashboardMetrics) -> some View {
        HStack(spacing: 16) {
            subset(title: "First recorded", value: metrics.firstRecorded.formatted(), subtitle: "Reported new individuals", icon: "calendar")
            subset(title: "Seen again", value: metrics.seenAgain.map { $0.formatted() } ?? "—", subtitle: "Count unavailable for this period", icon: "arrow.clockwise")
        }
        .frame(maxWidth: .infinity)
    }

    private func subset(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 12))
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct FigCraftTrendWidget: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                SectionTitle("Sightings over time", subtitle: "Recorded sightings · monthly")
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total sightings").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    Text(snapshot.metrics.sightings.formatted()).font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly average").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    Text(snapshot.metrics.monthlyAverage.formatted(.number.precision(.fractionLength(0)))).font(.system(size: 18, weight: .semibold))
                }
                .padding(.leading, 10)
            }
            SightingsLineChart(months: snapshot.months).frame(height: 150)
            Text("Counts reflect recorded sightings.").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftGeographicWidget: View {
    let sightings: [Sighting]
    let onOpenMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle("Where turtles were observed", subtitle: "Map records · current map filters")
                Spacer(minLength: 8)
                Button("Open map  →", action: onOpenMap).buttonStyle(AdaPillButtonStyle())
            }
            SightingMapPreview(sightings: sightings)
                .frame(height: 175)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("\(sightings.count) loaded sightings · Map data © Apple")
                .font(.system(size: 9))
                .foregroundStyle(AdaColors.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftRecentResightingsWidget: View {
    let sightings: [Sighting]
    let turtles: [Turtle]
    let onShowSightings: () -> Void
    let onSelect: (Turtle) -> Void

    var body: some View {
        let rows = Array(RecentResighting.rows(from: sightings).prefix(4))
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Recent resightings", subtitle: "From loaded map records")
                Spacer()
                Button("View all →", action: onShowSightings).buttonStyle(.plain).font(.system(size: 11))
            }
            if rows.isEmpty {
                ContentUnavailableView("No resightings in this range", systemImage: "tortoise", description: Text("A turtle needs two recorded encounters to appear here."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack {
                    Text("Turtle").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Previous").frame(width: 90, alignment: .leading)
                    Text("Latest location").frame(width: 110, alignment: .leading)
                }
                .font(.system(size: 10))
                .foregroundStyle(AdaColors.secondaryInk)

                ForEach(rows) { row in
                    Divider()
                    Button {
                        onSelect(turtles.first { $0.id == row.latest.turtleID } ?? row.latest.turtleReference)
                    } label: {
                        HStack(spacing: 10) {
                            TurtlePhoto(paths: turtles.first { $0.id == row.latest.turtleID }?.identityPhotoPaths ?? [], size: 30)
                            Text(row.latest.displayName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.previous.date).frame(width: 90, alignment: .leading)
                            Text(row.latest.location).lineLimit(1).frame(width: 110, alignment: .leading)
                        }
                        .font(.system(size: 11))
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftSpeciesWidget: View {
    let snapshot: DashboardSnapshot
    @State private var showSpeciesSightings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle("Species observed")
                Spacer()
                HStack(spacing: 2) {
                    ForEach([false, true], id: \.self) { sightings in
                        Button(sightings ? "Sightings" : "Individuals") { showSpeciesSightings = sightings }
                            .font(.system(size: 10))
                            .foregroundStyle(showSpeciesSightings == sightings ? .white : AdaColors.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(showSpeciesSightings == sightings ? AdaColors.navy : .clear, in: Capsule())
                            .accessibilityAddTraits(showSpeciesSightings == sightings ? .isSelected : [])
                    }
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(AdaColors.canvas, in: Capsule())
            }
            if snapshot.species.isEmpty {
                ContentUnavailableView("No species records", systemImage: "chart.bar").frame(height: 150)
            } else {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(snapshot.species) { item in
                        let value = showSpeciesSightings ? item.sightings : item.individuals
                        let maximum = max(snapshot.species.map { showSpeciesSightings ? $0.sightings : $0.individuals }.max() ?? 1, 1)
                        VStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Text(value.formatted()).font(.system(size: 11))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AdaColors.navy)
                                .frame(width: 40, height: max(2, 100 * CGFloat(value) / CGFloat(maximum)))
                            SpeciesLabel(species: item.species).font(.system(size: 9)).frame(height: 28)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(height: 150)
            }
            Divider()
            HStack {
                Text(showSpeciesSightings ? "Total species sightings" : "Total individuals").font(.system(size: 12))
                Spacer()
                Text(snapshot.species.reduce(0) { $0 + (showSpeciesSightings ? $1.sightings : $1.individuals) }.formatted())
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftTriageWidget: View {
    let item: DashboardWidgetItem
    let analytics: DashboardAnalytics
    let onUpdateMode: (String) -> Void
    let onSelectTurtle: (Turtle) -> Void
    let onOpenIndividualsTriage: () -> Void

    private var injuredOnly: Bool { item.metricMode == "injured_only" }
    private var displayedTurtles: [Turtle] { injuredOnly ? analytics.injuredTurtles : analytics.triageTurtles }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Veterinary triage", subtitle: "\(analytics.injuredTurtles.count) injured · \(analytics.scarredTurtles.count) scarred")
                Spacer()
                HStack(spacing: 2) {
                    ForEach([false, true], id: \.self) { onlyInjured in
                        Button(onlyInjured ? "Injured" : "All") {
                            onUpdateMode(onlyInjured ? "injured_only" : "all_triage")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(injuredOnly == onlyInjured ? .white : AdaColors.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(injuredOnly == onlyInjured ? AdaColors.navy : .clear, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(AdaColors.canvas, in: Capsule())
            }

            if displayedTurtles.isEmpty {
                ContentUnavailableView("No priority triage cases", systemImage: "cross.case", description: Text("All catalogued individuals are currently healthy."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack {
                    Text("Turtle").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Location").frame(width: 110, alignment: .leading)
                    Text("Condition").frame(width: 82, alignment: .trailing)
                }
                .font(.system(size: 10))
                .foregroundStyle(AdaColors.secondaryInk)

                ForEach(displayedTurtles.prefix(4)) { turtle in
                    Divider()
                    Button {
                        onSelectTurtle(turtle)
                    } label: {
                        HStack(spacing: 10) {
                            TurtlePhoto(paths: turtle.identityPhotoPaths, size: 30)
                            Text(turtle.displayName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(turtle.location).lineLimit(1).frame(width: 110, alignment: .leading).foregroundStyle(AdaColors.secondaryInk)
                            ConditionPill(condition: turtle.condition).frame(width: 82, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftRecaptureWidget: View {
    let analytics: DashboardAnalytics
    let onSelectTurtle: (Turtle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                SectionTitle("Mark-recapture fidelity", subtitle: "Sighting frequency cohorts")
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Recapture rate").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    Text("\(analytics.recaptureRatePercent)%").font(.system(size: 18, weight: .semibold)).monospacedDigit()
                }
            }

            VStack(spacing: 12) {
                ForEach(analytics.cohorts) { cohort in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(cohort.title).font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.ink)
                            Spacer()
                            Text("\(cohort.count) turtles").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AdaColors.canvas).frame(height: 8)
                                Capsule()
                                    .fill(AdaColors.navy)
                                    .frame(width: max(proxy.size.width * cohort.fraction, cohort.count > 0 ? 8 : 0), height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }

            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("Mean sightings per turtle").font(.system(size: 12))
                Spacer()
                Text(String(format: "%.1f×", analytics.meanSightingsPerIndividual)).font(.system(size: 16, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftHotspotsWidget: View {
    let analytics: DashboardAnalytics
    let onOpenMap: () -> Void

    private var maxSightings: Int { max(analytics.hotspots.map(\.totalSightings).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle("Reef hotspot density", subtitle: "Encounters by monitoring site")
                Spacer()
                Button("Open map  →", action: onOpenMap).buttonStyle(AdaPillButtonStyle())
            }

            if analytics.hotspots.isEmpty {
                ContentUnavailableView("No location records", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 11) {
                    ForEach(analytics.hotspots.prefix(4)) { site in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(site.location).font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.ink)
                                if site.injuredOrScarredCount > 0 {
                                    Text("\(site.injuredOrScarredCount) triage")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(AdaColors.red)
                                        .padding(.horizontal, 7)
                                        .frame(height: 17)
                                        .background(AdaColors.red.opacity(0.1), in: Capsule())
                                }
                                Spacer()
                                Text("\(site.totalSightings) sightings").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(AdaColors.canvas).frame(height: 7)
                                    Capsule()
                                        .fill(AdaColors.navy)
                                        .frame(width: max(proxy.size.width * CGFloat(site.totalSightings) / CGFloat(maxSightings), 8), height: 7)
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftNotSureQueueWidget: View {
    let onOpenScenario: (ReviewScenarioID, ScientistComparisonLayoutMode) -> Void
    let onOpenIdentification: () -> Void

    private struct NotSureQueueRowItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let badge: String
        let badgeTint: Color
        let sampleImageName: String
        let scenario: ReviewScenarioID
        let layoutMode: ScientistComparisonLayoutMode
    }

    private let items: [NotSureQueueRowItem] = [
        NotSureQueueRowItem(
            id: "SGT-2026-1109",
            title: "SGT-2026-1109 · Green turtle (L)",
            subtitle: "Crystal Bay · Rank #1 vs #2 (84% vs 79%)",
            badge: "Not Sure · 6 Junctions",
            badgeTint: AdaColors.orange,
            sampleImageName: "Amina3_L.jpg",
            scenario: .rankOneJunctionMismatch,
            layoutMode: .sideBySide
        ),
        NotSureQueueRowItem(
            id: "SGT-2026-1110",
            title: "SGT-2026-1110 · Hawksbill (R)",
            subtitle: "Jemeluk Wall · Specular glare over J2–J4",
            badge: "Not Sure · Glare",
            badgeTint: AdaColors.red,
            sampleImageName: "Zizo1_R.jpg",
            scenario: .glareOcclusionUnsure,
            layoutMode: .sideBySide
        ),
        NotSureQueueRowItem(
            id: "SCALE-REVIEW-001",
            title: "Scale Polygon Review · Turtle #001 (Amina)",
            subtitle: "Kuta Beach · 12 mock cheek scales (8 confirmed, 4 pending)",
            badge: "Numbered Scales",
            badgeTint: AdaColors.navy,
            sampleImageName: "Amina1_L.jpg",
            scenario: .rankOneJunctionMismatch,
            layoutMode: .scales
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionTitle(
                    "Not Sure review queue",
                    subtitle: "Encounters flagged 'Not Sure' · mock scale & junction annotations ready"
                )
                Spacer()
                Button("Open review  →") {
                    onOpenScenario(.rankOneJunctionMismatch, .sideBySide)
                }
                .buttonStyle(AdaPillButtonStyle())
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    Button {
                        onOpenScenario(row.scenario, row.layoutMode)
                    } label: {
                        HStack(spacing: 12) {
                            if let image = I3SSampleLibrary.loadImage(named: row.sampleImageName) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 38, height: 38)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(AdaColors.canvas)
                                    .frame(width: 38, height: 38)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AdaColors.ink)
                                    .lineLimit(1)
                                Text(row.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(AdaColors.secondaryInk)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(row.badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(row.badgeTint)
                                .padding(.horizontal, 9)
                                .frame(height: 22)
                                .background(row.badgeTint.opacity(0.13), in: Capsule())

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftPhotoIDWidget: View {
    let analytics: DashboardAnalytics
    let onSelectTurtle: (Turtle) -> Void
    let onOpenScientistReview: () -> Void
    let onOpenIdentification: () -> Void

    var body: some View {
        let cov = analytics.photoCoverage
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle("Photo-ID coverage", subtitle: "Same-side scale verification readiness")
                Spacer()
                HStack(spacing: 6) {
                    Button("Scale Review  →", action: onOpenScientistReview).buttonStyle(AdaPillButtonStyle())
                    Button("I3S", action: onOpenIdentification).buttonStyle(AdaPillButtonStyle(secondary: true))
                }
            }

            HStack(spacing: 12) {
                PhotoStatTile(title: "Dual-side", value: "\(cov.bothSidesCount)", tint: AdaColors.green)
                PhotoStatTile(title: "Left only", value: "\(cov.leftOnlyCount)", tint: AdaColors.orange)
                PhotoStatTile(title: "Right only", value: "\(cov.rightOnlyCount)", tint: AdaColors.orange)
                PhotoStatTile(title: "Missing", value: "\(cov.missingBothCount)", tint: AdaColors.red)
            }

            if cov.incompleteIndividuals.isEmpty {
                Text("All catalogued individuals have both Left and Right identity photos.")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.top, 8)
            } else {
                ForEach(cov.incompleteIndividuals.prefix(2)) { entry in
                    Divider()
                    Button {
                        onSelectTurtle(entry.turtle)
                    } label: {
                        HStack {
                            Text(entry.turtle.displayName).font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.ink)
                            Spacer()
                            Text(entry.missingDescription)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AdaColors.orange)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(AdaColors.orange.opacity(0.14), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct PhotoStatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint).monospacedDigit()
            Text(title).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FigCraftConditionWidget: View {
    let analytics: DashboardAnalytics
    let onSelectCondition: (TurtleCondition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Body condition", subtitle: "Catalog health distribution")

            GeometryReader { proxy in
                HStack(spacing: 4) {
                    ForEach(analytics.conditionDistribution.filter { $0.count > 0 }) { item in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(item.condition.tint)
                            .frame(width: max(proxy.size.width * item.fraction - 4, 8), height: 12)
                    }
                }
            }
            .frame(height: 12)

            VStack(spacing: 10) {
                ForEach(analytics.conditionDistribution) { item in
                    Button {
                        onSelectCondition(item.condition)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(item.condition.tint).frame(width: 8, height: 8)
                            Text(item.condition.rawValue).font(.system(size: 12)).foregroundStyle(AdaColors.ink)
                            Spacer()
                            Text("\(item.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(AdaColors.ink)
                            Text("\(Int((item.fraction * 100).rounded()))%")
                                .font(.system(size: 11))
                                .foregroundStyle(AdaColors.secondaryInk)
                                .frame(width: 38, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct FigCraftFavoritesWidget: View {
    let favorites: [Turtle]
    let onSelect: (Turtle) -> Void
    let onBrowseIndividuals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Pinned turtles", subtitle: "\(favorites.count) tracked by this account")
                Spacer()
                Button("Browse →", action: onBrowseIndividuals).buttonStyle(.plain).font(.system(size: 11))
            }

            if favorites.isEmpty {
                ContentUnavailableView("No pinned turtles", systemImage: "heart", description: Text("Favorite an individual to track its encounters here."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(favorites.prefix(4)) { turtle in
                    Divider()
                    Button {
                        onSelect(turtle)
                    } label: {
                        HStack(spacing: 10) {
                            TurtlePhoto(paths: turtle.identityPhotoPaths, size: 30)
                            Text(turtle.displayName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(turtle.location).lineLimit(1).frame(width: 110, alignment: .leading).foregroundStyle(AdaColors.secondaryInk)
                            ConditionPill(condition: turtle.condition)
                        }
                        .font(.system(size: 11))
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

// MARK: - Apple iOS / macOS Sonoma Visual Widget Gallery

private struct AppleStyleWidgetGallerySheet: View {
    @ObservedObject var store: AppStore
    let snapshot: DashboardSnapshot
    let analytics: DashboardAnalytics
    let sightings: [Sighting]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: DashboardWidgetCategory?
    @State private var searchText = ""

    private var activeKinds: Set<DashboardWidgetKind> {
        Set(store.dashboardLayout.widgets.map(\.kind))
    }

    private var filteredKinds: [DashboardWidgetKind] {
        DashboardWidgetKind.allCases.filter { kind in
            let matchesCategory = selectedCategory == nil || kind.category == selectedCategory
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || kind.title.localizedCaseInsensitiveContains(searchText)
                || kind.category.rawValue.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Clean Apple Widget Gallery Sidebar
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    GallerySidebarRow(
                        title: "All",
                        icon: "square.grid.2x2.fill",
                        count: DashboardWidgetKind.allCases.count,
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(DashboardWidgetCategory.allCases) { category in
                        let count = DashboardWidgetKind.allCases.filter { $0.category == category }.count
                        GallerySidebarRow(
                            title: category.rawValue,
                            icon: category.icon,
                            count: count,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }

                Spacer()
            }
            .padding(18)
            .frame(width: 200)
            .background(Color(red: 237 / 255, green: 240 / 255, blue: 243 / 255))

            Divider()

            // Right Visual Preview Grid
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(selectedCategory?.rawValue ?? "All Widgets")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)

                    Spacer()

                    if let category = selectedCategory {
                        let preset = category.matchingPreset
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                store.applyDashboardPreset(preset)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: store.dashboardLayout.activePreset == preset ? "checkmark" : "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Use \(preset.title) Preset")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(AdaPillButtonStyle(secondary: true))
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(AdaPillButtonStyle())
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)

                Divider()

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 20),
                            GridItem(.flexible(), spacing: 20),
                        ],
                        spacing: 20
                    ) {
                        ForEach(filteredKinds) { kind in
                            let isAdded = activeKinds.contains(kind)
                            WidgetGalleryPreviewCard(
                                kind: kind,
                                isAdded: isAdded,
                                snapshot: snapshot,
                                analytics: analytics,
                                sightings: sightings,
                                onToggleWidget: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        if isAdded, let existing = store.dashboardLayout.widgets.first(where: { $0.kind == kind }) {
                                            store.removeDashboardWidget(id: existing.id)
                                        } else {
                                            store.addDashboardWidget(kind)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(24)
                }
            }
            .background(AdaColors.canvas)
        }
        .frame(width: 880, height: 600)
    }
}

private struct GallerySidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : AdaColors.navy)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : AdaColors.ink)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : AdaColors.secondaryInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isSelected ? AdaColors.navy : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live Visual Miniature Preview Card for Widget Gallery

private struct WidgetGalleryPreviewCard: View {
    let kind: DashboardWidgetKind
    let isAdded: Bool
    let snapshot: DashboardSnapshot
    let analytics: DashboardAnalytics
    let sightings: [Sighting]
    let onToggleWidget: () -> Void

    var body: some View {
        Button(action: onToggleWidget) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 233 / 255, green: 236 / 255, blue: 240 / 255))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        }

                    WidgetLiveMiniaturePreview(
                        kind: kind,
                        snapshot: snapshot,
                        analytics: analytics,
                        sightings: sightings
                    )
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 168)
                .onDrag {
                    NSItemProvider(object: "kind:\(kind.rawValue)" as NSString)
                }

                HStack(alignment: .center) {
                    Text(kind.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(isAdded ? AdaColors.green.opacity(0.14) : AdaColors.navy)
                            .frame(width: 28, height: 28)
                        Image(systemName: isAdded ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isAdded ? AdaColors.green : .white)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(14)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Pure visual miniature preview with minimal text so the graphic speaks for itself.
private struct WidgetLiveMiniaturePreview: View {
    let kind: DashboardWidgetKind
    let snapshot: DashboardSnapshot
    let analytics: DashboardAnalytics
    let sightings: [Sighting]

    var body: some View {
        switch kind {
        case .kpiOverview:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Observed").font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                    Text("\(max(snapshot.metrics.observed, analytics.totalIndividuals))")
                        .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)).frame(height: 28)
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)).frame(height: 28)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(AdaColors.navy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "binoculars").font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                    Text("\(max(snapshot.metrics.sightings, analytics.totalCatalogSightings))")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Capsule().fill(.white).frame(width: 48, height: 12)
                }
                .padding(12)
                .frame(width: 88)
                .frame(maxHeight: .infinity, alignment: .leading)
                .background(AdaColors.navy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

        case .notSureQueue:
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("2 Pending")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdaColors.orange)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(AdaColors.orange.opacity(0.14), in: Capsule())
                    Spacer()
                    Image(systemName: "questionmark.diamond.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.navy)
                }
                ForEach([("SGT-1109 · Green (L)", "84% vs 79%"), ("SGT-1110 · Hawksbill (R)", "Glare J2–J4")], id: \.0) { title, sub in
                    HStack {
                        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(AdaColors.ink).lineLimit(1)
                        Spacer()
                        Text(sub).font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    }
                    .padding(8)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .sightingsTrend:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(max(snapshot.metrics.sightings, 43))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AdaColors.navy)
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                SightingsLineChart(
                    months: snapshot.months.isEmpty
                        ? [
                            .init(month: "2026-06", sightings: 3, newIndividuals: 1),
                            .init(month: "2026-07", sightings: 7, newIndividuals: 2),
                            .init(month: "2026-08", sightings: 5, newIndividuals: 1),
                            .init(month: "2026-09", sightings: 11, newIndividuals: 3),
                            .init(month: "2026-10", sightings: 9, newIndividuals: 1),
                            .init(month: "2026-11", sightings: 14, newIndividuals: 2),
                        ]
                        : snapshot.months
                )
            }
            .padding(12)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .geographicMap:
            SightingMapPreview(sightings: sightings)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .speciesBreakdown:
            HStack(alignment: .bottom, spacing: 14) {
                ForEach([("Green", 0.92), ("Hawksbill", 0.68), ("Ridley", 0.48), ("Logger", 0.32)], id: \.0) { label, frac in
                    VStack(spacing: 5) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdaColors.navy)
                            .frame(width: 28, height: 82 * frac)
                        Text(label).font(.system(size: 8)).foregroundStyle(AdaColors.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .recentSightings:
            VStack(spacing: 10) {
                ForEach([("Amina", "Kuta Beach"), ("Aikane", "Nusa Dua"), ("Ghost", "Serangan")], id: \.0) { name, loc in
                    HStack(spacing: 10) {
                        Circle().fill(AdaColors.navy.opacity(0.14)).frame(width: 22, height: 22)
                        Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.ink)
                        Spacer()
                        Text(loc).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .injuryTriage:
            VStack(spacing: 10) {
                ForEach([("Amina", TurtleCondition.injured), ("Nalu", .injured), ("Ghost", .scarred)], id: \.0) { name, cond in
                    HStack {
                        Circle().fill(cond.tint).frame(width: 8, height: 8)
                        Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.ink)
                        Spacer()
                        ConditionPill(condition: cond).scaleEffect(0.85)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .recaptureAnalysis:
            VStack(alignment: .leading, spacing: 10) {
                Text("\(analytics.recaptureRatePercent)%")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AdaColors.navy)
                ForEach([0.78, 0.48, 0.22], id: \.self) { frac in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AdaColors.canvas).frame(height: 8)
                            Capsule().fill(AdaColors.navy).frame(width: proxy.size.width * frac, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .habitatHotspots:
            VStack(alignment: .leading, spacing: 10) {
                ForEach([("Tuban", 0.9), ("Nusa Dua", 0.72), ("Kuta", 0.52)], id: \.0) { site, frac in
                    HStack(spacing: 10) {
                        Text(site).font(.system(size: 10, weight: .medium)).foregroundStyle(AdaColors.ink).frame(width: 54, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AdaColors.canvas).frame(height: 8)
                                Capsule().fill(AdaColors.navy).frame(width: proxy.size.width * frac, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .photoIDReadiness:
            HStack(spacing: 8) {
                ForEach([("L+R", "\(analytics.photoCoverage.bothSidesCount)", AdaColors.green), ("L", "\(analytics.photoCoverage.leftOnlyCount)", AdaColors.orange), ("R", "\(analytics.photoCoverage.rightOnlyCount)", AdaColors.orange)], id: \.0) { lbl, val, tint in
                    VStack(spacing: 4) {
                        Text(val).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                        Text(lbl).font(.system(size: 10, weight: .medium)).foregroundStyle(AdaColors.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .conditionBreakdown:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 5).fill(AdaColors.green).frame(height: 16)
                    RoundedRectangle(cornerRadius: 5).fill(AdaColors.orange).frame(width: 52, height: 16)
                    RoundedRectangle(cornerRadius: 5).fill(AdaColors.red).frame(width: 52, height: 16)
                }
                HStack(spacing: 14) {
                    HStack(spacing: 5) { Circle().fill(AdaColors.green).frame(width: 7, height: 7); Text("Healthy").font(.system(size: 10)) }
                    HStack(spacing: 5) { Circle().fill(AdaColors.orange).frame(width: 7, height: 7); Text("Scarred").font(.system(size: 10)) }
                    HStack(spacing: 5) { Circle().fill(AdaColors.red).frame(width: 7, height: 7); Text("Injured").font(.system(size: 10)) }
                }
                .foregroundStyle(AdaColors.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .favoritesWatch:
            VStack(spacing: 10) {
                ForEach(["Hoku · Green", "Zizo · Leatherback"], id: \.self) { name in
                    HStack(spacing: 10) {
                        Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(AdaColors.red)
                        Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.ink)
                        Spacer()
                    }
                    .padding(10)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Shared FigCraft Chart & Map Subcomponents

private struct SummaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(AdaColors.ink)
            .padding(.horizontal, 15)
            .frame(height: 27)
            .background(.white, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct SightingsLineChart: View {
    let months: [DashboardSnapshot.Month]
    var body: some View {
        GeometryReader { proxy in
            let values = months.map { CGFloat($0.sightings) }
            let maximum = max(values.max() ?? 1, 1)
            VStack(spacing: 8) {
                Canvas { context, size in
                    for step in 0...4 {
                        let y = size.height * CGFloat(step) / 4
                        var grid = Path(); grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y))
                        context.stroke(grid, with: .color(AdaColors.line), lineWidth: 0.5)
                    }
                    let points = values.enumerated().map { index, value in
                        CGPoint(x: size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)), y: size.height - value / maximum * (size.height - 14))
                    }
                    guard let first = points.first, let last = points.last else { return }
                    var line = Path(); line.move(to: first)
                    for point in points.dropFirst() { line.addLine(to: point) }
                    var area = line; area.addLine(to: .init(x: last.x, y: size.height)); area.addLine(to: .init(x: first.x, y: size.height)); area.closeSubpath()
                    context.fill(area, with: .linearGradient(Gradient(colors: [AdaColors.navy.opacity(0.15), .clear]), startPoint: .zero, endPoint: .init(x: 0, y: size.height)))
                    context.stroke(line, with: .color(AdaColors.navy), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                HStack {
                    ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                        if months.count <= 6 || index % 2 == 0 {
                            Text(monthLabel(month.month)).font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly sightings: " + months.map { "\($0.month): \($0.sightings)" }.joined(separator: ", "))
    }

    private func monthLabel(_ value: String) -> String {
        guard let month = Int(value.suffix(2)), (1...12).contains(month) else { return value }
        return Calendar.current.shortMonthSymbols[month - 1]
    }
}

struct SightingMapPreview: View {
    let sightings: [Sighting]
    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            ForEach(sightings) { sighting in
                Annotation(sighting.displayName, coordinate: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude)) {
                    TurtleMapPin(isSelected: false).scaleEffect(0.6)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .accessibilityLabel("Sighting locations map preview")
    }

    private var region: MKCoordinateRegion {
        let lat = sightings.map(\.coordinate.latitude), lon = sightings.map(\.coordinate.longitude)
        guard let minLat = lat.min(), let maxLat = lat.max(), let minLon = lon.min(), let maxLon = lon.max() else {
            return .init(center: .init(latitude: -8.72, longitude: 115.2), span: .init(latitudeDelta: 0.3, longitudeDelta: 0.3))
        }
        return .init(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max(0.06, (maxLat - minLat) * 1.5), longitudeDelta: max(0.06, (maxLon - minLon) * 1.5))
        )
    }
}
