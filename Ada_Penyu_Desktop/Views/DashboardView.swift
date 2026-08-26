import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    let turtles: [Turtle]
    let recentSightings: [Sighting]
    let dataMode: DataMode
    let isFallback: Bool
    @Binding var chartMode: String
    let onSelect: (Turtle) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Monitoring overview").font(.system(size: 22, weight: .semibold)).foregroundStyle(AdaColors.ink)
                        Text("A quick read of sightings and individual health across the group.").font(.system(size: 12)).foregroundStyle(AdaColors.tertiaryInk)
                    }
                    Spacer()
                    Text("Updated just now").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
                }
                SightingsChartCard(months: snapshot.months, dataMode: dataMode, isFallback: isFallback, chartMode: $chartMode)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        SpeciesFoundCard(summaries: snapshot.species).frame(maxWidth: .infinity)
                        RecentSightingsCard(sightings: recentSightings, turtles: turtles, onSelect: onSelect).frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 24) {
                        SpeciesFoundCard(summaries: snapshot.species)
                        RecentSightingsCard(sightings: recentSightings, turtles: turtles, onSelect: onSelect)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AdaLayout.pagePadding)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SightingsChartCard: View {
    let months: [DashboardSnapshot.Month]
    let dataMode: DataMode
    let isFallback: Bool
    @Binding var chartMode: String

    private var values: [CGFloat] { months.map { CGFloat(chartMode == "Sightings" ? $0.sightings : $0.newIndividuals) } }
    private var maxValue: CGFloat { max(values.max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 10) {
                SectionTitle("Sightings over time", subtitle: "\(chartMode) · All species · last 12 months")
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isFallback ? AdaColors.orange : (dataMode == .live ? AdaColors.green : AdaColors.accent))
                            .frame(width: 6, height: 6)
                        Text(isFallback ? "Fixture fallback" : (dataMode == .live ? "Live backend" : "Fixture data"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    HStack(spacing: 0) {
                        ForEach(["Sightings", "New individuals"], id: \.self) { mode in
                            Button(mode) { chartMode = mode }
                                .font(.system(size: 11, weight: chartMode == mode ? .medium : .regular))
                                .foregroundStyle(chartMode == mode ? AdaColors.ink : AdaColors.tertiaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 29)
                                .background(chartMode == mode ? AdaColors.card : Color.clear)
                        }
                    }
                    .background(Color.black.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .buttonStyle(.plain)
                }
            }

            if months.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 25))
                        .foregroundStyle(AdaColors.tertiaryInk)
                    Text("No monitoring data yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Text("Sightings will appear here after the first field record is synced.")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                .frame(maxWidth: .infinity, minHeight: 245)
            } else {
                HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach([maxValue, maxValue * 0.66, maxValue * 0.33, 0], id: \.self) { value in
                        Text("\(Int(value.rounded()))").font(.system(size: 9)).foregroundStyle(AdaColors.tertiaryInk).frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: 30, height: 210)
                VStack(spacing: 7) {
                    GeometryReader { proxy in
                        SightingsChart(months: months, chartMode: chartMode, values: values, maxValue: maxValue)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(height: 210)
                    HStack {
                        ForEach(months) { month in
                            Text(month.month.suffix(2)).font(.system(size: 9)).foregroundStyle(AdaColors.tertiaryInk).frame(maxWidth: .infinity)
                        }
                    }
                }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard(padding: 20)
    }
}

private struct SightingsChart: View {
    let months: [DashboardSnapshot.Month]
    let chartMode: String
    let values: [CGFloat]
    let maxValue: CGFloat
    @State private var hoveredIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(in: proxy.size)
            ZStack {
                Canvas { context, size in
                    for index in 0..<4 {
                        let y = size.height * CGFloat(index) / 3
                        var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(grid, with: .color(AdaColors.line), lineWidth: 1)
                    }
                    guard !points.isEmpty else { return }
                    var area = Path(); area.move(to: CGPoint(x: 0, y: size.height)); area.addLine(to: points[0]); for point in points.dropFirst() { area.addLine(to: point) }; area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
                    context.fill(area, with: .color(AdaColors.navy.opacity(0.07)))
                    var line = Path(); line.move(to: points[0]); for point in points.dropFirst() { line.addLine(to: point) }
                    context.stroke(line, with: .color(AdaColors.navy), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    for point in points {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(AdaColors.card))
                        context.stroke(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(AdaColors.navy), lineWidth: 1.5)
                    }
                    if let hoveredIndex, points.indices.contains(hoveredIndex) {
                        let point = points[hoveredIndex]
                        var guide = Path(); guide.move(to: CGPoint(x: point.x, y: 0)); guide.addLine(to: CGPoint(x: point.x, y: size.height))
                        context.stroke(guide, with: .color(AdaColors.navy.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(AdaColors.navy))
                    }
                }

                if let hoveredIndex, points.indices.contains(hoveredIndex), months.indices.contains(hoveredIndex) {
                    let point = points[hoveredIndex]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(monthLabel(months[hoveredIndex].month))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AdaColors.secondaryInk)
                        Text("\(Int(values[hoveredIndex])) \(chartMode.lowercased())")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(AdaColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                    .position(
                        x: min(max(point.x, 58), proxy.size.width - 58),
                        y: max(point.y - 38, 28)
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    guard !values.isEmpty else { hoveredIndex = nil; return }
                    let fraction = min(max(location.x / max(proxy.size.width, 1), 0), 1)
                    hoveredIndex = Int((fraction * CGFloat(max(values.count - 1, 0))).rounded())
                case .ended:
                    hoveredIndex = nil
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        values.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                y: size.height - (value / maxValue * size.height)
            )
        }
    }

    private func monthLabel(_ value: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM"
        guard let date = input.date(from: value) else { return value }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "MMM yyyy"
        return output.string(from: date)
    }
}

private struct SpeciesFoundCard: View {
    let summaries: [SpeciesSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Species found").font(.system(size: 14, weight: .semibold)).foregroundStyle(AdaColors.ink)
            HStack { Text("Species"); Spacer(); Text("Individuals").frame(width: 82, alignment: .trailing); Text("Sightings").frame(width: 68, alignment: .trailing) }.font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
            VStack(spacing: 15) {
                ForEach(summaries) { summary in
                    HStack { Text(summary.species.rawValue).font(.system(size: 13)).foregroundStyle(AdaColors.ink); Spacer(); Text("\(summary.individuals)").font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).frame(width: 82, alignment: .trailing); Text("\(summary.sightings)").font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink).frame(width: 68, alignment: .trailing) }
                }
                if summaries.isEmpty {
                    Text("No species summary available")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.tertiaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard(padding: 20)
    }
}

private struct RecentSightingsCard: View {
    let sightings: [Sighting]
    let turtles: [Turtle]
    let onSelect: (Turtle) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Recent sightings").font(.system(size: 14, weight: .semibold)).foregroundStyle(AdaColors.ink); Spacer(); Text("Latest field records").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk) }
            VStack(spacing: 0) {
                ForEach(sightings.prefix(5)) { sighting in
                    Button { if let turtle = turtles.first(where: { $0.id == sighting.turtleID }) ?? DemoFixtures.turtles.first(where: { $0.id == sighting.turtleID }) { onSelect(turtle) } } label: { RecentSightingRow(sighting: sighting) }
                        .buttonStyle(.plain)
                    if sighting.id != sightings.prefix(5).last?.id { Divider().overlay(AdaColors.line) }
                }
                if sightings.isEmpty {
                    Text("No recent sightings").font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard(padding: 20)
    }
}

private struct RecentSightingRow: View {
    let sighting: Sighting
    var body: some View {
        HStack(spacing: 12) {
            PlaceholderImage(size: 30)
            VStack(alignment: .leading, spacing: 3) { Text(sighting.turtleID).font(.system(size: 13)).foregroundStyle(AdaColors.ink); Text(sighting.location).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk) }
            Spacer(minLength: 8)
            ConditionPill(condition: sighting.condition)
            Text(sighting.date).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk).frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
