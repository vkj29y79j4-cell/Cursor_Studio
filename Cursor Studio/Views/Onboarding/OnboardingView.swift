import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages = OnboardingPage.allCases

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageView(pages[page])
                    .id(page)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "\(L10n.onboardingPage) \(page + 1) / \(pages.count)"
            )

            Divider()

            HStack {
                Button(L10n.back) {
                    move(to: page - 1)
                }
                .disabled(page == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Spacer()

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(
                                index == page
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.3)
                            )
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                }

                Spacer()

                if page == pages.count - 1 {
                    Button(L10n.startUsing, action: onComplete)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.next) {
                        move(to: page + 1)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
            .padding(20)
        }
        .frame(width: 660, height: 500)
        .interactiveDismissDisabled()
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Image(systemName: page.symbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(page.detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(48)
    }

    private func move(to newPage: Int) {
        guard pages.indices.contains(newPage) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            page = newPage
        }
    }
}

private enum OnboardingPage: Int, CaseIterable {
    case welcome
    case importCursors
    case applyRestore
    case marketplace

    var symbol: String {
        switch self {
        case .welcome: "cursorarrow.rays"
        case .importCursors: "square.and.arrow.down"
        case .applyRestore: "arrow.triangle.2.circlepath"
        case .marketplace: "storefront"
        }
    }

    var title: String {
        switch self {
        case .welcome: L10n.onboardingWelcomeTitle
        case .importCursors: L10n.onboardingImportTitle
        case .applyRestore: L10n.onboardingApplyTitle
        case .marketplace: L10n.onboardingMarketplaceTitle
        }
    }

    var detail: String {
        switch self {
        case .welcome: L10n.onboardingWelcomeDetail
        case .importCursors: L10n.onboardingImportDetail
        case .applyRestore: L10n.onboardingApplyDetail
        case .marketplace: L10n.onboardingMarketplaceDetail
        }
    }
}
