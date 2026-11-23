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

                    Label("Organization summary · last 12 months", systemImage: "info.circle")
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

            Button {
                store.isWidgetPickerPresented = true
            } label: {
                Label("Add Widget", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(AdaColors.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            Text("Drag cards to reorder")
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
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            widgetView(for: rightItem)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
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
                                height: 268,
                                label: "Empty Widget Slot",
                                subtitle: "Click to add a widget next to \(item.kind.title)"
                            ) {
                                store.isWidgetPickerPresented = true
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                FigCraftNotSureQueueWidget(cases: store.pendingNotSureCases,
                    queueError: store.notSureQueueError, onOpen: store.openNotSureReview(caseID:))
            case .sightingsTrend:
                FigCraftTrendWidget(
                    snapshot: snapshot,
                    historyMonths: store.trendMonths.isEmpty ? snapshot.months : store.trendMonths,
                    chartMode: $store.chartMode
                )
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                        Text("Unique individuals in this period").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
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
                Label("Confirmed sightings", systemImage: "binoculars").font(.system(size: 16))
                Text(metrics.sightings.formatted()).font(.system(size: 38, weight: .medium)).monospacedDigit()
                Text("All confirmed encounters").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
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
            subset(title: "First recorded", value: metrics.firstRecorded.formatted(), subtitle: "First record in this period", icon: "calendar")
            subset(title: "Seen again", value: metrics.seenAgain.map { $0.formatted() } ?? "—", subtitle: "Recorded before this period", icon: "arrow.clockwise")
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

enum SightingsWindowSpan: String, CaseIterable, Identifiable, Sendable {
    case sixMonths = "6M"
    case oneYear = "1Y"
    case twoYears = "2Y"

    var id: Self { self }

    var monthCount: Int {
        switch self {
        case .sixMonths: 6
        case .oneYear: 12
        case .twoYears: 24
        }
    }
}

enum SightingsChartStyle: String, CaseIterable, Identifiable, Sendable {
    case points = "Line"
    case bars = "Bars"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .points: "point.topleft.down.to.point.bottomright.curvepath"
        case .bars: "chart.bar.fill"
        }
    }
}

/// Pure, unit-testable sliding window over monthly sightings anchored to the latest month ("Now").
struct SightingsTimelineWindow {
    let allMonths: [DashboardSnapshot.Month]
    let span: SightingsWindowSpan
    let endOffsetFromNow: Int

    var visibleCount: Int {
        min(span.monthCount, allMonths.count)
    }

    var maxOffset: Int {
        max(0, allMonths.count - visibleCount)
    }

    var clampedOffset: Int {
        min(max(0, endOffsetFromNow), maxOffset)
    }

    var isAtNow: Bool { clampedOffset == 0 }

    var visibleMonths: [DashboardSnapshot.Month] {
        guard !allMonths.isEmpty else { return [] }
        let endIndex = max(0, allMonths.count - 1 - clampedOffset)
        let startIndex = max(0, endIndex - visibleCount + 1)
        return Array(allMonths[startIndex...endIndex])
    }

    var rangeLabel: String {
        guard let first = visibleMonths.first, let last = visibleMonths.last else {
            return "No recorded sightings"
        }
        let endText = Self.isCurrentMonth(last.month) ? "\(Self.shortMonthYear(last.month)) · Now" : Self.shortMonthYear(last.month)
        if first.month == last.month { return endText }
        return "\(Self.shortMonthYear(first.month)) – \(endText)"
    }

    static func currentMonthKey(now: Date = Date()) -> String {
        let cal = Calendar.current
        return String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
    }

    static func isCurrentMonth(_ monthKey: String, now: Date = Date()) -> Bool {
        monthKey == currentMonthKey(now: now)
    }

    static func shortMonth(_ value: String) -> String {
        guard let month = Int(value.suffix(2)), (1...12).contains(month) else { return value }
        return Calendar.current.shortMonthSymbols[month - 1]
    }

    static func shortMonthYear(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return value }
        return "\(Calendar.current.shortMonthSymbols[m - 1]) \(parts[0])"
    }
}

