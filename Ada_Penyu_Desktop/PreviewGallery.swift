#if DEBUG
import AppKit
import SwiftUI

/// Shared fixtures and isolated store builders for Xcode Canvas `#Preview` pages.
/// Every preview uses an ephemeral `NotSureReviewJournal` directory so previewing
/// never writes into the user's Application Support folder.
@MainActor
enum PreviewFixtures {
    static var injuredTurtle: Turtle {
        DemoFixtures.turtles.first { $0.condition == .injured } ?? DemoFixtures.turtles[0]
    }

    static var photoLoader: @MainActor (String?) async -> NSImage? {
        { path in
            guard let path, !path.isEmpty else { return nil }
            let filename = (path as NSString).lastPathComponent
            if let image = I3SSampleLibrary.loadImage(named: filename) {
                return image
            }
            if let image = I3SSampleLibrary.loadImage(named: path) {
                return image
            }
            return I3SSampleLibrary.loadImage(named: "Amina1_L.jpg")
        }
    }

    static func makeSampleDetail(for turtle: Turtle? = nil) -> TurtleDetailData {
        let target = turtle ?? injuredTurtle
        let primarySightingID = "preview-sighting-1"
        let secondarySightingID = "preview-sighting-2"
        let photoPaths = [target.leftPhotoURL, target.rightPhotoURL].compactMap { $0 }

        let measurements: [TurtleMeasurement] = [
            TurtleMeasurement(
                id: primarySightingID,
                date: target.lastSeen,
                length: 92.4,
                width: 81.6,
                weight: 104.2
            ),
            TurtleMeasurement(
                id: secondarySightingID,
                date: "2026-09-18",
                length: 91.8,
                width: 81.0,
                weight: 102.5
            ),
        ]

        let logs: [TurtleLogSummary] = [
            TurtleLogSummary(
                id: primarySightingID,
                date: target.lastSeen,
                location: target.location,
                status: "Sighting · \(target.species.rawValue)",
                condition: target.condition,
                notes: "Resighted cruising shallow coral shelf; clear left & right facial scale capture.",
                coordinate: target.coordinate,
                photoPaths: photoPaths
            ),
            TurtleLogSummary(
                id: secondarySightingID,
                date: "2026-09-18",
                location: "Crystal Bay, Nusa Penida",
                status: "Sighting · \(target.species.rawValue)",
                condition: .scarred,
                notes: "Previous encounter logged during morning reef transect.",
                coordinate: TurtleCoordinate(latitude: -8.7142, longitude: 115.4581),
                photoPaths: photoPaths
            ),
            TurtleLogSummary(
                id: "preview-marking-1",
                date: target.lastSeen,
                location: target.location,
                status: "Injury · Right Flipper",
                condition: .injured,
                notes: "Fresh fishing-line abrasion along trailing edge; swimming normally.",
                coordinate: target.coordinate,
                bodyPart: .flipperRight,
                markingSeverity: "Moderate",
                sourceSightingID: primarySightingID,
                photoPaths: Array(photoPaths.prefix(1))
            ),
            TurtleLogSummary(
                id: "preview-marking-2",
                date: "2026-09-18",
                location: "Crystal Bay, Nusa Penida",
                status: "Scar · Carapace",
                condition: .scarred,
                notes: "Healed notch on posterior marginal scutes.",
                coordinate: TurtleCoordinate(latitude: -8.7142, longitude: 115.4581),
                bodyPart: .carapace,
                markingSeverity: "Mild",
                sourceSightingID: secondarySightingID,
                photoPaths: Array(photoPaths.prefix(1))
            ),
            TurtleLogSummary(
                id: "preview-marking-3",
                date: target.lastSeen,
                location: target.location,
                status: "Healthy · Head",
                condition: .healthy,
                notes: "Postocular scales crisp and free of fibropapilloma or barnacle growth.",
                coordinate: target.coordinate,
                bodyPart: .head,
                markingSeverity: "Clear",
                sourceSightingID: primarySightingID,
                photoPaths: Array(photoPaths.prefix(1))
            ),
        ]

        return TurtleDetailData(turtle: target, measurements: measurements, logs: logs)
    }

