import SwiftUI

struct TurtleDetailView: View {
    let turtle: Turtle
    let detail: TurtleDetailData?
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onExport: () -> Void

    @State private var activeTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case bodyCondition

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .bodyCondition: "Body Condition"
            }
        }
    }

    private var measurements: [TurtleMeasurement] { detail?.measurements ?? [] }
    private var logs: [TurtleLogSummary] { detail?.logs ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TurtleSummaryCard(
                    turtle: turtle,
                    isFavorite: isFavorite,
                    onToggleFavorite: onToggleFavorite,
                    onExport: onExport
                )

                DetailTabBar(active: $activeTab, logCount: logs.count)

                switch activeTab {
                case .overview:
                    OverviewTab(logs: logs, measurements: measurements)
                case .bodyCondition:
                    BodyConditionTab(logs: logs, onExport: onExport)
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Tab bar

private struct DetailTabBar: View {
    @Binding var active: TurtleDetailView.DetailTab
    let logCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TurtleDetailView.DetailTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { active = tab }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.title)
                            .font(.system(size: 12, weight: active == tab ? .semibold : .regular))
                            .foregroundStyle(active == tab ? AdaColors.ink : AdaColors.secondaryInk)
                        if tab == .bodyCondition {
                            Text("\(logCount)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(active == tab ? AdaColors.ink : AdaColors.tertiaryInk)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 16)
                                .background(active == tab ? Color.black.opacity(0.06) : Color.black.opacity(0.035))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(active == tab ? AdaColors.card : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(3)
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Overview tab

private struct OverviewTab: View {
    let logs: [TurtleLogSummary]
    let measurements: [TurtleMeasurement]

    var body: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    SightingTrendPanel(logs: logs)
                        .frame(maxWidth: .infinity, minHeight: 215, maxHeight: 215, alignment: .topLeading)
                    MeasurementPanel(measurements: measurements)
                        .frame(width: 315)
                        .frame(minHeight: 215, maxHeight: 215, alignment: .topLeading)
                }
                VStack(spacing: 16) {
                    SightingTrendPanel(logs: logs)
                    MeasurementPanel(measurements: measurements)
                }
            }
            LocationPanel(logs: logs)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        }
    }
}

// MARK: - Body condition tab
//
// Two-column layout:
// • Left card: filter chips + turtle diagram with body parts tinted by their
//   worst recorded condition + a legend.
// • Right card: chronological, expandable history of body-condition records.

private struct BodyConditionTab: View {
    let logs: [TurtleLogSummary]
    let onExport: () -> Void

    @State private var diagramFilter: DiagramFilter = .all

    enum DiagramFilter: Hashable, Identifiable {
        case all
        case condition(TurtleCondition)

        static var allCases: [DiagramFilter] {
            [.all] + TurtleCondition.allCases.map(DiagramFilter.condition)
        }

        var id: String {
            switch self {
            case .all: "all"
            case .condition(let condition): condition.rawValue
            }
        }

        var title: String {
            switch self {
            case .all: "All"
            case .condition(let condition): condition.rawValue
            }
        }
    }

    /// Only entries anchored to a body part — plain sightings stay in the
    /// Overview tab's sighting history.
    private var bodyLogs: [TurtleLogSummary] {
        logs.filter { $0.bodyPart != nil && $0.condition != nil }
    }

    /// Body part → its worst recorded condition. Used for the diagram tint.
    private var highlights: [TurtleBodyPart: TurtleCondition] {
        var result: [TurtleBodyPart: TurtleCondition] = [:]
        for log in bodyLogs where matchesFilter(log) {
            guard let part = log.bodyPart, let condition = log.condition else { continue }
            if let existing = result[part], severity(existing) >= severity(condition) { continue }
            result[part] = condition
        }
        return result
    }

    /// The conditions we actually observed on this turtle — drives the legend.
    private var legendConditions: [TurtleCondition] {
        TurtleCondition.allCases.filter { condition in
            bodyLogs.contains(where: { $0.condition == condition })
        }
    }

    /// Newest first so the freshest record is auto-expanded.
    private var historyLogs: [TurtleLogSummary] {
        bodyLogs.sorted { lhs, rhs in
            let formatter = APIFormatters.display
            return (formatter.date(from: lhs.date) ?? .distantPast) > (formatter.date(from: rhs.date) ?? .distantPast)
        }
    }

    var body: some View {
        if bodyLogs.isEmpty {
            EmptyBodyCondition()
                .adaCard(padding: 24)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    BodyConditionDiagramCard(filter: $diagramFilter, highlights: highlights, legend: legendConditions)
                        .frame(width: 340)
                    BodyConditionHistoryCard(logs: historyLogs, onExport: onExport)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: 16) {
                    BodyConditionDiagramCard(filter: $diagramFilter, highlights: highlights, legend: legendConditions)
                    BodyConditionHistoryCard(logs: historyLogs, onExport: onExport)
                }
            }
        }
    }

    private func matchesFilter(_ log: TurtleLogSummary) -> Bool {
        switch diagramFilter {
        case .all: return true
        case .condition(let condition): return log.condition == condition
        }
    }

    private func severity(_ condition: TurtleCondition) -> Int {
        switch condition {
        case .healthy: 0
        case .scarred: 1
        case .injured: 2
        }
    }
}