struct FigCraftTrendWidget: View {
    let snapshot: DashboardSnapshot
    var historyMonths: [DashboardSnapshot.Month] = []
    @Binding var chartMode: ChartMode

    @State private var span: SightingsWindowSpan = .oneYear
    @State private var chartStyle: SightingsChartStyle = .points
    @State private var endOffsetFromNow: Int = 0
    @State private var activeMonthIndex: Int? = nil

    init(
        snapshot: DashboardSnapshot,
        historyMonths: [DashboardSnapshot.Month] = [],
        chartMode: Binding<ChartMode> = .constant(.sightings)
    ) {
        self.snapshot = snapshot
        self.historyMonths = historyMonths
        self._chartMode = chartMode
    }

    private var sourceMonths: [DashboardSnapshot.Month] {
        historyMonths.isEmpty ? snapshot.months : historyMonths
    }

    private var availableSpans: [SightingsWindowSpan] {
        sourceMonths.count > 12 ? SightingsWindowSpan.allCases : [.sixMonths, .oneYear]
    }

    private var window: SightingsTimelineWindow {
        SightingsTimelineWindow(allMonths: sourceMonths, span: span, endOffsetFromNow: endOffsetFromNow)
    }

    private var visibleMonths: [DashboardSnapshot.Month] {
        window.visibleMonths
    }

    private func metricValue(_ month: DashboardSnapshot.Month) -> Int {
        switch chartMode {
        case .sightings: month.sightings
        case .newIndividuals: month.newIndividuals
        }
    }

    private var windowTotal: Int {
        visibleMonths.reduce(0) { $0 + metricValue($1) }
    }

    private var windowMonthlyAverage: Double {
        guard !visibleMonths.isEmpty else { return 0 }
        return Double(windowTotal) / Double(visibleMonths.count)
    }

    private var activeMonth: DashboardSnapshot.Month? {
        guard let idx = activeMonthIndex, visibleMonths.indices.contains(idx) else { return nil }
        return visibleMonths[idx]
    }

