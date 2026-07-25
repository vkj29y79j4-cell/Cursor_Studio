import SwiftUI

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var showsDoneButton = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductInfo.name)
                        .font(.title2.weight(.bold))
                    Text(L10n.privateLocalThemes)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PrivacyRow(
                        symbol: "macbook",
                        title: L10n.everythingStaysLocal,
                        detail: L10n.noImagesLeaveMac
                    )
                    PrivacyRow(
                        symbol: "chart.bar.xaxis",
                        title: L10n.noAnalytics,
                        detail: L10n.noAnalyticsDetail
                    )
                    PrivacyRow(
                        symbol: "person.crop.circle.badge.xmark",
                        title: L10n.noAccount,
                        detail: L10n.noAccountDetail
                    )
                }
                .padding(4)
            }

            Label {
                Text(ProductInfo.compatibilityNotice)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)

            if showsDoneButton {
                HStack {
                    Spacer()
                    Button(L10n.done) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 520)
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
