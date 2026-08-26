import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection
    let favoriteCount: Int
    let individualCount: Int

    private var highlightedSection: AppSection {
        selection == .detail ? .individuals : selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaColors.ink.opacity(0.82))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)

            HStack(spacing: 14) {
                TurtleAppIconMark(size: 36)
                Text("Sea Turtle Group")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
            }
            .padding(.horizontal, 15)
            .padding(.top, 14)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 3) {
                SidebarRow(section: .dashboard, selection: $selection)
                SidebarRow(section: .map, selection: $selection)

                HStack(spacing: 8) {
                    Text("Sea Turtle Group")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                .padding(.horizontal, 18)
                .padding(.top, 19)
                .padding(.bottom, 5)

                SidebarRow(section: .individuals, selection: $selection, count: individualCount, isHighlighted: highlightedSection == .individuals)
                SidebarRow(section: .favorites, selection: $selection, count: favoriteCount, isHighlighted: highlightedSection == .favorites)
            }

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Circle()
                    .fill(AdaColors.navy)
                    .frame(width: 28, height: 28)
                    .overlay { Text("B").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bli Wayan").font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink)
                    Text("Field researcher").font(.system(size: 10)).foregroundStyle(AdaColors.tertiaryInk)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: AdaLayout.sidebarWidth)
        .background(AdaColors.sidebar)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    @Binding var selection: AppSection
    var count: Int?
    var isHighlighted: Bool?

    private var isSelected: Bool { isHighlighted ?? (selection == section) }

    var body: some View {
        Button { selection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 14)
                Text(section.title).font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
                if let count { Text("\(count)").font(.system(size: 12)).foregroundStyle(AdaColors.tertiaryInk) }
            }
            .foregroundStyle(AdaColors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black.opacity(0.075) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityLabel(section.title)
    }
}

struct TopBar: View {
    let title: String
    let subtitle: String?
    @Binding var searchText: String
    let onExport: (() -> Void)?
    let onBack: (() -> Void)?
    let mode: DataMode
    let isFallback: Bool
    let onModeChange: (DataMode) -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AdaColors.ink)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk) }
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(DataMode.allCases) { value in
                    Button {
                        onModeChange(value)
                    } label: {
                        if value == mode && !isFallback {
                            Label(value.title, systemImage: "checkmark")
                        } else {
                            Text(value.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isFallback ? AdaColors.orange : (mode == .live ? AdaColors.green : AdaColors.accent))
                        .frame(width: 6, height: 6)
                    Text(isFallback ? "Demo fallback" : mode.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(AdaColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.tertiaryInk)
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search individuals").foregroundStyle(AdaColors.secondaryInk)
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.ink)
                    .tint(AdaColors.navy)
                    .focused($isSearchFocused)
                    .frame(width: 214)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(AdaColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSearchFocused ? AdaColors.accent : AdaColors.line, lineWidth: isSearchFocused ? 1.5 : 1)
            }

            if let onExport {
                Button(action: onExport) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                        Text("Export").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(AdaColors.navy)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 23)
        .padding(.trailing, 32)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(AdaColors.canvas)
    }
}
