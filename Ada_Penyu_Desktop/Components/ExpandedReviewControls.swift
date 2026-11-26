import SwiftUI

struct DesktopReviewProgressCard: View {
    let state: DesktopReviewState
    let isSearching: Bool
    let isBusy: Bool
    let onSearchAll: () -> Void
    let onStopWaiting: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(state.coveragePercent)% search · \(state.comparedCount)/\(state.eligibleCount) reference photos compared")
                .font(.system(size: 11, weight: .medium))
            Text("\(state.rejectedCandidateIDs.count)/\(state.candidateTotal) candidates ruled out")
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.secondaryInk)
            if state.excludedCount > 0 {
                Label("\(state.excludedCount) turtles could not be compared. Their references need attention before creating a turtle.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AdaColors.orange)
            }
            if isSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching reference photos…").font(.caption)
                    Spacer(minLength: 0)
                    Button("Stop waiting", action: onStopWaiting)
                        .font(.caption)
                        .help("The search may finish in the background. Reopen this case to retrieve its result.")
                }
            } else if state.coveragePercent == 70 {
                Button(action: onSearchAll) {
                    Text("Didn’t find a match? Search all")
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AdaColors.navy)
                .disabled(isBusy)
            }
        }
        .foregroundStyle(AdaColors.ink)
        .padding(10)
        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ReviewNewTurtleFields: View {
    @Binding var name: String
    @Binding var profileCode: String
    @Binding var species: TurtleSpecies?
    @Binding var photosAdequate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Turtle name", text: $name)
            TextField("Six-digit profile code", text: $profileCode)
            Picker("Species", selection: $species) {
                Text("Select species").tag(Optional<TurtleSpecies>.none)
                ForEach(TurtleSpecies.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            Toggle("Photos are clear enough to identify this turtle", isOn: $photosAdequate)
                .font(.caption)
            Text("Both left and right reference photos are required. This creates an identity and links this sighting.")
                .font(.caption)
                .foregroundStyle(AdaColors.secondaryInk)
        }
        .textFieldStyle(.roundedBorder)
    }
}
