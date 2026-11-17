import SwiftUI

struct IndividualsView: View {
    let turtles: [Turtle]
    let total: Int
    @Binding var searchText: String
    @Binding var selectedCondition: TurtleCondition?
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    var selectedSpecies: Binding<TurtleSpecies?> = .constant(nil)
    var pageSize: Binding<Int> = .constant(10)
    var offset = 0
    var isLoading = false
    var onPage: (Int) -> Void = { _ in }

    private var currentPage: Int { offset / max(1, pageSize.wrappedValue) }
    private var pageCount: Int { max(1, Int(ceil(Double(total) / Double(max(1, pageSize.wrappedValue))))) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 28) {
                    Text("Individuals  \(total)").font(.system(size: 13, weight: .semibold))
                        .padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(AdaColors.navy).frame(height: 2) }
                    Text("Not Sure").font(.system(size: 13)).foregroundStyle(AdaColors.secondaryInk)
                        .help("The review queue is not available from the current API.")
                    Spacer()
                    Text("Review queue unavailable").font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(AdaColors.line).frame(height: 1) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { search; filters }
                    VStack(alignment: .leading, spacing: 12) { search; HStack { filters; Spacer(minLength: 0) } }
                }
                HStack {
                    Text("\(total) individuals").font(.system(size: 13))
                    Spacer()
                    Text("Sorted by last sighting · newest first").font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                }
                VStack(spacing: 0) {
                    TurtleTableView(turtles: turtles, favoriteIDs: favoriteIDs, onToggleFavorite: onToggleFavorite, onSelect: onSelect)
                    Divider().padding(.horizontal, 22)
                    pagination.padding(22).disabled(isLoading)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius))
                Text("Select an individual to explore its sighting history and body condition.")
                    .font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(.horizontal, AdaLayout.pagePadding).padding(.top, 12).padding(.bottom, 32)
        }.scrollIndicators(.hidden)
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AdaColors.secondaryInk)
            TextField("Search name or Turtle ID", text: $searchText).textFieldStyle(.plain).font(.system(size: 12))
                .accessibilityLabel("Search sea turtles")
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).frame(minWidth: 240, maxWidth: .infinity, minHeight: 38)
        .background(.white, in: Capsule())
    }

    private var filters: some View {
        HStack(spacing: 12) {
            SpeciesPicker(selection: selectedSpecies)
            ConditionPicker(selection: $selectedCondition)
        }.fixedSize()
    }

    private var pagination: some View {
        HStack(spacing: 14) {
            Text("Rows per page").foregroundStyle(AdaColors.secondaryInk)
            Picker("Rows per page", selection: pageSize) {
                ForEach([10, 25, 50], id: \.self) { size in Text("\(size)").tag(size) }
            }.labelsHidden().frame(width: 70)
            Text(total == 0 ? "0 of 0 individuals" : "\(offset + 1)–\(min(offset + turtles.count, total)) of \(total) individuals")
            Spacer()
            Button { onPage(currentPage - 1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 30) }
                .disabled(currentPage == 0).accessibilityLabel("Previous page")
            ForEach(Array(max(0, currentPage - 2)..<min(pageCount, currentPage + 3)), id: \.self) { page in
                Button { onPage(page) } label: {
                    Text("\(page + 1)").frame(width: 30, height: 30)
                        .foregroundStyle(currentPage == page ? .white : AdaColors.ink)
                        .background(currentPage == page ? AdaColors.navy : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel("Page \(page + 1)").accessibilityAddTraits(currentPage == page ? .isSelected : [])
            }
            Button { onPage(currentPage + 1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 30) }
                .disabled(currentPage >= pageCount - 1).accessibilityLabel("Next page")
        }.font(.system(size: 11)).buttonStyle(.plain)
    }
}

struct FavoritesView: View {
    let turtles: [Turtle]
    @Binding var searchText: String
    @Binding var selectedCondition: TurtleCondition?
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    let onBrowseIndividuals: () -> Void

    var filtered: [Turtle] {
        turtles.filter { turtle in
            (searchText.isEmpty || turtle.displayName.localizedCaseInsensitiveContains(searchText) || turtle.id.localizedCaseInsensitiveContains(searchText) || turtle.location.localizedCaseInsensitiveContains(searchText)) &&
            (selectedCondition == nil || selectedCondition == turtle.condition)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    TextField("Search favorites", text: $searchText).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                    ConditionPicker(selection: $selectedCondition)
                }
                HStack {
                    Text("\(filtered.count) favorites").font(.system(size: 13))
                    Spacer()
                    Button("Browse Sea Turtles", action: onBrowseIndividuals).buttonStyle(AdaPillButtonStyle(secondary: true))
                }
                TurtleTableView(turtles: filtered, favoriteIDs: favoriteIDs, onToggleFavorite: onToggleFavorite, onSelect: onSelect)
                    .background(.white, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius))
            }.padding(AdaLayout.pagePadding)
        }
    }
}

