import SwiftUI

struct CursorRoleCard: View {
    let role: CursorRole
    let entry: CursorEntry?
    let assetURL: URL?
    let isSelected: Bool
    let onSelect: () -> Void
    let onDrop: (URL) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(role.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: entry == nil ? "plus.circle" : "checkmark.circle.fill")
                        .foregroundStyle(entry == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                        .accessibilityHidden(true)
                    if let entry, entry.isAnimated {
                        Image(
                            systemName: entry.usesStaticAnimationFallback
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .foregroundStyle(
                            entry.usesStaticAnimationFallback
                                ? AnyShapeStyle(.orange)
                                : AnyShapeStyle(.blue)
                        )
                        .help(
                            L10n.animationHelp(
                                frameCount: entry.frameCount,
                                fallback: entry.usesStaticAnimationFallback
                            )
                        )
                    }
                }

                HStack {
                    Spacer()
                    CursorAssetView(
                        url: assetURL,
                        maximumSize: 76,
                        fallbackSymbol: role.symbolName
                    )
                    Spacer()
                }

                Text(
                    entry.map {
                        let size = L10n.pixelSize(
                            width: $0.pixelWidth,
                            height: $0.pixelHeight
                        )
                        return $0.isAnimated
                            ? "\(size) · \(L10n.frameCount($0.frameCount))"
                            : size
                    }
                        ?? L10n.dropPNGHere
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.11)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            onDrop(first)
            return true
        }
        .accessibilityLabel(
            L10n.cursorAccessibility(role: role.displayName, configured: entry != nil)
        )
        .accessibilityHint(L10n.cursorCardAccessibilityHint)
    }
}
