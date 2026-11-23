import SwiftUI

struct ProfileWorkspaceView: View {
    let turtle: Turtle
    let detail: TurtleDetailData?
    let isLoading: Bool
    let error: String?
    @Binding var selectedSightingID: String?
    let onBack: () -> Void
    let onMap: () -> Void
    let onExport: () -> Void
    var originTitle: String = "Sea Turtles"
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    var onRetry: () -> Void = {}
    @State private var bodyCondition = false

    private var sighting: TurtleLogSummary? { detail?.sightingLogs.first { $0.id == selectedSightingID } }
    private var bodyConditionCount: Int { detail?.logs.filter(\.isBodyConditionRecord).count ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Button {
                        if selectedSightingID != nil { selectedSightingID = nil } else { onBack() }
                    } label: { Label(selectedSightingID == nil ? "Back to \(originTitle)" : "Back to \(turtle.displayName)", systemImage: "chevron.left") }
                        .buttonStyle(.plain).font(.system(size: 12))
                    Spacer()
                    if let onToggleFavorite {
                        Button(action: onToggleFavorite) {
                            Label(isFavorite ? "On Watchlist" : "Watchlist", systemImage: isFavorite ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12, weight: isFavorite ? .semibold : .medium))
                                .foregroundStyle(isFavorite ? .white : AdaColors.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(isFavorite ? AdaColors.navy : AdaColors.card, in: Capsule())
                                .overlay(Capsule().stroke(isFavorite ? AdaColors.navy : AdaColors.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove from watchlist" : "Add to watchlist")
                    }
                    Button(action: onExport) {
                        Label("Export", systemImage: "arrow.down.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Export this individual's records")
                    Button("View on map", action: onMap).buttonStyle(.plain).font(.system(size: 12))
                }
                if isLoading {
                    ProgressView("Loading sighting history…").frame(maxWidth: .infinity, minHeight: 200)
                } else if let error {
                    VStack(spacing: 14) {
                        Text("Could not load this profile").font(.headline)
                        Text(error).font(.callout).textSelection(.enabled)
                        Button("Retry", action: onRetry).buttonStyle(AdaPillButtonStyle())
                    }.frame(maxWidth: .infinity).adaCard()
                } else if selectedSightingID != nil {
                    if let sighting { SightingDetailsView(turtle: turtle, sighting: sighting, detail: detail) }
                    else { ContentUnavailableView("Sighting unavailable", systemImage: "binoculars", description: Text("This record was not returned with the turtle's history.")) }
                } else {
                    summary
                    HStack(spacing: 10) {
                        Button("Overview") { bodyCondition = false }.buttonStyle(AdaPillButtonStyle(secondary: bodyCondition))
                        Button(bodyConditionCount > 0 ? "Body Condition (\(bodyConditionCount))" : "Body Condition") {
                            bodyCondition = true
                        }.buttonStyle(AdaPillButtonStyle(secondary: !bodyCondition))
                        Spacer()
                    }
                    if bodyCondition {
                        BodyConditionTab(logs: detail?.logs ?? [], onExport: onExport, onOpenSighting: { selectedSightingID = $0 })
                    } else { overview }
                }
                Text("Organization records · missing assessments do not imply recovery")
                    .font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk).padding(.top, 12)
            }
            .padding(.horizontal, AdaLayout.pagePadding).padding(.top, 12).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .onChange(of: turtle.id) { _, _ in
            bodyCondition = false
        }
    }

    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 28) { identity; Spacer(minLength: 12); metrics }
            VStack(alignment: .leading, spacing: 24) { identity; metrics }
        }
        .frame(maxWidth: .infinity, alignment: .leading).adaCard(padding: 24)
    }

    private var identity: some View {
        HStack(spacing: 24) {
            IdentityPhotoPair(turtle: turtle, size: 84)
            VStack(alignment: .leading, spacing: 12) {
                Text(turtle.displayName).font(.system(size: 25, weight: .semibold))
                SpeciesLabel(species: turtle.species).font(.system(size: 13))
                Text(turtle.profileCode ?? turtle.id).font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk).textSelection(.enabled)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 30) {
            metric("First recorded", turtle.firstRecorded)
            metric("Last seen", turtle.lastSeen)
            metric("Sightings", turtle.sightings.formatted())
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
            Text(value).font(.system(size: 14, weight: .semibold))
        }
    }

    private var overview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                overviewFacts.frame(width: 330)
                history.frame(minWidth: 380, maxWidth: .infinity)
            }
            VStack(spacing: 24) { overviewFacts; history }
        }
    }

    private var overviewFacts: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle("Latest available measurements")
                if let measurement = detail?.measurements.first {
                    Text("Measured on \(measurement.date)").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                    HStack(spacing: 24) {
                        metric("CCL", measurement.length.map { "\($0.formatted()) cm" } ?? "—")
                        metric("CCW", measurement.width.map { "\($0.formatted()) cm" } ?? "—")
                        metric("Weight", measurement.weight.map { "\($0.formatted()) kg" } ?? "—")
                    }
                    Button("View source sighting") { selectedSightingID = measurement.id }
                        .buttonStyle(AdaPillButtonStyle(secondary: true))
                } else { Text("Not recorded").font(.system(size: 15)).foregroundStyle(AdaColors.secondaryInk) }
            }.frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).adaCard(padding: 22)
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle("Body condition")
                ConditionPill(condition: turtle.condition)
                Text("A missing assessment does not mean recovery.").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                Button("Explore body condition") { bodyCondition = true }.buttonStyle(AdaPillButtonStyle())
            }.frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading).adaCard(padding: 22)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Sighting history", subtitle: "\(detail?.sightingLogs.count ?? 0) recorded encounters")
            if let logs = detail?.sightingLogs, !logs.isEmpty {
                ForEach(logs) { log in
                    Button { selectedSightingID = log.id } label: {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(log.date).font(.system(size: 13, weight: .semibold))
                                Text(log.status).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
                            }.frame(width: 110, alignment: .leading)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(log.location).font(.system(size: 14, weight: .medium))
                                Text(log.notes ?? "No notes recorded").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right").font(.system(size: 12))
                        }
                        .padding(18).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            } else { Text("No sightings recorded.").font(.callout).foregroundStyle(AdaColors.secondaryInk).frame(minHeight: 150) }
        }
        .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading).adaCard(padding: 22)
    }
}

