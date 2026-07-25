import SwiftUI

struct CheckerboardView: View {
    var squareSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    let color: Color = (row + column).isMultiple(of: 2)
                        ? Color(nsColor: .controlBackgroundColor)
                        : Color(nsColor: .separatorColor).opacity(0.28)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
