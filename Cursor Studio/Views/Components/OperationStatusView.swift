import SwiftUI

struct OperationStatusView: View {
    let state: CursorOperationState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working(let message):
            Label {
                Text(message)
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
            .statusStyle(color: .secondary)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .statusStyle(color: .green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .statusStyle(color: .red)
        }
    }
}

private extension View {
    func statusStyle(color: Color) -> some View {
        self
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}
