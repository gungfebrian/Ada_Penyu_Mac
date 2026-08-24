import SwiftUI

struct TurtleDetailView: View {
    let turtle: Turtle
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TurtleSummaryCard(turtle: turtle, onBack: onBack)

                HStack(alignment: .top, spacing: 24) {
                    DetailPanel(title: "Sighting trend")
                        .frame(maxWidth: .infinity)
                    DetailPanel(title: "Known locations")
                        .frame(maxWidth: .infinity)
                }

                DetailPanel(title: "Sighting log")
                    .frame(height: 315)
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TurtleSummaryCard: View {
    let turtle: Turtle
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .frame(width: 85, height: 85)

            VStack(alignment: .leading, spacing: 7) {
                Text(turtle.species.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaColors.ink)
                Text(turtle.id)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                HStack(spacing: 7) {
                    DetailTag(text: "Unknown sex")
                    DetailTag(text: turtle.location)
                    ConditionPill(condition: turtle.condition)
                }
            }

            Spacer()
            Rectangle()
                .fill(AdaColors.line)
                .frame(width: 1, height: 75)

            HStack(spacing: 35) {
                DetailMetric(title: "First recorded", value: turtle.firstRecorded)
                DetailMetric(title: "Last seen", value: "12-04-2026")
                DetailMetric(title: "Total sightings", value: "05")
            }

            Button(action: onBack) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaColors.tertiaryInk)
                    .frame(width: 29, height: 29)
                    .background(Color.black.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Back to Individuals")
        }
        .adaCard(padding: 20)
    }
}

private struct DetailTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(AdaColors.secondaryInk)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Color.black.opacity(0.045))
            .clipShape(Capsule())
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AdaColors.ink)
        }
    }
}

private struct DetailPanel: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaColors.tertiaryInk)
                .padding(18)
            Spacer(minLength: 0)
        }
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