// MARK: Diagram card

private struct BodyConditionDiagramCard: View {
    @Binding var filter: BodyConditionTab.DiagramFilter
    let highlights: [TurtleBodyPart: TurtleCondition]
    let legend: [TurtleCondition]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Body Condition")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdaColors.ink)

            DiagramFilterChips(filter: $filter)

            TurtleBodyDiagram(highlights: highlights)
                .frame(maxWidth: .infinity, minHeight: 190)

            if !legend.isEmpty {
                HStack(spacing: 20) {
                    ForEach(legend) { condition in LegendDot(condition: condition) }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct DiagramFilterChips: View {
    @Binding var filter: BodyConditionTab.DiagramFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BodyConditionTab.DiagramFilter.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { filter = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: filter == option ? .semibold : .regular))
                        .foregroundStyle(filter == option ? .white : AdaColors.secondaryInk)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(filter == option ? AdaColors.navy : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.045))
        .clipShape(Capsule())
    }
}

private struct LegendDot: View {
    let condition: TurtleCondition
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(condition.tint).frame(width: 8, height: 8)
            Text(condition.rawValue)
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Renders the top-down turtle silhouette with each body part tinted by its
/// worst recorded condition. Parts without a record render in a neutral tint.
/// Each body-part asset is cropped to its own bounding box (not a full-frame
/// image), so parts are placed at hand-tuned positions within a shared
/// `canvasSize` — matching the carapace artboard, which is the full silhouette
/// — rather than naively stacked, which would scale every part to fill the
/// whole frame and destroy the layout.
private struct TurtleBodyDiagram: View {
    let highlights: [TurtleBodyPart: TurtleCondition]

    private struct PartLayout {
        let size: CGSize
        let origin: CGPoint // top-left, in canvas points
    }

    // The canvas spans the true bounding box of every positioned part below —
    // head at y:0..323, flippers reaching x:0..1076 — so nothing spills past
    // the frame the way it did when the canvas only matched the shell's own
    // artboard while limbs were positioned outside of it.
    private static let canvasSize = CGSize(width: 1076, height: 955)
    private static let neutralTint = AdaColors.tertiaryInk.opacity(0.55)
    private static let outlineWidth: CGFloat = 3

    /// Shell shrunk to ~72% of its own artboard so the limbs have visible
    /// clearance to poke out past its edge instead of being swallowed by an
    /// ellipse that spans the entire shell artboard.
    private static let layouts: [TurtleBodyPart: PartLayout] = [
        .carapace: PartLayout(size: CGSize(width: 446, height: 547), origin: CGPoint(x: 315, y: 293)),
        .head: PartLayout(size: CGSize(width: 234, height: 323), origin: CGPoint(x: 421, y: 0)),
        .flipperLeft: PartLayout(size: CGSize(width: 378, height: 247), origin: CGPoint(x: 0, y: 317)),
        .flipperRight: PartLayout(size: CGSize(width: 378, height: 247), origin: CGPoint(x: 698, y: 317)),
        .footLeft: PartLayout(size: CGSize(width: 192, height: 252), origin: CGPoint(x: 168, y: 617)),
        .footRight: PartLayout(size: CGSize(width: 192, height: 252), origin: CGPoint(x: 716, y: 617)),
        .tail: PartLayout(size: CGSize(width: 143, height: 140), origin: CGPoint(x: 466, y: 815)),
    ]

