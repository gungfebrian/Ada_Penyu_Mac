import MapKit
import SwiftUI

private struct MapSightingCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let sightings: [Sighting]
    let spanLatitudeDelta: Double
    let spanLongitudeDelta: Double

    var uniqueTurtleCount: Int {
        Set(sightings.map(\.turtleID)).count
    }

    var primaryLabel: String {
        let firstLoc = sightings.first?.location ?? "Region"
        let parts = firstLoc.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.last ?? firstLoc
    }
}

private enum MapAnnotationNode: Identifiable {
    case single(Sighting)
    case cluster(MapSightingCluster)

    var id: String {
        switch self {
        case .single(let sighting): "pin-\(sighting.id)"
        case .cluster(let cluster): "cluster-\(cluster.id)"
        }
    }
}

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
    @State private var hasFittedInitial = false
    @State private var lastSightingsSignature = ""
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var settledSpan: MKCoordinateSpan = Self.defaultRegion.span
    @State private var cameraDebounceTask: Task<Void, Never>?
    @State private var selectionDebounceTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let defaultRegion = MKCoordinateRegion(
        center: .init(latitude: 6.5, longitude: 103.0),
        span: .init(latitudeDelta: 34.0, longitudeDelta: 48.0)
    )

    private var selected: Sighting? {
        sightings.first { $0.id == selectedSightingID }
    }

    private var sightingsSignature: String {
        "\(selectedPeriod.rawValue)|\(selectedSpecies?.rawValue ?? "all")|\(selectedCondition?.rawValue ?? "all")|\(sightings.count)|\(sightings.first?.id ?? "")"
    }

    private var selectedTurtleTrack: [CLLocationCoordinate2D] {
        guard let selected else { return [] }
        let matches = sightings.filter { $0.turtleID == selected.turtleID }
        guard matches.count >= 2 else { return [] }
        return matches.map { CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    /// Dynamically clusters nearby sightings when zoomed out to pan-Asian or regional scale,
    /// while preserving full clarity for the active selected turtle's sightings.
    private var annotationNodes: [MapAnnotationNode] {
        let isZoomedOut = settledSpan.latitudeDelta > 2.2 || settledSpan.longitudeDelta > 2.6 || sightings.count > 45
        guard isZoomedOut else {
            return sightings.map { .single($0) }
        }

        let cellLat = max(1.2, settledSpan.latitudeDelta * 0.16)
        let cellLon = max(1.4, settledSpan.longitudeDelta * 0.16)
        let activeTurtleID = selected?.turtleID

        var singles: [MapAnnotationNode] = []
        var buckets: [String: [Sighting]] = [:]

        for item in sightings {
            if item.turtleID == activeTurtleID {
                singles.append(.single(item))
                continue
            }
            let latBin = Int(floor((item.coordinate.latitude + 90.0) / cellLat))
            let lonBin = Int(floor((item.coordinate.longitude + 180.0) / cellLon))
            let key = "\(latBin):\(lonBin)"
            buckets[key, default: []].append(item)
        }

        var clustered: [MapAnnotationNode] = []
        for (key, group) in buckets {
            if group.count == 1, let sole = group.first {
                clustered.append(.single(sole))
            } else if !group.isEmpty {
                let lats = group.map(\.coordinate.latitude)
                let lons = group.map(\.coordinate.longitude)
                let minLat = lats.min() ?? 0
                let maxLat = lats.max() ?? 0
                let minLon = lons.min() ?? 0
                let maxLon = lons.max() ?? 0
                let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) * 0.5, longitude: (minLon + maxLon) * 0.5)
                let cluster = MapSightingCluster(
                    id: key,
                    coordinate: center,
                    sightings: group,
                    spanLatitudeDelta: max((maxLat - minLat) * 1.9, 0.35),
                    spanLongitudeDelta: max((maxLon - minLon) * 1.9, 0.35)
                )
                clustered.append(.cluster(cluster))
            }
        }
        return clustered + singles
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if selectedTurtleTrack.count >= 2 {
                MapPolyline(coordinates: selectedTurtleTrack)
                    .stroke(AdaColors.navy.opacity(0.75), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 5]))
            }

            ForEach(annotationNodes) { node in
                switch node {
                case .single(let sighting):
                    Annotation(
                        sighting.location,
                        coordinate: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude),
                        anchor: .bottom
                    ) {
                        Button {
                            scheduleSelectionFocus(sighting)
                        } label: {
                            TurtleMapPin(isSelected: selectedSightingID == sighting.id)
                                .opacity(selected == nil || selected?.turtleID == sighting.turtleID ? 1 : 0.48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sighting.displayName), \(sighting.date), \(sighting.location)")
                    }

                case .cluster(let cluster):
                    Annotation(
                        "\(cluster.sightings.count) sightings",
                        coordinate: cluster.coordinate,
                        anchor: .center
                    ) {
                        Button {
                            zoomToCluster(cluster)
                        } label: {
                            MapClusterBadge(
                                count: cluster.sightings.count,
                                turtleCount: cluster.uniqueTurtleCount,
                                label: cluster.primaryLabel
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Zoom into \(cluster.primaryLabel) (\(cluster.sightings.count) sightings)")
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in
            let nextSpan = context.region.span
            cameraDebounceTask?.cancel()
            cameraDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                settledSpan = nextSpan
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where turtles were observed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Text(settledSpan.latitudeDelta > 4.0
                         ? "Pan-regional view · click any cluster to zoom in or select a pin"
                         : "Click a turtle pin to view encounters and profile")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)

                HStack(spacing: 8) {
                    Text(selected.map { $0.displayName } ?? "All sightings (\(sightings.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .foregroundStyle(.white)
                        .background(AdaColors.navy, in: Capsule())

                    ConditionPicker(selection: $selectedCondition)

                    Button {
                        fitMap(force: true)
                    } label: {
                        Label("Fit All", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdaColors.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom map to show all loaded turtles")
                }
            }
            .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            if let selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(selected.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Spacer()
                        Button {
                            selectionDebounceTask?.cancel()
                            selectedSightingID = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                                .frame(width: 24, height: 24)
                                .background(AdaColors.canvas, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear selected sighting")
                    }

                    SpeciesLabel(species: selected.species)
                        .font(.system(size: 12))
                    Text("\(selected.date) · \(selected.location)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AdaColors.secondaryInk)

                    Button("Open turtle profile →") {
                        onSelect(turtles.first { $0.id == selected.turtleID } ?? selected.turtleReference)
                    }
                    .buttonStyle(AdaPillButtonStyle())

                    let sameTurtleSightings = sightings.filter { $0.turtleID == selected.turtleID }
                    if !sameTurtleSightings.isEmpty {
                        Divider()
                        Text("Encounters (\(sameTurtleSightings.count))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AdaColors.secondaryInk)
                        ForEach(sameTurtleSightings.prefix(6)) { item in
                            Button {
                                scheduleSelectionFocus(item, recenterEvenWhenZoomed: true)
                            } label: {
                                HStack {
                                    Text(item.date)
                                        .font(.system(size: 11, weight: item.id == selected.id ? .bold : .regular))
                                    Spacer()
                                    Text(item.location)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(item.id == selected.id ? AdaColors.navy : AdaColors.ink)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
                .frame(width: 268)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
                .padding(18)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 14) {
                legend("Selected", color: AdaColors.navy)
                legend("Same turtle", color: AdaColors.secondaryInk)
                legend("Cluster", color: AdaColors.accent)
                Text("\(sightings.count) sightings")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
            .padding(18)
        }
        .overlay {
            if sightings.isEmpty {
                ContentUnavailableView(
                    "No sightings in this range",
                    systemImage: "map",
                    description: Text("Try All Time or clear filters.")
                )
                .frame(width: 320, height: 170)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .onAppear {
            if !hasFittedInitial {
                hasFittedInitial = true
                lastSightingsSignature = sightingsSignature
                fitMap(force: true)
            }
        }
        .onChange(of: sightingsSignature) { _, nextSig in
            guard nextSig != lastSightingsSignature else { return }
            lastSightingsSignature = nextSig
            if let selectedSightingID, !sightings.contains(where: { $0.id == selectedSightingID }) {
                self.selectedSightingID = nil
            }
            // Only auto-fit when filter/dataset changed intentionally, not mid-pan
            if !sightings.isEmpty {
                fitMap(force: false)
            }
        }
        .onChange(of: focusTurtleID) { _, _ in
            fitMap(force: true)
        }
        .onDisappear {
            cameraDebounceTask?.cancel()
            selectionDebounceTask?.cancel()
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 10.5))
        }
        .foregroundStyle(AdaColors.secondaryInk)
    }

    private func scheduleSelectionFocus(_ sighting: Sighting, recenterEvenWhenZoomed: Bool = false) {
        selectionDebounceTask?.cancel()
        selectedSightingID = sighting.id
        selectionDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            let needsZoomIn = settledSpan.latitudeDelta > 2.8 || settledSpan.longitudeDelta > 3.2
            guard needsZoomIn || recenterEvenWhenZoomed else { return }
            let targetSpan = MKCoordinateSpan(
                latitudeDelta: needsZoomIn ? 0.55 : min(settledSpan.latitudeDelta, 0.25),
                longitudeDelta: needsZoomIn ? 0.55 : min(settledSpan.longitudeDelta, 0.25)
            )
            let region = MKCoordinateRegion(
                center: .init(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude),
                span: targetSpan
            )
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                cameraPosition = .region(region)
                settledSpan = targetSpan
            }
        }
    }

    private func zoomToCluster(_ cluster: MapSightingCluster) {
        selectionDebounceTask?.cancel()
        let span = MKCoordinateSpan(
            latitudeDelta: cluster.spanLatitudeDelta,
            longitudeDelta: cluster.spanLongitudeDelta
        )
        let region = MKCoordinateRegion(center: cluster.coordinate, span: span)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.30)) {
            cameraPosition = .region(region)
            settledSpan = span
        }
    }

    private func fitMap(force: Bool) {
        if let focusTurtleID, consumedFocusID != focusTurtleID,
           let record = sightings.first(where: { $0.turtleID == focusTurtleID }) {
            consumedFocusID = focusTurtleID
            scheduleSelectionFocus(record, recenterEvenWhenZoomed: true)
            return
        }
        if !force, selected != nil { return }
        if !sightings.contains(where: { $0.id == selectedSightingID }) {
            selectedSightingID = nil
        }
        guard let minLat = sightings.map(\.coordinate.latitude).min(),
              let maxLat = sightings.map(\.coordinate.latitude).max(),
              let minLon = sightings.map(\.coordinate.longitude).min(),
              let maxLon = sightings.map(\.coordinate.longitude).max() else {
            cameraPosition = .region(Self.defaultRegion)
            settledSpan = Self.defaultRegion.span
            return
        }
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.38, 0.08),
            longitudeDelta: max((maxLon - minLon) * 1.38, 0.08)
        )
        let region = MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: span
        )
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            cameraPosition = .region(region)
            settledSpan = span
        }
    }
}

private struct MapClusterBadge: View {
    let count: Int
    let turtleCount: Int
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(AdaColors.navy)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AdaColors.navy)
                    .lineLimit(1)
                Text("\(turtleCount) turtle\(turtleCount == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(.trailing, 8)
        }
        .padding(3)
        .background(.white.opacity(0.95), in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
    }
}
