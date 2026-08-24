import SwiftUI

struct ContentView: View {
    @State private var activeSection: AppSection = .dashboard
    @State private var selectedTurtle: Turtle?
    @State private var searchText = ""
    @State private var chartMode = "Sightings"
    @State private var showingExportAlert = false
    @State private var favoriteIDs = Set(DemoData.turtles.filter { $0.isFavorite }.map { $0.id })

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $activeSection, favoriteCount: favoriteIDs.count)

            VStack(spacing: 0) {
                TopBar(
                    title: pageTitle,
                    subtitle: pageSubtitle,
                    searchText: $searchText,
                    onExport: { showingExportAlert = true },
                    onBack: backAction
                )

                ZStack {
                    AdaColors.canvas
                    pageView
                }
            }
        }
        .frame(minWidth: 1_080, minHeight: 700)
        .background(AdaColors.canvas)
        .alert("Export ready", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The demo report is ready to export when a data source is connected.")
        }
    }

    private var pageTitle: String {
        activeSection == .detail ? (selectedTurtle?.id ?? "Turtle #001") : activeSection.title
    }

    private var pageSubtitle: String? {
        if activeSection == .detail { return selectedTurtle?.species.rawValue }
        if activeSection == .map { return "last seen 30 days" }
        return nil
    }

    private var backAction: (() -> Void)? {
        activeSection == .detail ? { returnToIndividuals() } : nil
    }

    @ViewBuilder
    private var pageView: some View {
        switch activeSection {
        case .dashboard:
            DashboardView(chartMode: $chartMode)
        case .map:
            MapPageView(onSelect: showDetail)
        case .individuals:
            IndividualsView(
                searchText: $searchText,
                favoriteIDs: $favoriteIDs,
                onToggleFavorite: toggleFavorite,
                onSelect: showDetail
            )
        case .favorites:
            FavoritesView(
                searchText: $searchText,
                favoriteIDs: $favoriteIDs,
                onToggleFavorite: toggleFavorite,
                onSelect: showDetail
            )
        case .detail:
            TurtleDetailView(turtle: selectedTurtle ?? DemoData.turtles[0], onBack: returnToIndividuals)
        }
    }

    private func showDetail(_ turtle: Turtle) {
        selectedTurtle = turtle
        activeSection = .detail
    }

    private func toggleFavorite(_ turtle: Turtle) {
        if favoriteIDs.contains(turtle.id) {
            favoriteIDs.remove(turtle.id)
        } else {
            favoriteIDs.insert(turtle.id)
        }
    }

    private func returnToIndividuals() {
        selectedTurtle = nil
        activeSection = .individuals
    }
}

private struct SidebarView: View {
    @Binding var selection: AppSection
    let favoriteCount: Int

    private var highlightedSection: AppSection {
        selection == .detail ? .individuals : selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color(red: 0.98, green: 0.40, blue: 0.38)).frame(width: 14, height: 14)
                Circle().fill(Color(red: 1.00, green: 0.68, blue: 0.13)).frame(width: 14, height: 14)
                Circle().fill(Color(red: 0.11, green: 0.72, blue: 0.25)).frame(width: 14, height: 14)
            }
            .padding(.top, 15)
            .padding(.horizontal, 12)

            HStack(spacing: 14) {
                TurtleBrandMark(size: 36)

                Text("Sea Turtle Group")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
            }
            .padding(.horizontal, 16)
            .padding(.top, 19)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 3) {
                SidebarRow(section: .dashboard, selection: $selection)
                SidebarRow(section: .map, selection: $selection)

                HStack(spacing: 8) {
                    TurtleBrandMark(size: 20)
                    Text("Sea Turtle Group")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                .padding(.horizontal, 18)
                .padding(.top, 19)
                .padding(.bottom, 5)

                SidebarRow(section: .individuals, selection: $selection, count: DemoData.turtles.count, isHighlighted: highlightedSection == .individuals)
                SidebarRow(section: .favorites, selection: $selection, count: favoriteCount, isHighlighted: highlightedSection == .favorites)
            }

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Circle()
                    .fill(AdaColors.navy)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text("B").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bli Wayan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                    Text("Field researcher")
                        .font(.system(size: 10))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaColors.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 252)
        .background(AdaColors.sidebar)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    @Binding var selection: AppSection
    var count: Int?
    var isHighlighted: Bool?

    private var isSelected: Bool { isHighlighted ?? (selection == section) }

    var body: some View {
        Button { selection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 14)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
            }
            .foregroundStyle(AdaColors.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityLabel(section.title)
    }
}

private struct TopBar: View {
    let title: String
    let subtitle: String?
    @Binding var searchText: String
    let onExport: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .frame(width: 25, height: 25)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Back to Individuals")
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AdaColors.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.tertiaryInk)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.tertiaryInk)
                TextField("Search individuals", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 178)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.black.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Button(action: onExport) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                    Text("Export").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(AdaColors.navy)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(AdaColors.card)
    }
}

private struct DashboardView: View {
    @Binding var chartMode: String

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SightingsChartCard(chartMode: $chartMode)
                HStack(alignment: .top, spacing: 24) {
                    SpeciesFoundCard().frame(minWidth: 350, maxWidth: 510)
                    RecentSightingsCard().frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SightingsChartCard: View {
    @Binding var chartMode: String
    private let values: [CGFloat] = [64, 70, 59, 49, 55, 68, 83, 95, 88, 78, 91, 105]
    private let months = ["Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug"]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                SectionTitle("Sightings over time", subtitle: "Sightings · All species · last 12 months")
                Spacer()
                Menu {
                    Button("All species") {}
                    Button("Green turtle") {}
                    Button("Hawksbill") {}
                } label: {
                    HStack(spacing: 8) {
                        Text("All species")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 12)
                    .frame(height: 29)
                    .background(Color.black.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .menuStyle(.borderlessButton)

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
                                Text("Nov").font(.system(size: 10)).foregroundStyle(AdaColors.tertiaryInk)
                                Text("58 Sightings").font(.system(size: 12, weight: .semibold)).foregroundStyle(AdaColors.ink)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdaColors.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                            .offset(x: proxy.size.width * 0.15, y: 72)
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
        .adaCard(padding: 20)
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
                CGPoint(x: size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)), y: size.height - (value / 120 * size.height))
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
            context.stroke(line, with: .color(AdaColors.navy), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if points.count > 2 {
                let selected = points[2]
                context.fill(Path(ellipseIn: CGRect(x: selected.x - 6, y: selected.y - 6, width: 12, height: 12)), with: .color(AdaColors.card))
                context.stroke(Path(ellipseIn: CGRect(x: selected.x - 6, y: selected.y - 6, width: 12, height: 12)), with: .color(AdaColors.navySoft), lineWidth: 2)
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
                        Text(summary.species.rawValue).font(.system(size: 13)).foregroundStyle(AdaColors.ink)
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
                    if sighting.id != DemoData.sightings.last?.id { Divider().overlay(AdaColors.line) }
                }
            }
        }
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
                Text(sighting.turtleID).font(.system(size: 13)).foregroundStyle(AdaColors.ink)
                Text(sighting.location).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
            }
            Spacer()
            ConditionPill(condition: sighting.condition)
            Text(sighting.date)
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }
}

#Preview {
    ContentView()
}