    /// Back-to-front stacking order: shell first so the appendages layer on top.
    private static let drawOrder: [TurtleBodyPart] = [.carapace, .flipperLeft, .flipperRight, .footLeft, .footRight, .head, .tail]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.canvasSize.width, proxy.size.height / Self.canvasSize.height)
            let xInset = (proxy.size.width - Self.canvasSize.width * scale) / 2
            let yInset = (proxy.size.height - Self.canvasSize.height * scale) / 2

            ForEach(Self.drawOrder) { part in
                if let layout = Self.layouts[part] {
                    let condition = highlights[part]
                    let width = layout.size.width * scale
                    let height = layout.size.height * scale
                    let centerX = xInset + (layout.origin.x + layout.size.width / 2) * scale
                    let centerY = yInset + (layout.origin.y + layout.size.height / 2) * scale

                    ZStack {
                        // A slightly oversized, card-colored copy behind the fill acts as
                        // a halo so overlapping parts stay visually separated regardless
                        // of which two colors happen to land next to each other.
                        Image(part.imageName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: width + Self.outlineWidth * 2, height: height + Self.outlineWidth * 2)
                            .foregroundStyle(AdaColors.card)

                        Image(part.imageName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: width, height: height)
                            .foregroundStyle(condition?.tint ?? Self.neutralTint)
                    }
                    .position(x: centerX, y: centerY)
                    .accessibilityLabel("\(part.displayName)\(condition.map { ": \($0.rawValue)" } ?? "")")
                }
            }
        }
        .aspectRatio(Self.canvasSize.width / Self.canvasSize.height, contentMode: .fit)
        .frame(maxWidth: 230)
        .frame(maxWidth: .infinity)
    }
}

// MARK: History card

private struct BodyConditionHistoryCard: View {
    let logs: [TurtleLogSummary]
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Spacer()
                Button(action: onExport) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                        Text("Export").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AdaColors.ink)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.black.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Export body condition history")
                .accessibilityLabel("Export body condition history")
            }

            VStack(spacing: 10) {
                ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                    BodyConditionEntry(log: log, initiallyExpanded: index == 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct BodyConditionEntry: View {
    let log: TurtleLogSummary
    @State private var isExpanded: Bool

    init(log: TurtleLogSummary, initiallyExpanded: Bool) {
        self.log = log
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(log.condition?.tint ?? AdaColors.tertiaryInk)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                header
                if isExpanded { expandedBody }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(log.bodyPart?.displayName ?? "Unknown")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                if let notes = log.notes {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Text(log.date)
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaColors.tertiaryInk)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse entry" : "Expand entry")
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        HStack(spacing: 10) {
            if let condition = log.condition {
                ConditionPill(condition: condition)
            }
            Text("Recorded at \(log.location)")
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)
        }

        VStack(alignment: .leading, spacing: 5) {
            Text("OBSERVATION")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(AdaColors.tertiaryInk)
            Text(log.notes ?? "No observation recorded.")
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Static placeholder photo strip — encounter photos will hook in once
        // the API returns per-log attachments. Kept here so the layout is
        // faithful to the design brief.
        PhotoStrip(visibleCount: 3, extraCount: 2)

        Button {
            // Placeholder: dedicated encounter view isn't built yet.
        } label: {
            HStack(spacing: 4) {
                Text("Open \(log.date) encounter")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(AdaColors.navySoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(log.date) encounter")
    }
}

private struct PhotoStrip: View {
    let visibleCount: Int
    let extraCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ForEach(0..<visibleCount, id: \.self) { _ in PlaceholderPhoto() }
                if extraCount > 0 {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.045))
                            .frame(width: 56, height: 56)
                        Text("+\(extraCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    .accessibilityLabel("\(extraCount) more photos")
                }
                Spacer()
            }
            Text("\(visibleCount + extraCount) photos")
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
        }
    }
}

private struct PlaceholderPhoto: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.05))
            .frame(width: 56, height: 56)
            .overlay {
                DiagonalStripes()
                    .stroke(Color.black.opacity(0.09), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .accessibilityHidden(true)
    }
}

private struct DiagonalStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 6
        var x: CGFloat = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            x += spacing
        }
        return path
    }
}

