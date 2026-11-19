import MapKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class MacAppAuditTests: XCTestCase {
    override func tearDown() {
        BackendStub.handler = nil
        BackendStub.responseDelay = nil
        super.tearDown()
    }

    // MARK: - Import & Export

    func testDemoCSVExportHonorsScopeRangeAndFields() async throws {
        let repo = DemoTurtleRepository(dataset: .baliBaseline)

        let allCSV = try await repo.export(ExportRequest(
            scope: .all,
            range: .all,
            fields: Set(ExportField.allCases),
            format: .csv,
            query: IndividualQuery(species: [.hawksbill])
        ))
        let allText = try XCTUnwrap(String(data: allCSV.data, encoding: .utf8))
        XCTAssertTrue(allCSV.filename.hasSuffix(".csv"))
        XCTAssertTrue(allText.contains("Profile Code"))
        XCTAssertTrue(allText.contains("CCL (cm)"))
        XCTAssertTrue(allText.contains("Latitude"))
        // Scope `.all` ignores species filter and exports every Bali turtle
        let allRows = allText.split(whereSeparator: \.isNewline)
        XCTAssertEqual(allRows.count, DemoFixtures.turtles.count + 1)

        let filteredCSV = try await repo.export(ExportRequest(
            scope: .currentView,
            range: .all,
            fields: [.profile],
            format: .csv,
            query: IndividualQuery(species: [.hawksbill])
        ))
        let filteredText = try XCTUnwrap(String(data: filteredCSV.data, encoding: .utf8))
        XCTAssertFalse(filteredText.contains("CCL (cm)"))
        let hawksbillCount = DemoFixtures.turtles.filter { $0.species == .hawksbill }.count
        let filteredRows = filteredText.split(whereSeparator: \.isNewline)
        XCTAssertEqual(filteredRows.count, hawksbillCount + 1)
    }

    func testDemoXLSXExportBuildsValidOOXMLArchive() async throws {
        let repo = DemoTurtleRepository(dataset: .worldSuperAccount)
        let file = try await repo.export(ExportRequest(
            scope: .all,
            range: .all,
            fields: [.profile, .coordinates],
            format: .xlsx,
            query: IndividualQuery()
        ))

        XCTAssertTrue(file.filename.hasSuffix(".xlsx"))
        // ZIP local file header signature "PK\x03\x04"
        XCTAssertGreaterThan(file.data.count, 500)
        XCTAssertEqual(Array(file.data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let ascii = String(decoding: file.data, as: UTF8.self)
        XCTAssertTrue(ascii.contains("[Content_Types].xml"))
        XCTAssertTrue(ascii.contains("xl/workbook.xml"))
        XCTAssertTrue(ascii.contains("xl/worksheets/sheet1.xml"))
    }

    func testDemoPDFExportBuildsReadablePDFDocument() async throws {
        let repo = DemoTurtleRepository(dataset: .panAsiaSuperAccount)
        let file = try await repo.export(ExportRequest(
            scope: .all,
            range: .all,
            fields: [.profile, .conditionHistory],
            format: .pdf,
            query: IndividualQuery()
        ))

        XCTAssertTrue(file.filename.hasSuffix(".pdf"))
        XCTAssertTrue(file.data.starts(with: Data("%PDF-".utf8)))
        let doc = try XCTUnwrap(PDFDocument(data: file.data))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
        let extracted = doc.string ?? ""
        XCTAssertTrue(extracted.contains("ADA Penyu"))
    }

    func testContentDispositionFilenameParsing() {
        XCTAssertEqual(
            ExportFileBuilder.parseContentDispositionFilename("attachment; filename=\"turtles-2026.xlsx\"", fallback: "fallback.xlsx"),
            "turtles-2026.xlsx"
        )
        XCTAssertEqual(
            ExportFileBuilder.parseContentDispositionFilename("attachment; filename*=UTF-8''sea%20turtles%20bali.pdf", fallback: "fallback.pdf"),
            "sea turtles bali.pdf"
        )
        XCTAssertEqual(
            ExportFileBuilder.parseContentDispositionFilename("attachment; filename=\"../../etc/passwd.csv\"", fallback: "fallback.csv"),
            "passwd.csv"
        )
        XCTAssertEqual(
            ExportFileBuilder.parseContentDispositionFilename(nil, fallback: "fallback.csv"),
            "fallback.csv"
        )
    }

    func testExportAllowedContentTypesAndAcceptHeaders() {
        XCTAssertEqual(AppStore.allowedContentTypes(for: .csv), [.commaSeparatedText])
        XCTAssertEqual(AppStore.allowedContentTypes(for: .pdf), [.pdf])
        XCTAssertEqual(
            AppStore.allowedContentTypes(for: .xlsx).first?.preferredFilenameExtension,
            "xlsx"
        )
        XCTAssertEqual(ExportFormat.csv.acceptHeader, "text/csv, */*")
        XCTAssertEqual(
            ExportFormat.xlsx.acceptHeader,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, */*"
        )
        XCTAssertEqual(ExportFormat.pdf.acceptHeader, "application/pdf, */*")
    }

    func testRemoteExportScopeAllOmitsFiltersAndSendsAcceptHeader() async throws {
        var capturedRequest: URLRequest?
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url?.path == "/api/v1/exports/individuals" {
                capturedRequest = request
                return (200, Data("id,name\n1,Amina\n".utf8))
            }
            return (404, Data())
        }

        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: BackendStub.session(),
            credentialStore: MemoryCredentials()
        )
        _ = try await client.login(email: "person@example.test", password: "test-only-password", rememberMe: false)
        let repo = RemoteTurtleRepository(client: client)

        _ = try await repo.export(ExportRequest(
            scope: .all,
            range: .thirtyDays,
            fields: [.profile, .coordinates],
            format: .xlsx,
            query: IndividualQuery(
                search: "Amina",
                species: [.green],
                condition: .injured,
                page: PageRequest(limit: 10, offset: 20)
            )
        ))

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Accept"),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, */*"
        )
        let items = URLComponents(url: try XCTUnwrap(req.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let grouped = Dictionary(grouping: items, by: \.name).mapValues { $0.compactMap(\.value) }
        XCTAssertEqual(grouped["scope"], ["all"])
        XCTAssertEqual(grouped["format"], ["xlsx"])
        XCTAssertEqual(grouped["fields"], ["profile", "coordinates"])
        XCTAssertNil(grouped["q"])
        XCTAssertNil(grouped["species"])
        XCTAssertNil(grouped["condition"])
        XCTAssertNil(grouped["limit"])
        XCTAssertNil(grouped["offset"])
    }

    // MARK: - Details

    func testDemoDetailResolvesSparseReferenceAndLinksMeasurementsAndMarkings() async throws {
        let repo = DemoTurtleRepository(dataset: .baliBaseline)
        let sightings = try await repo.mapSightings(query: MapQuery(period: .allTime, species: nil, condition: nil, page: PageRequest(limit: 200)))
        let injuredSighting = try XCTUnwrap(sightings.first { $0.condition == .injured })

        // Passing the sparse sighting.turtleReference should resolve full catalog metadata
        let detail = try await repo.detail(for: injuredSighting.turtleReference)
        let sightingIDs = Set(detail.sightingLogs.map(\.id))

        XCTAssertFalse(detail.sightingLogs.isEmpty)
        XCTAssertFalse(detail.measurements.isEmpty)
        // Measurement ID must match a sighting log so "View source sighting" & SightingDetailsView work
        let latestMeasurement = try XCTUnwrap(detail.measurements.first)
        XCTAssertTrue(sightingIDs.contains(latestMeasurement.id))

        // Body-condition records must be populated and linked to a valid source sighting
        let markings = detail.logs.filter(\.isBodyConditionRecord)
        XCTAssertFalse(markings.isEmpty)
        for marking in markings {
            let sourceID = try XCTUnwrap(marking.sourceSightingID)
            XCTAssertTrue(sightingIDs.contains(sourceID))
        }
    }

    func testPanAsiaDemoFavoritesReturnsAllFourSeededIndividuals() async throws {
        let repo = DemoTurtleRepository(dataset: .panAsiaSuperAccount)
        let favorites = try await repo.listFavorites()
        XCTAssertEqual(favorites.count, 4)
    }

    func testMarkingConditionCoversAllV2Kinds() {
        func makeLog(status: String, condition: TurtleCondition? = nil) -> TurtleLogSummary {
            TurtleLogSummary(
                id: UUID().uuidString,
                date: "2026-10-01",
                location: "Crystal Bay",
                status: status,
                condition: condition,
                notes: nil,
                coordinate: nil,
                bodyPart: .carapace
            )
        }
        XCTAssertEqual(makeLog(status: "Missing Limb").markingCondition, .injured)
        XCTAssertEqual(makeLog(status: "Fibropapilloma").markingCondition, .injured)
        XCTAssertEqual(makeLog(status: "Barnacles").markingCondition, .scarred)
        XCTAssertEqual(makeLog(status: "Scratch").markingCondition, .scarred)
        XCTAssertEqual(makeLog(status: "Deformity").markingCondition, .scarred)
        XCTAssertEqual(makeLog(status: "Other").markingCondition, .scarred)
        XCTAssertEqual(makeLog(status: "Healthy").markingCondition, .healthy)
    }

    // MARK: - Maps

    func testDemoMapSightingsFiltersByPeriod() async throws {
        let repo = DemoTurtleRepository(dataset: .worldSuperAccount)
        let all = try await repo.mapSightings(query: MapQuery(period: .allTime, species: nil, condition: nil, page: PageRequest(limit: 200)))
        let year = try await repo.mapSightings(query: MapQuery(period: .twelveMonths, species: nil, condition: nil, page: PageRequest(limit: 200)))
        let month = try await repo.mapSightings(query: MapQuery(period: .thirtyDays, species: nil, condition: nil, page: PageRequest(limit: 200)))
        let week = try await repo.mapSightings(query: MapQuery(period: .sevenDays, species: nil, condition: nil, page: PageRequest(limit: 200)))

        XCTAssertFalse(all.isEmpty)
        XCTAssertLessThanOrEqual(week.count, month.count)
        XCTAssertLessThanOrEqual(month.count, year.count)
        XCTAssertLessThanOrEqual(year.count, all.count)
        // Strict narrowing: 7-day window should be smaller than full world all-time dataset
        XCTAssertLessThan(week.count, all.count)
    }

    func testMapFocusSpanExitsH3HexAggregationIntoPins() {
        let focusRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.7142, longitude: 115.4581),
            span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.30)
        )
        XCTAssertNil(H3SpatialIndex.resolution(for: focusRegion))
    }

    // MARK: - Not Sure & Practice Review

    func testScientistReviewDecisionClearsStaleConfirmedStatus() {
        let vm = ScientistReviewViewModel()
        vm.selectCandidate(at: 1) // Amina (isomorphic match)
        vm.confirmSameTurtleIdentity()
        XCTAssertEqual(vm.candidates[1].status, .confirmed)

        // Switching to "Save as Unsure" must clear previous confirmed candidate status
        vm.saveUnsureDecision()
        XCTAssertFalse(vm.candidates.contains { $0.status == .confirmed })
        XCTAssertEqual(vm.savedOutcomes[vm.activeScenario]?.resolution, .savedUnsure)
    }

    func testNotSureReviewJournalRoundTripAndWorkflow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "AdaPenyu-AuditTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let journal = NotSureReviewJournal(directory: tempDir)
        let sampleImage = NSImage(size: NSSize(width: 64, height: 64))
        sampleImage.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        sampleImage.unlockFocus()
        let photo = try XCTUnwrap(NotSureReviewPhoto(snapshot: sampleImage))

        var item = EscalatedNotSureCase(
            title: "Test Encounter",
            side: .left,
            photo: photo,
            companion: nil,
            queryFingerprint: nil,
            queryROI: [],
            candidates: [
                EscalatedNotSureCandidate(
                    id: "cand-1",
                    rank: 1,
                    name: "Turtle #007",
                    profileCode: "PEN-007",
                    side: .left,
                    sideMatches: true,
                    dateText: "2026-10-10",
                    location: "Crystal Bay",
                    confidencePercent: 85,
                    photo: photo,
                    sampleImageName: nil,
                    fingerprint: nil,
                    isBundledExample: false
                ),
            ],
            submittedBy: "Ranger Test",
            isExample: false
        )

        // Blank note should be rejected
        XCTAssertThrowsError(try item.apply(.recommend("cand-1", note: "   ")))
        try item.apply(.recommend("cand-1", note: "All 6 postocular junctions align."))
        XCTAssertEqual(item.decision, .recommendedMatch)
        XCTAssertEqual(item.recommendedCandidateID, "cand-1")

        try journal.save(item, scope: "test-scope")
        let loaded = try journal.load(scope: "test-scope")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.decision, .recommendedMatch)
        XCTAssertEqual(loaded.first?.recommendedCandidateID, "cand-1")

        try item.apply(.reopen)
        XCTAssertEqual(item.decision, .pending)
        XCTAssertNil(item.recommendedCandidateID)
    }
}
