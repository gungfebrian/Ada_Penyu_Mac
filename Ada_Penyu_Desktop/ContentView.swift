import SwiftUI

struct ContentView: View {
    @StateObject private var store = AppStore()
    @State private var showingExport = false
    @State private var exportQueryOverride: IndividualQuery?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(selection: $store.activeSection, favoriteCount: store.favoriteTurtles.count, individualCount: store.totalIndividuals)

                VStack(spacing: 0) {
                    TopBar(
                        title: pageTitle,
                        subtitle: pageSubtitle,
                        searchText: searchBinding,
                        onExport: store.activeSection == .individuals ? { exportQueryOverride = nil; showingExport = true } : nil,
                        onBack: nil,
                        mode: store.mode,
                        isFallback: store.isUsingFallback,
                        onModeChange: store.switchMode
                    )

                    ZStack {
                        AdaColors.canvas
                        pageView

                        if store.isLoading {
                            ProgressView("Loading records…")
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let turtle = store.selectedTurtle {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.22))
                    .ignoresSafeArea()
                    .onTapGesture { store.dismissDetail() }

                GeometryReader { proxy in
                    IndividualDetailModal(
                        turtle: turtle,
                        detail: store.selectedDetail,
                        isLoading: store.isDetailLoading,
                        errorMessage: store.detailError,
                        isFavorite: store.favoriteTurtles.contains(where: { $0.id == turtle.id }),
                        onClose: store.dismissDetail,
                        onToggleFavorite: { store.toggleFavorite(turtle) },
                        onExport: {
                            exportQueryOverride = IndividualQuery(search: turtle.id, page: PageRequest(limit: 1))
                            showingExport = true
                        }
                    )
                    .frame(
                        width: min(max(proxy.size.width - 72, 820), 1_100),
                        height: min(max(proxy.size.height - 72, 600), 760)
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if showingExport {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.16))
                    .ignoresSafeArea()
                    .onTapGesture { showingExport = false }

                ExportSheet(
                    query: exportQueryOverride ?? store.currentIndividualQuery,
                    resultCount: exportQueryOverride == nil ? store.turtles.count : 1,
                    onCancel: { showingExport = false; exportQueryOverride = nil }
                ) { request in
                    showingExport = false
                    exportQueryOverride = nil
                    store.export(request)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(AdaColors.canvas)
        .frame(minWidth: AdaLayout.minimumWindowSize.width, minHeight: AdaLayout.minimumWindowSize.height)
        .task { await store.bootstrap() }
        .animation(.easeOut(duration: 0.16), value: showingExport)
        .animation(.easeOut(duration: 0.18), value: store.selectedTurtle?.id)
        .onExitCommand {
            if showingExport {
                showingExport = false
                exportQueryOverride = nil
            } else if store.selectedTurtle != nil {
                store.dismissDetail()
            }
        }
        .alert("Could not complete request", isPresented: Binding(
            get: { store.lastError != nil && !store.isUsingFallback },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.lastError ?? "Please try again.")
        }
    }

    private var pageTitle: String {
        store.activeSection == .detail ? AppSection.individuals.title : store.activeSection.title
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { store.searchText },
            set: { value in
                store.searchText = value
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   store.activeSection != .individuals,
                   store.activeSection != .favorites {
                    store.activeSection = .individuals
                }
            }
        )
    }

    private var pageSubtitle: String? {
        if store.activeSection == .map { return "last seen 30 days" }
        if store.activeSection == .dashboard { return "Sea Turtle Group · Bali monitoring" }
        return nil
    }

    @ViewBuilder
    private var pageView: some View {
        switch store.activeSection {
        case .dashboard:
            DashboardView(snapshot: store.dashboard, turtles: store.turtles, recentSightings: store.sightings, dataMode: store.mode, isFallback: store.isUsingFallback, chartMode: $store.chartMode) { turtle in store.select(turtle) }
        case .map:
            MapPageView(turtles: store.turtles, sightings: store.sightings, selectedPeriod: $store.selectedMapPeriod, selectedSpecies: $store.mapSpecies, selectedCondition: $store.mapCondition, onReload: { Task { await store.reloadMap() } }, onSelect: store.select)
        case .individuals:
            IndividualsView(turtles: store.turtles, total: store.totalIndividuals, searchText: $store.searchText, selectedSpecies: $store.selectedSpecies, selectedCondition: $store.selectedCondition, favoriteIDs: Set(store.favoriteTurtles.map(\.id)), onToggleFavorite: store.toggleFavorite, onSelect: store.select)
        case .favorites:
            FavoritesView(turtles: store.favoriteTurtles, searchText: $store.searchText, selectedCondition: $store.selectedCondition, favoriteIDs: Set(store.favoriteTurtles.map(\.id)), onToggleFavorite: store.toggleFavorite, onSelect: store.select, onBrowseIndividuals: { store.searchText = ""; store.selectedCondition = nil; store.activeSection = .individuals })
        case .detail:
            IndividualsView(turtles: store.turtles, total: store.totalIndividuals, searchText: $store.searchText, selectedSpecies: $store.selectedSpecies, selectedCondition: $store.selectedCondition, favoriteIDs: Set(store.favoriteTurtles.map(\.id)), onToggleFavorite: store.toggleFavorite, onSelect: store.select)
        }
    }
}

private struct IndividualDetailModal: View {
    let turtle: Turtle
    let detail: TurtleDetailData?
    let isLoading: Bool
    let errorMessage: String?
    let isFavorite: Bool
    let onClose: () -> Void
    let onToggleFavorite: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Individual profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Text("Field history, measurements, and known locations")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.045))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close individual profile")
            }
            .padding(.horizontal, 22)
            .frame(height: 62)
            .background(AdaColors.card)

            Divider().overlay(AdaColors.line)

            Group {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading field history…")
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, detail == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 23))
                            .foregroundStyle(AdaColors.orange)
                        Text("Could not load this individual")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TurtleDetailView(
                        turtle: turtle,
                        detail: detail,
                        isFavorite: isFavorite,
                        onToggleFavorite: onToggleFavorite,
                        onExport: onExport
                    )
                }
            }
            .background(AdaColors.canvas)
        }
        .background(AdaColors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.2), radius: 30, y: 12)
    }
}