private struct EmptyBodyCondition: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cross.case")
                .font(.system(size: 26))
                .foregroundStyle(AdaColors.tertiaryInk)
            Text("No body condition records yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AdaColors.ink)
            Text("Log a body-part observation to populate the diagram and history.")
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

// MARK: - Shared panels

private struct DetailTrendPoint: Identifiable {
    let date: String
    let count: Int
    var id: String { date }
}

private struct SightingTrendPanel: View {
    let logs: [TurtleLogSummary]

    private var points: [DetailTrendPoint] {
        Dictionary(grouping: logs, by: \.date)
            .map { DetailTrendPoint(date: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                let formatter = APIFormatters.display
                return (formatter.date(from: lhs.date) ?? .distantPast) < (formatter.date(from: rhs.date) ?? .distantPast)
            }
    }

    private var maximum: CGFloat {
        CGFloat(max(points.map(\.count).max() ?? 1, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionTitle("Sighting trend", subtitle: "Recorded observations for this individual")
                Spacer()
                Text("\(logs.count) total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(AdaColors.navy.opacity(0.07))
                    .clipShape(Capsule())
            }

            if points.isEmpty {
                InlineEmptyState(text: "No sighting history recorded yet")
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        VStack(spacing: 6) {
                            Text("\(point.count)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AdaColors.secondaryInk)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(AdaColors.navy)
                                .frame(height: max(CGFloat(point.count) / maximum * 70, 5))
                            Text(shortDate(point.date))
                                .font(.system(size: 9))
                                .foregroundStyle(AdaColors.tertiaryInk)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 105, alignment: .bottom)
                .padding(.horizontal, 4)
                .background(alignment: .bottom) {
                    Rectangle().fill(AdaColors.line).frame(height: 1).offset(y: -21)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }

    private func shortDate(_ date: String) -> String {
        guard let value = APIFormatters.display.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: value)
    }
}

private struct TurtleSummaryCard: View {
    let turtle: Turtle
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            PlaceholderImage(size: 85)
            VStack(alignment: .leading, spacing: 7) {
                Text(turtle.species.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink)
                Text(turtle.id).font(.system(size: 22, weight: .semibold)).foregroundStyle(AdaColors.ink)
                HStack(spacing: 7) {
                    DetailTag(text: "Unknown sex")
                    DetailTag(text: turtle.location)
                    ConditionPill(condition: turtle.condition)
                }
            }
            Spacer()
            Rectangle().fill(AdaColors.line).frame(width: 1, height: 75)
            HStack(spacing: 28) {
                DetailMetric(title: "First recorded", value: turtle.firstRecorded)
                DetailMetric(title: "Last seen", value: turtle.lastSeen)
                DetailMetric(title: "Total sightings", value: String(format: "%02d", turtle.sightings))
            }
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isFavorite ? AdaColors.accent : AdaColors.ink)
                    .frame(width: 29, height: 29)
                    .background(Color.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Favorite")
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")

            Button(action: onExport) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaColors.ink)
                    .frame(width: 29, height: 29)
                    .background(Color.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Export individual")
            .accessibilityLabel("Export individual")
        }
        .adaCard(padding: 20)
    }
}

private struct DetailTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .lineLimit(1)
            .foregroundStyle(AdaColors.secondaryInk)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Color.black.opacity(0.045))
            .clipShape(Capsule())
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(AdaColors.ink)
        }
    }
}

private struct MeasurementPanel: View {
    let measurements: [TurtleMeasurement]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Body measurements", subtitle: "Latest recorded values")
            if let latest = measurements.first {
                HStack(spacing: 22) {
                    MeasurementValue(label: "CCL", value: latest.length.map { String(format: "%.1f cm", $0) } ?? "—")
                    MeasurementValue(label: "CCW", value: latest.width.map { String(format: "%.1f cm", $0) } ?? "—")
                    MeasurementValue(label: "Weight", value: latest.weight.map { String(format: "%.1f kg", $0) } ?? "—")
                }
                Text("Measured \(latest.date)").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
            } else {
                InlineEmptyState(text: "No measurements recorded yet")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct MeasurementValue: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(AdaColors.tertiaryInk)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(AdaColors.ink)
        }
    }
}

private struct LocationPanel: View {
    let logs: [TurtleLogSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Known locations", subtitle: "Most recent monitoring sites")
            if logs.isEmpty {
                InlineEmptyState(text: "No location history recorded yet")
            } else {
                ForEach(Array(logs.prefix(3))) { log in
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(AdaColors.navySoft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.location).font(.system(size: 13, weight: .medium)).foregroundStyle(AdaColors.ink)
                            Text(log.date).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct InlineEmptyState: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(AdaColors.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}
