import SwiftUI

struct DashboardView: View {
    @Binding var chartMode: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SightingsChartCard(chartMode: $chartMode)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        SpeciesFoundCard()
                            .frame(maxWidth: .infinity)
                        RecentSightingsCard()
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 24) {
                        SpeciesFoundCard()
                        RecentSightingsCard()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AdaLayout.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.hidden)
    }
}

private struct SightingsChartCard: View {
    @Binding var chartMode: String
    private let values: [CGFloat] = [64, 70, 59, 49, 55, 68, 83, 95, 88, 78, 91, 105]
    private let months = ["Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug"]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DashboardChartHeader(chartMode: $chartMode)

            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(["120", "80", "40", "0"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(AdaColors.tertiaryInk)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: 22, height: 235)

                VStack(spacing: 7) {
                    GeometryReader { proxy in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(AdaColors.navy.opacity(0.05))
                                .frame(width: max(30, proxy.size.width * 0.075), height: proxy.size.height)
                                .offset(x: proxy.size.width * 0.18)
                            SightingsChart(values: values)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nov")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AdaColors.tertiaryInk)
                                Text("58 Sightings")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AdaColors.ink)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdaColors.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                            .offset(x: min(proxy.size.width * 0.15, 120), y: 72)
                        }
                    }
                    .frame(height: 235)

                    HStack {
                        ForEach(months, id: \.self) { month in
                            Text(month)
                                .font(.system(size: 9))
                                .foregroundStyle(AdaColors.tertiaryInk)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard(padding: 20)
    }
}

private struct DashboardChartHeader: View {
    @Binding var chartMode: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                title
                Spacer(minLength: 12)
                controls
            }

            VStack(alignment: .leading, spacing: 12) {
                title
                controls
            }
        }
    }

    private var title: some View {
        SectionTitle("Sightings over time", subtitle: "Sightings · All species · last 12 months")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            speciesMenu
            chartModeToggle
            Button(action: {}) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaColors.tertiaryInk)
                    .frame(width: 29, height: 29)
                    .background(Color.black.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var speciesMenu: some View {
        Menu {
            Button("All species") {}
            Button("Green turtle") {}
            Button("Hawksbill") {}
        } label: {
            HStack(spacing: 8) {
                Text("All species")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11))
            .foregroundStyle(AdaColors.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 29)
            .background(Color.black.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private var chartModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(["Sightings", "New individuals"], id: \.self) { mode in
                Button(mode) { chartMode = mode }
                    .font(.system(size: 11, weight: chartMode == mode ? .medium : .regular))
                    .foregroundStyle(chartMode == mode ? AdaColors.ink : AdaColors.tertiaryInk)
                    .padding(.horizontal, 12)
                    .frame(height: 29)
                    .background(chartMode == mode ? AdaColors.card : Color.black.opacity(0.025))
            }
        }
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .buttonStyle(.plain)
    }
}

private struct SightingsChart: View {
    let values: [CGFloat]

    var body: some View {
        Canvas { context, size in
            for index in 0..<4 {
                let y = size.height * CGFloat(index) / 3
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(AdaColors.line), lineWidth: 1)
            }

            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: size.height - (value / 120 * size.height)
                )
            }

            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            if let first = points.first { area.addLine(to: first) }
            for point in points.dropFirst() { area.addLine(to: point) }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(AdaColors.navy.opacity(0.06)))

            var line = Path()
            if let first = points.first { line.move(to: first) }
            for point in points.dropFirst() { line.addLine(to: point) }
            context.stroke(
                line,
                with: .color(AdaColors.navy),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            if points.count > 2 {
                let selected = points[2]
                let marker = Path(ellipseIn: CGRect(x: selected.x - 6, y: selected.y - 6, width: 12, height: 12))
                context.fill(marker, with: .color(AdaColors.card))
                context.stroke(marker, with: .color(AdaColors.navySoft), lineWidth: 2)
            }
        }
    }
}

private struct SpeciesFoundCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Species Found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdaColors.ink)

            HStack {
                Text("Species")
                Spacer()
                Text("Individuals").frame(width: 82, alignment: .trailing)
                Text("Sightings").frame(width: 68, alignment: .trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(AdaColors.tertiaryInk)

            VStack(spacing: 17) {
                ForEach(DemoData.speciesSummaries) { summary in
                    HStack {
                        Text(summary.species.rawValue)
                            .font(.system(size: 13))
                            .foregroundStyle(AdaColors.ink)
                        Spacer()
                        Text("\(summary.individuals)")
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .frame(width: 82, alignment: .trailing)
                        Text("\(summary.sightings)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaColors.ink)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard(padding: 20)
    }
}

private struct RecentSightingsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent sightings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Spacer()
                Button("See all ›") {}
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.navySoft)
                    .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(DemoData.sightings) { sighting in
                    RecentSightingRow(sighting: sighting)
                    if sighting.id != DemoData.sightings.last?.id {
                        Divider().overlay(AdaColors.line)
                    }
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
            HStack(spacing: 4) {
                PlaceholderImage(size: 30)
                PlaceholderImage(size: 30)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sighting.turtleID)
                    .font(.system(size: 13))
                    .foregroundStyle(AdaColors.ink)
                Text(sighting.location)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.tertiaryInk)
            }
            Spacer(minLength: 8)
            ConditionPill(condition: sighting.condition)
            Text(sighting.date)
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }
}