private struct TurtleTableView: View {
    let turtles: [Turtle]
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text("Individual").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Species").frame(width: 130, alignment: .leading)
                        Text("Observation history").frame(width: 155, alignment: .leading)
                        Text("Locations").frame(width: 135, alignment: .leading)
                        Text("Sightings").frame(width: 65, alignment: .leading)
                        Text("Last assessed condition").frame(width: 140, alignment: .leading)
                    }
                    .font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk).frame(height: 52)
                    Divider()
                    if turtles.isEmpty {
                        ContentUnavailableView("No sea turtles to show", systemImage: "tortoise", description: Text("Try another search or clear a filter."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(turtles) { turtle in
                            TurtleTableRow(turtle: turtle, isFavorite: favoriteIDs.contains(turtle.id),
                                onToggleFavorite: { onToggleFavorite(turtle) }, onSelect: { onSelect(turtle) })
                            if turtle.id != turtles.last?.id { Divider().opacity(0.5) }
                        }
                    }
                }
                .padding(.horizontal, 22).frame(width: max(proxy.size.width, 1080))
            }
        }
        .frame(height: turtles.isEmpty ? 282 : 53 + CGFloat(turtles.count) * 125)
    }
}

private struct TurtleTableRow: View {
    let turtle: Turtle
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FavoriteButton(isFavorite: isFavorite, action: onToggleFavorite)
            Button(action: onSelect) {
                HStack(spacing: 16) {
                    HStack(spacing: 12) {
                        IdentityPhotoPair(turtle: turtle, size: 46)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(turtle.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(turtle.profileCode ?? turtle.id).font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    SpeciesLabel(species: turtle.species).font(.system(size: 11)).frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last: \(turtle.lastSeen)").font(.system(size: 11))
                        Text("First: \(turtle.firstRecorded)").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    }.frame(width: 155, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(turtle.location).font(.system(size: 11)).lineLimit(2)
                        Text("Latest recorded location").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    }.frame(width: 135, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(turtle.sightings.formatted()).font(.system(size: 13, weight: .semibold))
                        Text("total").font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    }.frame(width: 65, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        ConditionPill(condition: turtle.condition)
                        Text(turtle.condition == .unknown ? "No assessment available" : "Latest available assessment")
                            .font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
                    }.frame(width: 140, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 124).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Open \(turtle.displayName), \(turtle.species.rawValue)")
        }.foregroundStyle(AdaColors.ink)
    }
}

struct IdentityPhotoPair: View {
    let turtle: Turtle
    var size: CGFloat = 84
    var body: some View {
        HStack(spacing: 6) {
            photo(turtle.leftPhotoURL, label: "Left")
            photo(turtle.rightPhotoURL, label: "Right")
        }
    }
    private func photo(_ path: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TurtlePhoto(paths: path.map { [$0] } ?? [], size: size)
            Text(size < 60 ? String(label.prefix(1)) : label).font(.system(size: 9)).foregroundStyle(AdaColors.secondaryInk)
        }.accessibilityElement(children: .combine).accessibilityLabel("\(label) identity photo")
    }
}

struct SightingsListView: View {
    let sightings: [Sighting]
    var onOpenNotSureReview: ((ReviewScenarioID) -> Void)? = nil
    let onSelect: (Sighting) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let onOpenNotSureReview {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionTitle(
                                "Pending 'Not Sure' review",
                                subtitle: "2 ranger encounters marked 'Not Sure' · mock scale & junction annotations ready"
                            )
                            Spacer()
                            Button("Open Review Workspace  →") {
                                onOpenNotSureReview(.rankOneJunctionMismatch)
                            }
                            .buttonStyle(AdaPillButtonStyle())
                        }

                        HStack(spacing: 16) {
                            notSureSightingCard(
                                id: "SGT-2026-1109",
                                species: .green,
                                side: "Left Head",
                                date: "09 Nov 2026",
                                location: "Crystal Bay, Nusa Penida",
                                note: "Rank #1 vs #2 (84% vs 79%) · 6 scale junctions annotated",
                                scenario: .rankOneJunctionMismatch,
                                action: onOpenNotSureReview
                            )
                            notSureSightingCard(
                                id: "SGT-2026-1110",
                                species: .hawksbill,
                                side: "Right Head",
                                date: "10 Nov 2026",
                                location: "Jemeluk Wall, Amed",
                                note: "Specular glare over J2–J4 · Head ROI & scales annotated",
                                scenario: .glareOcclusionUnsure,
                                action: onOpenNotSureReview
                            )
                        }
                    }
                    .adaCard(padding: 22)
                }

                SectionTitle("Recorded sightings", subtitle: "\(sightings.count) loaded records · current map filters")
                if sightings.isEmpty {
                    ContentUnavailableView("No sightings in this range", systemImage: "binoculars", description: Text("Change the time window or species filter."))
                } else {
                    ForEach(sightings) { sighting in
                        Button { onSelect(sighting) } label: {
                            HStack(spacing: 20) {
                                Text(sighting.displayName).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                SpeciesLabel(species: sighting.species).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                                Text(sighting.date).font(.system(size: 12)).frame(width: 115, alignment: .leading)
                                Text(sighting.location).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                                Image(systemName: "arrow.right")
                            }.contentShape(Rectangle()).adaCard(padding: 22)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(AdaLayout.pagePadding)
        }
    }

    private func notSureSightingCard(
        id: String,
        species: TurtleSpecies,
        side: String,
        date: String,
        location: String,
        note: String,
        scenario: ReviewScenarioID,
        action: @escaping (ReviewScenarioID) -> Void
    ) -> some View {
        Button {
            action(scenario)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(id)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Text("Not Sure · \(side)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AdaColors.orange)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(AdaColors.orange.opacity(0.14), in: Capsule())
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.navy)
                }
                HStack(spacing: 12) {
                    SpeciesLabel(species: species).font(.system(size: 11))
                    Text("·").foregroundStyle(AdaColors.secondaryInk)
                    Text("\(date) · \(location)")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
