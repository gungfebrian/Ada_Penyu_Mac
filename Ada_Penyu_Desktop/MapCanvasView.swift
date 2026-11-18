import MapKit
import SwiftUI

struct MapPageView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case h3Grid = "H3 Grid"
        case pins = "Pins"
        var id: String { rawValue }
    }

    let turtles: [Turtle]
    let sightings: [Sighting]
    @Binding var selectedPeriod: MapPeriod
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?
    let onReload: () -> Void
    let onSelect: (Turtle) -> Void
    var focusTurtleID: String? = nil
    var onOpenSighting: ((Sighting) -> Void)? = nil

    @State private var displayMode: DisplayMode = .h3Grid
    @State private var selectedSightingID: String?
    @State private var selectedH3Index: UInt64?
    @State private var consumedFocusID: String?
    @State private var hasFittedInitial = false
    @State private var cameraPosition: MapCameraPosition = .region(MapSightingLayout.defaultRegion)
    @State private var visibleRegion = MapSightingLayout.defaultRegion
    @State private var debouncedRegion = MapSightingLayout.defaultRegion
    @State private var cameraDebounceTask: Task<Void, Never>?
    @State private var drilledCountryID: String?
    @State private var drilledRegion: MKCoordinateRegion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    private var activeLanguage: AppLanguage {
        locale.language.languageCode?.identifier == "id" ? .id : .en
    }

    private var selected: Sighting? { sightings.first { $0.id == selectedSightingID } }

    /// Active H3 resolution based on debounced zoom level (`nil` when zoomed in tightly enough for penyu pins).
    private var activeH3Resolution: Int? {
        guard displayMode == .h3Grid else { return nil }
        return H3SpatialIndex.resolution(for: debouncedRegion)
    }

    private var showsH3HexGrid: Bool {
        activeH3Resolution != nil && !sightings.isEmpty
    }

    private var h3Cells: [H3CellAggregate] {
        guard let res = activeH3Resolution else { return [] }
        let viewport = H3ViewportQuery(region: debouncedRegion, resolution: res, paddingFactor: 0.35)
        return H3SpatialIndex.aggregate(sightings: sightings, resolution: res, viewport: viewport)
    }

    private var selectedH3Cell: H3CellAggregate? {
        guard let selectedH3Index else { return nil }
        return h3Cells.first { $0.index == selectedH3Index }
    }

    private var uniqueTurtleTotal: Int {
        Set(sightings.map(\.turtleID)).count
    }

    private var resolvedCountryCount: Int {
        H3SpatialIndex.resolvedCountryCounts(for: sightings, language: activeLanguage)
            .filter { !$0.isoCode.isEmpty }
            .count
    }

    private var countryGroups: [MapSightingLayout.Country] { MapSightingLayout.countries(for: sightings) }
    private var drilledCountry: MapSightingLayout.Country? { countryGroups.first { $0.id == drilledCountryID } }
    private var showsCountries: Bool {
        displayMode == .pins && drilledCountry == nil && MapSightingLayout.showsCountryMarkers(in: debouncedRegion)
    }

    private var pinLocations: [MapSightingLayout.Location] {
        guard !showsH3HexGrid else { return [] }
        if let drilledCountry { return MapSightingLayout.locations(for: drilledCountry.sightings) }
        if showsCountries {
            let groupedIDs = Set(countryGroups.flatMap { $0.sightings.map(\.id) })
            return MapSightingLayout.locations(for: sightings.filter { !groupedIDs.contains($0.id) })
        }
        return MapSightingLayout.locations(for: sightings)
    }

    private var related: [Sighting] {
        guard let selected else { return [] }
        return sightings.filter { $0.turtleID == selected.turtleID }.sorted {
            let lhs = APIFormatters.display.date(from: $0.date) ?? .distantPast
            let rhs = APIFormatters.display.date(from: $1.date) ?? .distantPast
            return lhs > rhs
        }
    }

    private var selectedTurtleTrack: [CLLocationCoordinate2D] {
        related.reversed().map { .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            .filter { CLLocationCoordinate2DIsValid($0) }
    }

    var body: some View {
        MapReader { mapProxy in
            Map(position: $cameraPosition) {
                if showsH3HexGrid {
                    ForEach(h3Cells) { cell in
                        let isSelected = cell.index == selectedH3Index
                        MapPolygon(coordinates: cell.boundary)
                            .foregroundStyle(h3FillColor(for: cell, selected: isSelected))
                            .stroke(
                                isSelected ? Color.white : AdaColors.navy.opacity(0.68),
                                lineWidth: isSelected ? 2.5 : 1.25
                            )

                        Annotation(cell.countryDisplayName(for: activeLanguage), coordinate: cell.center, anchor: .center) {
                            Button {
                                if selectedH3Index == cell.index {
                                    zoomIntoCell(cell)
                                } else {
                                    selectedH3Index = cell.index
                                    selectedSightingID = nil
                                }
                            } label: {
                                H3CellBadge(
                                    cell: cell,
                                    countryLabel: cell.resolution <= 3 ? cell.countryDisplayName(for: activeLanguage) : nil,
                                    isSelected: isSelected
                                )
                            }
                            .buttonStyle(.plain)
                            .help("\(cell.countryDisplayName(for: activeLanguage)) · \(cell.uniqueTurtleCount) unique turtles · \(cell.sightingCount) sightings (H3 Res \(cell.resolution))")
                            .accessibilityLabel("\(cell.countryDisplayName(for: activeLanguage)), \(cell.uniqueTurtleCount) unique turtles, \(cell.sightingCount) sightings")
                            .accessibilityHint("Inspect this H3 cell or click again to zoom in")
                        }
                        .annotationTitles(.hidden)
                    }
                } else {
                    if !showsCountries, selectedTurtleTrack.count >= 2 {
                        MapPolyline(coordinates: selectedTurtleTrack)
                            .stroke(AdaColors.navy.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                    }

                    if showsCountries {
                        ForEach(countryGroups) { country in
                            Annotation(country.label, coordinate: country.anchor, anchor: .bottom) {
                                Button { zoomToCountry(country) } label: {
                                    MapCountryMarker(label: country.label, sightings: country.sightings.count)
                                }
                                .buttonStyle(.plain)
                                .help("Show \(country.turtleCount) turtles observed in \(country.label)")
                                .accessibilityLabel("\(country.label), \(country.sightings.count) loaded sightings")
                                .accessibilityHint("Zoom into this country")
                            }
                            .annotationTitles(.hidden)
                        }
                    }

                    ForEach(pinLocations) { location in
                        if let sighting = representative(for: location) {
                            Annotation(sighting.location, coordinate: location.mapCoordinate, anchor: .bottom) {
                                Button {
                                    selectedH3Index = nil
                                    selectedSightingID = sighting.id
                                } label: {
                                    TurtleMapPin(
                                        state: pinState(for: sighting),
                                        count: Set(location.sightings.map(\.turtleID)).count
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("\(sighting.displayName) · \(sighting.location)")
                                .accessibilityLabel("\(sighting.displayName), \(sighting.date), \(sighting.location)")
                                .accessibilityHint(location.sightings.count > 1 ? "Open sightings at this location" : "Open sighting overview")
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
            }
            .onTapGesture { screenPoint in
                guard showsH3HexGrid,
                      let res = activeH3Resolution,
                      let coord = mapProxy.convert(screenPoint, from: .local),
                      let tappedIndex = H3SpatialIndex.cell(for: coord, resolution: res) else {
                    return
                }
                if h3Cells.contains(where: { $0.index == tappedIndex }) {
                    selectedH3Index = tappedIndex
                    selectedSightingID = nil
                } else {
                    selectedH3Index = nil
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { context in
            let nextRegion = context.region
            let byUser = cameraPosition.positionedByUser
            visibleRegion = nextRegion
            cameraDebounceTask?.cancel()
            cameraDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { return }
                applySettledRegion(nextRegion, positionedByUser: byUser)
            }
        }
        .overlay(alignment: .topLeading) { controls.padding(18) }
        .overlay(alignment: .topTrailing) {
            if let cell = selectedH3Cell {
                h3Inspector(for: cell).padding(18)
            } else if let selected {
                inspector(for: selected).padding(18)
            }
        }
        .overlay(alignment: .bottomLeading) { legend.padding(18) }
        .overlay(alignment: .bottomTrailing) { zoomControls.padding(18) }
        .overlay {
            if sightings.isEmpty {
                ContentUnavailableView {
                    Label("No sightings in this range", systemImage: "map")
                } description: {
                    Text("Try All Time or clear filters.")
                } actions: {
                    Button("Reload map", action: onReload).buttonStyle(AdaPillButtonStyle())
                }
                .frame(width: 320, height: 170)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .onAppear(perform: updateSightings)
        .onDisappear { cameraDebounceTask?.cancel() }
        .onChange(of: sightings) { _, _ in updateSightings() }
        .onChange(of: focusTurtleID) { _, _ in
            consumedFocusID = nil
            updateSightings()
        }
        .onChange(of: displayMode) { _, newMode in
            if newMode == .pins {
                selectedH3Index = nil
            } else {
                if activeH3Resolution != nil {
                    selectedSightingID = nil
                }
            }
        }
    }

    private func applySettledRegion(_ region: MKCoordinateRegion, positionedByUser: Bool) {
        let previousResolution = activeH3Resolution
        let previouslyShowingCountries = showsCountries
        debouncedRegion = region

        if activeH3Resolution != previousResolution {
            selectedH3Index = nil
        }
        if activeH3Resolution != nil {
            selectedSightingID = nil
        }

        if positionedByUser {
            returnToCountriesIfZoomedOut(region)
            if !previouslyShowingCountries, showsCountries { selectedSightingID = nil }
        } else if drilledCountry != nil {
            drilledRegion = drilledRegion.map {
                MKCoordinateRegion(center: $0.center, span: .init(
                    latitudeDelta: max($0.span.latitudeDelta, region.span.latitudeDelta),
                    longitudeDelta: max($0.span.longitudeDelta, region.span.longitudeDelta)
                ))
            }
        }
    }

    private func h3FillColor(for cell: H3CellAggregate, selected: Bool) -> Color {
        if selected {
            return AdaColors.navy.opacity(0.64)
        }
        return AdaColors.navy.opacity(0.18 + 0.40 * cell.densityRatio)
    }

    // MARK: - Top-Left Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Where turtles were observed")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Spacer(minLength: 4)
                    if let res = activeH3Resolution {
                        Text("H3 R\(res)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(AdaColors.navy, in: Capsule())
                    }
                }
                Text(mapDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(2)
            }
            .frame(width: 318, alignment: .leading)
            .adaCard(padding: 15, radius: 16)
            .shadow(color: AdaColors.navy.opacity(0.08), radius: 10, y: 3)

            HStack(spacing: 8) {
                modeToggle

                if selectedH3Index != nil || selectedSightingID != nil {
                    Button("Clear") {
                        selectedH3Index = nil
                        selectedSightingID = nil
                    }
                    .buttonStyle(AdaPillButtonStyle())
                } else if drilledCountry != nil {
                    Button("All countries", action: fitAll)
                        .buttonStyle(AdaPillButtonStyle())
                }

                ConditionPicker(selection: $selectedCondition)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(DisplayMode.allCases) { mode in
                let active = displayMode == mode
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        displayMode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .h3Grid ? "hexagon.fill" : "mappin.and.ellipse")
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                    }
                    .foregroundStyle(active ? .white : AdaColors.ink)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(active ? AdaColors.navy : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AdaColors.card, in: Capsule())
        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 5, y: 1.5)
    }

    private var mapDescription: String {
        if let cell = selectedH3Cell {
            return "\(cell.countryDisplayName(for: activeLanguage)) · \(cell.uniqueTurtleCount) unique turtles · \(cell.sightingCount) sightings"
        }
        if let selected { return "\(selected.displayName) · \(selected.date) · \(related.count) linked sightings" }
        if let res = activeH3Resolution {
            return "H3 hex aggregation (Res \(res)) · Tap any hexagon to inspect or zoom in."
        }
        if let drilledCountry { return "\(drilledCountry.label) · \(drilledCountry.sightings.count) loaded sightings" }
        return showsCountries ? "Select a country to see individual sightings." : "Detailed reef markers · Select a penyu pin to trace resightings."
    }

    // MARK: - Bottom-Right Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: 5) {
            Button(action: fitAll) {
                Label("Fit all", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    .padding(.horizontal, 8).frame(height: 34)
            }
            .help("Fit all loaded sightings")

            Divider().frame(height: 18)

            Button { zoom(by: 2) } label: {
                Image(systemName: "minus").frame(width: 34, height: 34)
            }
            .accessibilityLabel("Zoom out")
            .help("Zoom out")

            Button { zoom(by: 0.5) } label: {
                Image(systemName: "plus").frame(width: 34, height: 34)
            }
            .accessibilityLabel("Zoom in")
            .help("Zoom in")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(AdaColors.ink)
        .buttonStyle(.plain)
        .padding(4)
        .background(AdaColors.card, in: Capsule())
        .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
    }

    // MARK: - Interactive H3 Cell Inspector

    private func h3Inspector(for cell: H3CellAggregate) -> some View {
        let countryTitle = cell.countryDisplayName(for: activeLanguage)
        let maxSpeciesCount = max(1, cell.speciesBreakdown.first?.sightingCount ?? 1)
        let sampleSightings = Array(cell.sightings.prefix(4))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(countryTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        if let iso = cell.countryMatch?.isoCode, !iso.isEmpty {
                            Text(iso)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdaColors.navy)
                                .padding(.horizontal, 6)
                                .frame(height: 19)
                                .background(AdaColors.canvas, in: Capsule())
                                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                        }
                    }

                    HStack(spacing: 6) {
                        Text("H3 Res \(cell.resolution)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AdaColors.navy)
                        Text("·")
                            .foregroundStyle(AdaColors.secondaryInk)
                        Text(cell.hexID)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .textSelection(.enabled)
                    }

                    if let match = cell.countryMatch {
                        Text(match.isOffshore ? "Offshore waters · \(Int(match.distanceKm.rounded())) km from coast" : "Coastal waters · GPS resolved offline")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AdaColors.secondaryInk)
                    } else {
                        Text("International waters · GPS resolved offline")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                }

                Spacer(minLength: 4)

                Button { selectedH3Index = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(AdaColors.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close H3 cell inspector")
            }

            // Explicit distinction: Unique Turtles vs Total Sightings
            HStack(spacing: 10) {
                metricTile(
                    title: "Unique turtles",
                    value: "\(cell.uniqueTurtleCount)",
                    accent: true
                )
                metricTile(
                    title: "Total sightings",
                    value: "\(cell.sightingCount)",
                    accent: false
                )
            }

            if !cell.speciesBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Species observed")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)

                    ForEach(cell.speciesBreakdown) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                SpeciesLabel(species: row.species)
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                                Text("\(row.uniqueTurtleCount) indiv · \(row.sightingCount) sight.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(AdaColors.secondaryInk)
                            }
                            GeometryReader { bar in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(AdaColors.canvas)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(AdaColors.navy)
                                            .frame(width: max(8, bar.size.width * CGFloat(row.sightingCount) / CGFloat(maxSpeciesCount)))
                                    }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }

            if !sampleSightings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Encounters in cell")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)

                    ForEach(sampleSightings) { item in
                        Button {
                            selectedH3Index = nil
                            focus(item)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.condition.tint)
                                    .frame(width: 7, height: 7)
                                Text(item.displayName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(AdaColors.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(item.location)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(AdaColors.secondaryInk)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                zoomIntoCell(cell)
            } label: {
                HStack(spacing: 6) {
                    Text(cell.resolution >= 6 ? "Show individual markers" : "Zoom into cell")
                    Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AdaPillButtonStyle())
        }
        .foregroundStyle(AdaColors.ink)
        .padding(18)
        .frame(width: 318)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
        .shadow(color: AdaColors.navy.opacity(0.14), radius: 16, y: 6)
    }

    private func metricTile(title: String, value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(accent ? .white.opacity(0.78) : AdaColors.secondaryInk)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(accent ? .white : AdaColors.ink)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent ? AdaColors.navy : AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Individual Sighting Inspector

    private func inspector(for sighting: Sighting) -> some View {
        let turtle = turtles.first { $0.id == sighting.turtleID } ?? sighting.turtleReference
        let otherTurtlesHere = sightings.filter { $0.coordinate == sighting.coordinate && $0.turtleID != sighting.turtleID }
        let resolvedCountry = FrontendCountryResolver.shared.resolve(
            latitude: sighting.coordinate.latitude,
            longitude: sighting.coordinate.longitude
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sighting Overview").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { selectedSightingID = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(AdaColors.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selected sighting")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !turtle.identityPhotoPaths.isEmpty {
                        TurtlePhoto(paths: turtle.identityPhotoPaths, size: 268)
                            .frame(height: 112)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Profile reference photo of \(turtle.displayName)")
                    }
                    Text(turtle.displayName).font(.system(size: 20, weight: .semibold))
                    SpeciesLabel(species: sighting.species).font(.system(size: 12))
                    if let profile = turtle.profileCode { fact("Turtle ID", profile) }

                    Divider()
                    fact("Date", sighting.date)
                    fact("Location", sighting.location)
                    if let resolvedCountry {
                        let suffix = resolvedCountry.isOffshore
                            ? " · Offshore (\(Int(resolvedCountry.distanceKm.rounded())) km)"
                            : ""
                        fact("Country (from GPS)", "\(resolvedCountry.localizedName(for: activeLanguage))\(suffix)")
                    }
                    fact("Condition at this sighting", sighting.condition.rawValue)

                    if related.count > 1 {
                        Text("Linked sightings").font(.system(size: 12, weight: .semibold))
                        ForEach(related) { item in
                            encounterButton(item, selected: item.id == sighting.id, showsName: false)
                        }
                    }

                    if !otherTurtlesHere.isEmpty {
                        Text("Other turtles at this location").font(.system(size: 12, weight: .semibold))
                        ForEach(otherTurtlesHere) { item in
                            encounterButton(item, selected: false, showsName: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 330)

            if let onOpenSighting {
                Button { onOpenSighting(sighting) } label: {
                    Text("View sighting details").frame(maxWidth: .infinity)
                }
                .buttonStyle(AdaPillButtonStyle())
            }

            Button { onSelect(turtle) } label: {
                Text("Open turtle profile").frame(maxWidth: .infinity)
            }
            .buttonStyle(AdaPillButtonStyle(secondary: onOpenSighting != nil))
        }
        .foregroundStyle(AdaColors.ink)
        .padding(18)
        .frame(width: 304)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }

    private func encounterButton(_ sighting: Sighting, selected: Bool, showsName: Bool) -> some View {
        Button { focus(sighting) } label: {
            HStack(spacing: 8) {
                Text(showsName ? sighting.displayName : sighting.date)
                    .fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: 12)
                Text(showsName ? sighting.date : sighting.location).lineLimit(1)
            }
            .font(.system(size: 11))
            .padding(8)
            .background(selected ? AdaColors.canvas : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
            Text(value).font(.system(size: 12))
        }
    }

    // MARK: - Bottom-Left Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let res = activeH3Resolution, showsH3HexGrid {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "hexagon.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AdaColors.navy)
                        Text("H3 Res \(res) (\(H3SpatialIndex.nominalScaleLabel(for: res)))")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                    }
                    HStack(spacing: 3) {
                        Text("Low").font(.system(size: 9.5)).foregroundStyle(AdaColors.secondaryInk)
                        ForEach([0.22, 0.36, 0.50, 0.64], id: \.self) { alpha in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AdaColors.navy.opacity(alpha))
                                .frame(width: 11, height: 8)
                        }
                        Text("High").font(.system(size: 9.5)).foregroundStyle(AdaColors.secondaryInk)
                    }
                }
            } else if showsCountries {
                legendItem("Country · loaded sightings", fill: AdaColors.navy)
            } else {
                HStack(spacing: 18) {
                    legendItem("Selected sighting", fill: AdaColors.navy)
                    legendItem("Same turtle", fill: AdaColors.secondaryInk)
                    legendItem("Other turtles", fill: .white)
                }
            }

            HStack(spacing: 6) {
                Text("\(uniqueTurtleTotal.formatted()) unique turtles · \(sightings.count.formatted()) sightings")
                if resolvedCountryCount > 0 {
                    Text("· \(resolvedCountryCount) \(resolvedCountryCount == 1 ? "country" : "countries")")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(AdaColors.secondaryInk)
        }
        .adaCard(padding: 12, radius: 13)
        .shadow(color: AdaColors.navy.opacity(0.06), radius: 8, y: 2)
    }

    private func legendItem(_ title: String, fill: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(AdaColors.secondaryInk, lineWidth: 0.75))
                .frame(width: 9, height: 9)
            Text(title).font(.system(size: 10.5))
        }
        .foregroundStyle(AdaColors.secondaryInk)
    }

    // MARK: - Helpers & Camera Navigation

    private func representative(for location: MapSightingLayout.Location) -> Sighting? {
        location.sightings.first { $0.id == selectedSightingID }
            ?? location.sightings.first { $0.turtleID == selected?.turtleID }
            ?? location.sightings.first
    }

    private func pinState(for sighting: Sighting) -> TurtleMapPin.PinState {
        if sighting.id == selectedSightingID { return .selected }
        return sighting.turtleID == selected?.turtleID ? .linked : .other
    }

    private func updateSightings() {
        if selected == nil { selectedSightingID = nil }
        if drilledCountry == nil { clearDrillDown() }
        if let focusTurtleID, consumedFocusID != focusTurtleID,
           let record = sightings.first(where: { $0.turtleID == focusTurtleID }) {
            consumedFocusID = focusTurtleID
            hasFittedInitial = true
            focus(record)
        } else if !hasFittedInitial, !sightings.isEmpty {
            hasFittedInitial = true
            fitAll()
        }
    }

    private func focus(_ sighting: Sighting) {
        selectedH3Index = nil
        selectedSightingID = sighting.id
        if let drilledCountry, !drilledCountry.sightings.contains(where: { $0.id == sighting.id }) {
            clearDrillDown()
        }
        move(to: MKCoordinateRegion(
            center: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude),
            span: .init(latitudeDelta: min(visibleRegion.span.latitudeDelta, 0.28),
                        longitudeDelta: min(visibleRegion.span.longitudeDelta, 0.42))
        ))
    }

    private func zoomIntoCell(_ cell: H3CellAggregate) {
        selectedH3Index = nil
        selectedSightingID = nil
        move(to: cell.drillInRegion)
    }

    private func zoomToCountry(_ country: MapSightingLayout.Country) {
        selectedSightingID = nil
        selectedH3Index = nil
        drilledCountryID = country.id
        drilledRegion = country.region
        move(to: country.region)
    }

    private func zoom(by factor: Double) {
        let span = visibleRegion.span
        let target = MKCoordinateRegion(
            center: visibleRegion.center,
            span: .init(latitudeDelta: min(170, max(0.005, span.latitudeDelta * factor)),
                        longitudeDelta: min(360, max(0.005, span.longitudeDelta * factor)))
        )
        if factor > 1 {
            returnToCountriesIfZoomedOut(target)
            if drilledCountry == nil, MapSightingLayout.showsCountryMarkers(in: target) {
                selectedSightingID = nil
            }
        }
        move(to: target)
    }

    private func returnToCountriesIfZoomedOut(_ region: MKCoordinateRegion) {
        guard let drilledRegion, MapSightingLayout.showsCountryMarkers(in: region) else { return }
        if region.span.latitudeDelta > drilledRegion.span.latitudeDelta * 1.30
            || region.span.longitudeDelta > drilledRegion.span.longitudeDelta * 1.30 {
            clearDrillDown()
            selectedSightingID = nil
        }
    }

    private func clearDrillDown() {
        drilledCountryID = nil
        drilledRegion = nil
    }

    private func fitAll() {
        clearDrillDown()
        selectedSightingID = nil
        selectedH3Index = nil
        move(to: MapSightingLayout.region(containing: sightings))
    }

    private func move(to region: MKCoordinateRegion) {
        cameraDebounceTask?.cancel()
        visibleRegion = region
        debouncedRegion = region
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            cameraPosition = .region(region)
        }
    }
}

private struct H3CellBadge: View {
    let cell: H3CellAggregate
    let countryLabel: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let countryLabel {
                Text(countryLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : AdaColors.navy)
                    .lineLimit(1)
            } else {
                Image("AdaPenyuMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(isSelected ? .white : AdaColors.navy)
            }

            Text("\(cell.uniqueTurtleCount)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(isSelected ? AdaColors.navy : .white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20)
                .frame(height: 18)
                .background(isSelected ? .white : AdaColors.navy, in: Capsule())

            if cell.sightingCount > cell.uniqueTurtleCount {
                Text("(\(cell.sightingCount))")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : AdaColors.secondaryInk)
            }
        }
        .padding(.leading, countryLabel == nil ? 6 : 8)
        .padding(.trailing, 5)
        .frame(height: 26)
        .background(isSelected ? AdaColors.navy : AdaColors.card, in: Capsule())
        .overlay(
            Capsule().stroke(isSelected ? Color.white : AdaColors.navy.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: AdaColors.navy.opacity(isSelected ? 0.30 : 0.16), radius: isSelected ? 8 : 4, y: 2)
        .contentShape(Capsule())
    }
}

private struct MapCountryMarker: View {
    let label: String
    let sightings: Int

    var body: some View {
        VStack(spacing: 4) {
            TurtleMapPin(state: .selected, count: sightings)
                .scaleEffect(0.88, anchor: .bottom)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AdaColors.navy)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(AdaColors.card, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 1.5)
        }
        .contentShape(Rectangle())
    }
}
