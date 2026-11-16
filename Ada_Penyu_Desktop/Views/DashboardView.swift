import MapKit
import SwiftUI

struct DashboardView: View {
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
    @State private var showSpeciesSightings = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary(compact: proxy.size.width < 1050)
                    adaptiveRow(width: proxy.size.width) {
                        trend
                        geographicCard
                    }
                    adaptiveRow(width: proxy.size.width) {
                        recentCard
                        speciesCard
                    }
                    Label("Organization records · summary covers the last 12 months", systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(.horizontal, AdaLayout.pagePadding).padding(.top, 14).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func adaptiveRow<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        if width >= 1000 { HStack(alignment: .top, spacing: 24, content: content) }
        else { VStack(spacing: 24, content: content) }
    }

    private func summary(compact: Bool) -> some View {
        let metrics = snapshot.metrics
        return HStack(spacing: 24) {
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
            .padding(22).frame(maxWidth: .infinity, minHeight: compact ? 255 : 170, alignment: .leading)
            .background(AdaColors.navy, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius))
            VStack(alignment: .leading, spacing: 10) {
                Label("Recorded sightings", systemImage: "binoculars").font(.system(size: 16))
                Text(metrics.sightings.formatted()).font(.system(size: 38, weight: .medium)).monospacedDigit()
                Text("All records in the summary").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                Button("View sightings  →", action: onShowSightings).buttonStyle(SummaryButtonStyle())
            }
            .padding(22).frame(width: compact ? 220 : 255, height: compact ? 255 : 170, alignment: .leading)
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
        .padding(16).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var trend: some View {
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
                }.padding(.leading, 10)
            }
            SightingsLineChart(months: snapshot.months).frame(height: 150)
            Text("Counts reflect recorded sightings.").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading).adaCard(padding: 22)
    }

    private var geographicCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle("Where turtles were observed", subtitle: "Map records · current map filters")
                Spacer(minLength: 8)
                Button("Open map  →", action: onOpenMap).buttonStyle(AdaPillButtonStyle())
            }
            SightingMapPreview(sightings: recentSightings).frame(height: 175)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("\(recentSightings.count) loaded sightings · Map data © Apple")
                .font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading).adaCard(padding: 22)
    }

    private var recentCard: some View {
        let rows = Array(RecentResighting.rows(from: recentSightings).prefix(4))
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Recent resightings", subtitle: "From loaded map records")
                Spacer()
                Button("View all →", action: onShowSightings).buttonStyle(.plain).font(.system(size: 11))
            }
            if rows.isEmpty {
                ContentUnavailableView("No resightings in this range", systemImage: "tortoise", description: Text("A turtle needs two recorded encounters to appear here."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack { Text("Turtle").frame(maxWidth: .infinity, alignment: .leading); Text("Previous").frame(width: 90, alignment: .leading); Text("Latest location").frame(width: 110, alignment: .leading) }
                    .font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
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
                        .font(.system(size: 11)).frame(minHeight: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading).adaCard(padding: 22)
    }

    private var speciesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle("Species observed")
                Spacer()
                HStack(spacing: 2) {
                    ForEach([false, true], id: \.self) { sightings in
                        Button(sightings ? "Sightings" : "Individuals") { showSpeciesSightings = sightings }
                            .font(.system(size: 10)).foregroundStyle(showSpeciesSightings == sightings ? .white : AdaColors.ink)
                            .padding(.horizontal, 12).frame(height: 26)
                            .background(showSpeciesSightings == sightings ? AdaColors.navy : .clear, in: Capsule())
                            .accessibilityAddTraits(showSpeciesSightings == sightings ? .isSelected : [])
                    }
                }.buttonStyle(.plain).padding(2).background(AdaColors.canvas, in: Capsule())
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
                            RoundedRectangle(cornerRadius: 4).fill(AdaColors.navy)
                                .frame(width: 40, height: max(2, 100 * CGFloat(value) / CGFloat(maximum)))
                            SpeciesLabel(species: item.species).font(.system(size: 9)).frame(height: 28)
                        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                    }
                }.frame(height: 150)
            }
            Divider()
            HStack {
                Text(showSpeciesSightings ? "Total species sightings" : "Total individuals").font(.system(size: 12))
                Spacer()
                Text(snapshot.species.reduce(0) { $0 + (showSpeciesSightings ? $1.sightings : $1.individuals) }.formatted()).font(.system(size: 16, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading).adaCard(padding: 22)
    }
}

private struct SummaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11)).foregroundStyle(AdaColors.ink)
            .padding(.horizontal, 15).frame(height: 27).background(.white, in: Capsule()).opacity(configuration.isPressed ? 0.7 : 1)
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
        return .init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max(0.06, (maxLat - minLat) * 1.5), longitudeDelta: max(0.06, (maxLon - minLon) * 1.5)))
    }
}