private struct SightingDetailsView: View {
    let turtle: Turtle
    let sighting: TurtleLogSummary
    let detail: TurtleDetailData?

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(turtle.displayName + (turtle.profileCode.map { " · \($0)" } ?? "")).font(.system(size: 22, weight: .semibold))
                    Text("\(sighting.date) · \(sighting.location)").font(.system(size: 13)).foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer()
                SpeciesLabel(species: turtle.species).font(.system(size: 12))
                Text("Read-only").font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 8).background(AdaColors.canvas, in: Capsule())
            }.adaCard(padding: 24)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { photos.frame(width: 390); observation.frame(minWidth: 340, maxWidth: .infinity) }
                VStack(spacing: 24) { photos; observation }
            }
            HStack(alignment: .top, spacing: 24) {
                measurements.frame(maxWidth: .infinity)
                assessment.frame(maxWidth: .infinity)
            }
        }
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !sighting.photoPaths.isEmpty {
                SectionTitle("Encounter photos", subtitle: "\(sighting.photoPaths.count) attached photo\(sighting.photoPaths.count == 1 ? "" : "s")")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(sighting.photoPaths.enumerated()), id: \.offset) { _, path in
                            TurtlePhoto(paths: [path], size: 155)
                        }
                    }
                }
            } else {
                SectionTitle("Identity reference photos", subtitle: "Profile photos · encounter photos unavailable")
                IdentityPhotoPair(turtle: turtle, size: 155)
            }
        }.frame(maxWidth: .infinity, minHeight: 285, alignment: .topLeading).adaCard(padding: 22)
    }

    private var observation: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Observation details")
            fact("Sighting ID", sighting.id)
            fact("Date", sighting.date)
            fact("Location", sighting.location)
            fact("Coordinates", sighting.coordinate.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) } ?? "Not recorded")
            fact("Event", sighting.status)
            fact("Notes", sighting.notes ?? "Not recorded")
        }.frame(maxWidth: .infinity, minHeight: 285, alignment: .topLeading).adaCard(padding: 22)
    }

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle("Measurements at this sighting")
            if let value = detail?.measurements.first(where: { $0.id == sighting.id }) {
                fact("CCL", value.length.map { "\($0.formatted()) cm" } ?? "Not recorded")
                fact("CCW", value.width.map { "\($0.formatted()) cm" } ?? "Not recorded")
                fact("Weight", value.weight.map { "\($0.formatted()) kg" } ?? "Not recorded")
            } else {
                Text("Not recorded").font(.system(size: 18))
                Text("No measurements were entered for this sighting.").font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
            }
        }.frame(maxWidth: .infinity, minHeight: 165, alignment: .topLeading).adaCard(padding: 22)
    }

    private var assessment: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle("Body condition at this sighting")
            if let condition = sighting.condition { ConditionPill(condition: condition) }
            else { Text("Not recorded").font(.system(size: 18)) }
            Text("A missing assessment does not indicate recovery.").font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
        }.frame(maxWidth: .infinity, minHeight: 165, alignment: .topLeading).adaCard(padding: 22)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk).frame(width: 90, alignment: .leading)
            Text(value).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("Turtle Profile · Overview & Body Condition") {
    @Previewable @State var selectedSightingID: String? = nil
    @Previewable @State var isFavorite = true
    let detail = PreviewFixtures.makeSampleDetail()

    ProfileWorkspaceView(
        turtle: PreviewFixtures.injuredTurtle,
        detail: detail,
        isLoading: false,
        error: nil,
        selectedSightingID: $selectedSightingID,
        onBack: {},
        onMap: {},
        onExport: {},
        originTitle: "Map",
        isFavorite: isFavorite,
        onToggleFavorite: { isFavorite.toggle() }
    )
    .background(AdaColors.canvas)
    .environment(\.turtlePhotoLoader, PreviewFixtures.photoLoader)
    .frame(width: 1220, height: 860)
    .preferredColorScheme(.light)
}

#Preview("Sighting Details") {
    @Previewable @State var selectedSightingID: String? = PreviewFixtures.makeSampleDetail().sightingLogs.first?.id
    let detail = PreviewFixtures.makeSampleDetail()

    ProfileWorkspaceView(
        turtle: PreviewFixtures.injuredTurtle,
        detail: detail,
        isLoading: false,
        error: nil,
        selectedSightingID: $selectedSightingID,
        onBack: {},
        onMap: {},
        onExport: {},
        originTitle: "Sightings",
        isFavorite: false,
        onToggleFavorite: {}
    )
    .background(AdaColors.canvas)
    .environment(\.turtlePhotoLoader, PreviewFixtures.photoLoader)
    .frame(width: 1220, height: 860)
    .preferredColorScheme(.light)
}
#endif
