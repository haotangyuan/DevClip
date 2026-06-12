import DevClipCore
import SwiftUI

struct QuickPanelResultRow: View {
    var result: SearchResult
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.entry.isPinned ? "pin.fill" : ClipboardKindPresentation.iconName(result.entry.detectedKind))
                .foregroundStyle(isSelected ? .white : .secondary)
                .font(.system(size: 13))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(result.entry.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary)
                    .lineLimit(2)
                metadataLine
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selectionBackground)
    }

    private var metadataLine: some View {
        HStack(spacing: 6) {
            Text(ClipboardKindPresentation.displayName(result.entry.detectedKind))
            Text(result.entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let sourceAppName = result.entry.sourceAppName {
                Text(sourceAppName)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.72)) : AnyShapeStyle(.tertiary))
        .lineLimit(1)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
    }
}

struct QuickPanelActionRow: View {
    var action: TransformDefinition
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(isSelected ? .white : .secondary)
                .font(.system(size: 13))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(ClipboardKindPresentation.categoryName(action.category))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.76) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selectionBackground)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
    }
}
