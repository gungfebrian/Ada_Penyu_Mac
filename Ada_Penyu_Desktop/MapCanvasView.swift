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
    @State private var selectedSightingID: String?
    @State private var consumedFocusID: String?
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let defaultRegion = MKCoordinateRegion(center: .init(latitude: -8.72, longitude: 115.20), span: .init(latitudeDelta: 0.24, longitudeDelta: 0.24))
    private var selected: Sighting? { sightings.first { $0.id == selectedSightingID } }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(sightings) { sighting in
                Annotation(sighting.location, coordinate: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude), anchor: .bottom) {
                    Button { focus(sighting) } label: {
                        TurtleMapPin(isSelected: selectedSightingID == sighting.id)
                            .opacity(selected == nil || selected?.turtleID == sighting.turtleID ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(sighting.displayName), \(sighting.date), \(sighting.location)")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where turtles were observed").font(.system(size: 18, weight: .semibold))
                    Text("Select a sighting to highlight the same turtle").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(20).frame(width: 380, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                HStack(spacing: 8) {
                    Text(selected.map { $0.displayName } ?? "All sightings").font(.system(size: 11))
                        .padding(.horizontal, 15).frame(height: 30).foregroundStyle(.white).background(AdaColors.navy, in: Capsule())
                    ConditionPicker(selection: $selectedCondition)
                }
            }.padding(20)
        }
        .overlay(alignment: .topTrailing) {
            if let selected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selected.displayName).font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Button { selectedSightingID = nil; fitMap() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Clear selected sighting")
                    }
                    SpeciesLabel(species: selected.species).font(.system(size: 12))
                    Text("\(selected.date) · \(selected.location)").font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
                    Button("Open turtle profile →") { onSelect(turtles.first { $0.id == selected.turtleID } ?? selected.turtleReference) }
                        .buttonStyle(AdaPillButtonStyle())
                    Divider()
                    Text("Same turtle · loaded sightings").font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
                    ForEach(sightings.filter { $0.turtleID == selected.turtleID }.prefix(6)) { sighting in
                        Button { focus(sighting) } label: {
                            HStack { Text(sighting.date); Spacer(); Text(sighting.location).lineLimit(1) }
                                .font(.system(size: 11)).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(20).frame(width: 270).background(.white, in: RoundedRectangle(cornerRadius: 20)).padding(20)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 18) {
                legend("Selected sighting", color: AdaColors.navy)
                legend("Same turtle", color: AdaColors.secondaryInk)
                legend("Other turtles", color: .gray.opacity(0.3))
                Text("\(sightings.count) loaded").font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)).padding(20)
        }
        .overlay {
            if sightings.isEmpty {
                ContentUnavailableView("No sightings in this range", systemImage: "map", description: Text("Try a wider time window or clear a filter."))
                    .frame(width: 340, height: 180).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20).padding(.bottom, 20)
        .onAppear { fitMap() }
        .onChange(of: sightings.map(\.id)) { _, _ in fitMap() }
        .onChange(of: focusTurtleID) { _, _ in fitMap() }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 7) { Circle().fill(color).frame(width: 9, height: 9); Text(title).font(.system(size: 10)) }
            .foregroundStyle(AdaColors.secondaryInk)
    }

    private func focus(_ sighting: Sighting) {
        selectedSightingID = sighting.id
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            cameraPosition = .region(.init(center: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude), span: .init(latitudeDelta: 0.06, longitudeDelta: 0.06)))
        }
    }

    private func fitMap() {
        if let focusTurtleID, consumedFocusID != focusTurtleID,
           let record = sightings.first(where: { $0.turtleID == focusTurtleID }) {
            consumedFocusID = focusTurtleID
            focus(record)
            return
        }
        if !sightings.contains(where: { $0.id == selectedSightingID }) { selectedSightingID = nil }
        guard let minLat = sightings.map(\.coordinate.latitude).min(), let maxLat = sightings.map(\.coordinate.latitude).max(),
              let minLon = sightings.map(\.coordinate.longitude).min(), let maxLon = sightings.map(\.coordinate.longitude).max() else {
            cameraPosition = .region(Self.defaultRegion); return
        }
        cameraPosition = .region(.init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max((maxLat - minLat) * 1.6, 0.05), longitudeDelta: max((maxLon - minLon) * 1.6, 0.05))))
    }
}