    static func makeSampleNotSureCases() -> [EscalatedNotSureCase] {
        let queryLeft = samplePhoto(named: "Amina3_L.jpg", fallbackColor: .systemTeal)
        let queryRightCompanion = samplePhoto(named: "Amina1_R.jpg", fallbackColor: .systemBlue)
        let refSurya = samplePhoto(named: "Aikane2_L.jpg", fallbackColor: .systemOrange)
        let refAmina = samplePhoto(named: "Amina1_L.jpg", fallbackColor: .systemGreen)
        let refGhost = samplePhoto(named: "Ghost1_L.jpg", fallbackColor: .systemPurple)

        let case1 = EscalatedNotSureCase(
            title: "Crystal Bay · Sighting #S-2026-114",
            side: .left,
            photo: queryLeft,
            companion: queryRightCompanion,
            queryFingerprint: nil,
            queryROI: [],
            candidates: [
                EscalatedNotSureCandidate(
                    id: "00000000-0000-4000-8000-000000000002",
                    rank: 1,
                    name: "Turtle #002 · Aikane",
                    profileCode: "000002",
                    side: .left,
                    sideMatches: true,
                    dateText: "14 Aug 2026",
                    location: "Toyapakeh",
                    confidencePercent: 84,
                    photo: refSurya,
                    sampleImageName: "Aikane2_L.jpg",
                    fingerprint: nil,
                    isBundledExample: true
                ),
                EscalatedNotSureCandidate(
                    id: "00000000-0000-4000-8000-000000000001",
                    rank: 2,
                    name: "Turtle #001 · Amina",
                    profileCode: "000001",
                    side: .left,
                    sideMatches: true,
                    dateText: "03 May 2026",
                    location: "Crystal Bay",
                    confidencePercent: 79,
                    photo: refAmina,
                    sampleImageName: "Amina1_L.jpg",
                    fingerprint: nil,
                    isBundledExample: true
                ),
                EscalatedNotSureCandidate(
                    id: "00000000-0000-4000-8000-000000000003",
                    rank: 3,
                    name: "Turtle #003 · Ghost",
                    profileCode: "000003",
                    side: .left,
                    sideMatches: true,
                    dateText: "12 Jun 2026",
                    location: "Manta Point",
                    confidencePercent: 68,
                    photo: refGhost,
                    sampleImageName: "Ghost1_L.jpg",
                    fingerprint: nil,
                    isBundledExample: true
                ),
            ],
            submittedBy: "Mobile Patrol",
            isExample: true,
            sourceLogID: UUID(uuidString: "00000000-0000-4000-8999-000000000114")
        )

        let queryRight = samplePhoto(named: "Zizo1_R.jpg", fallbackColor: .systemBlue)
        let refZizo = samplePhoto(named: "Zizo2_R.jpg", fallbackColor: .systemIndigo)
        let case2 = EscalatedNotSureCase(
            title: "Mangrove Point · Sighting #S-2026-118",
            side: .right,
            photo: queryRight,
            companion: nil,
            queryFingerprint: nil,
            queryROI: [],
            candidates: [
                EscalatedNotSureCandidate(
                    id: "00000000-0000-4000-8000-000000000004",
                    rank: 1,
                    name: "Turtle #004 · Zizo",
                    profileCode: "000004",
                    side: .right,
                    sideMatches: true,
                    dateText: "22 Jul 2026",
                    location: "Mangrove Point",
                    confidencePercent: 76,
                    photo: refZizo,
                    sampleImageName: "Zizo2_R.jpg",
                    fingerprint: nil,
                    isBundledExample: true
                ),
            ],
            submittedBy: "Ranger Kadek",
            isExample: true
        )

        return [case1, case2]
    }

    static func makeDemoStore(
        persona: DemoDashboardPersona = .worldSuperNetwork,
        section: AppSection = .dashboard,
        withNotSureCases: Bool = false,
        openFirstNotSureCase: Bool = false
    ) -> AppStore {
        let previewDir = FileManager.default.temporaryDirectory
            .appending(path: "AdaPenyu-Previews-\(UUID().uuidString)", directoryHint: .isDirectory)
        let journal = NotSureReviewJournal(directory: previewDir)
        let suiteName = "ada.penyu.preview.\(UUID().uuidString)"
        let layoutStore = DashboardLayoutStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        let store = AppStore(
            dashboardLayoutStore: layoutStore,
            reviewJournal: journal
        )
        store.enterDemoWorkspace(persona: persona)
        if withNotSureCases {
            let cases = makeSampleNotSureCases()
            for item in cases.reversed() {
                try? store.escalateToNotSureReview(item)
            }
            if openFirstNotSureCase, let firstID = cases.first?.id {
                store.openNotSureReview(caseID: firstID)
            } else {
                store.requestedEscalatedCaseID = nil
            }
        }
        store.activeSection = section
        return store
    }

