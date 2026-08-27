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
    @State private var selectedSightingID: String?
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static let defaultRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -8.72, longitude: 115.20), span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.24))

    var body: some View {
        HStack(spacing: 0) {
            mapCard
            MapFilterPanel(selectedPeriod: $selectedPeriod, selectedSpecies: $selectedSpecies, selectedCondition: $selectedCondition, selectedSightingID: $selectedSightingID, sightings: sightings, onFocus: focus, onOpen: open)
                .frame(width: AdaLayout.mapFilterWidth)
        }
        .background(AdaColors.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { fitMap() }
        .onChange(of: selectedPeriod) { _, _ in onReload() }
        .onChange(of: selectedSpecies) { _, _ in onReload() }
        .onChange(of: selectedCondition) { _, _ in onReload() }
        .onChange(of: sightings.map(\.id)) { _, _ in fitMap() }
    }

    private var mapCard: some View {
        Map(position: $cameraPosition) {
            ForEach(sightings) { sighting in
                Annotation(sighting.location, coordinate: CLLocationCoordinate2D(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude), anchor: .bottom) {
                    Button { focus(sighting) } label: { TurtleMapPin(isSelected: selectedSightingID == sighting.id) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Focus \(sighting.turtleID)")
                }
            }
        }
        .mapStyle(.standard)
        .mapControls { MapCompass(); MapScaleView() }
        .overlay {
            if sightings.isEmpty { EmptyMapState() }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: AdaLayout.containerRadius, style: .continuous))
    }

    private func focus(_ sighting: Sighting) {
        selectedSightingID = sighting.id
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude), span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)))
        }
    }

    private func open(_ sighting: Sighting) {
        guard let turtle = turtles.first(where: { $0.id == sighting.turtleID }) ?? DemoFixtures.turtles.first(where: { $0.id == sighting.turtleID }) else { return }
        onSelect(turtle)
    }

    private func fitMap() {
        guard !sightings.isEmpty else { cameraPosition = .region(Self.defaultRegion); selectedSightingID = nil; return }
        let latitudes = sightings.map { $0.coordinate.latitude }
        let longitudes = sightings.map { $0.coordinate.longitude }
        let center = CLLocationCoordinate2D(latitude: (latitudes.min()! + latitudes.max()!) / 2, longitude: (longitudes.min()! + longitudes.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.8, 0.04),
            longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.8, 0.04)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct EmptyMapState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "map").font(.system(size: 28)).foregroundStyle(AdaColors.tertiaryInk)
            Text("No sightings in this range").font(.system(size: 14, weight: .medium)).foregroundStyle(AdaColors.ink)
            Text("Try a wider time window.").font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MapFilterPanel: View {
    @Binding var selectedPeriod: MapPeriod
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?
    @Binding var selectedSightingID: String?
    let sightings: [Sighting]
    let onFocus: (Sighting) -> Void
    let onOpen: (Sighting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filters").font(.system(size: 14, weight: .semibold)).foregroundStyle(AdaColors.ink)
                Spacer()
                Button("Reset") { selectedPeriod = .thirtyDays; selectedSpecies = nil; selectedCondition = nil; selectedSightingID = nil }.font(.system(size: 11)).foregroundStyle(AdaColors.navySoft).buttonStyle(.plain)
            }
            MapFilterGroup(title: "Last seen") {
                ChipFlowLayout(spacing: 7) {
                    ForEach(MapPeriod.allCases) { period in FilterChip(title: period.rawValue, isSelected: selectedPeriod == period, horizontalPadding: 10, unselectedBackground: AdaColors.canvas) { selectedPeriod = period } }
                }
            }
            MapFilterGroup(title: "Species") {
                ChipFlowLayout(spacing: 7) {
                    FilterChip(title: "All", isSelected: selectedSpecies == nil, horizontalPadding: 10, unselectedBackground: AdaColors.canvas) { selectedSpecies = nil }
                    ForEach(TurtleSpecies.allCases) { species in
                        FilterChip(title: species.rawValue, isSelected: selectedSpecies == species, horizontalPadding: 10, unselectedBackground: AdaColors.canvas) { selectedSpecies = species }
                    }
                }
            }
            MapFilterGroup(title: "Condition") {
                ChipFlowLayout(spacing: 7) {
                    FilterChip(title: "All", isSelected: selectedCondition == nil, horizontalPadding: 10, unselectedBackground: AdaColors.canvas) { selectedCondition = nil }
                    ForEach(TurtleCondition.allCases) { condition in
                        FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition, horizontalPadding: 10, unselectedBackground: AdaColors.canvas) { selectedCondition = condition }
                    }
                }
            }
            HStack {
                Text("\(sightings.count) results")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.tertiaryInk)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sightings) { sighting in
                        Button { onOpen(sighting) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(sighting.condition.tint).frame(width: 4, height: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sighting.turtleID).font(.system(size: 13, weight: .medium)).foregroundStyle(AdaColors.ink)
                                    Text("\(sighting.species.rawValue) · \(sighting.date)").font(.system(size: 10)).foregroundStyle(AdaColors.tertiaryInk)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(height: 56)
                        .background(AdaColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .background(AdaColors.card)
    }
}

private struct MapFilterGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk); content } }
}

private struct ChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + (x == 0 ? 0 : spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