    private var activeDeltaText: (text: String, positive: Bool)? {
        guard let idx = activeMonthIndex, idx > 0, visibleMonths.indices.contains(idx) else { return nil }
        let curr = metricValue(visibleMonths[idx])
        let prev = metricValue(visibleMonths[idx - 1])
        let diff = curr - prev
        if diff == 0 { return ("Same as \(SightingsTimelineWindow.shortMonth(visibleMonths[idx - 1].month))", true) }
        let sign = diff > 0 ? "+" : ""
        return ("\(sign)\(diff) vs \(SightingsTimelineWindow.shortMonth(visibleMonths[idx - 1].month))", diff > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            SightingsLineChart(
                months: visibleMonths,
                chartMode: chartMode,
                style: chartStyle,
                interactive: true,
                selectedIndex: $activeMonthIndex
            )
            .frame(height: 162)

            timelineFooter
        }
        .frame(maxWidth: .infinity, minHeight: 286, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 22)
        .onChange(of: span) { _, _ in
            endOffsetFromNow = min(endOffsetFromNow, window.maxOffset)
            activeMonthIndex = nil
        }
        .onChange(of: sourceMonths.count) { _, _ in
            if !availableSpans.contains(span) { span = .oneYear }
            endOffsetFromNow = min(endOffsetFromNow, window.maxOffset)
            activeMonthIndex = nil
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Sightings over time", subtitle: window.rangeLabel)
                HStack(spacing: 6) {
                    // Metric toggle (Sightings vs New turtles)
                    HStack(spacing: 2) {
                        metricChip("Sightings", mode: .sightings)
                        metricChip("New", mode: .newIndividuals)
                    }
                    .padding(2)
                    .background(AdaColors.surfaceMuted, in: Capsule())

                    // Window span selector (6M | 1Y | 2Y)
                    HStack(spacing: 2) {
                        ForEach(availableSpans) { option in
                            let selected = span == option
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) { span = option }
                            } label: {
                                Text(option.rawValue)
                                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? .white : AdaColors.secondaryInk)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(selected ? AdaColors.navy : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(AdaColors.surfaceMuted, in: Capsule())

                    // Style toggle (Discrete points line vs Bars)
                    HStack(spacing: 2) {
                        ForEach(SightingsChartStyle.allCases) { option in
                            let selected = chartStyle == option
                            Button {
                                withAnimation(.easeOut(duration: 0.14)) { chartStyle = option }
                            } label: {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(selected ? .white : AdaColors.secondaryInk)
                                    .frame(width: 24, height: 22)
                                    .background(selected ? AdaColors.navy : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(option == .points ? "Line with monthly data points" : "Monthly bar chart")
                        }
                    }
                    .padding(2)
                    .background(AdaColors.surfaceMuted, in: Capsule())
                }
            }

            Spacer(minLength: 8)

            if let focused = activeMonth {
                HStack(spacing: 14) {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 5) {
                            if SightingsTimelineWindow.isCurrentMonth(focused.month) {
                                Circle().fill(AdaColors.green).frame(width: 6, height: 6)
                            }
                            Text(SightingsTimelineWindow.shortMonthYear(focused.month) + (SightingsTimelineWindow.isCurrentMonth(focused.month) ? " · Now" : ""))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AdaColors.accent)
                        }
                        Text(metricValue(focused).formatted())
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    }
                    if let delta = activeDeltaText {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Change")
                                .font(.system(size: 9))
                                .foregroundStyle(AdaColors.secondaryInk)
                            Text(delta.text)
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(delta.positive ? AdaColors.green : AdaColors.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((delta.positive ? AdaColors.green : AdaColors.orange).opacity(0.11), in: Capsule())
                        }
                    }
                }
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chartMode == .sightings ? "Window total" : "New turtles")
                            .font(.system(size: 9))
                            .foregroundStyle(AdaColors.secondaryInk)
                        Text(windowTotal.formatted())
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly avg")
                            .font(.system(size: 9))
                            .foregroundStyle(AdaColors.secondaryInk)
                        Text(windowMonthlyAverage.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    }
                }
            }
        }
    }

    private func metricChip(_ title: String, mode: ChartMode) -> some View {
        let selected = chartMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { chartMode = mode }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : AdaColors.secondaryInk)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(selected ? AdaColors.navy : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var timelineFooter: some View {
        if window.maxOffset > 0 {
            // Slidable time-window bar (left = older history, right = Now)
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        endOffsetFromNow = min(window.maxOffset, endOffsetFromNow + 1)
                        activeMonthIndex = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(AdaColors.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(endOffsetFromNow >= window.maxOffset ? AdaColors.secondaryInk.opacity(0.35) : AdaColors.ink)
                .disabled(endOffsetFromNow >= window.maxOffset)
                .help("Earlier month")

                Text(SightingsTimelineWindow.shortMonthYear(sourceMonths.first?.month ?? ""))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .fixedSize()

                Slider(
                    value: Binding(
                        get: { Double(window.maxOffset - window.clampedOffset) },
                        set: { newValue in
                            let target = window.maxOffset - Int(newValue.rounded())
                            if target != endOffsetFromNow {
                                endOffsetFromNow = max(0, min(window.maxOffset, target))
                                activeMonthIndex = nil
                            }
                        }
                    ),
                    in: 0...Double(window.maxOffset),
                    step: 1
                )
                .tint(AdaColors.navy)
                .controlSize(.mini)
                .accessibilityLabel("Slide timeline window toward now")

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        endOffsetFromNow = max(0, endOffsetFromNow - 1)
                        activeMonthIndex = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(AdaColors.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(window.isAtNow ? AdaColors.secondaryInk.opacity(0.35) : AdaColors.ink)
                .disabled(window.isAtNow)
                .help("Later month")

                nowSnapButton(isAnchored: window.isAtNow) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        endOffsetFromNow = 0
                        activeMonthIndex = max(0, visibleMonths.count - 1)
                    }
                }
            }
        } else if visibleMonths.count >= 2 {
            // Direct month scrubber right up to Now when viewing the full loaded span
            let maxIdx = visibleMonths.count - 1
            let currentIdx = activeMonthIndex ?? maxIdx
            let isAtLatest = currentIdx == maxIdx
            HStack(spacing: 8) {
                Text(SightingsTimelineWindow.shortMonthYear(visibleMonths.first?.month ?? ""))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .fixedSize()

                Slider(
                    value: Binding(
                        get: { Double(currentIdx) },
                        set: { activeMonthIndex = min(maxIdx, max(0, Int($0.rounded()))) }
                    ),
                    in: 0...Double(maxIdx),
                    step: 1
                )
                .tint(AdaColors.navy)
                .controlSize(.mini)
                .accessibilityLabel("Scrub sightings timeline to now")

                nowSnapButton(isAnchored: isAtLatest) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        activeMonthIndex = maxIdx
                    }
                }
            }
        } else {
            Text("Hover or drag across the graph to inspect monthly counts.")
                .font(.system(size: 9.5))
                .foregroundStyle(AdaColors.secondaryInk)
        }
    }

    private func nowSnapButton(isAnchored: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isAnchored ? AdaColors.green : Color.white)
                    .frame(width: 5.5, height: 5.5)
                Text(isAnchored ? "Now" : "Slide to Now")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isAnchored ? AdaColors.navy : .white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(isAnchored ? AdaColors.accentSoft : AdaColors.navy, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Jump timeline to the current month")
    }
}

