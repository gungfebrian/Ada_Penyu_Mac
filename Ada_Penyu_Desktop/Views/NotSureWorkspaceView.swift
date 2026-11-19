import AppKit
import SwiftUI

struct NotSureWorkspaceView: View {
    @ObservedObject var store: AppStore
    let onOpenPractice: () -> Void

    @State private var selectedCaseID: UUID?
    @State private var showsReviewed = false

    private var pendingCount: Int { store.pendingNotSureCases.count }
    private var visibleCases: [EscalatedNotSureCase] {
        store.escalatedNotSureCases
            .filter { ($0.decision != .pending) == showsReviewed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if let item = store.escalatedNotSureCases.first(where: { $0.id == selectedCaseID }) {
                NotSureCaseDetail(store: store, item: item) {
                    showsReviewed = item.decision != .pending
                    selectedCaseID = nil
                }
                .id(item.id)
            } else {
                inbox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AdaColors.canvas)
        .foregroundStyle(AdaColors.ink)
        .onAppear(perform: openRequestedCase)
        .onChange(of: store.reviewNavigationTrigger) { _, _ in
            selectedCaseID = nil
            openRequestedCase()
        }
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                queueTab("Pending", count: pendingCount, reviewed: false)
                queueTab("Reviewed", count: store.escalatedNotSureCases.count - pendingCount, reviewed: true)
                Spacer(minLength: 0)
                Button(action: onOpenPractice) {
                    Label("Practice cases", systemImage: "graduationcap")
                }
                .buttonStyle(AdaPillButtonStyle(secondary: true))
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(showsReviewed ? "Reviewed cases" : "Identity awaiting confirmation")
                            .font(.system(size: 24, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Your review drafts and decisions are saved to this Mac. Only confirmed sightings appear on the map.")
                            .font(.system(size: 13))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = store.notSureQueueError {
                        HStack {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Retry", action: store.reloadNotSureQueue)
                        }
                        .adaCard(padding: 16)
                    }
                    if visibleCases.isEmpty {
                        emptyQueue
                    } else {
                        caseList
                    }
                }
                .padding(.vertical, 28)
            }
        }
        .padding(.horizontal, AdaLayout.pagePadding)
    }