    private static func samplePhoto(named filename: String, fallbackColor: NSColor) -> NotSureReviewPhoto {
        if let data = I3SSampleLibrary.loadImageData(named: filename) {
            return NotSureReviewPhoto(data: data)
        }
        let image = NSImage(size: NSSize(width: 240, height: 180))
        image.lockFocus()
        fallbackColor.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: 0, width: 240, height: 180).fill()
        image.unlockFocus()
        return NotSureReviewPhoto(snapshot: image) ?? NotSureReviewPhoto(data: Data())
    }

    static func makeSampleImportPhotos() -> [StagedImportPhoto] {
        let now = Date()
        let aminaL = samplePhoto(named: "Amina1_L.jpg", fallbackColor: .systemTeal).data
        let aminaR = samplePhoto(named: "Amina1_R.jpg", fallbackColor: .systemBlue).data
        let aikaneL = samplePhoto(named: "Aikane2_L.jpg", fallbackColor: .systemOrange).data
        let zizoR = samplePhoto(named: "Zizo1_R.jpg", fallbackColor: .systemIndigo).data

        return [
            StagedImportPhoto(
                filename: "CrystalBay_01_L.HEIC",
                originalFormat: "HEIC",
                jpegData: aminaL,
                pixelWidth: 1600,
                pixelHeight: 1200,
                capturedAt: now.addingTimeInterval(-3600),
                coordinate: TurtleCoordinate(latitude: -8.7142, longitude: 115.4581),
                side: .left,
                sideWasInferred: true,
                pairStem: "CrystalBay_01"
            ),
            StagedImportPhoto(
                filename: "CrystalBay_01_R.HEIC",
                originalFormat: "HEIC",
                jpegData: aminaR,
                pixelWidth: 1600,
                pixelHeight: 1200,
                capturedAt: now.addingTimeInterval(-3540),
                coordinate: TurtleCoordinate(latitude: -8.7142, longitude: 115.4581),
                side: .right,
                sideWasInferred: true,
                pairStem: "CrystalBay_01"
            ),
            StagedImportPhoto(
                filename: "Toyapakeh_Reef.png",
                originalFormat: "PNG",
                jpegData: aikaneL,
                pixelWidth: 1280,
                pixelHeight: 960,
                capturedAt: now.addingTimeInterval(-7200),
                coordinate: nil,
                side: .left,
                sideWasInferred: false,
                pairStem: "Toyapakeh_Reef"
            ),
            StagedImportPhoto(
                filename: "Mangrove_09_R.jpg",
                originalFormat: "JPG",
                jpegData: zizoR,
                pixelWidth: 1400,
                pixelHeight: 1050,
                capturedAt: now.addingTimeInterval(-10800),
                coordinate: TurtleCoordinate(latitude: -8.6725, longitude: 115.4612),
                side: .right,
                sideWasInferred: true,
                pairStem: "Mangrove_09"
            ),
        ]
    }

    static func makeSampleCatalogImportRows() -> [StagedCatalogRow] {
        let now = Date()
        return [
            StagedCatalogRow(
                id: UUID(), rowNumber: 2, profileCode: "004201", name: "Kadek",
                species: .green, sex: "female", firstSeenAt: now,
                location: "Crystal Bay, Bali", coordinate: TurtleCoordinate(latitude: -8.7142, longitude: 115.4581),
                condition: .healthy, leftPhotoFilename: "Kadek_L.heic", rightPhotoFilename: "Kadek_R.heic",
                validationError: nil
            ),
            StagedCatalogRow(
                id: UUID(), rowNumber: 3, profileCode: "004202", name: "Nusa",
                species: .hawksbill, sex: "unknown", firstSeenAt: now,
                location: "Toyapakeh, Bali", coordinate: TurtleCoordinate(latitude: -8.6850, longitude: 115.4790),
                condition: .scarred, leftPhotoFilename: "Nusa_L.jpg", rightPhotoFilename: nil,
                validationError: nil
            ),
            StagedCatalogRow(
                id: UUID(), rowNumber: 4, profileCode: "BAD-ID", name: "Manta",
                species: .oliveRidley, sex: "male", firstSeenAt: now,
                location: "Sanur Reef", coordinate: nil,
                condition: .healthy, leftPhotoFilename: nil, rightPhotoFilename: nil,
                validationError: "Code must be 6 digits"
            ),
        ]
    }
}

/// Interactive wrapper that boots a demo `AppStore` on the requested section inside `ContentView`.
struct PreviewDemoShell: View {
    @StateObject private var store: AppStore

