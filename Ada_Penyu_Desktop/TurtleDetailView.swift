import SwiftUI

struct TurtleDetailView: View {
    let turtle: Turtle
    let detail: TurtleDetailData?
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onExport: () -> Void

    private var measurements: [TurtleMeasurement] { detail?.measurements ?? [] }
    private var logs: [TurtleLogSummary] { detail?.logs ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TurtleSummaryCard(turtle: turtle, isFavorite: isFavorite, onToggleFavorite: onToggleFavorite, onExport: onExport)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        SightingTrendPanel(logs: logs)
                            .frame(maxWidth: .infinity, minHeight: 215, maxHeight: 215, alignment: .topLeading)
                        MeasurementPanel(measurements: measurements)
                            .frame(width: 315)
                            .frame(minHeight: 215, maxHeight: 215, alignment: .topLeading)
                    }
                    VStack(spacing: 16) {
                        SightingTrendPanel(logs: logs)
                        MeasurementPanel(measurements: measurements)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        LocationPanel(logs: logs)
                            .frame(width: 315)
                            .frame(minHeight: 220, alignment: .topLeading)
                        SightingLogPanel(logs: logs)
                            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    }
                    VStack(spacing: 16) {
                        LocationPanel(logs: logs)
                        SightingLogPanel(logs: logs)
                    }
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }
}

private struct DetailTrendPoint: Identifiable {
    let date: String
    let count: Int
    var id: String { date }
}

private struct SightingTrendPanel: View {
    let logs: [TurtleLogSummary]

    private var points: [DetailTrendPoint] {
        Dictionary(grouping: logs, by: \.date)
            .map { DetailTrendPoint(date: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                let formatter = APIFormatters.display
                return (formatter.date(from: lhs.date) ?? .distantPast) < (formatter.date(from: rhs.date) ?? .distantPast)
            }
    }

    private var maximum: CGFloat {
        CGFloat(max(points.map(\.count).max() ?? 1, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionTitle("Sighting trend", subtitle: "Recorded observations for this individual")
                Spacer()
                Text("\(logs.count) total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(AdaColors.navy.opacity(0.07))
                    .clipShape(Capsule())
            }

            if points.isEmpty {
                InlineEmptyState(text: "No sighting history recorded yet")
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        VStack(spacing: 6) {
                            Text("\(point.count)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AdaColors.secondaryInk)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(AdaColors.navy)
                                .frame(height: max(CGFloat(point.count) / maximum * 70, 5))
                            Text(shortDate(point.date))
                                .font(.system(size: 9))
                                .foregroundStyle(AdaColors.tertiaryInk)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 105, alignment: .bottom)
                .padding(.horizontal, 4)
                .background(alignment: .bottom) {
                    Rectangle().fill(AdaColors.line).frame(height: 1).offset(y: -21)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }

    private func shortDate(_ date: String) -> String {
        guard let value = APIFormatters.display.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: value)
    }
}

private struct TurtleSummaryCard: View {
    let turtle: Turtle
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onExport: () -> Void
    var body: some View {
        HStack(spacing: 22) {
            PlaceholderImage(size: 85)
            VStack(alignment: .leading, spacing: 7) {
                Text(turtle.species.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink)
                Text(turtle.id).font(.system(size: 22, weight: .semibold)).foregroundStyle(AdaColors.ink)
                HStack(spacing: 7) { DetailTag(text: "Unknown sex"); DetailTag(text: turtle.location); ConditionPill(condition: turtle.condition) }
            }
            Spacer()
            Rectangle().fill(AdaColors.line).frame(width: 1, height: 75)
            HStack(spacing: 28) {
                DetailMetric(title: "First recorded", value: turtle.firstRecorded)
                DetailMetric(title: "Last seen", value: turtle.lastSeen)
                DetailMetric(title: "Total sightings", value: String(format: "%02d", turtle.sightings))
            }
            Button(action: onToggleFavorite) { Image(systemName: isFavorite ? "heart.fill" : "heart").font(.system(size: 13, weight: .medium)).foregroundStyle(isFavorite ? AdaColors.accent : AdaColors.ink).frame(width: 29, height: 29).background(Color.black.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous)) }.buttonStyle(.plain).help(isFavorite ? "Remove from favorites" : "Favorite")
            Button(action: onExport) { Image(systemName: "arrow.down").font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink).frame(width: 29, height: 29).background(Color.black.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous)) }.buttonStyle(.plain).help("Export individual")
        }
        .adaCard(padding: 20)
    }
}

private struct DetailTag: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10)).lineLimit(1).foregroundStyle(AdaColors.secondaryInk).padding(.horizontal, 10).frame(height: 25).background(Color.black.opacity(0.045)).clipShape(Capsule()) }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk); Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(AdaColors.ink) } }
}

private struct MeasurementPanel: View {
    let measurements: [TurtleMeasurement]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Body measurements", subtitle: "Latest recorded values")
            if let latest = measurements.first {
                HStack(spacing: 22) {
                    MeasurementValue(label: "CCL", value: latest.length.map { String(format: "%.1f cm", $0) } ?? "—")
                    MeasurementValue(label: "CCW", value: latest.width.map { String(format: "%.1f cm", $0) } ?? "—")
                    MeasurementValue(label: "Weight", value: latest.weight.map { String(format: "%.1f kg", $0) } ?? "—")
                }
                Text("Measured \(latest.date)").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
            } else {
                InlineEmptyState(text: "No measurements recorded yet")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct MeasurementValue: View {
    let label: String
    let value: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 10)).foregroundStyle(AdaColors.tertiaryInk); Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(AdaColors.ink) } }
}

private struct LocationPanel: View {
    let logs: [TurtleLogSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Known locations", subtitle: "Most recent monitoring sites")
            if logs.isEmpty { InlineEmptyState(text: "No location history recorded yet") }
            else {
                ForEach(Array(logs.prefix(3))) { log in
                    HStack(spacing: 10) { Image(systemName: "mappin.circle.fill").foregroundStyle(AdaColors.navySoft); VStack(alignment: .leading, spacing: 2) { Text(log.location).font(.system(size: 13, weight: .medium)).foregroundStyle(AdaColors.ink); Text(log.date).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk) }; Spacer() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct SightingLogPanel: View {
    let logs: [TurtleLogSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Sighting log", subtitle: "Every recorded observation for this individual")
            if logs.isEmpty { InlineEmptyState(text: "No sightings recorded yet") }
            else {
                ForEach(logs) { log in
                    HStack(spacing: 12) {
                        Text(log.date).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk).frame(width: 86, alignment: .leading)
                        Text(log.status).font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink).frame(width: 100, alignment: .leading)
                        Text(log.location).font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
                        Spacer()
                        if let condition = log.condition { ConditionPill(condition: condition) }
                    }
                    .padding(.vertical, 8)
                    if log.id != logs.last?.id { Divider().overlay(AdaColors.line) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaCard(padding: 20)
    }
}

private struct InlineEmptyState: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(AdaColors.tertiaryInk).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }
}