private struct FigCraftGeographicWidget: View {
    let sightings: [Sighting]
    let onOpenMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle("Where turtles were observed", subtitle: "Select a sighting to highlight the same turtle")
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
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: .infinity, alignment: .topLeading)
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
                HStack(spacing: 8) {
                    Text("Turtle").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Species").frame(width: 82, alignment: .leading)
                    Text("Previous").frame(width: 72, alignment: .leading)
                    Text("Latest location").frame(width: 105, alignment: .leading)
                    Text("Latest").frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 10))
                .foregroundStyle(AdaColors.secondaryInk)

                ForEach(rows) { row in
                    Divider()
                    Button {
                        onSelect(turtles.first { $0.id == row.latest.turtleID } ?? row.latest.turtleReference)
                    } label: {
                        HStack(spacing: 8) {
                            HStack(spacing: 8) {
                                TurtlePhoto(paths: turtles.first { $0.id == row.latest.turtleID }?.identityPhotoPaths ?? [], size: 28)
                                Text(row.latest.displayName).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(row.latest.species.rawValue)
                                .lineLimit(1)
                                .foregroundStyle(AdaColors.secondaryInk)
                                .frame(width: 82, alignment: .leading)
                            Text(row.previous.date)
                                .lineLimit(1)
                                .foregroundStyle(AdaColors.secondaryInk)
                                .frame(width: 72, alignment: .leading)
                            Text(row.latest.location)
                                .lineLimit(1)
                                .frame(width: 105, alignment: .leading)
                            Text(row.latest.date)
                                .lineLimit(1)
                                .foregroundStyle(AdaColors.secondaryInk)
                                .frame(width: 72, alignment: .trailing)
                        }
                        .font(.system(size: 10.5))
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: .infinity, alignment: .topLeading)
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
    let cases: [EscalatedNotSureCase]
    let queueError: String?
    let onOpen: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionTitle("Not Sure review queue", subtitle: "\(cases.count) pending on this Mac")
                Spacer()
                Button("Open queue") { onOpen(nil) }
                    .buttonStyle(AdaPillButtonStyle())
            }

            if let queueError {
                Text(queueError).font(.callout).foregroundStyle(AdaColors.secondaryInk)
            } else if cases.isEmpty {
                Label("Photos sent from Photo ID will appear here.", systemImage: "tray")
                    .font(.callout).foregroundStyle(AdaColors.secondaryInk)
                    .padding(.vertical, 18)
            } else {
                ForEach(cases.prefix(3)) { item in
                    Button {
                        onOpen(item.id)
                    } label: {
                        HStack(spacing: 12) {
                            if let image = item.queryImage {
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: 38, height: 38).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "photo").frame(width: 38, height: 38)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(item.isExample ? "Sample review" : item.side.title)
                                    .font(.caption).foregroundStyle(AdaColors.secondaryInk)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionTitle("Photo-ID coverage", subtitle: "Same-side facial photo completeness")
                Spacer()
                Button("Review  →", action: onOpenScientistReview)
                    .buttonStyle(AdaPillButtonStyle())
            }

            HStack(spacing: 10) {
                PhotoStatTile(title: "Dual-side", value: "\(cov.bothSidesCount)")
                PhotoStatTile(title: "Left only", value: "\(cov.leftOnlyCount)")
                PhotoStatTile(title: "Right only", value: "\(cov.rightOnlyCount)")
                PhotoStatTile(title: "Missing", value: "\(cov.missingBothCount)")
            }

            if cov.incompleteIndividuals.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.navy)
                    Text("All \(cov.totalCount) catalogued turtles have Left & Right photos.")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(.top, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cov.incompleteIndividuals.prefix(2).enumerated()), id: \.element.id) { idx, entry in
                        Divider()
                        Button {
                            onSelectTurtle(entry.turtle)
                        } label: {
                            HStack(spacing: 10) {
                                TurtlePhoto(paths: entry.turtle.identityPhotoPaths, size: 28)
                                Text(entry.turtle.displayName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(AdaColors.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.missingDescription)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AdaColors.navy)
                                    .padding(.horizontal, 10)
                                    .frame(height: 22)
                                    .background(AdaColors.canvas, in: Capsule())
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("Dual-side coverage")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AdaColors.secondaryInk)
                Spacer()
                Text("\(cov.bothSidesCount) / \(cov.totalCount) (\(cov.dualSidePercent)%)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaColors.navy)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 22)
    }
}

private struct PhotoStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaColors.navy)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AdaColors.secondaryInk)
                .lineLimit(1)
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
                SectionTitle("Watchlist", subtitle: "\(favorites.count) tracked by this account")
                Spacer()
                Button("Browse →", action: onBrowseIndividuals).buttonStyle(.plain).font(.system(size: 11))
            }

            if favorites.isEmpty {
                ContentUnavailableView("No tracked turtles", systemImage: "bookmark", description: Text("Bookmark an individual to track its encounters here."))
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
                    Text("Pending review")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.navy)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(AdaColors.canvas, in: Capsule())
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.navy)
                }
                ForEach([("SGT-1109 · Green (L)", "84% vs 79%"), ("SGT-1110 · Hawksbill (R)", "Glare review")], id: \.0) { title, sub in
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
                ForEach([("L+R", "\(analytics.photoCoverage.bothSidesCount)"), ("L", "\(analytics.photoCoverage.leftOnlyCount)"), ("R", "\(analytics.photoCoverage.rightOnlyCount)")], id: \.0) { lbl, val in
                    VStack(spacing: 4) {
                        Text(val).font(.system(size: 22, weight: .bold)).foregroundStyle(AdaColors.navy)
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
                        Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(AdaColors.navy)
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
    var chartMode: ChartMode = .sightings
    var style: SightingsChartStyle = .points
    var interactive: Bool = false
    @Binding var selectedIndex: Int?

    init(
        months: [DashboardSnapshot.Month],
        chartMode: ChartMode = .sightings,
        style: SightingsChartStyle = .points,
        interactive: Bool = false,
        selectedIndex: Binding<Int?> = .constant(nil)
    ) {
        self.months = months
        self.chartMode = chartMode
        self.style = style
        self.interactive = interactive
        self._selectedIndex = selectedIndex
    }

    private func value(for month: DashboardSnapshot.Month) -> Int {
        switch chartMode {
        case .sightings: month.sightings
        case .newIndividuals: month.newIndividuals
        }
    }

    private var maxCount: Int {
        max(months.map(value(for:)).max() ?? 1, 1)
    }

    /// Always includes the first month and the final ("Now") month so the current month is never hidden.
    private func visibleTickIndices(count: Int) -> Set<Int> {
        guard count > 0 else { return [] }
        if count <= 7 { return Set(0..<count) }
        let strideStep = count > 14 ? 3 : 2
        var ticks = Set<Int>([0, count - 1])
        var idx = strideStep
        while idx < count - 1 {
            if (count - 1) - idx >= max(1, strideStep - 1) {
                ticks.insert(idx)
            }
            idx += strideStep
        }
        return ticks
    }

    var body: some View {
        let values = months.map { CGFloat(value(for: $0)) }
        let maximum = CGFloat(maxCount)
        let yAxisWidth: CGFloat = interactive ? 26 : 0
        let plotInsetH: CGFloat = interactive ? 10 : 4
        let topPad: CGFloat = interactive ? 24 : 8
        let bottomPad: CGFloat = 4
        let tickIndices = visibleTickIndices(count: months.count)

        GeometryReader { proxy in
            let plotWidth = max(16, proxy.size.width - yAxisWidth)
            let xAxisHeight: CGFloat = 18
            let plotHeight = max(24, proxy.size.height - xAxisHeight - 6)
            let usableHeight = max(12, plotHeight - topPad - bottomPad)

            let xForIndex: (Int) -> CGFloat = { idx in
                guard values.count > 1 else { return plotInsetH + (plotWidth - plotInsetH * 2) * 0.5 }
                let usableW = max(1, plotWidth - plotInsetH * 2)
                return plotInsetH + usableW * CGFloat(idx) / CGFloat(values.count - 1)
            }
            let yForValue: (CGFloat) -> CGFloat = { v in
                topPad + usableHeight * (1.0 - min(1.0, max(0.0, v / maximum)))
            }

            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    if interactive {
                        VStack {
                            Text("\(maxCount)")
                            Spacer()
                            Text("\((maxCount + 1) / 2)")
                            Spacer()
                            Text("0")
                        }
                        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(AdaColors.secondaryInk.opacity(0.75))
                        .frame(width: yAxisWidth, height: plotHeight, alignment: .trailing)
                        .padding(.trailing, 4)
                    }

                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            // Horizontal guide lines
                            for step in 0...2 {
                                let y = topPad + usableHeight * CGFloat(step) / 2.0
                                var grid = Path()
                                grid.move(to: CGPoint(x: 0, y: y))
                                grid.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(grid, with: .color(AdaColors.line.opacity(0.85)), lineWidth: 0.6)
                            }

                            guard !values.isEmpty else { return }
                            let baselineY = topPad + usableHeight

                            if style == .bars {
                                let slotW = (size.width - plotInsetH * 2) / CGFloat(max(values.count, 1))
                                let barW = min(22, max(5, slotW * 0.58))
                                for (idx, val) in values.enumerated() {
                                    let cx = xForIndex(idx)
                                    let topY = yForValue(val)
                                    let barH = max(val > 0 ? 3 : 1.5, baselineY - topY)
                                    let rect = CGRect(x: cx - barW * 0.5, y: baselineY - barH, width: barW, height: barH)
                                    let isSelected = selectedIndex == idx
                                    let isNow = idx == values.count - 1 && SightingsTimelineWindow.isCurrentMonth(months[idx].month)
                                    let fillColor: Color = isSelected
                                        ? AdaColors.accent
                                        : (isNow ? AdaColors.navy : AdaColors.navy.opacity(val > 0 ? 0.72 : 0.16))
                                    let barPath = Path(roundedRect: rect, cornerRadius: min(4, barW * 0.35))
                                    context.fill(barPath, with: .color(fillColor))
                                }
                            } else {
                                // Honest segmented line + discrete monthly data points (zero spline overshoot)
                                let points = values.enumerated().map { idx, val in
                                    CGPoint(x: xForIndex(idx), y: yForValue(val))
                                }
                                guard let first = points.first, let last = points.last else { return }

                                var line = Path()
                                line.move(to: first)
                                for pt in points.dropFirst() {
                                    line.addLine(to: pt)
                                }

                                var area = line
                                area.addLine(to: CGPoint(x: last.x, y: baselineY))
                                area.addLine(to: CGPoint(x: first.x, y: baselineY))
                                area.closeSubpath()
                                context.fill(
                                    area,
                                    with: .linearGradient(
                                        Gradient(colors: [AdaColors.navy.opacity(0.14), AdaColors.navy.opacity(0.01)]),
                                        startPoint: CGPoint(x: 0, y: topPad),
                                        endPoint: CGPoint(x: 0, y: baselineY)
                                    )
                                )
                                context.stroke(
                                    line,
                                    with: .color(AdaColors.navy),
                                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                                )

                                // Draw discrete monthly nodes so real data points are unmistakably clear
                                let nodeRadius: CGFloat = values.count > 14 ? 2.6 : 3.4
                                for (idx, pt) in points.enumerated() {
                                    let isNow = idx == points.count - 1 && SightingsTimelineWindow.isCurrentMonth(months[idx].month)
                                    let isSelected = selectedIndex == idx
                                    let r = isSelected ? 5.2 : (isNow ? 4.2 : nodeRadius)
                                    let dot = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                                    if isSelected {
                                        let halo = Path(ellipseIn: CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18))
                                        context.fill(halo, with: .color(AdaColors.accent.opacity(0.20)))
                                        context.fill(dot, with: .color(AdaColors.accent))
                                        context.stroke(dot, with: .color(.white), lineWidth: 2.0)
                                    } else if isNow {
                                        context.fill(dot, with: .color(AdaColors.accent))
                                        context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                                    } else {
                                        context.fill(dot, with: .color(AdaColors.card))
                                        context.stroke(dot, with: .color(AdaColors.navy), lineWidth: 1.7)
                                    }
                                }
                            }

                            // Vertical scrub hairline for the active month
                            if let activeIdx = selectedIndex, values.indices.contains(activeIdx) {
                                let ax = xForIndex(activeIdx)
                                var guide = Path()
                                guide.move(to: CGPoint(x: ax, y: topPad - 6))
                                guide.addLine(to: CGPoint(x: ax, y: baselineY))
                                context.stroke(
                                    guide,
                                    with: .color(AdaColors.navy.opacity(0.35)),
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                )
                            }
                        }
                        .frame(width: plotWidth, height: plotHeight)

                        // Floating compact readout badge above the scrubbed node
                        if interactive, let activeIdx = selectedIndex, months.indices.contains(activeIdx) {
                            let m = months[activeIdx]
                            let val = value(for: m)
                            let ax = xForIndex(activeIdx)
                            let clampedX = min(max(ax, 66), max(66, plotWidth - 66))
                            let isNow = SightingsTimelineWindow.isCurrentMonth(m.month)
                            let unit = chartMode == .sightings ? (val == 1 ? "sighting" : "sightings") : (val == 1 ? "new turtle" : "new turtles")
                            HStack(spacing: 5) {
                                Text(SightingsTimelineWindow.shortMonth(m.month) + (isNow ? " · Now" : ""))
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("\(val) \(unit)")
                                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(AdaColors.navy, in: Capsule())
                            .shadow(color: Color.black.opacity(0.14), radius: 4, y: 1)
                            .position(x: clampedX, y: 10)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: plotWidth, height: plotHeight)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard interactive, !months.isEmpty else { return }
                        switch phase {
                        case .active(let location):
                            selectedIndex = nearestIndex(forX: location.x, plotWidth: plotWidth, inset: plotInsetH)
                        case .ended:
                            break
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard interactive, !months.isEmpty else { return }
                                selectedIndex = nearestIndex(forX: value.location.x, plotWidth: plotWidth, inset: plotInsetH)
                            }
                    )
                }

                // X-axis month labels (anchored cleanly to exact node X positions, always showing Now!)
                ZStack(alignment: .leading) {
                    ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                        if tickIndices.contains(index) {
                            let isNow = index == months.count - 1 && SightingsTimelineWindow.isCurrentMonth(month.month)
                            let isSelected = selectedIndex == index
                            let rawX = yAxisWidth + xForIndex(index)
                            let clampedX = min(max(rawX, yAxisWidth + 16), max(yAxisWidth + 16, proxy.size.width - (isNow ? 22 : 14)))
                            Text(isNow ? "\(SightingsTimelineWindow.shortMonth(month.month)) · Now" : SightingsTimelineWindow.shortMonth(month.month))
                                .font(.system(size: 9, weight: (isNow || isSelected) ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AdaColors.navy : (isNow ? AdaColors.accent : AdaColors.secondaryInk))
                                .fixedSize()
                                .position(x: clampedX, y: xAxisHeight * 0.5)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: xAxisHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly sightings: " + months.map { "\($0.month): \(value(for: $0))" }.joined(separator: ", "))
    }

    private func nearestIndex(forX x: CGFloat, plotWidth: CGFloat, inset: CGFloat) -> Int {
        guard months.count > 1 else { return 0 }
        let usableW = max(1, plotWidth - inset * 2)
        let fraction = min(1, max(0, (x - inset) / usableW))
        return min(months.count - 1, max(0, Int((fraction * CGFloat(months.count - 1)).rounded())))
    }
}

struct SightingMapPreview: View {
    let sightings: [Sighting]

    private var previewPins: [Sighting] {
        // Keep mini overview map clean across both Bali and pan-Asian Super Account datasets
        var seenCells = Set<String>()
        var result: [Sighting] = []
        let cellSize = region.span.latitudeDelta > 8 ? 4.0 : 0.03
        for item in sightings {
            let key = "\(Int((item.coordinate.latitude / cellSize).rounded())):\(Int((item.coordinate.longitude / cellSize).rounded()))"
            if seenCells.insert(key).inserted {
                result.append(item)
            }
            if result.count >= 16 { break }
        }
        return result
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            ForEach(previewPins) { sighting in
                Annotation(sighting.displayName, coordinate: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude), anchor: .bottom) {
                    TurtleMapPin(state: .other).scaleEffect(0.68, anchor: .bottom)
                }
                .annotationTitles(.hidden)
            }
        }
        .id("\(sightings.count)-\(sightings.first?.id ?? "empty")")
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

#if DEBUG
#Preview("Dashboard · Sightings Over Time (Slide to Now)") {
    let cal = Calendar.current
    let now = Date()
    let sampleCounts = [4, 6, 5, 9, 12, 8, 7, 11, 15, 13, 18, 14, 10, 12, 16, 21, 19, 14, 17, 23, 28, 22, 26, 31]
    let sampleNew    = [1, 2, 1, 3,  4, 2, 2,  3,  4,  3,  5,  3,  2,  3,  4,  6,  5,  3,  4,  6,  7,  5,  6,  8]
    let months: [DashboardSnapshot.Month] = (0..<24).compactMap { idx in
        guard let d = cal.date(byAdding: .month, value: -23 + idx, to: now) else { return nil }
        let key = String(format: "%04d-%02d", cal.component(.year, from: d), cal.component(.month, from: d))
        return DashboardSnapshot.Month(month: key, sightings: sampleCounts[idx], newIndividuals: sampleNew[idx])
    }
    let snapshot = DashboardSnapshot(months: Array(months.suffix(12)), species: [])
    return FigCraftTrendWidget(snapshot: snapshot, historyMonths: months)
        .padding(24)
        .frame(width: 720, height: 340)
        .background(AdaColors.canvas)
        .preferredColorScheme(.light)
}
#endif
