import SwiftUI

struct ThemeSidebarView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.library, selection: $model.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Text(section.displayName).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            List(selection: $model.selectedThemeID) {
                if model.selectedSection == .library {
                    Section(L10n.themes) {
                        ForEach(model.store.themes) { theme in
                            ThemeSidebarRow(
                                theme: theme,
                                previewURL: model.store.previewURL(for: theme),
                                isActive: model.store.activeThemeID == theme.id
                            )
                            .tag(theme.id)
                            .contextMenu {
                                Button(L10n.duplicate) {
                                    model.selectedThemeID = theme.id
                                    model.duplicateSelectedTheme()
                                }
                                Divider()
                                Button(L10n.delete, role: .destructive) {
                                    model.selectedThemeID = theme.id
                                    model.requestDeleteSelectedTheme()
                                }
                            }
                        }
                    }
                } else {
                    Section(L10n.discover) {
                        Label(L10n.featured, systemImage: "sparkles")
                        Label(L10n.recent, systemImage: "clock")
                        Label(L10n.popular, systemImage: "chart.line.uptrend.xyaxis")
                    }

                    Section {
                        Text(L10n.marketplaceSidebarDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                if model.selectedSection == .library {
                    Button {
                        model.createTheme()
                    } label: {
                        Label(L10n.addTheme, systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .keyboardShortcut("n", modifiers: .command)
                }

                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 18)
                }
                .labelsHidden()
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minWidth: 36, minHeight: 36)
                .help(L10n.settings)
                .accessibilityLabel(L10n.settings)
            }
            .font(.callout)
            .padding(12)
        }
        .navigationTitle(ProductInfo.name)
        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 300)
    }
}

private struct ThemeSidebarRow: View {
    let theme: CursorTheme
    let previewURL: URL?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            CursorAssetView(
                url: previewURL,
                maximumSize: 34,
                fallbackSymbol: "cursorarrow.rays"
            )
            .padding(3)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .lineLimit(1)
                Text(L10n.cursorCount(theme.entries.count, total: CursorRole.allCases.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(L10n.activeThemeHelp)
                    .accessibilityLabel(L10n.active)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