    init(
        persona: DemoDashboardPersona = .worldSuperNetwork,
        section: AppSection = .dashboard,
        withNotSureCases: Bool = false,
        openFirstNotSureCase: Bool = false
    ) {
        _store = StateObject(
            wrappedValue: PreviewFixtures.makeDemoStore(
                persona: persona,
                section: section,
                withNotSureCases: withNotSureCases,
                openFirstNotSureCase: openFirstNotSureCase
            )
        )
    }

    var body: some View {
        ContentView(store: store)
    }
}

// MARK: - Complete Preview Gallery (Open this file in Xcode Canvas to browse every screen)

#Preview("01 · App Overview (World Super Account)") {
    PreviewDemoShell(persona: .worldSuperNetwork, section: .dashboard)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("02 · Map · World H3 Hex Grid") {
    PreviewDemoShell(persona: .worldSuperNetwork, section: .map)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("03 · Map · Bali Local Pins") {
    PreviewDemoShell(persona: .demoResearcher, section: .map)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("04 · Not Sure Queue · Inbox") {
    PreviewDemoShell(
        persona: .worldSuperNetwork,
        section: .scientistReview,
        withNotSureCases: true,
        openFirstNotSureCase: false
    )
    .frame(width: 1440, height: 900)
    .preferredColorScheme(.light)
}

#Preview("05 · Not Sure · Compare (Paired L/R)") {
    PreviewDemoShell(
        persona: .worldSuperNetwork,
        section: .scientistReview,
        withNotSureCases: true,
        openFirstNotSureCase: true
    )
    .frame(width: 1440, height: 900)
    .preferredColorScheme(.light)
}

#Preview("05b · Not Sure · Contours # (Zero .fgp)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(
            persona: .worldSuperNetwork,
            section: .scientistReview,
            withNotSureCases: true,
            openFirstNotSureCase: true
        ),
        onOpenPractice: {},
        initialStageMode: .contours
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("05c · Not Sure · Align (3-Tap Warp)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(
            persona: .worldSuperNetwork,
            section: .scientistReview,
            withNotSureCases: true,
            openFirstNotSureCase: true
        ),
        onOpenPractice: {},
        initialStageMode: .align
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("06 · Practice Review · Pattern 1 vs 3") {
    ScientistReviewWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview)
    )
    .frame(width: 1440, height: 900)
    .preferredColorScheme(.light)
}

#Preview("07 · Details · Turtle Profile") {
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
        originTitle: "Sea Turtles",
        isFavorite: isFavorite,
        onToggleFavorite: { isFavorite.toggle() }
    )
    .background(AdaColors.canvas)
    .environment(\.turtlePhotoLoader, PreviewFixtures.photoLoader)
    .frame(width: 1220, height: 860)
    .preferredColorScheme(.light)
}

#Preview("08 · Details · Sighting Details") {
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
        isFavorite: true,
        onToggleFavorite: {}
    )
    .background(AdaColors.canvas)
    .environment(\.turtlePhotoLoader, PreviewFixtures.photoLoader)
    .frame(width: 1220, height: 860)
    .preferredColorScheme(.light)
}

#Preview("09 · Details · Body Condition Diagram") {
    let detail = PreviewFixtures.makeSampleDetail()

    ScrollView {
        BodyConditionTab(logs: detail.logs, onExport: {}, onOpenSighting: { _ in })
            .padding(24)
    }
    .background(AdaColors.canvas)
    .environment(\.turtlePhotoLoader, PreviewFixtures.photoLoader)
    .frame(width: 1120, height: 740)
    .preferredColorScheme(.light)
}

#Preview("10 · Import & Export · I3S Pattern ID") {
    PreviewDemoShell(persona: .demoResearcher, section: .identification)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("11 · Export Data Modal") {
    ZStack {
        AdaColors.canvas
        ExportSheet(query: IndividualQuery(), resultCount: 45, onCancel: {}, onExport: { _ in })
    }
    .frame(width: 640, height: 600)
    .preferredColorScheme(.light)
}

#Preview("11b · Import · Dropzone (HEIC / JPG / PNG / CSV / XLSX)") {
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

#Preview("11c · Import · Batch Photos (Paired L+R + HEIC)") {
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

#Preview("11d · Import · Spreadsheet Validation (CSV / XLSX)") {
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

#Preview("12 · Sea Turtles Catalog") {
    PreviewDemoShell(persona: .worldSuperNetwork, section: .individuals)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("13 · Sightings List") {
    PreviewDemoShell(persona: .worldSuperNetwork, section: .sightings)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("14 · Settings") {
    PreviewDemoShell(persona: .demoResearcher, section: .settings)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("15 · Sign In") {
    AccountLoginView(store: AppStore())
        .frame(width: 1200, height: 800)
        .preferredColorScheme(.light)
}
#endif