    private var emptyQueue: some View {
        VStack(spacing: 0) {
            ContentUnavailableView(
                showsReviewed ? "No reviewed cases" : "No pending cases",
                systemImage: showsReviewed ? "checkmark.circle" : "tray",
                description: Text(showsReviewed
                    ? "Recorded recommendations and reviewed unknowns will appear here."
                    : "Import a photo in Photo ID and send it to Not Sure when the identity needs another look.")
            )
            if !showsReviewed {
                Button("Open Photo ID") { store.activeSection = .identification }
                    .buttonStyle(AdaPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .adaCard()
    }

    private func queueTab(_ title: String, count: Int, reviewed: Bool) -> some View {
        let selected = showsReviewed == reviewed
        return Button { showsReviewed = reviewed } label: {
            HStack(spacing: 8) {
                Text(title).fontWeight(selected ? .semibold : .medium)
                Text(count, format: .number).monospacedDigit().foregroundStyle(AdaColors.secondaryInk)
            }
            .font(.system(size: 13))
            .foregroundStyle(selected ? AdaColors.ink : AdaColors.secondaryInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(selected ? AdaColors.navy : .clear).frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) cases")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var caseList: some View {
        let cases = visibleCases
        return LazyVStack(spacing: 0) {
            ForEach(cases) { item in
                Button { selectedCaseID = item.id } label: {
                    HStack(spacing: 18) {
                        HStack(spacing: 8) {
                            NotSureThumbnail(image: item.queryImage, size: 76)
                            if let companion = item.companionImage {
                                NotSureThumbnail(image: companion, size: 76)
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text("\(item.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(item.side.title) · \(candidateCountLabel(for: item))")
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                            Text(item.isExample ? "Example case" : "Submitted by \(item.submittedBy)")
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        NotSureStatusPill(title: item.decision.title)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                if item.id != cases.last?.id { Divider().padding(.horizontal, 22) }
            }
        }
        .adaCard(padding: 0)
    }

    private func candidateCountLabel(for item: EscalatedNotSureCase) -> String {
        let count = item.candidates.count
        return count == 1 ? "1 candidate" : "\(count.formatted()) candidates"
    }

    private func openRequestedCase() {
        guard let requested = store.requestedEscalatedCaseID else { return }
        store.requestedEscalatedCaseID = nil
        guard let item = store.escalatedNotSureCases.first(where: { $0.id == requested }) else { return }
        showsReviewed = item.decision != .pending
        selectedCaseID = item.id
    }
}

private struct NotSureCaseDetail: View {
    private enum Evidence: String, CaseIterable {
        case photos = "Photos"
        case contours = "Pattern studio"
        case photoContours = "Photo contours"
        case scales = "Numbered scales"
    }
    private enum CandidateFilter: String, CaseIterable { case available = "Available", sameSide = "Same side", rejected = "Rejected" }
    private enum Decision: Identifiable {
        case match(id: String, name: String), unknown

        var id: String {
            switch self {
            case .match(let id, _): id
            case .unknown: "unknown"
            }
        }

        var title: String {
            switch self {
            case .match(_, let name): "Recommend \(name)?"
            case .unknown: "Complete review as unknown?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .match: "Record recommendation"
            case .unknown: "Save as reviewed unknown"
            }
        }

        func action(note: String) -> NotSureReviewAction {
            switch self {
            case .match(let id, _): .recommend(id, note: note)
            case .unknown: .resolveUnknown(note: note)
            }
        }
    }

    @ObservedObject var store: AppStore
    let item: EscalatedNotSureCase
    let onBack: () -> Void

    @StateObject private var scaleReviews = ScaleReviewStore()
    @State private var evidence: Evidence = .photos
    @State private var candidateFilter: CandidateFilter = .available
    @State private var selectedCandidateID = ""
    @State private var studioMode: PatternStudioMode = .oneToOne
    @State private var contourSettings: ContourSettings
    @State private var noteDraft: String
    @State private var inlineError: String?
    @State private var foundNoCandidates = false
    @State private var searchRequest: UUID?
    @State private var isSearching = false
    @State private var confirmation: Decision?
    @State private var showsCompanion = false
    @State private var showsUnsavedNoteAlert = false
    private let initialShowScaleNumbers: Bool

    init(store: AppStore, item: EscalatedNotSureCase, onBack: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.onBack = onBack
        self._noteDraft = State(initialValue: item.note)
        let defaults = store.contourPreferences.preferences
        self.initialShowScaleNumbers = defaults.showScaleNumbers
        self._contourSettings = State(initialValue: defaults.makeContourSettings(
            enabled: true,
            querySide: item.side,
            gallerySide: item.side
        ))
    }

    private var isPending: Bool { item.decision == .pending }
    private var liveSearchAvailable: Bool { isPending && store.isAuthenticated && !store.isDemoBypassActive && !item.isExample }
    private var filteredCandidates: [EscalatedNotSureCandidate] {
        item.candidates.filter { candidate in
            let rejected = item.rejectedCandidateIDs.contains(candidate.id)
            switch candidateFilter {
            case .available: return !rejected
            case .sameSide: return !rejected && candidate.sideMatches
            case .rejected: return rejected
            }
        }
    }
    private var selectedCandidate: EscalatedNotSureCandidate? {
        let preferred = selectedCandidateID.isEmpty ? item.recommendedCandidateID : selectedCandidateID
        return filteredCandidates.first { $0.id == preferred }
            ?? filteredCandidates.first(where: { $0.sideMatches && $0.image != nil })
            ?? filteredCandidates.first
    }
    private var studioCandidates: [EscalatedNotSureCandidate] {
        let top = Array(filteredCandidates.prefix(3))
        guard let selectedCandidate, !top.contains(where: { $0.id == selectedCandidate.id }) else { return top }
        return top + [selectedCandidate]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    comparisonCard
                    notesCard
                }
                .padding(.vertical, 18)
            }
            Divider()
            if let inlineError { errorLabel(inlineError).padding(.top, 10) }
            decisionBar
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .task(id: searchRequest) {
            guard searchRequest != nil else { return }
            await findCandidates()
        }
        .onChange(of: selectedCandidate?.side) { _, newSide in
            contourSettings.gallerySide = newSide ?? item.side
        }
        .sheet(item: $confirmation) { decision in
            decisionSheet(decision)
        }
        .sheet(isPresented: $showsCompanion) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Other side").font(.headline)
                    Spacer()
                    Button("Done") { showsCompanion = false }.keyboardShortcut(.cancelAction)
                }
                if let image = item.companionImage {
                    Image(nsImage: image).resizable().scaledToFit()
                        .accessibilityLabel("Photograph of the other side")
                }
            }
            .padding(24)
            .frame(width: 620, height: 470)
        }
        .alert("Save your review note?", isPresented: $showsUnsavedNoteAlert) {
            Button("Save and return") {
                if perform(.saveNote(noteDraft)) { onBack() }
            }
            Button("Discard unsaved note", role: .destructive, action: onBack)
            Button("Continue reviewing", role: .cancel) { }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if noteDraft != item.note { showsUnsavedNoteAlert = true }
                else { onBack() }
            } label: {
                Label("Back to queue", systemImage: "chevron.left")
            }
            .buttonStyle(AdaPillButtonStyle(secondary: true))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Text(caseMetadata)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer(minLength: 0)
                NotSureStatusPill(title: item.decision.title)
            }
            if item.decision == .recommendedMatch,
               let candidate = item.candidates.first(where: { $0.id == item.recommendedCandidateID }) {
                Label("Recommended match: \(candidateLabel(candidate))", systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.vertical, 12)
    }

    private var caseMetadata: String {
        let source = item.isExample ? "Example case" : "Submitted by \(item.submittedBy)"
        return "\(item.side.title) · \(source) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Compare evidence").font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
                Picker("Evidence view", selection: $evidence) {
                    ForEach(Evidence.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            comparison
            if let companion = item.companionImage {
                Button { showsCompanion = true } label: {
                    HStack(spacing: 8) {
                        NotSureThumbnail(image: companion, size: 36)
                        Label("View other side", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            candidateList
        }
        .adaCard()
    }

    @ViewBuilder private var comparison: some View {
        switch evidence {
        case .photos:
            HStack(alignment: .top, spacing: 12) {
                photoPanel(title: "Submitted photo · \(item.side.title)", image: item.queryImage, empty: "Photo unavailable")
                photoPanel(
                    title: selectedCandidate.map { "\($0.name) · \($0.side.title)" } ?? "Gallery reference",
                    image: selectedCandidate?.image,
                    empty: selectedCandidate == nil ? "Select a candidate to compare" : "Reference photo unavailable"
                )
            }
        case .contours:
            PatternContourStudioView(
                query: PatternComparisonTarget(
                    id: item.id.uuidString, rank: 0, title: item.title, subtitle: item.side.title,
                    side: item.side, sideMatches: true, image: item.queryImage, sampleEntry: nil,
                    fingerprint: item.queryFingerprint, customROI: item.queryROI.count >= 3 ? item.queryROI : nil
                ),
                candidates: studioCandidates.map(studioTarget),
                selectedCandidateID: Binding(get: { selectedCandidate?.id ?? "" }, set: { selectedCandidateID = $0 }),
                mode: $studioMode,
                initialShowNumbers: initialShowScaleNumbers
            )
            .frame(height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .photoContours:
            ContourComparisonView(
                queryImage: item.queryImage,
                galleryImage: selectedCandidate?.image,
                settings: $contourSettings,
                queryTitle: "\(item.title) · \(item.side.title)",
                galleryTitle: selectedCandidate.map { "\($0.name) · \($0.side.title)" } ?? "Gallery reference",
                showsVisibilityControl: false
            )
            .frame(height: 410)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .scales:
            ScaleReviewComparisonView(
                queryImage: item.queryImage,
                galleryImage: selectedCandidate?.image,
                store: scaleReviews,
                initialShowsNumbers: initialShowScaleNumbers
            )
                .frame(height: 440)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func photoPanel(title: String, image: NSImage?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            ZStack {
                AdaColors.canvas
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().accessibilityLabel(title)
                } else {
                    Label(empty, systemImage: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 215)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func studioTarget(_ candidate: EscalatedNotSureCandidate) -> PatternComparisonTarget {
        PatternComparisonTarget(
            id: candidate.id, rank: candidate.rank, title: candidate.name, subtitle: candidate.evidenceLabel,
            side: candidate.side, sideMatches: candidate.sideMatches, image: candidate.image,
            sampleEntry: candidate.sampleImageName.flatMap { I3SSampleLibrary.sample(forFilenameOrID: $0) },
            fingerprint: candidate.fingerprint, customROI: nil
        )
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Candidates").font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                if !item.candidates.isEmpty {
                    Picker("Candidate filter", selection: $candidateFilter) {
                        ForEach(CandidateFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if liveSearchAvailable {
                    Button(item.candidates.isEmpty ? "Find candidates" : "Search again") { searchRequest = UUID() }
                        .disabled(isSearching)
                }
                if isSearching { ProgressView().controlSize(.small).accessibilityLabel("Searching gallery") }
            }
            if filteredCandidates.isEmpty {
                Text(candidateEmptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.vertical, 10)
            } else {
                ForEach(filteredCandidates) { candidate in candidateRow(candidate) }
            }
        }
    }

    private var candidateEmptyMessage: String {
        if foundNoCandidates { return "The gallery search returned no candidates for this photo." }
        if item.candidates.isEmpty { return "No candidate references in this case." }
        switch candidateFilter {
        case .available: return "All candidates have been rejected. Choose Rejected to inspect or restore them."
        case .sameSide: return "No available candidates show the same side."
        case .rejected: return "No rejected candidates."
        }
    }

    private func candidateRow(_ candidate: EscalatedNotSureCandidate) -> some View {
        let selected = selectedCandidate?.id == candidate.id
        let rejected = item.rejectedCandidateIDs.contains(candidate.id)
        return HStack(spacing: 8) {
            Button { selectedCandidateID = candidate.id } label: {
                HStack(spacing: 10) {
                    NotSureThumbnail(image: candidate.image, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidateLabel(candidate))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("\(candidate.sideMatches ? "Same side" : "Different side") · \(candidate.evidenceLabel)")
                            .font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    if candidate.id == item.recommendedCandidateID { NotSureStatusPill(title: "Recommended") }
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(AdaColors.navy)
                        .accessibilityHidden(true)
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if isPending && !isSearching {
                Button(rejected ? "Restore" : "Reject") {
                    perform(rejected ? .restoreCandidate(candidate.id) : .rejectCandidate(candidate.id))
                }
                .accessibilityLabel("\(rejected ? "Restore" : "Reject") \(candidate.name)")
                .padding(.trailing, 8)
            }
        }
        .background(selected ? AdaColors.accentSoft : AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10))
    }

    private func candidateLabel(_ candidate: EscalatedNotSureCandidate) -> String {
        candidate.profileCode.isEmpty ? candidate.name : "\(candidate.name) · \(candidate.profileCode)"
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review note").font(.system(size: 15, weight: .semibold))
            if isPending {
                noteEditor
                Button("Save note") { perform(.saveNote(noteDraft)) }
                    .disabled(noteDraft == item.note)
            } else {
                Text(item.note).font(.system(size: 13)).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard()
    }

    private var noteEditor: some View {
        TextEditor(text: $noteDraft)
            .font(.system(size: 13))
            .foregroundStyle(AdaColors.ink)
            .scrollContentBackground(.hidden)
            .frame(height: 88)
            .padding(8)
            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Review note")
    }

    private var decisionBar: some View {
        HStack(spacing: 10) {
            Text(decisionContext)
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)
            Spacer(minLength: 0)
            if isPending {
                Button("Complete as unknown…") { confirm(.unknown) }
                    .buttonStyle(.bordered)
                    .disabled(isSearching)
                if let selectedCandidate, item.canRecommend(selectedCandidate) {
                    Button("Recommend match…") { confirm(.match(id: selectedCandidate.id, name: selectedCandidate.name)) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSearching)
                }
            } else {
                Button("Reopen review") { perform(.reopen) }
                    .buttonStyle(.bordered)
            }
        }
        .tint(AdaColors.navy)
        .controlSize(.large)
        .padding(.vertical, 10)
    }

    private var decisionContext: String {
        if !isPending { return "Reviewed \(item.updatedAt.formatted(date: .abbreviated, time: .omitted))" }
        if let selectedCandidate, !item.canRecommend(selectedCandidate) {
            return "A recommendation needs an available same-side reference photo."
        }
        return "Review decisions are saved on this Mac."
    }

    private func decisionSheet(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(decision.title).font(.title2.weight(.semibold))
            Text("This saves a local review decision with your supporting note.")
                .font(.system(size: 13)).foregroundStyle(AdaColors.secondaryInk)
            Text("What evidence supports this decision?").font(.system(size: 13, weight: .semibold))
            noteEditor
            if let inlineError { errorLabel(inlineError) }
            HStack {
                Spacer()
                Button("Cancel") { confirmation = nil }.keyboardShortcut(.cancelAction)
                Button(decision.buttonTitle) {
                    if perform(decision.action(note: noteDraft)) { confirmation = nil }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .foregroundStyle(AdaColors.ink)
        .tint(AdaColors.navy)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12))
            .foregroundStyle(AdaColors.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confirm(_ decision: Decision) {
        inlineError = nil
        confirmation = decision
    }

    @discardableResult private func perform(_ action: NotSureReviewAction) -> Bool {
        do {
            try store.updateNotSureCase(item.id, action: action)
            inlineError = nil
            switch action {
            case .saveNote, .recommend, .resolveUnknown:
                noteDraft = store.escalatedNotSureCases.first(where: { $0.id == item.id })?.note ?? noteDraft
            case .rejectCandidate, .restoreCandidate, .reopen:
                break
            }
            return true
        } catch {
            inlineError = error.localizedDescription
            return false
        }
    }

    private func findCandidates() async {
        guard liveSearchAvailable, !isSearching else { return }
        isSearching = true
        inlineError = nil
        foundNoCandidates = false
        defer { isSearching = false }
        do {
            try await store.findNotSureCandidates(for: item.id)
            guard !Task.isCancelled else { return }
            candidateFilter = .available
            foundNoCandidates = store.escalatedNotSureCases.first { $0.id == item.id }?.candidates.isEmpty == true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            inlineError = error.localizedDescription
        }
    }
}

private struct NotSureThumbnail: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            AdaColors.canvas
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(AdaColors.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }
}

private struct NotSureStatusPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(AdaColors.ink)
            .background(AdaColors.surfaceMuted, in: Capsule())
            .fixedSize()
    }
}

#if DEBUG
#Preview("Not Sure Queue · Inbox") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true),
        onOpenPractice: {}
    )
    .frame(width: 1280, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure Queue · Case Detail") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {}
    )
    .frame(width: 1280, height: 840)
    .preferredColorScheme(.light)
}
#endif
