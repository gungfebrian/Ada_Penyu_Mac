import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportSheetView: View {
    @ObservedObject var store: AppStore
    let onDismiss: () -> Void

    @State private var stagedPhotos: [StagedImportPhoto]
    @State private var stagedEncounters: [StagedPhotoEncounter]
    @State private var stagedCatalogRows: [StagedCatalogRow]
    @State private var stagedNotSureCases: [EscalatedNotSureCase]
    @State private var skippedFiles: [(filename: String, reason: String)] = []
    @State private var destination: PhotoBatchDestination = .matchAndTriage
    @State private var isDropTargeted = false
    @State private var isScanning = false
    @State private var inlineError: String?

    init(
        store: AppStore,
        initialPhotos: [StagedImportPhoto] = [],
        initialCatalogRows: [StagedCatalogRow] = [],
        initialNotSureCases: [EscalatedNotSureCase] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onDismiss = onDismiss
        self._stagedPhotos = State(initialValue: initialPhotos)
        self._stagedEncounters = State(initialValue: PhotoBatchGrouper.group(initialPhotos))
        self._stagedCatalogRows = State(initialValue: initialCatalogRows)
        self._stagedNotSureCases = State(initialValue: initialNotSureCases)
    }

    private var hasStagedItems: Bool {
        !stagedEncounters.isEmpty || !stagedCatalogRows.isEmpty || !stagedNotSureCases.isEmpty
    }

    private var validCatalogRows: [StagedCatalogRow] {
        stagedCatalogRows.filter(\.isValid)
    }

    private var pairedEncounterCount: Int {
        stagedEncounters.filter(\.isPaired).count
    }

    private var gpsTaggedCount: Int {
        stagedPhotos.filter { $0.coordinate != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AdaColors.line)

            Group {
                if isScanning {
                    scanningView
                } else if !hasStagedItems {
                    dropzoneView
                } else if !stagedEncounters.isEmpty {
                    photoStagingView
                } else if !stagedCatalogRows.isEmpty {
                    catalogStagingView
                } else {
                    notSureBundleStagingView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let inlineError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AdaColors.red)
                    Text(inlineError)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AdaColors.red)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }

            Divider().overlay(AdaColors.line)
            footer
        }
        .frame(width: 700, height: 540)
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isDropTargeted ? AdaColors.navy : AdaColors.line, lineWidth: isDropTargeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 28, y: 10)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import data")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text("HEIC, JPEG, PNG, folders, CSV, XLSX, or Not Sure queue")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            Spacer()
            if hasStagedItems && !store.isImporting {
                Button("Add more", action: openFilePicker)
                    .buttonStyle(ImportPillStyle(.subtle, height: 28))
                Button("Clear", action: clearAll)
                    .buttonStyle(ImportPillStyle(.subtle, height: 28))
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(AdaColors.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.isImporting)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Empty Dropzone

    private var dropzoneView: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isDropTargeted ? AdaColors.navy : AdaColors.accent)

                Text(isDropTargeted ? "Drop to stage files" : "Drop turtle photos, a folder, or spreadsheet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)

                HStack(spacing: 6) {
                    formatTag("HEIC / iPhone")
                    formatTag("JPEG / PNG")
                    formatTag("Folder")
                    formatTag("CSV / XLSX")
                    formatTag("Not Sure JSON")
                }

                Button("Choose files or folder…", action: openFilePicker)
                    .buttonStyle(ImportPillStyle(.primary, height: 36))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 42)
            .background(
                isDropTargeted ? AdaColors.accentSoft : AdaColors.canvas,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? AdaColors.navy : AdaColors.line,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .padding(.horizontal, 22)

            if !skippedFiles.isEmpty {
                skippedBanner
                    .padding(.horizontal, 22)
            }
            Spacer()
        }
    }

    private func formatTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AdaColors.secondaryInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AdaColors.card, in: Capsule())
            .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Reading photos & EXIF metadata…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AdaColors.secondaryInk)
            Spacer()
        }
    }

    // MARK: - Batch Photos Staging View

    private var photoStagingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary pills
            HStack(spacing: 8) {
                summaryChip("\(stagedPhotos.count) photo\(stagedPhotos.count == 1 ? "" : "s")", tint: AdaColors.navy, bg: AdaColors.navy.opacity(0.08))
                summaryChip("\(stagedEncounters.count) encounter\(stagedEncounters.count == 1 ? "" : "s")", tint: AdaColors.ink, bg: AdaColors.surfaceMuted)
                if pairedEncounterCount > 0 {
                    summaryChip("\(pairedEncounterCount) paired L+R", tint: AdaColors.green, bg: AdaColors.green.opacity(0.12))
                }
                if gpsTaggedCount > 0 {
                    summaryChip("\(gpsTaggedCount) EXIF GPS", tint: AdaColors.accent, bg: AdaColors.accentSoft)
                }
                if !skippedFiles.isEmpty {
                    summaryChip("\(skippedFiles.count) skipped", tint: AdaColors.orange, bg: AdaColors.orange.opacity(0.16))
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Visual encounter cards
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(stagedEncounters) { encounter in
                        encounterCard(encounter)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }

            // 3 Clear Destination Pills
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(PhotoBatchDestination.allCases) { option in
                        let active = destination == option
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) { destination = option }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(option.rawValue)
                                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                            }
                            .foregroundStyle(active ? .white : AdaColors.ink)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(active ? AdaColors.navy : AdaColors.surfaceMuted, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                Text(destination.shortHint)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
    }

    private func encounterCard(_ encounter: StagedPhotoEncounter) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                photoThumb(encounter.primary.previewImage, size: 52)
                if let companion = encounter.companion {
                    photoThumb(companion.previewImage, size: 52)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(encounter.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if encounter.isPaired {
                        summaryChip("Left + Right", tint: AdaColors.green, bg: AdaColors.green.opacity(0.12))
                    } else {
                        Button {
                            toggleSinglePhotoSide(encounterID: encounter.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(encounter.primary.side == .left ? "Left" : "Right")
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AdaColors.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Click to flip Left / Right side")
                    }

                    summaryChip(encounter.primary.originalFormat, tint: AdaColors.secondaryInk, bg: AdaColors.card)

                    if encounter.coordinate != nil {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AdaColors.accent)
                            .help("EXIF GPS detected")
                    }
                }

                if let date = encounter.capturedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                removeEncounter(encounter.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .frame(width: 22, height: 22)
                    .background(AdaColors.card, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.isImporting)
        }
        .padding(10)
        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func photoThumb(_ image: NSImage?, size: CGFloat) -> some View {
        ZStack {
            AdaColors.surfaceMuted
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(AdaColors.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Catalog Spreadsheet Staging View

    private var catalogStagingView: some View {
        let invalidCount = stagedCatalogRows.count - validCatalogRows.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                summaryChip("\(validCatalogRows.count) ready", tint: AdaColors.green, bg: AdaColors.green.opacity(0.12))
                if invalidCount > 0 {
                    summaryChip("\(invalidCount) skipped", tint: AdaColors.red, bg: AdaColors.red.opacity(0.12))
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(stagedCatalogRows) { row in
                        HStack(spacing: 12) {
                            Text(row.profileCode)
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AdaColors.navy)
                                .frame(width: 64, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(AdaColors.ink)
                                    .lineLimit(1)
                                Text("\(row.species.rawValue) · \(row.sex.capitalized) · \(row.location)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdaColors.secondaryInk)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if let err = row.validationError {
                                summaryChip(err, tint: AdaColors.red, bg: AdaColors.red.opacity(0.11))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AdaColors.green)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if row.id != stagedCatalogRows.last?.id {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
                .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Not Sure Bundle Staging View

    private var notSureBundleStagingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                summaryChip("\(stagedNotSureCases.count) Not Sure case\(stagedNotSureCases.count == 1 ? "" : "s")", tint: AdaColors.navy, bg: AdaColors.navy.opacity(0.08))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(stagedNotSureCases) { item in
                        HStack(spacing: 12) {
                            photoThumb(item.queryImage, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(item.side.title) · \(item.candidates.count) candidate\(item.candidates.count == 1 ? "" : "s") · \(item.decisionSummaryTitle)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdaColors.secondaryInk)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private var skippedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(AdaColors.orange)
            Text("Skipped \(skippedFiles.count) file\(skippedFiles.count == 1 ? "" : "s"): \(skippedFiles.prefix(3).map(\.filename).joined(separator: ", "))")
                .font(.system(size: 11.5))
                .foregroundStyle(AdaColors.secondaryInk)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AdaColors.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func summaryChip(_ title: String, tint: Color, bg: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if store.isImporting {
                ProgressView().controlSize(.small)
                Text(store.importProgressText ?? "Importing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            Spacer()
            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(ImportPillStyle(.subtle, height: 34))
                .disabled(store.isImporting)

            Button(primaryActionTitle) {
                Task { await executeImport() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(ImportPillStyle(.primary, height: 34))
            .disabled(!canImport || store.isImporting || isScanning)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var canImport: Bool {
        if !stagedEncounters.isEmpty { return true }
        if !validCatalogRows.isEmpty { return true }
        if !stagedNotSureCases.isEmpty { return true }
        return false
    }

    private var primaryActionTitle: String {
        if !stagedEncounters.isEmpty {
            let n = stagedEncounters.count
            switch destination {
            case .matchAndTriage: return "Match \(n) encounter\(n == 1 ? "" : "s")"
            case .notSureQueue: return "Send \(n) to Not Sure"
            case .enrollNew: return "Enroll \(n) turtle\(n == 1 ? "" : "s")"
            }
        }
        if !stagedCatalogRows.isEmpty {
            let n = validCatalogRows.count
            return "Import \(n) individual\(n == 1 ? "" : "s")"
        }
        if !stagedNotSureCases.isEmpty {
            let n = stagedNotSureCases.count
            return "Import \(n) case\(n == 1 ? "" : "s")"
        }
        return "Import"
    }

    // MARK: - File Picker, Drop & Staging Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = PhotoImportNormalizer.panelAllowedContentTypes
        panel.prompt = "Add to Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        ingestURLs(panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                ingestURLs(urls)
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func ingestURLs(_ urls: [URL]) {
        isScanning = true
        inlineError = nil
        let existingCodes = store.existingProfileCodes

        Task {
            let scan = await Task.detached(priority: .userInitiated) {
                PhotoBatchGrouper.scan(urls: urls, existingProfileCodes: existingCodes)
            }.value

            isScanning = false
            skippedFiles.append(contentsOf: scan.skippedFiles)

            if !scan.photos.isEmpty {
                stagedPhotos.append(contentsOf: scan.photos)
                stagedEncounters = PhotoBatchGrouper.group(stagedPhotos)
                stagedCatalogRows = []
                stagedNotSureCases = []
            } else if !scan.catalogRows.isEmpty {
                stagedCatalogRows.append(contentsOf: scan.catalogRows)
                stagedPhotos = []
                stagedEncounters = []
                stagedNotSureCases = []
            } else if !scan.notSureCases.isEmpty {
                stagedNotSureCases.append(contentsOf: scan.notSureCases)
                stagedPhotos = []
                stagedEncounters = []
                stagedCatalogRows = []
            } else if !scan.skippedFiles.isEmpty {
                inlineError = "No supported images or spreadsheets found."
            }
        }
    }

    private func toggleSinglePhotoSide(encounterID: UUID) {
        guard let idx = stagedEncounters.firstIndex(where: { $0.id == encounterID }), !stagedEncounters[idx].isPaired else { return }
        let nextSide: TurtlePhotoSide = stagedEncounters[idx].primary.side == .left ? .right : .left
        stagedEncounters[idx].primary.side = nextSide
        if let pIdx = stagedPhotos.firstIndex(where: { $0.id == stagedEncounters[idx].primary.id }) {
            stagedPhotos[pIdx].side = nextSide
        }
    }

    private func removeEncounter(_ id: UUID) {
        guard let enc = stagedEncounters.first(where: { $0.id == id }) else { return }
        let removedIDs = Set([enc.primary.id, enc.companion?.id].compactMap { $0 })
        stagedPhotos.removeAll { removedIDs.contains($0.id) }
        stagedEncounters.removeAll { $0.id == id }
    }

    private func clearAll() {
        stagedPhotos = []
        stagedEncounters = []
        stagedCatalogRows = []
        stagedNotSureCases = []
        skippedFiles = []
        inlineError = nil
    }

    private func executeImport() async {
        inlineError = nil
        if !stagedEncounters.isEmpty {
            _ = await store.importPhotoEncounters(stagedEncounters, destination: destination)
            onDismiss()
        } else if !validCatalogRows.isEmpty {
            _ = await store.importCatalogRows(stagedCatalogRows)
            onDismiss()
        } else if !stagedNotSureCases.isEmpty {
            let count = store.importNotSureBundleCases(stagedNotSureCases)
            if count > 0 { onDismiss() } else { inlineError = "Could not import cases into this workspace." }
        }
    }
}

private struct ImportPillStyle: ButtonStyle {
    enum Tone { case primary, subtle }
    let tone: Tone
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var isEnabled

    init(_ tone: Tone, height: CGFloat = 34) {
        self.tone = tone
        self.height = height
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: tone == .primary ? .semibold : .medium))
            .foregroundStyle(tone == .primary ? .white : AdaColors.ink)
            .padding(.horizontal, 15)
            .frame(height: height)
            .background(
                tone == .primary
                    ? AdaColors.navy.opacity(configuration.isPressed ? 0.84 : 1)
                    : (configuration.isPressed ? AdaColors.surfaceMuted : AdaColors.card),
                in: Capsule()
            )
            .overlay(Capsule().stroke(tone == .primary ? .clear : AdaColors.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Capsule())
    }
}

#if DEBUG
#Preview("Import · Dropzone") {
    ZStack {
        AdaColors.canvas
        ImportSheetView(
            store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork),
            onDismiss: {}
        )
    }
    .frame(width: 820, height: 640)
    .preferredColorScheme(.light)
}

#Preview("Import · Batch Photos (Paired L+R + HEIC)") {
    ZStack {
        AdaColors.canvas
        ImportSheetView(
            store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork),
            initialPhotos: PreviewFixtures.makeSampleImportPhotos(),
            onDismiss: {}
        )
    }
    .frame(width: 820, height: 640)
    .preferredColorScheme(.light)
}

#Preview("Import · Spreadsheet Validation (CSV/XLSX)") {
    ZStack {
        AdaColors.canvas
        ImportSheetView(
            store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork),
            initialCatalogRows: PreviewFixtures.makeSampleCatalogImportRows(),
            onDismiss: {}
        )
    }
    .frame(width: 820, height: 640)
    .preferredColorScheme(.light)
}
#endif
