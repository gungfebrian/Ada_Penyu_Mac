import MapKit
import SwiftUI

struct MapPageView: View {
    let turtles: [Turtle]
    let sightings: [Sighting]
    @Binding var selectedPeriod: MapPeriod
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?
    let onReload: () -> Void
    let onSelect: (Turtle) -> Void
    var focusTurtleID: String? = nil
    var onOpenSighting: ((Sighting) -> Void)? = nil

    @State private var selectedSightingID: String?
    @State private var consumedFocusID: String?
    @State private var hasFittedInitial = false
    @State private var cameraPosition: MapCameraPosition = .region(MapSightingLayout.defaultRegion)
    @State private var visibleRegion = MapSightingLayout.defaultRegion
    @State private var drilledCountryID: String?
    @State private var drilledRegion: MKCoordinateRegion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: Sighting? { sightings.first { $0.id == selectedSightingID } }

    private var countryGroups: [MapSightingLayout.Country] { MapSightingLayout.countries(for: sightings) }
    private var drilledCountry: MapSightingLayout.Country? { countryGroups.first { $0.id == drilledCountryID } }
    private var showsCountries: Bool { drilledCountry == nil && MapSightingLayout.showsCountryMarkers(in: visibleRegion) }

    private var pinLocations: [MapSightingLayout.Location] {
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
        Map(position: $cameraPosition) {
            if !showsCountries, selectedTurtleTrack.count >= 2 {
                MapPolyline(coordinates: selectedTurtleTrack)
                    .stroke(AdaColors.navy.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
            }

            if showsCountries {
                ForEach(countryGroups) { country in
                    Annotation(country.label, coordinate: country.anchor, anchor: .center) {
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
                        Button { selectedSightingID = sighting.id } label: {
                            FigCraftSightingPin(
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
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { context in
            let previouslyShowingCountries = showsCountries
            visibleRegion = context.region
            if cameraPosition.positionedByUser {
                returnToCountriesIfZoomedOut(context.region)
                if !previouslyShowingCountries, showsCountries { selectedSightingID = nil }
            } else if drilledCountry != nil {
                // MapKit may widen the requested region to fit the window.
                drilledRegion = drilledRegion.map {
                    MKCoordinateRegion(center: $0.center, span: .init(
                        latitudeDelta: max($0.span.latitudeDelta, context.region.span.latitudeDelta),
                        longitudeDelta: max($0.span.longitudeDelta, context.region.span.longitudeDelta)
                    ))
                }
            }
        }
        .overlay(alignment: .topLeading) { controls.padding(18) }
        .overlay(alignment: .topTrailing) {
            if let selected { inspector(for: selected).padding(18) }
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
        .onChange(of: sightings) { _, _ in updateSightings() }
        .onChange(of: focusTurtleID) { _, _ in
            consumedFocusID = nil
            updateSightings()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Where turtles were observed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text(mapDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(2)
            }
            .frame(width: 308, alignment: .leading)
            .adaCard(padding: 16, radius: 16)

            HStack(spacing: 8) {
                if selectedSightingID != nil {
                    Button("Clear selection") { selectedSightingID = nil }
                        .buttonStyle(AdaPillButtonStyle())
                } else if drilledCountry != nil {
                    Button("All countries", action: fitAll)
                        .buttonStyle(AdaPillButtonStyle())
                } else {
                    Text("All sightings")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(AdaColors.navy, in: Capsule())
                }

                ConditionPicker(selection: $selectedCondition)
            }
        }
    }

    private var mapDescription: String {
        if let selected { return "\(selected.displayName) · \(selected.date) · \(related.count) linked sightings" }
        if let drilledCountry { return "\(drilledCountry.label) · \(drilledCountry.sightings.count) loaded sightings" }
        return showsCountries ? "Select a country to see individual sightings." : "Select a sighting to highlight the same turtle."
    }

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

    private func inspector(for sighting: Sighting) -> some View {
        let turtle = turtles.first { $0.id == sighting.turtleID } ?? sighting.turtleReference
        let otherTurtlesHere = sightings.filter { $0.coordinate == sighting.coordinate && $0.turtleID != sighting.turtleID }

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

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsCountries {
                legendItem("Country · loaded sightings", fill: AdaColors.navy)
            } else {
                HStack(spacing: 18) {
                    legendItem("Selected sighting", fill: AdaColors.navy)
                    legendItem("Same turtle", fill: AdaColors.secondaryInk)
                    legendItem("Other turtles", fill: .white)
                }
            }
            Text("\(sightings.count.formatted()) loaded sightings")
                .font(.system(size: 10))
                .foregroundStyle(AdaColors.secondaryInk)
        }
        .adaCard(padding: 12, radius: 13)
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

    private func representative(for location: MapSightingLayout.Location) -> Sighting? {
        location.sightings.first { $0.id == selectedSightingID }
            ?? location.sightings.first { $0.turtleID == selected?.turtleID }
            ?? location.sightings.first
    }

    private func pinState(for sighting: Sighting) -> FigCraftSightingPin.State {
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
        } else if !hasFittedInitial, !pinLocations.isEmpty || !countryGroups.isEmpty {
            hasFittedInitial = true
            fitAll()
        }
    }

    private func focus(_ sighting: Sighting) {
        selectedSightingID = sighting.id
        if let drilledCountry, !drilledCountry.sightings.contains(where: { $0.id == sighting.id }) {
            clearDrillDown()
        }
        move(to: MKCoordinateRegion(
            center: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude),
            span: .init(latitudeDelta: min(visibleRegion.span.latitudeDelta, 0.35),
                        longitudeDelta: min(visibleRegion.span.longitudeDelta, 0.55))
        ))
    }

    private func zoomToCountry(_ country: MapSightingLayout.Country) {
        selectedSightingID = nil
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
        move(to: MapSightingLayout.region(containing: sightings))
    }

    private func move(to region: MKCoordinateRegion) {
        visibleRegion = region
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            cameraPosition = .region(region)
        }
    }
}

private struct FigCraftSightingPin: View {
    enum State { case selected, linked, other }
    let state: State
    let count: Int

    private var fill: Color {
        switch state {
        case .selected: AdaColors.navy
        case .linked: AdaColors.secondaryInk
        case .other: .white
        }
    }

    var body: some View {
        VStack(spacing: -4) {
            Circle()
                .fill(fill)
                .frame(width: 39, height: 39)
                .overlay {
                    Image("TurtleMapPinIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 23, height: 23)
                        .foregroundStyle(state == .other ? AdaColors.navy : .white)
                }
                .overlay(alignment: .topTrailing) {
                    if count > 1 {
                        Text(count.formatted()).font(.system(size: 9, weight: .semibold))
                            .padding(3)
                            .background(AdaColors.canvas, in: Circle())
                            .foregroundStyle(AdaColors.navy)
                            .offset(x: 4, y: -4)
                    }
                }

            PinPointerTriangle()
                .fill(fill)
                .frame(width: 18, height: 13)
        }
        .frame(width: 46)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
    }
}

private struct MapCountryMarker: View {
    let label: String
    let sightings: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(sightings.formatted())
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(minWidth: 24, minHeight: 24)
                .background(AdaColors.navy, in: Capsule())
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaColors.navy)
                .lineLimit(1)
                .padding(.trailing, 6)
        }
        .padding(4)
        .frame(minHeight: 34)
        .background(AdaColors.card, in: Capsule())
        .contentShape(Capsule())
        .shadow(color: .black.opacity(0.19), radius: 5, y: 2)
    }
}