private struct ExportSheet: View {
    let query: IndividualQuery
    let resultCount: Int
    let onCancel: () -> Void
    let onExport: (ExportRequest) -> Void
    @State private var scope: ExportScope = .currentView
    @State private var range: ExportRange = .sevenDays
    @State private var fields: Set<ExportField> = [.profile]
    @State private var format: ExportFormat = .csv

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export data")
                        .font(.system(size: 16, weight: .semibold))
                    Text(scope == .currentView ? "Filtered from \(resultCount) catalogued individuals" : "All catalogued individuals")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
            }
            .frame(height: 48, alignment: .top)

            ExportSectionLabel("Scope")
                .padding(.top, 5)
                .padding(.bottom, 7)
            HStack(spacing: 0) {
                ForEach(ExportScope.allCases) { option in
                    ExportOptionButton(title: option.title, isSelected: scope == option, style: .segment) { scope = option }
                }
            }
            .padding(2)
            .frame(width: 218, height: 29)
            .background(Color.black.opacity(0.055))
            .clipShape(Capsule())

            ExportSectionLabel("Data range")
                .padding(.top, 16)
                .padding(.bottom, 7)
            HStack(spacing: 7) {
                ForEach(ExportRange.allCases) { option in
                    ExportOptionButton(title: option.title.capitalized, isSelected: range == option) { range = option }
                }
            }

            ExportSectionLabel("Fields")
                .padding(.top, 22)
                .padding(.bottom, 7)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(ExportField.allCases) { field in
                    ExportFieldButton(title: field.title, isSelected: fields.contains(field)) {
                        if fields.contains(field), fields.count > 1 { fields.remove(field) }
                        else { fields.insert(field) }
                    }
                }
            }

            ExportSectionLabel("Format")
                .padding(.top, 22)
                .padding(.bottom, 7)
            HStack(spacing: 8) {
                ForEach(ExportFormat.allCases) { option in
                    ExportOptionButton(title: option == .pdf ? "PDF report" : option.title, isSelected: format == option) { format = option }
                }
            }

            Spacer(minLength: 20)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(ModalSecondaryButtonStyle())
                Button("Export") {
                    onExport(ExportRequest(scope: scope, range: range, fields: fields, format: format, query: query))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ModalPrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 414, height: 493)
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
    }
}

private struct ExportSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(AdaColors.ink) }
}

private struct ExportOptionButton: View {
    enum Style { case chip, segment }
    let title: String
    let isSelected: Bool
    var style: Style = .chip
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isSelected && style == .chip ? Color.white : AdaColors.secondaryInk)
                .padding(.horizontal, style == .segment ? 13 : 12)
                .frame(maxWidth: style == .segment ? .infinity : nil)
                .frame(height: 25)
                .background(isSelected ? (style == .chip ? AdaColors.navy : AdaColors.card) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ExportFieldButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? AdaColors.navy : AdaColors.card)
                    .frame(width: 15, height: 15)
                    .overlay { if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                    .overlay { Circle().stroke(AdaColors.line, lineWidth: isSelected ? 0 : 1) }
                Text(title).font(.system(size: 11)).foregroundStyle(AdaColors.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isSelected ? AdaColors.brandBlue.opacity(0.09) : Color.black.opacity(0.035))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ModalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 17).frame(height: 30).background(AdaColors.navy.opacity(configuration.isPressed ? 0.8 : 1)).clipShape(Capsule())
    }
}

private struct ModalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).padding(.horizontal, 15).frame(height: 30).background(Color.black.opacity(configuration.isPressed ? 0.08 : 0.045)).clipShape(Capsule())
    }
}
