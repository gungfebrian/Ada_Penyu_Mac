import SwiftUI
import MapKit

struct MapPageView: View {
    let onSelect: (Turtle) -> Void

    @State private var selectedPeriod = "30 days"
    @State private var selectedSpecies: TurtleSpecies?
    @State private var selectedCondition: TurtleCondition?
    @State private var selectedSightingID: String?
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.72, longitude: 115.20),
        span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.24)
    )

    private var filteredSightings: [Sighting] {
        DemoData.sightings.filter { sighting in
            let matchesSpecies = selectedSpecies == nil || sighting.species == selectedSpecies
            let matchesCondition = selectedCondition == nil || sighting.condition == selectedCondition
            let matchesPeriod: Bool
            switch selectedPeriod {
            case "7 days": matchesPeriod = sighting.id == "sighting-1" || sighting.id == "sighting-2"
            case "This year", "All time": matchesPeriod = true
            default: matchesPeriod = true
            }
            return matchesSpecies && matchesCondition && matchesPeriod
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            mapCard

            MapFilterPanel(
                selectedPeriod: $selectedPeriod,
                selectedSpecies: $selectedSpecies,
                selectedCondition: $selectedCondition,
                selectedSightingID: $selectedSightingID,
                sightings: filteredSightings,
                onFocus: focus,
                onSelect: onSelect
            )
            .frame(width: 287)
        }
        .background(AdaColors.canvas)
        .onAppear { fitMapIfNeeded() }
        .onChange(of: filteredSightings.map(\.id)) { _, _ in
            fitMapIfNeeded()
        }
    }

    private var mapCard: some View {
        Map(position: $cameraPosition) {
            ForEach(filteredSightings) { sighting in
                Annotation(
                    sighting.location,
                    coordinate: CLLocationCoordinate2D(
                        latitude: sighting.coordinate.latitude,
                        longitude: sighting.coordinate.longitude
                    ),
                    anchor: .bottom
                ) {
                    Button {
                        focus(sighting)
                    } label: {
                        TurtleMapPin(isSelected: selectedSightingID == sighting.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(sighting.turtleID) on map")
                }
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topLeading) {
            Text("MAP OVERVIEW")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AdaColors.navy)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func focus(_ sighting: Sighting) {
        selectedSightingID = sighting.id
        let coordinate = CLLocationCoordinate2D(
            latitude: sighting.coordinate.latitude,
            longitude: sighting.coordinate.longitude
        )
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
                )
            )
        }
    }

    private func fitMapIfNeeded() {
        guard !filteredSightings.isEmpty else {
            cameraPosition = .region(Self.defaultRegion)
            selectedSightingID = nil
            return
        }

        if let selectedSightingID,
           filteredSightings.contains(where: { $0.id == selectedSightingID }) {
            return
        }

        selectedSightingID = nil
        let latitudes = filteredSightings.map { $0.coordinate.latitude }
        let longitudes = filteredSightings.map { $0.coordinate.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.6, 0.04),
            longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.6, 0.04)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct MapFilterPanel: View {
    @Binding var selectedPeriod: String
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?
    @Binding var selectedSightingID: String?
    let sightings: [Sighting]
    let onFocus: (Sighting) -> Void
    let onSelect: (Turtle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Spacer()
                Button("Reset") {
                    selectedPeriod = "30 days"
                    selectedSpecies = nil
                    selectedCondition = nil
                    selectedSightingID = nil
                }
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.navySoft)
                .buttonStyle(.plain)
            }

            MapFilterGroup(title: "Last seen") {
                HStack(spacing: 7) {
                    ForEach(["7 days", "30 days", "This year"], id: \.self) { period in
                        FilterChip(title: period, isSelected: selectedPeriod == period) {
                            selectedPeriod = period
                        }
                    }
                }
                FilterChip(title: "All time", isSelected: selectedPeriod == "All time") {
                    selectedPeriod = "All time"
                }
            }

            MapFilterGroup(title: "Species") {
                HStack(spacing: 7) {
                    FilterChip(title: "All", isSelected: selectedSpecies == nil) { selectedSpecies = nil }
                    FilterChip(title: "Green turtle", isSelected: selectedSpecies == .green) { selectedSpecies = .green }
                    FilterChip(title: "Hawksbill", isSelected: selectedSpecies == .hawksbill) { selectedSpecies = .hawksbill }
                }
                HStack(spacing: 7) {
                    FilterChip(title: "Olive Ridley", isSelected: selectedSpecies == .oliveRidley) { selectedSpecies = .oliveRidley }
                    FilterChip(title: "Loggerhead", isSelected: selectedSpecies == .loggerhead) { selectedSpecies = .loggerhead }
                }
                FilterChip(title: "Leatherback", isSelected: selectedSpecies == .leatherback) { selectedSpecies = .leatherback }
            }

            MapFilterGroup(title: "Condition") {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        FilterChip(title: "All", isSelected: selectedCondition == nil) { selectedCondition = nil }
                        FilterChip(title: "Healthy", isSelected: selectedCondition == .healthy) { selectedCondition = .healthy }
                    }
                    HStack(spacing: 7) {
                        FilterChip(title: "Scarred", isSelected: selectedCondition == .scarred) { selectedCondition = .scarred }
                        FilterChip(title: "Injured", isSelected: selectedCondition == .injured) { selectedCondition = .injured }
                    }
                }
            }

            HStack {
                Text("\(sightings.count) results")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.tertiaryInk)
                Spacer()
                Button("Export ↓") {}
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.navySoft)
                    .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sightings) { sighting in
                        Button {
                            onFocus(sighting)
                            if let turtle = DemoData.turtles.first(where: { $0.id == sighting.turtleID }) {
                                onSelect(turtle)
                            }
                        } label: {
                            MapResultCard(
                                sighting: sighting,
                                isSelected: selectedSightingID == sighting.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 17)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(AdaColors.canvas)
    }
}

private struct MapFilterGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
            content
        }
    }
}

private struct MapResultCard: View {
    let sighting: Sighting
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(sighting.condition.tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(sighting.turtleID)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AdaColors.ink)
                Text("\(sighting.species.rawValue) · \(sighting.date)")
                    .font(.system(size: 10))
                    .foregroundStyle(AdaColors.tertiaryInk)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AdaColors.tertiaryInk)
        }
        .padding(.trailing, 12)
        .frame(height: 56)
        .background(isSelected ? AdaColors.navy.opacity(0.08) : AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
